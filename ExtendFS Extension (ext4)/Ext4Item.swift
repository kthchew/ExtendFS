//
//  Ext4Item.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/28/25.
//

import Foundation
import FSKit

class Ext4Item: FSItem {
    let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item")
    
    let containingVolume: Ext4Volume
    /// The number of the index node for this item.
    let inodeNumber: UInt32
    
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
                        throw POSIXError(.EIO)
                    }
                }
            }
            let inodeSize = containingVolume.superblock.inodeSize
            fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        }
        
        guard let indexNode = IndexNode(from: fetchedData, creator: volume.superblock.creatorOS) else {
            throw POSIXError(.EIO)
        }
        self._indexNode = indexNode
    }
    
    var _indexNode: IndexNode?
    var indexNode: IndexNode {
        get throws {
            try fetchInode()
            return _indexNode!
        }
    }
    
    private func fetchInode() throws {
        if _indexNode != nil {
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
                    throw POSIXError(.EIO)
                }
            }
        }
        let inodeSize = containingVolume.superblock.inodeSize
        let fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        
        guard let inode = IndexNode(from: fetchedData, creator: containingVolume.superblock.creatorOS) else { throw POSIXError(.EIO) }
        self._indexNode = inode
    }
    
    var filetype: FSItem.ItemType {
        get {
            // cases must be in descending order of value because they are mutually exclusive but can still overlap
            guard let mode = try? indexNode.mode else {
                return .unknown
            }
            
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
        get throws {
            try indexNode.flags.contains(.usesExtents) ? nil : IndirectBlockMap(from: indexNode.block)
        }
    }
    /// The root of an extent tree used on ext4.
    ///
    /// If this is used repeatedly, call this once and save the result. The instance can save some cached data.
    private var extentTreeRoot: FileExtentTreeLevel? {
        get throws {
            try indexNode.flags.contains(.usesExtents) ? FileExtentTreeLevel(from: indexNode.block) : nil
        }
    }
    
    /// A map of file names to their directory entries.
    private var _directoryContentsInodes: [String: DirectoryEntry]? = nil
    /// A value that changes if the contents of the directory changes.
    private var directoryVerifier: FSDirectoryVerifier? = nil
    var directoryContents: ([DirectoryEntry], FSDirectoryVerifier)? {
        get async throws {
            guard filetype == .directory else { return nil }
            if _directoryContentsInodes != nil, let group = _directoryContentsInodes, let verifier = directoryVerifier {
                return (Array(group.values), verifier)
            }
            
            try await loadDirectoryContentCache()
            if let group = _directoryContentsInodes, let verifier = directoryVerifier {
                return (Array(group.values), verifier)
            }
            return nil
        }
    }
    
    func findItemInDirectory(named name: FSFileName) async throws -> Ext4Item? {
        if _directoryContentsInodes == nil {
            try await loadDirectoryContentCache()
        }
        
        if let _directoryContentsInodes, let nameStr = name.string, let dirEntry = _directoryContentsInodes[nameStr] {
            return try await containingVolume.item(forInode: dirEntry.inodePointee)
        }
        return nil
    }
    
    private func loadDirectoryContentCache() async throws {
        guard filetype == .directory else { return }
        logger.debug("loadDirectoryContentCache")
        var cache: [String: DirectoryEntry] = [:]
        
        let extents = try await findExtentsCovering(0, with: Int.max)
        for extent in extents {
            logger.debug("Fetching extent at block \(extent.physicalBlock)")
            guard let lengthInBlocks = extent.lengthInBlocks else {
                throw POSIXError(.EIO)
            }
            let data = try BlockDeviceReader.fetchExtent(from: containingVolume.resource, blockNumbers: extent.physicalBlock..<extent.physicalBlock+Int64(extent.lengthInBlocks ?? 0), blockSize: containingVolume.superblock.blockSize)
            for block in 0..<lengthInBlocks {
                let byteOffset = containingVolume.superblock.blockSize * Data.Index(block)
                let blockData = data.subdata(in: byteOffset..<(byteOffset+containingVolume.superblock.blockSize))
                logger.debug("Trying to decode data of length \(blockData.count)")
                guard let dirEntryBlock = ClassicDirectoryEntryBlock(from: blockData) else { continue }
                logger.debug("Block has \(dirEntryBlock.entries.count) entries")
                for entry in dirEntryBlock.entries {
                    guard entry.inodePointee != 0, entry.nameLength != 0 else { continue }
                    cache[entry.name] = entry
                }
            }
        }
        
        _directoryContentsInodes = cache
        directoryVerifier = FSDirectoryVerifier(UInt64.random(in: 1..<UInt64.max))
    }
    
    var symbolicLinkTarget: String? {
        get async throws {
            guard filetype == .symlink else { return nil }
            let indexNode = try indexNode
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
        get throws {
            guard try indexNode.xattrBlock != 0 else { return nil }
            let data = try BlockDeviceReader.fetchExtent(from: containingVolume.resource, blockNumbers: off_t(indexNode.xattrBlock)..<(Int64(indexNode.xattrBlock) + 1), blockSize: containingVolume.superblock.blockSize)
            return ExtendedAttrBlock(from: data)
        }
    }
    
    func getValueForEmbeddedAttribute(_ entry: ExtendedAttrEntry) throws -> Data? {
        guard (try indexNode.embeddedExtendedAttributes) != nil else { return nil }
        let offset = Data.Index(try entry.valueOffset - indexNode.embeddedXattrEntryBytes)
        let length = Data.Index(entry.valueLength)
        let data = try indexNode.remainingData.subdata(in: offset..<offset+length)
        guard data.count == length else { throw POSIXError(.EIO) }
        return data
    }
    
    func getAttributes(_ request: GetAttributesRequest) throws -> FSItem.Attributes {
        let attributes = try indexNode.getAttributes(request, superblock: containingVolume.superblock, readOnlySystem: containingVolume.readOnly)
        
        if request.isAttributeWanted(.fileID) {
            attributes.fileID = FSItem.Identifier(rawValue: UInt64(inodeNumber)) ?? .invalid
        }
        
        return attributes
    }
    
    func findExtentsCovering(_ fileBlock: UInt64, with blockLength: Int) async throws -> [FileExtentNode] {
        if let extentTreeRoot = try extentTreeRoot {
            return try extentTreeRoot.findExtentsCovering(fileBlock, with: blockLength, in: containingVolume)
        } else {
            let actualBlockLength = try min(blockLength, Int((Double(indexNode.size) / Double(containingVolume.superblock.blockSize)).rounded(.up)))
            guard var indirectBlockMap = try indirectBlockMap else {
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
