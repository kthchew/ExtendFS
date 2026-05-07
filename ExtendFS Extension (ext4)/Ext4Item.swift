// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import Synchronization

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item")

final class Ext4Item: FSItem {
    let containingVolume: Ext4Volume
    /// The number of the index node for this item.
    let inodeNumber: UInt32
    
    let indexNode: Mutex<IndexNode>
    
    var blockGroupNumber: UInt32 {
        get throws {
            (inodeNumber - 1) / containingVolume.superblock.inodesPerGroup
        }
    }
    var blockGroupDescriptor: BlockGroupDescriptor? {
        get throws {
            return try containingVolume.blockGroupDescriptors[Int(blockGroupNumber)]
        }
    }
    var groupInodeTableIndex: UInt32 {
        get {
            (inodeNumber - 1) % (containingVolume.superblock.inodesPerGroup)
        }
    }
    var inodeTableOffset: UInt64 {
        get throws {
            UInt64(groupInodeTableIndex) * UInt64(containingVolume.superblock.inodeSize)
        }
    }
    /// The offset of the inode table entry on the disk.
    var inodeLocation: UInt64 {
        get throws {
            guard let inodeTableLocation = try blockGroupDescriptor?.inodeTableLocation else {
                logger.error("Failed to fetch inode table location from block group descriptor")
                throw POSIXError(.EIO)
            }
            return try (inodeTableLocation * UInt64(containingVolume.superblock.blockSize)) + inodeTableOffset
        }
    }
    /// The byte offset of the block containing the inode table entry on disk.
    var inodeBlockLocation: UInt64 {
        get throws {
            try inodeLocation / UInt64(containingVolume.superblock.blockSize) * UInt64(containingVolume.superblock.blockSize)
        }
    }
    var inodeBlockOffset: UInt64 {
        get throws {
            try inodeLocation % UInt64(containingVolume.superblock.blockSize)
        }
    }
    
    init(volume: Ext4Volume, inodeNumber: UInt32, inodeData: Data? = nil) throws {
        guard inodeNumber != 0 else {
            logger.error("Volume contains a file with inode number 0, but this is invalid")
            throw POSIXError(.EIO)
        }
        self.containingVolume = volume
        self.inodeNumber = inodeNumber
        self.indexNode = Mutex(IndexNode())
        
        super.init()
        
        let fetchedData: Data
        if let inodeData {
            fetchedData = inodeData
        } else {
            let blockSize = containingVolume.superblock.blockSize
            var data = Data(count: Int(blockSize))
            try data.withUnsafeMutableBytes { ptr in
                if BlockDeviceReader.useMetadataRead {
                    try containingVolume.resource.metadataRead(into: ptr, startingAt: off_t(inodeBlockLocation), length: Int(blockSize))
                } else {
                    let count = try containingVolume.resource.read(into: ptr, startingAt: off_t(inodeBlockLocation), length: Int(blockSize))
                    guard count == Int(blockSize) else {
                        logger.error("Expected to read \(blockSize) bytes, but only read \(count) bytes from inode block")
                        throw POSIXError(.EIO)
                    }
                }
            }
            let inodeSize = containingVolume.superblock.inodeSize
            fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        }
        
        guard let indexNode = IndexNode(from: fetchedData, creator: volume.superblock.creatorOS, inodeNumber: inodeNumber, fsMetadataSeed: volume.metadataChecksumSeed) else {
            logger.error("Index node \(inodeNumber, privacy: .public) is not well formed")
            throw POSIXError(.EIO)
        }
        self.indexNode.withLock { $0 = indexNode }
    }

    /// Whether directory data blocks should be treated as containing a checksum tail.
    private var directoryBlocksHaveChecksumTail: Bool {
        containingVolume.metadataChecksumSeed != nil
    }

    private func caseFoldedNameData(_ nameData: Data) -> Data? {
        guard let nameString = String(data: nameData, encoding: .utf8) else { return nil }
        return Data(nameString.lowercased().utf8)
    }

    private func nameMatches(_ entry: DirectoryEntry, lookupName: Data, caseInsensitive: Bool) -> Bool {
        guard entry.inodePointee != 0, entry.nameLength != 0 else { return false }
        if caseInsensitive {
            if let entryName = entry.nameUTF8, let lookupName = String(data: lookupName, encoding: .utf8) {
                return entryName.caseInsensitiveCompare(lookupName) == .orderedSame
            } else if let encodingFlags = containingVolume.superblock.encodingFlags, encodingFlags.contains(.noCompatFallback) {
                return false
            }
        }
        
        return entry.name == lookupName
    }

    /// Reads one logical directory block and returns its raw bytes.
    private func directoryBlockData(at logicalBlock: UInt64) throws -> Data? {
        let extents = try findExtentsCovering(logicalBlock, with: 1)
        guard let extent = extents.first(where: { extent in
            guard let lengthInBlocks = extent.lengthInBlocks else { return false }
            let start = UInt64(extent.logicalBlock)
            let end = start + UInt64(lengthInBlocks)
            return extent.type != .zeroFill && logicalBlock >= start && logicalBlock < end
        }), let lengthInBlocks = extent.lengthInBlocks else {
            return nil
        }

        let offsetInExtent = logicalBlock - UInt64(extent.logicalBlock)
        guard offsetInExtent < UInt64(lengthInBlocks) else { return nil }

        let physicalBlock = extent.physicalBlock + off_t(offsetInExtent)
        return try BlockDeviceReader.fetchExtent(
            from: containingVolume.resource,
            blockNumbers: physicalBlock..<physicalBlock + 1,
            blockSize: containingVolume.superblock.blockSize
        )
    }

    /// Returns the block selected by an HTree hash->block table.
    private func hashTreeBlock(startingAt block: UInt32, entries: some RandomAccessCollection<HashTreeDirectoryEntry>, for hash: UInt32, interpretHashAsSigned: Bool) -> UInt32 {
        let foundIndex = entries.partitioningIndex { $0.hash > hash }
        let index = entries.index(before: foundIndex)
        let selectedBlock = index >= entries.startIndex && index < entries.endIndex ? entries[index].block : block
        return selectedBlock
    }

    private func hashVersion(for root: HashTreeDirectoryRoot) -> Superblock.HashVersion? {
        if root.info.hashVersion != .unknown {
            return root.info.hashVersion
        }
        if let defaultHashAlgorithm = containingVolume.superblock.defaultHashAlgorithm, defaultHashAlgorithm != .unknown {
            return defaultHashAlgorithm
        }
        return nil
    }

    private func directoryEntry(named lookupName: Data, in blockData: Data, caseInsensitive: Bool) -> DirectoryEntry? {
        guard let dirEntryBlock = ClassicDirectoryEntryBlock(from: blockData, withParentInode: inodeNumber) else { return nil }
        return dirEntryBlock.entries.first { entry in
            nameMatches(entry, lookupName: lookupName, caseInsensitive: caseInsensitive)
        }
    }

    private func findItemInHashTreeDirectory(named name: FSFileName, caseInsensitive: Bool) throws -> DirectoryEntry? {
        let indexNode = indexNode.withLock { $0 }
        guard indexNode.flags.contains(.hashedIndices) else { return nil }
        let lookupNameData = name.data
        let hashInputData: Data
        if caseInsensitive {
            if let folded = caseFoldedNameData(lookupNameData) {
                hashInputData = folded
            } else if let encodingFlags = containingVolume.superblock.encodingFlags, encodingFlags.contains(.strictMode) {
                return nil
            } else {
                hashInputData = lookupNameData
            }
        } else {
            hashInputData = lookupNameData
        }
        guard let rootData = try directoryBlockData(at: 0) else { return nil }
        guard let root = HashTreeDirectoryRoot(from: rootData, parentInode: nil, hasChecksumTail: directoryBlocksHaveChecksumTail, inodeChecksumSeed: indexNode.metadataChecksumSeed) else { return nil }
        guard let seed = containingVolume.superblock.hashSeed else { return nil }
        guard let hashVersion = hashVersion(for: root), let hash = HTreeHasher.hash(name: hashInputData, hashType: hashVersion, hashSeed: seed) else { return nil }

        let majorHash = hash.upperHalf

        let maxIndirectLevels = containingVolume.superblock.incompatibleFeatures.contains(.largeDirectory) ? 3 : 2
        guard root.info.indirectLevels <= maxIndirectLevels else {
            logger.error("Directory has \(root.info.indirectLevels, privacy: .public) levels of indirection, which exceeds the maximum supported level of \(maxIndirectLevels, privacy: .public)")
            return nil
        }
        var currentBlock = hashTreeBlock(startingAt: root.block, entries: root.entries, for: majorHash, interpretHashAsSigned: hashVersion.isSigned)
        for _ in 0..<root.info.indirectLevels {
            guard let nextData = try directoryBlockData(at: UInt64(currentBlock)),
                  let nextNode = HashTreeDirectoryNode(from: nextData, hasChecksumTail: directoryBlocksHaveChecksumTail, inodeChecksumSeed: indexNode.metadataChecksumSeed) else {
                return nil
            }
            currentBlock = hashTreeBlock(startingAt: nextNode.block, entries: nextNode.entries, for: majorHash, interpretHashAsSigned: hashVersion.isSigned)
        }
        let leafBlock = currentBlock

        guard let leafData = try directoryBlockData(at: UInt64(leafBlock)) else { return nil }
        return directoryEntry(named: lookupNameData, in: leafData, caseInsensitive: caseInsensitive)
    }
    
    private func refetchInode() throws {
        let blockSize = containingVolume.superblock.blockSize
        var data = Data(count: Int(blockSize))
        try data.withUnsafeMutableBytes { ptr in
            if BlockDeviceReader.useMetadataRead {
                try containingVolume.resource.metadataRead(into: ptr, startingAt: off_t(inodeBlockLocation), length: Int(blockSize))
            } else {
                let count = try containingVolume.resource.read(into: ptr, startingAt: off_t(inodeBlockLocation), length: Int(blockSize))
                guard count == Int(blockSize) else {
                    logger.error("Expected to read \(blockSize) bytes, but only read \(count) bytes from inode block")
                    throw POSIXError(.EIO)
                }
            }
        }
        let inodeSize = containingVolume.superblock.inodeSize
        let fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        
        guard let inode = IndexNode(from: fetchedData, creator: containingVolume.superblock.creatorOS, inodeNumber: inodeNumber, fsMetadataSeed: containingVolume.metadataChecksumSeed) else {
            logger.error("Index node \(self.inodeNumber, privacy: .public) is not well formed")
            throw POSIXError(.EIO)
        }
        self.indexNode.withLock { $0 = inode }
    }
    
    var filetype: FSItem.ItemType {
        get {
            // cases must be in descending order of value because they are mutually exclusive but can still overlap
            let mode = indexNode.withLock { $0.mode }
            
            switch mode {
            case _ where mode.contains(.socketType):
                return .socket
            case _ where mode.contains(.symbolicLinkType):
                return .symlink
            case _ where mode.contains(.regularFileType):
                return .file
            case _ where mode.contains(.blockDeviceType):
                return .blockDevice
            case _ where mode.contains(.directoryType):
                return .directory
            case _ where mode.contains(.characterDeviceType):
                return .charDevice
            case _ where mode.contains(.fifoType):
                return .fifo
            default:
                return .unknown
            }
        }
    }
    
    /// The root of an indirect block map used on ext2 and ext3.
    ///
    /// If this is used repeatedly, call this once and save the result. The instance can save some cached data.
    private var indirectBlockMap: IndirectBlockMap? {
        get {
            indexNode.withLock { $0.flags.contains(.usesExtents) ? nil : IndirectBlockMap(from: $0.block) }
        }
    }
    /// The root of an extent tree used on ext4.
    ///
    /// If this is used repeatedly, call this once and save the result. The instance can save some cached data.
    private var extentTreeRoot: FileExtentTreeLevel? {
        get {
            indexNode.withLock { $0.flags.contains(.usesExtents) ? FileExtentTreeLevel(from: $0.block, inodeChecksumSeed: $0.metadataChecksumSeed) : nil }
        }
    }
    
    func findItemInDirectory(named name: FSFileName, cache: DirectoryCache) async throws -> (Ext4Item, FSFileName)? {
        let caseInsensitive = indexNode.withLock { $0.flags.contains(.caseInsensitiveDirectoryContents) }
        let lookupNameData = name.data
        let keyData = caseInsensitive ? (caseFoldedNameData(lookupNameData) ?? lookupNameData) : lookupNameData
        let key = DirectoryCacheKey(parentInode: inodeNumber, pathComponent: keyData)
        let (cachedEntry, negativeIsCorrect) = cache.lookup(forKey: key)
        if let cachedEntry = cachedEntry {
            if cachedEntry.inodePointee == 0 {
                return nil
            } else {
                return try await (containingVolume.item(forInode: cachedEntry.inodePointee), FSFileName(data: cachedEntry.name))
            }
        } else if negativeIsCorrect {
            let inserted = cache.insertEmptyEntry(forKey: key)
            if !inserted {
                logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
            }
            return nil
        }
        
        let inodeFlags = indexNode.withLock({ $0.flags })
        
        if containingVolume.superblock.incompatibleFeatures.contains(.inlineDataInInode) && inodeFlags.contains(.inodeHasInlineData) {
            let (entries, _) = try fetchAllDirectoryEntries(cache: cache)
            let entry = entries.first { entry in
                nameMatches(entry, lookupName: lookupNameData, caseInsensitive: caseInsensitive)
            }
            if let entry {
                return try await (containingVolume.item(forInode: entry.inodePointee), FSFileName(data: entry.name))
            } else {
                let inserted = cache.insertEmptyEntry(forKey: key)
                if !inserted {
                    logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
                }
                return nil
            }
        }

        if inodeFlags.contains(.hashedIndices) {
            if let entry = try findItemInHashTreeDirectory(named: name, caseInsensitive: caseInsensitive) {
                let cachedEntry = cache.insert(entry, forKey: key) ?? entry
                return try await (containingVolume.item(forInode: cachedEntry.inodePointee), FSFileName(data: cachedEntry.name))
            }
            
            guard cache.insertEmptyEntry(forKey: key) else {
                logger.error("Couldn't find entry in htree directory, but inserting negative entry failed")
                return nil
            }
            return nil
        }
        
        let (entries, _) = try fetchAllDirectoryEntries(cache: cache)
        let (secondCachedEntry, secondNegativeIsCorrect) = cache.lookup(forKey: key)
        if let secondCachedEntry {
            if secondCachedEntry.inodePointee == 0 {
                return nil
            } else {
                return try await (containingVolume.item(forInode: secondCachedEntry.inodePointee), FSFileName(data: secondCachedEntry.name))
            }
        } else if secondNegativeIsCorrect {
            let inserted = cache.insertEmptyEntry(forKey: key)
            if !inserted {
                logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
            }
            return nil
        }
        if let entry = entries.first(where: { entry in
            nameMatches(entry, lookupName: lookupNameData, caseInsensitive: caseInsensitive)
        }) {
            return try await (containingVolume.item(forInode: entry.inodePointee), FSFileName(data: entry.name))
        }
        
        let inserted = cache.insertEmptyEntry(forKey: key)
        if !inserted {
            logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
        }
        return nil
    }
    
    func fetchAllDirectoryEntries(cache: DirectoryCache) throws -> (ContiguousArray<DirectoryEntry>, FSDirectoryVerifier) {
        guard filetype == .directory else { throw POSIXError(.ENOSYS) }
        let indexNode = indexNode.withLock { $0 }
        let caseInsensitive = indexNode.flags.contains(.caseInsensitiveDirectoryContents)
        
        if let (entries, version) = cache.fetchAllEntriesInDirectory(directoryInode: inodeNumber) {
            return (entries, FSDirectoryVerifier(version))
        }
        
        var loadedEntries: ContiguousArray<DirectoryEntry> = []
        
        if containingVolume.superblock.incompatibleFeatures.contains(.inlineDataInInode) && indexNode.flags.contains(.inodeHasInlineData) {
            let block = indexNode.block
            guard let firstDirEntryBlock = ClassicDirectoryEntryBlock(from: block.advanced(by: 4), withParentInode: inodeNumber) else {
                logger.error("Inline data directory did not have a valid directory entry block")
                throw POSIXError(.EIO)
            }
            for entry in firstDirEntryBlock.entries {
                guard entry.inodePointee != 0, entry.nameLength != 0 else { continue }
                loadedEntries.append(entry)
            }
            if let systemDataXattrEntry = indexNode.embeddedExtendedAttributes?.first(where: { $0.name == "system.data" }), systemDataXattrEntry.valueLength > 0 {
                guard let systemDataXattrValue = try getValueForEmbeddedAttribute(systemDataXattrEntry) else {
                    logger.error("Directory with inline data had a system.data xattr entry, but the value could not be fetched")
                    throw POSIXError(.EIO)
                }
                guard let systemDataDirEntry = ClassicDirectoryEntryBlock(from: systemDataXattrValue, withParentInode: inodeNumber) else {
                    logger.error("Directory with inline data had a system.data xattr entry, but the value did not contain a valid directory entry block")
                    throw POSIXError(.EIO)
                }
                for entry in systemDataDirEntry.entries {
                    guard entry.inodePointee != 0, entry.nameLength != 0 else { continue }
                    loadedEntries.append(entry)
                }
            }
        } else {
            let extents = try findExtentsCovering(0, with: Int.max)
            for extent in extents {
                logger.debug("Fetching extent at block \(extent.physicalBlock, privacy: .public)")
                guard let lengthInBlocks = extent.lengthInBlocks else {
                    logger.fault("Extent somehow does not have a length")
                    throw POSIXError(.EIO)
                }
                let data = try BlockDeviceReader.fetchExtent(from: containingVolume.resource, blockNumbers: extent.physicalBlock..<extent.physicalBlock+Int64(extent.lengthInBlocks ?? 0), blockSize: containingVolume.superblock.blockSize)
                for block in 0..<lengthInBlocks {
                    let byteOffset = containingVolume.superblock.blockSize * Data.Index(block)
                    let blockData = data.subdata(in: byteOffset..<(byteOffset+containingVolume.superblock.blockSize))
                    logger.debug("Trying to decode data of length \(blockData.count, privacy: .public)")
                    guard let dirEntryBlock = ClassicDirectoryEntryBlock(from: blockData, withParentInode: inodeNumber) else { continue }
                    logger.debug("Block has \(dirEntryBlock.entries.count, privacy: .public) entries")
                    for entry in dirEntryBlock.entries {
                        guard entry.inodePointee != 0, entry.nameLength != 0 else { continue }
                        loadedEntries.append(entry)
                    }
                }
            }
        }
        
        loadedEntries.sort { entry1, entry2 in
            entry1.inodePointee < entry2.inodePointee
        }
        let (realEntries, versionNum) = cache.insert(completeEntryList: loadedEntries, forParentDirectoryInode: inodeNumber, caseInsensitive: caseInsensitive)
        
        let verifier = FSDirectoryVerifier(versionNum ?? UInt64.random(in: 1..<UInt64.max))
        return (realEntries, verifier)
    }
    
    var symbolicLinkTarget: String? {
        get async throws {
            guard filetype == .symlink else { return nil }
            let indexNode = indexNode.withLock { $0 }
            if indexNode.size < 60 {
                return indexNode.block.readString(at: 0, maxLength: indexNode.block.count)
            } else {
                let extents = try findExtentsCovering(0, with: Int.max)
                var data = Data(capacity: Int(indexNode.size).roundUp(toMultipleOf: Int(containingVolume.resource.physicalBlockSize)))
                let remaining = indexNode.size
                for extent in extents {
                    let remainingSectorAligned = remaining.roundUp(toMultipleOf: containingVolume.resource.physicalBlockSize)
                    let toActuallyRead = min(Int(remainingSectorAligned), Int(Int(extent.lengthInBlocks ?? 1) * containingVolume.superblock.blockSize))
                    let pointer = UnsafeMutableRawBufferPointer.allocate(byteCount: toActuallyRead, alignment: MemoryLayout<UInt8>.alignment)
                    defer { pointer.deallocate() }
                    let actuallyRead = try await containingVolume.resource.read(into: pointer, startingAt: extent.physicalBlock * Int64(containingVolume.superblock.blockSize), length: toActuallyRead)
                    data += Data(bytes: pointer.baseAddress!, count: actuallyRead)
                }
                
                return String(data: data, encoding: .utf8)
            }
        }
    }
    
    private let _extendedAttributeBlock: Mutex<ExtendedAttrBlock?> = Mutex(nil)
    var extendedAttributeBlock: ExtendedAttrBlock? {
        get throws {
            if let block = _extendedAttributeBlock.withLock({$0}) { return block }
            let xattrBlock = indexNode.withLock { $0.xattrBlock }
            guard xattrBlock != 0 else { return nil }
            let data = try BlockDeviceReader.fetchExtent(from: containingVolume.resource, blockNumbers: off_t(xattrBlock)..<(Int64(xattrBlock) + 1), blockSize: containingVolume.superblock.blockSize)
            let block = ExtendedAttrBlock(from: data)
            _extendedAttributeBlock.withLock { $0 = block }
            return block
        }
    }
    
    func getValueForEmbeddedAttribute(_ entry: ExtendedAttrEntry) throws -> Data? {
        let indexNode = indexNode.withLock { $0 }
        guard indexNode.embeddedExtendedAttributes != nil else { return nil }
        if entry.valueLength == 0 {
            return Data()
        }
        guard entry.valueOffset >= indexNode.embeddedXattrEntryBytes else {
            logger.error("Value offset \(entry.valueOffset, privacy: .public) was less than embedded xattr entry bytes \(indexNode.embeddedXattrEntryBytes, privacy: .public)")
            return nil
        }
        let offset = Data.Index(entry.valueOffset - indexNode.embeddedXattrEntryBytes)
        let length = Data.Index(entry.valueLength)
        let data = indexNode.remainingData.subdata(in: offset..<offset+length)
        guard data.count == length else {
            logger.error("Extended attribute is apparently longer than the data available")
            throw POSIXError(.EIO)
        }
        return data
    }
    
    func getInlineData() throws -> Data? {
        let indexNode = indexNode.withLock { $0 }
        guard containingVolume.superblock.incompatibleFeatures.contains(.inlineDataInInode) && indexNode.flags.contains(.inodeHasInlineData) else {
            return nil
        }
        
        let block = indexNode.block
        guard let systemDataXattrEntry = indexNode.embeddedExtendedAttributes?.first(where: { $0.name == "system.data" }) else {
            return nil
        }
        guard let systemDataXattrValue = try getValueForEmbeddedAttribute(systemDataXattrEntry) else {
            return nil
        }
        let size = Int(indexNode.size)
        let data = (block + systemDataXattrValue).prefix(size)
        guard data.count == size else {
            logger.error("Inline data fetched is not the correct size")
            throw POSIXError(.EIO)
        }
        
        return data
    }
    
    func getAttributes(_ request: GetAttributesRequest) -> FSItem.Attributes {
        let attributes = indexNode.withLock { $0.getAttributes(request, superblock: containingVolume.superblock, readOnlySystem: containingVolume.readOnly) }
        
        if request.isAttributeWanted(.fileID) {
            attributes.fileID = FSItem.Identifier(rawValue: UInt64(inodeNumber)) ?? .invalid
        }
        
        if !containingVolume.superblock.incompatibleFeatures.contains(.inlineDataInInode) { // override if feature not enabled in superblock
            attributes.inhibitKernelOffloadedIO = false
        }
        
        return attributes
    }
    
    func setAttributes(_ request: SetAttributesRequest) async throws -> FSItem.Attributes {
        let attributes = FSItem.Attributes()
        let readOnlyAttributes: [FSItem.Attribute] = [.fileID, .parentID, .type, .linkCount, .supportsLimitedXAttrs, .inhibitKernelOffloadedIO]
        for attribute in readOnlyAttributes {
            guard !request.isValid(attribute) else {
                throw POSIXError(.EINVAL)
            }
        }
        
        indexNode.withLock { newInode in
            if request.isValid(.mode) {
                let type: IndexNode.Mode
                switch filetype {
                case .unknown:
                    type = []
                case .file:
                    type = .regularFileType
                case .directory:
                    type = .directoryType
                case .symlink:
                    type = .symbolicLinkType
                case .fifo:
                    type = .fifoType
                case .charDevice:
                    type = .characterDeviceType
                case .blockDevice:
                    type = .blockDeviceType
                case .socket:
                    type = .socketType
                @unknown default:
                    type = []
                }
                newInode.mode = IndexNode.Mode(rawValue: request.mode).union(type)
                request.consumedAttributes.insert(.mode)
                attributes.mode = newInode.mode.rawValue
            }
            if request.isValid(.uid) {
                newInode.uid = request.uid
                request.consumedAttributes.insert(.uid)
                attributes.uid = newInode.uid
            }
            if request.isValid(.gid) {
                newInode.gid = request.gid
                request.consumedAttributes.insert(.gid)
                attributes.gid = newInode.gid
            }
            if request.isValid(.flags) {
                var flags = newInode.flags
                if (request.flags | UInt32(SF_IMMUTABLE | UF_IMMUTABLE)) != 0 {
                    flags.insert(.noDump)
                } else {
                    flags.remove(.noDump)
                }
                if (request.flags | UInt32(SF_IMMUTABLE | UF_IMMUTABLE)) != 0 {
                    flags.insert(.immutable)
                } else {
                    flags.remove(.immutable)
                }
                if (request.flags | UInt32(SF_APPEND | UF_APPEND)) != 0 {
                    flags.insert(.appendOnly)
                } else {
                    flags.remove(.appendOnly)
                }
                if (request.flags | UInt32(UF_COMPRESSED)) != 0 {
                    flags.insert(.compressed)
                } else {
                    flags.remove(.compressed)
                }
                
                // no OPAQUE
                // no TRACKED
                // no DATAVAULT
                // no HIDDEN
                
                newInode.flags = flags
                request.consumedAttributes.insert(.gid)
                attributes.flags = request.flags
            }
            if request.isValid(.size) {
                
            }
            if request.isValid(.allocSize) {
                
            }
            if request.isValid(.accessTime) {
                newInode.lastAccessTime = request.accessTime
                request.consumedAttributes.insert(.accessTime)
                attributes.accessTime = newInode.lastAccessTime
            }
            if request.isValid(.modifyTime) {
                newInode.lastDataModifyTime = request.modifyTime
                request.consumedAttributes.insert(.modifyTime)
                attributes.modifyTime = newInode.lastDataModifyTime
            }
            if request.isValid(.changeTime) {
                newInode.lastInodeChangeTime = request.changeTime
                request.consumedAttributes.insert(.changeTime)
                attributes.changeTime = newInode.lastInodeChangeTime
            }
            if request.isValid(.birthTime) {
                newInode.fileCreationTime = request.birthTime
                request.consumedAttributes.insert(.birthTime)
                attributes.birthTime = request.birthTime
            }
            // addedTime and backupTime not supported
            
            // TODO: write new inode to disk
        }
        
        return attributes
    }
    
    /// Finds a list of extents covering the specified range of file blocks.
    ///
    /// If the file uses extents, this will read the extent tree. If the file uses indirect blocks, this will read the indirect block map and convert the mapped blocks into extents.
    ///
    /// > Note: If there is the opportunity to do so, it is possible that the extents returned by this method will cover areas beyond the range that was requested. For example, some extents returned may cover areas entirely outside of the range provided.
    /// - Parameters:
    ///   - fileBlock: The starting logical file block.
    ///   - blockLength: The length of the range.
    ///   - performAdditionalIO: Whether to perform additional IO to fetch extents that are not immediately available. If `false`, only extents that can be fetched without performing additional IO will be returned, if any, and it is not guaranteed that the provided extents will cover the entire range.
    /// - Returns: A list of extents.
    func findExtentsCovering(_ fileBlock: UInt64, with blockLength: Int, performAdditionalIO: Bool = true) throws -> [FileExtentNode] {
        if let extentTreeRoot = extentTreeRoot {
            return try extentTreeRoot.findExtentsCovering(fileBlock, with: blockLength, in: containingVolume, performAdditionalIO: performAdditionalIO)
        } else {
            let sizeInBlocks = indexNode.withLock { Int((Double($0.size) / Double(containingVolume.superblock.blockSize)).rounded(.up)) }
            let actualBlockLength = min(blockLength, sizeInBlocks)
            let upperBound = fileBlock + UInt64(actualBlockLength)
            guard var indirectBlockMap = indirectBlockMap else {
                logger.error("An item had no extent tree, but also no indirect block map")
                throw POSIXError(.EIO)
            }
            var extents = [FileExtentNode]()
            var block = fileBlock
            while block < upperBound {
                let level1End: UInt32 = 11
                guard performAdditionalIO || block <= level1End else {
                    continue
                }
                let answerBlock = try indirectBlockMap.getIndirectBlockForPhysicalBlockLocation(for: block, blockDevice: containingVolume.resource, blockSize: containingVolume.superblock.blockSize)
                
                for (n, physicalLocation) in answerBlock.blockNumbers.enumerated() {
                    let currentLogicalBlock = UInt32(n) + answerBlock.startingBlock
                    guard currentLogicalBlock < sizeInBlocks else { break }
                    if let last = extents.last {
                        guard currentLogicalBlock >= (last.logicalBlock + Int64(last.lengthInBlocks ?? 1)) else { continue }
                        
                    }
                    if let last = extents.last, (last.physicalBlock + off_t(last.lengthInBlocks ?? 1) == physicalLocation) || (last.type == .zeroFill && physicalLocation == 0) {
                        extents[extents.count - 1].lengthInBlocks? += 1
                    } else {
                        let extent = FileExtentNode(physicalBlock: off_t(physicalLocation), logicalBlock: off_t(currentLogicalBlock), lengthInBlocks: 1, type: physicalLocation == 0 ? .zeroFill : .data)
                        extents.append(extent)
                    }
                }
                
                block = UInt64(answerBlock.startingBlock) + UInt64(answerBlock.blockNumbers.count)
            }
            return extents
        }
    }
}
