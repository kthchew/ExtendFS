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
    var inodeTableOffset: Int64 {
        get throws {
            // FIXME: not all inode entries are necessarily the same size - see https://www.kernel.org/doc/html/v4.19/filesystems/ext4/ondisk/index.html#inode-size
            // this might be correct though since the records should be the correct size?
            Int64(groupInodeTableIndex) * Int64(containingVolume.superblock.inodeSize)
        }
    }
    /// The offset of the inode table entry on the disk.
    var inodeLocation: Int64 {
        get throws {
            guard let inodeTableLocation = try blockGroupDescriptor?.inodeTableLocation else {
                throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
            }
            return try Int64((Int64(inodeTableLocation) * Int64(containingVolume.superblock.blockSize)) + inodeTableOffset)
        }
    }
    /// The byte offset of the block containing the inode table entry on disk.
    var inodeBlockLocation: Int64 {
        get throws {
            try inodeLocation / Int64(containingVolume.superblock.blockSize) * Int64(containingVolume.superblock.blockSize)
        }
    }
    var inodeBlockOffset: Int64 {
        get throws {
            try inodeLocation % Int64(containingVolume.superblock.blockSize)
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
                    try containingVolume.resource.metadataRead(into: ptr, startingAt: inodeBlockLocation, length: Int(blockSize))
                } else {
                    let count = try containingVolume.resource.read(into: ptr, startingAt: inodeBlockLocation, length: Int(blockSize))
                    guard count == Int(blockSize) else {
                        throw POSIXError(.EIO)
                    }
                }
            }
            let inodeSize = containingVolume.superblock.inodeSize
            fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        }
        
        guard let indexNode = IndexNode(from: fetchedData) else {
            throw POSIXError(.EIO)
        }
        self._indexNode = indexNode
        
        self.extentTreeRoot = try await indexNode.flags.contains(.usesExtents) ? FileExtentTreeLevel(volume: containingVolume, offset: inodeLocation + 0x28) : nil
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
                try containingVolume.resource.metadataRead(into: ptr, startingAt: inodeBlockLocation, length: Int(blockSize))
            } else {
                let count = try containingVolume.resource.read(into: ptr, startingAt: inodeBlockLocation, length: Int(blockSize))
                guard count == Int(blockSize) else {
                    throw POSIXError(.EIO)
                }
            }
        }
        let inodeSize = containingVolume.superblock.inodeSize
        let fetchedData = try data.subdata(in: Int(inodeBlockOffset)..<Int(inodeBlockOffset)+Int(inodeSize))
        
        guard let inode = IndexNode(from: fetchedData) else { throw POSIXError(.EIO) }
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
    
    var extentTreeRoot: FileExtentTreeLevel?
    
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
            return try await containingVolume.item(forInode: dirEntry.inodePointee, withParentInode: self.inodeNumber, withName: FSFileName(string: dirEntry.name))
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
        let attributes = try indexNode.getAttributes(request, superblock: containingVolume.superblock)
        
        if request.isAttributeWanted(.fileID) {
            attributes.fileID = FSItem.Identifier(rawValue: UInt64(inodeNumber)) ?? .invalid
        }
        
        return attributes
    }
    
    func indirectAddressing(for block: Int64, currentDepth: Int, currentLevelDiskPosition: UInt64, currentLevelStartsAtBlock: Int64) throws -> FileExtentNode {
        let blockOffset = block - currentLevelStartsAtBlock
        let pointerSize = Int64(MemoryLayout<UInt32>.size)
        let coveredPerLevelOfIndirection = containingVolume.superblock.blockSize / 4
        
        if currentDepth == 0 {
            let address: UInt32 = try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: Int64(currentLevelDiskPosition) + (blockOffset * pointerSize))
            return FileExtentNode(physicalBlock: off_t(address), logicalBlock: block, lengthInBlocks: 1, type: .data)
        } else {
            let blocksCoveredPerItem = Int(pow(Double(coveredPerLevelOfIndirection), Double(currentDepth)))
            let index = Int(blockOffset) / blocksCoveredPerItem
            let address: UInt32 = try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: Int64(currentLevelDiskPosition) + (Int64(index) * pointerSize))
            return try indirectAddressing(for: block, currentDepth: currentDepth - 1, currentLevelDiskPosition: UInt64(address) * UInt64(containingVolume.superblock.blockSize), currentLevelStartsAtBlock: currentLevelStartsAtBlock + Int64((index * blocksCoveredPerItem)))
        }
    }
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int) async throws -> [FileExtentNode] {
        if let extentTreeRoot {
            return try await extentTreeRoot.findExtentsCovering(fileBlock, with: blockLength)
        } else {
            let actualBlockLength = try min(blockLength, Int((Double(indexNode.size) / Double(containingVolume.superblock.blockSize)).rounded(.up)))
            return try (fileBlock..<(fileBlock + Int64(actualBlockLength))).map { block in
                let iBlockOffset = try inodeLocation + 0x28
                let pointerSize = Int64(MemoryLayout<UInt32>.size)
                let coveredPerLevelOfIndirection = Int64(containingVolume.superblock.blockSize / 4)
                
                let level1End: Int64 = 11
                let level2End = level1End + coveredPerLevelOfIndirection
                let level3End = level2End + Int64(pow(Double(coveredPerLevelOfIndirection), 2))
                let level4End = level3End + Int64(pow(Double(coveredPerLevelOfIndirection), 3)) + 1
                switch block {
                case 0...level1End:
                    return try indirectAddressing(for: block, currentDepth: 0, currentLevelDiskPosition: UInt64(iBlockOffset), currentLevelStartsAtBlock: 0)
                case (level1End + 1)...(level2End):
                    return try indirectAddressing(for: block, currentDepth: 1, currentLevelDiskPosition: UInt64(iBlockOffset) + UInt64(pointerSize * 12), currentLevelStartsAtBlock: level1End + 1)
                case (level2End + 1)...(level3End):
                    return try indirectAddressing(for: block, currentDepth: 2, currentLevelDiskPosition: UInt64(iBlockOffset) + UInt64(pointerSize * 13), currentLevelStartsAtBlock: level2End + 1)
                case (level3End + 1)...(level4End):
                    return try indirectAddressing(for: block, currentDepth: 3, currentLevelDiskPosition: UInt64(iBlockOffset) + UInt64(pointerSize * 14), currentLevelStartsAtBlock: level3End + 1)
                default:
                    throw fs_errorForPOSIXError(POSIXError.EFBIG.rawValue)
                }
            }
        }
    }
}
