// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

actor ItemCache {
    var indexNode: IndexNode?
    func getCachedIndexNode() -> IndexNode? {
        return indexNode
    }
    func setCachedIndexNode(_ node: IndexNode) {
        indexNode = node
    }
}

final class Ext4Item: FSItem {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item")
    
    let containingVolume: Ext4Volume
    /// The number of the index node for this item.
    let inodeNumber: UInt32
    /// If this is a directory, this is the directory entry for this item in its parent directory, if it has one and if it has been loaded. Otherwise, this is `nil`.
//    let directoryEntry: DirectoryEntry?
    
    let cache = ItemCache()
    
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
                Self.logger.error("Failed to fetch inode table location from block group descriptor")
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
    
    init(volume: Ext4Volume, inodeNumber: UInt32, inodeData: Data? = nil) async throws {
        guard inodeNumber != 0 else {
            Self.logger.error("Volume contains a file with inode number 0, but this is invalid")
            throw POSIXError(.EIO)
        }
        self.containingVolume = volume
        self.inodeNumber = inodeNumber
        
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
                        Self.logger.error("Expected to read \(blockSize) bytes, but only read \(count) bytes from inode block")
                        throw POSIXError(.EIO)
                    }
                }
            }
            let inodeSize = containingVolume.superblock.inodeSize
            fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        }
        
        guard let indexNode = IndexNode(from: fetchedData, creator: volume.superblock.creatorOS, inodeNumber: inodeNumber, fsMetadataSeed: volume.metadataChecksumSeed) else {
            Self.logger.error("Index node \(inodeNumber, privacy: .public) is not well formed")
            throw POSIXError(.EIO)
        }
        await cache.setCachedIndexNode(indexNode)
    }
    
    var indexNode: IndexNode {
        get async throws {
            return try await fetchInode()
        }
    }
    
    private func fetchInode() async throws -> IndexNode {
        if let inode = await cache.getCachedIndexNode() {
            return inode
        }
        let blockSize = containingVolume.superblock.blockSize
        var data = Data(count: Int(blockSize))
        try data.withUnsafeMutableBytes { ptr in
            if BlockDeviceReader.useMetadataRead {
                try containingVolume.resource.metadataRead(into: ptr, startingAt: off_t(inodeBlockLocation), length: Int(blockSize))
            } else {
                let count = try containingVolume.resource.read(into: ptr, startingAt: off_t(inodeBlockLocation), length: Int(blockSize))
                guard count == Int(blockSize) else {
                    Self.logger.error("Expected to read \(blockSize) bytes, but only read \(count) bytes from inode block")
                    throw POSIXError(.EIO)
                }
            }
        }
        let inodeSize = containingVolume.superblock.inodeSize
        let fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        
        guard let inode = IndexNode(from: fetchedData, creator: containingVolume.superblock.creatorOS, inodeNumber: inodeNumber, fsMetadataSeed: containingVolume.metadataChecksumSeed) else {
            Self.logger.error("Index node \(self.inodeNumber, privacy: .public) is not well formed")
            throw POSIXError(.EIO)
        }
        await cache.setCachedIndexNode(inode)
        return inode
    }
    
    var filetype: FSItem.ItemType {
        get async {
            // cases must be in descending order of value because they are mutually exclusive but can still overlap
            guard let indexNode = try? await indexNode else {
                return .unknown
            }
            let mode = indexNode.mode
            
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
        get async throws {
            try await indexNode.flags.contains(.usesExtents) ? nil : IndirectBlockMap(from: indexNode.block)
        }
    }
    /// The root of an extent tree used on ext4.
    ///
    /// If this is used repeatedly, call this once and save the result. The instance can save some cached data.
    private var extentTreeRoot: FileExtentTreeLevel? {
        get async throws {
            try await indexNode.flags.contains(.usesExtents) ? FileExtentTreeLevel(from: indexNode.block, inodeChecksumSeed: indexNode.metadataChecksumSeed) : nil
        }
    }
    
    func findItemInDirectory(named name: FSFileName, cache: DirectoryCache) async throws -> (Ext4Item, FSFileName)? {
        let caseInsensitive = try await indexNode.flags.contains(.caseInsensitiveDirectoryContents)
        let keyComponent = caseInsensitive ? FSFileName(string: name.string?.lowercased() ?? "") : name
        let key = DirectoryCacheKey(parentInode: inodeNumber, pathComponent: keyComponent.data)
        let (cachedEntry, negativeIsCorrect) = cache.lookup(forKey: key)
        if let cachedEntry = cachedEntry {
            if cachedEntry.inodePointee == 0 {
                return nil
            } else {
                return try await (containingVolume.item(forInode: cachedEntry.inodePointee), FSFileName(string: cachedEntry.name))
            }
        } else if negativeIsCorrect {
            let inserted = cache.insertEmptyEntry(forKey: key)
            if !inserted {
                Self.logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
            }
            return nil
        }
        
        let (entries, _) = try await fetchAllDirectoryEntries(cache: cache)
        let (secondCachedEntry, secondNegativeIsCorrect) = cache.lookup(forKey: key)
        if let secondCachedEntry {
            if secondCachedEntry.inodePointee == 0 {
                return nil
            } else {
                return try await (containingVolume.item(forInode: secondCachedEntry.inodePointee), FSFileName(string: secondCachedEntry.name))
            }
        } else if secondNegativeIsCorrect {
            let inserted = cache.insertEmptyEntry(forKey: key)
            if !inserted {
                Self.logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
            }
            return nil
        }
        if let entry = entries.first(where: { entry in
            if caseInsensitive {
                return entry.name.caseInsensitiveCompare(name.string ?? "") == .orderedSame
            } else {
                return entry.name == name.string
            }
        }) {
            return try await (containingVolume.item(forInode: entry.inodePointee), FSFileName(string: entry.name))
        }
        
        let inserted = cache.insertEmptyEntry(forKey: key)
        if !inserted {
            Self.logger.warning("Empty entry supposedly inserted for negative lookup was not inserted")
        }
        return nil
    }
    
    func fetchAllDirectoryEntries(cache: DirectoryCache) async throws -> (ContiguousArray<DirectoryEntry>, FSDirectoryVerifier) {
        guard await filetype == .directory else { throw POSIXError(.ENOSYS) }
        let caseInsensitive = try await indexNode.flags.contains(.caseInsensitiveDirectoryContents)
        
        if let (entries, version) = cache.fetchAllEntriesInDirectory(directoryInode: inodeNumber) {
            return (entries, FSDirectoryVerifier(version))
        }
        
        var loadedEntries: ContiguousArray<DirectoryEntry> = []
        
        let extents = try await findExtentsCovering(0, with: Int.max)
        for extent in extents {
            Self.logger.debug("Fetching extent at block \(extent.physicalBlock, privacy: .public)")
            guard let lengthInBlocks = extent.lengthInBlocks else {
                Self.logger.fault("Extent somehow does not have a length")
                throw POSIXError(.EIO)
            }
            let data = try BlockDeviceReader.fetchExtent(from: containingVolume.resource, blockNumbers: extent.physicalBlock..<extent.physicalBlock+Int64(extent.lengthInBlocks ?? 0), blockSize: containingVolume.superblock.blockSize)
            for block in 0..<lengthInBlocks {
                let byteOffset = containingVolume.superblock.blockSize * Data.Index(block)
                let blockData = data.subdata(in: byteOffset..<(byteOffset+containingVolume.superblock.blockSize))
                Self.logger.debug("Trying to decode data of length \(blockData.count, privacy: .public)")
                guard let dirEntryBlock = ClassicDirectoryEntryBlock(from: blockData, withParentInode: inodeNumber) else { continue }
                Self.logger.debug("Block has \(dirEntryBlock.entries.count, privacy: .public) entries")
                for entry in dirEntryBlock.entries {
                    guard entry.inodePointee != 0, entry.nameLength != 0 else { continue }
                    loadedEntries.append(entry)
                }
            }
        }
        
        loadedEntries.sort { entry1, entry2 in
            entry1.inodePointee < entry2.inodePointee
        }
        let realEntries = cache.insert(completeEntryList: loadedEntries, forParentDirectoryInode: inodeNumber, caseInsensitive: caseInsensitive)
        
        let verifier = FSDirectoryVerifier(UInt64.random(in: 1..<UInt64.max))
        return (realEntries, verifier)
    }
    
    var symbolicLinkTarget: String? {
        get async throws {
            guard await filetype == .symlink else { return nil }
            let indexNode = try await indexNode
            if indexNode.size < 60 {
                return indexNode.block.readString(at: 0, maxLength: indexNode.block.count)
            } else {
                let extents = try await findExtentsCovering(0, with: Int.max)
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
    
    var extendedAttributeBlock: ExtendedAttrBlock? {
        get async throws {
            let indexNode = try await indexNode
            guard indexNode.xattrBlock != 0 else { return nil }
            let data = try BlockDeviceReader.fetchExtent(from: containingVolume.resource, blockNumbers: off_t(indexNode.xattrBlock)..<(Int64(indexNode.xattrBlock) + 1), blockSize: containingVolume.superblock.blockSize)
            return ExtendedAttrBlock(from: data)
        }
    }
    
    func getValueForEmbeddedAttribute(_ entry: ExtendedAttrEntry) async throws -> Data? {
        let indexNode = try await indexNode
        guard indexNode.embeddedExtendedAttributes != nil else { return nil }
        guard entry.valueOffset >= indexNode.embeddedXattrEntryBytes else {
            Self.logger.error("Value offset \(entry.valueOffset, privacy: .public) was less than embedded xattr entry bytes \(indexNode.embeddedXattrEntryBytes, privacy: .public)")
            return nil
        }
        let offset = Data.Index(entry.valueOffset - indexNode.embeddedXattrEntryBytes)
        let length = Data.Index(entry.valueLength)
        let data = indexNode.remainingData.subdata(in: offset..<offset+length)
        guard data.count == length else {
            Self.logger.error("Extended attribute is apparently longer than the data available")
            throw POSIXError(.EIO)
        }
        return data
    }
    
    func getAttributes(_ request: GetAttributesRequest) async throws -> FSItem.Attributes {
        let attributes = try await indexNode.getAttributes(request, superblock: containingVolume.superblock, readOnlySystem: containingVolume.readOnly)
        
        if request.isAttributeWanted(.fileID) {
            attributes.fileID = FSItem.Identifier(rawValue: UInt64(inodeNumber)) ?? .invalid
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
        
        var newInode = try await indexNode
        if request.isValid(.mode) {
            let type: IndexNode.Mode
            switch await filetype {
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
        await cache.setCachedIndexNode(newInode)
        
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
    func findExtentsCovering(_ fileBlock: UInt64, with blockLength: Int, performAdditionalIO: Bool = true) async throws -> [FileExtentNode] {
        if let extentTreeRoot = try await extentTreeRoot {
            return try extentTreeRoot.findExtentsCovering(fileBlock, with: blockLength, in: containingVolume, performAdditionalIO: performAdditionalIO)
        } else {
            let indexNode = try await self.indexNode
            let sizeInBlocks = Int((Double(indexNode.size) / Double(containingVolume.superblock.blockSize)).rounded(.up))
            let actualBlockLength = min(blockLength, sizeInBlocks)
            let upperBound = fileBlock + UInt64(actualBlockLength)
            guard var indirectBlockMap = try await indirectBlockMap else {
                Self.logger.error("An item had no extent tree, but also no indirect block map")
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
