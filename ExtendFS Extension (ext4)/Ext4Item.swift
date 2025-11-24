// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

actor ItemCache {
    /// Used to temporarily store `com.apple.*` attributes. Such attributes won't be written to disk or persisted.
    var temporaryXattrs: [String: Data] = [:]
    func getTemporaryXattr(_ name: String) -> Data? {
        temporaryXattrs[name]
    }
    func setTemporaryXattr(_ data: Data?, for name: String) {
        temporaryXattrs[name] = data
    }
    
    var indexNode: IndexNode?
    func getCachedIndexNode() -> IndexNode? {
        return indexNode
    }
    func setCachedIndexNode(_ node: IndexNode) {
        indexNode = node
    }
    
    /// An array of directory entries, if this item is a directory and they have been queried.
    ///
    /// This list is sorted by the entry names.
    private var directoryContentsInodes: [DirectoryEntry]? = nil
    /// A value that changes if the contents of the directory changes.
    private var directoryVerifier: FSDirectoryVerifier? = nil
    func getDirectoryEntries() -> ([DirectoryEntry], FSDirectoryVerifier)? {
        if let directoryVerifier, let directoryContentsInodes {
            return (directoryContentsInodes, directoryVerifier)
        }
        return nil
    }
    func setDirectoryEntries(_ entries: [DirectoryEntry], withVerifier verifier: FSDirectoryVerifier) {
        directoryContentsInodes = entries
        directoryVerifier = verifier
    }
}

final class Ext4Item: FSItem {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item")
    
    let containingVolume: Ext4Volume
    /// The number of the index node for this item.
    let inodeNumber: UInt32
    
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
        
        guard let indexNode = IndexNode(from: fetchedData, creator: volume.superblock.creatorOS) else {
            Self.logger.error("Index node \(inodeNumber, privacy: .public) is not well formed")
            throw POSIXError(.EIO)
        }
        await cache.setCachedIndexNode(indexNode)
    }
    
    var indexNode: IndexNode {
        get async throws {
            try await fetchInode()
            return await cache.getCachedIndexNode()!
        }
    }
    
    private func fetchInode() async throws {
        if await cache.getCachedIndexNode() != nil {
            return
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
        
        guard let inode = IndexNode(from: fetchedData, creator: containingVolume.superblock.creatorOS) else {
            Self.logger.error("Index node \(self.inodeNumber, privacy: .public) is not well formed")
            throw POSIXError(.EIO)
        }
        await cache.setCachedIndexNode(inode)
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
            try await indexNode.flags.contains(.usesExtents) ? FileExtentTreeLevel(from: indexNode.block) : nil
        }
    }
    
    var directoryContents: ([DirectoryEntry], FSDirectoryVerifier)? {
        get async throws {
            guard await filetype == .directory else { return nil }
            if let (group, verifier) = await cache.getDirectoryEntries() {
                return (group, verifier)
            }
            
            try await loadDirectoryContentCache()
            if let (group, verifier) = await cache.getDirectoryEntries() {
                return (group, verifier)
            }
            return nil
        }
    }
    
    func findItemInDirectory(named name: FSFileName) async throws -> Ext4Item? {
        if await cache.getDirectoryEntries() == nil {
            try await loadDirectoryContentCache()
        }
        
        if let (directoryContentsInodes, _) = await cache.getDirectoryEntries(), let nameStr = name.string {
            let dirEntryIndex = directoryContentsInodes.partitioningIndex { $0.name >= nameStr }
            if dirEntryIndex != directoryContentsInodes.endIndex, directoryContentsInodes[dirEntryIndex].name == nameStr {
                return try await containingVolume.item(forInode: directoryContentsInodes[dirEntryIndex].inodePointee)
            }
        }
        
        return nil
    }
    
    private func loadDirectoryContentCache() async throws {
        guard await filetype == .directory else { return }
        Self.logger.debug("Loading directory content cache for directory (inode \(self.inodeNumber, privacy: .public))")
        var cache: [DirectoryEntry] = []
        
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
                guard let dirEntryBlock = ClassicDirectoryEntryBlock(from: blockData) else { continue }
                Self.logger.debug("Block has \(dirEntryBlock.entries.count, privacy: .public) entries")
                for entry in dirEntryBlock.entries {
                    guard entry.inodePointee != 0, entry.nameLength != 0 else { continue }
                    cache.append(entry)
                }
            }
        }
        
        await self.cache.setDirectoryEntries(cache.sorted(by: { $0.name < $1.name }), withVerifier: FSDirectoryVerifier(UInt64.random(in: 1..<UInt64.max)))
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
    
    func findExtentsCovering(_ fileBlock: UInt64, with blockLength: Int) async throws -> [FileExtentNode] {
        if let extentTreeRoot = try await extentTreeRoot {
            return try extentTreeRoot.findExtentsCovering(fileBlock, with: blockLength, in: containingVolume)
        } else {
            let actualBlockLength = try await min(blockLength, Int((Double(indexNode.size) / Double(containingVolume.superblock.blockSize)).rounded(.up)))
            guard var indirectBlockMap = try await indirectBlockMap else {
                Self.logger.error("An item had no extent tree, but also no indirect block map")
                throw POSIXError(.EIO)
            }
            return try (fileBlock..<(fileBlock + UInt64(actualBlockLength))).reduce(into: []) { extents, block in
                let answer = try indirectBlockMap.getPhysicalBlockLocations(for: block, blockDevice: containingVolume.resource, blockSize: containingVolume.superblock.blockSize)
                
                if var last = extents.last, (last.physicalBlock + off_t(last.lengthInBlocks ?? 1) == answer) {
                    last.lengthInBlocks? += 1
                    extents[extents.count - 1] = last
                } else {
                    let extent = FileExtentNode(physicalBlock: off_t(answer), logicalBlock: off_t(block), lengthInBlocks: 1, type: .data)
                    extents.append(extent)
                }
            }
        }
    }
}
