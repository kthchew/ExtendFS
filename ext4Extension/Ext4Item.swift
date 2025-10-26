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
    var parentInodeNumber: UInt32
    
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
    
    let name: FSFileName
    
    init(name: FSFileName, in volume: Ext4Volume, inodeNumber: UInt32, parentInodeNumber: UInt32, inodeData: Data? = nil) async throws {
        self.name = name
        self.containingVolume = volume
        self.inodeNumber = inodeNumber
        self.parentInodeNumber = parentInodeNumber
        
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
        
        self.indexNode = try IndexNode(fetchedData)
        
        self.extentTreeRoot = try await indexNode.flags.contains(.usesExtents) ? FileExtentTreeLevel(volume: containingVolume, offset: inodeLocation + 0x28) : nil
    }
    
    var indexNode: IndexNode!
    
    var filetype: FSItem.ItemType {
        get throws {
            // cases must be in descending order of value because they are mutually exclusive but can still overlap
            switch indexNode.mode {
            case _ where indexNode.mode.contains(.socketType):
                return .socket
            case _ where indexNode.mode.contains(.symbolicLinkType):
                return .symlink
            case _ where indexNode.mode.contains(.regularFileType):
                return .file
            case _ where indexNode.mode.contains(.blockDeviceType):
                return .blockDevice
            case _ where indexNode.mode.contains(.directoryType):
                return .directory
            case _ where indexNode.mode.contains(.characterDeviceType):
                return .charDevice
            case _ where indexNode.mode.contains(.fifoType):
                return .fifo
            default:
                return .unknown
            }
        }
    }
    
    // TODO: extra bits from extended fields, actual file contents, osd values
    
    var extentTreeRoot: FileExtentTreeLevel?
    
    /// A map of file names to their directory entries.
    private var _directoryContentsInodes: [String: DirectoryEntry]? = nil
    /// A value that changes if the contents of the directory changes.
    private var directoryVerifier: FSDirectoryVerifier? = nil
    var directoryContents: (any AsyncSequence<DirectoryEntry, any Error>, FSDirectoryVerifier)? {
        get async throws {
            guard try filetype == .directory else { return nil }
            if _directoryContentsInodes != nil, let group = await asyncGroupForCachedDirectoryContents(), let verifier = directoryVerifier {
                return (group, verifier)
            }
            
            try await loadDirectoryContentCache()
            if let group = await asyncGroupForCachedDirectoryContents(), let verifier = directoryVerifier {
                return (group, verifier)
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
        guard try filetype == .directory else { return }
        var cache: [String: DirectoryEntry] = [:]
        
        let extents = try await findExtentsCovering(0, with: Int.max)
        for extent in extents {
            let byteOffset = extent.physicalBlock * Int64(containingVolume.superblock.blockSize)
            var currentOffset = 0
            while currentOffset < Int(extent.lengthInBlocks!) * containingVolume.superblock.blockSize {
                let directoryEntry = try DirectoryEntry(volume: containingVolume, offset: byteOffset + Int64(currentOffset), inodeParent: self.inodeNumber)
                guard directoryEntry.inodePointee != 0, directoryEntry.nameLength != 0 else { break }
                cache[directoryEntry.name] = directoryEntry
                currentOffset += Int(directoryEntry.directoryEntryLength)
            }
        }
        
        _directoryContentsInodes = cache
        directoryVerifier = FSDirectoryVerifier(UInt64.random(in: 1..<UInt64.max))
    }
    
    private func asyncGroupForCachedDirectoryContents() async -> (any AsyncSequence<DirectoryEntry, any Error>)? {
        guard let _directoryContentsInodes else { return nil }
        return AsyncThrowingStream { continuation in
            Task {
                for item in _directoryContentsInodes {
                    continuation.yield(item.value)
                }
                continuation.finish()
            }
        }
    }
    
    var symbolicLinkTarget: String? {
        get async throws {
            guard try filetype == .symlink else { return nil }
            if indexNode.size < 60 {
                return indexNode.block.span.bytes.withUnsafeBytes { buffer in
                    return String(bytes: buffer, encoding: .utf8)
                }
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
    
    func getAttributes(_ request: GetAttributesRequest) -> FSItem.Attributes {
        let attributes = FSItem.Attributes()
        
        // FIXME: many of these need to properly handle the upper values
        if request.isAttributeWanted(.uid) {
            attributes.uid = UInt32(indexNode.uid)
        }
        if request.isAttributeWanted(.gid) {
            attributes.gid = UInt32(indexNode.gid)
        }
        if request.isAttributeWanted(.mode) {
            // FIXME: not correct way to enforce read-only file system but does FSKit currently have a better way?
            let useMode = containingVolume.readOnly ? indexNode.mode.subtracting([.ownerWrite, .groupWrite, .otherWrite]) : indexNode.mode
            attributes.mode = UInt32(useMode.rawValue)
        }
        if request.isAttributeWanted(.flags) {
            let fileFlags = indexNode.flags
            var flags: UInt32 = 0
            if fileFlags.contains(.noDump) { flags |= UInt32(UF_NODUMP) }
            if fileFlags.contains(.immutable) { flags |= UInt32(SF_IMMUTABLE | UF_IMMUTABLE) }
            if fileFlags.contains(.appendOnly) { flags |= UInt32(SF_APPEND | UF_APPEND) }
            // no OPAQUE
            if fileFlags.contains(.compressed) { flags |= UInt32(UF_COMPRESSED) }
            // no TRACKED
            // no DATAVAULT
            // no HIDDEN
        }
        if request.isAttributeWanted(.fileID) {
            attributes.fileID = FSItem.Identifier(rawValue: UInt64(inodeNumber)) ?? .invalid
        }
        if request.isAttributeWanted(.type) {
            attributes.type = (try? filetype) ?? .unknown
        }
        if request.isAttributeWanted(.size) {
            attributes.size = UInt64(indexNode.size)
        }
        if request.isAttributeWanted(.allocSize) {
            let usesHugeBlocks = containingVolume.superblock.readonlyFeatureCompatibilityFlags.contains(.hugeFile) && indexNode.flags.contains(.hugeFile)
            attributes.allocSize = (UInt64(indexNode.blockCount) * UInt64(usesHugeBlocks ? containingVolume.superblock.blockSize : 512))
        }
        if request.isAttributeWanted(.inhibitKernelOffloadedIO) {
            attributes.inhibitKernelOffloadedIO = false
        }
        if request.isAttributeWanted(.accessTime) {
            attributes.accessTime = timespec(tv_sec: Int(indexNode.lastAccessTime), tv_nsec: 0)
        }
        if request.isAttributeWanted(.changeTime) {
            attributes.changeTime = timespec(tv_sec: Int(indexNode.lastInodeChangeTime), tv_nsec: 0)
        }
        if request.isAttributeWanted(.modifyTime) {
            attributes.modifyTime = timespec(tv_sec: Int(indexNode.lastDataModifyTime), tv_nsec: 0)
        }
        if request.isAttributeWanted(.birthTime) {
            attributes.birthTime = timespec(tv_sec: Int(indexNode.fileCreationTime ?? 0), tv_nsec: 0)
        }
        if request.isAttributeWanted(.addedTime) {
            // TODO: proper implementation
            attributes.addedTime = timespec()
        }
        if request.isAttributeWanted(.linkCount) {
            attributes.linkCount = UInt32(indexNode.hardLinkCount)
        }
        if request.isAttributeWanted(.parentID) {
            attributes.parentID = FSItem.Identifier(rawValue: UInt64(parentInodeNumber)) ?? .invalid
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
            let actualBlockLength = min(blockLength, Int((Double(indexNode.size) / Double(containingVolume.superblock.blockSize)).rounded(.up)))
            Logger().log("findExtentsCovering fileBlock is \(fileBlock) actualBlockLength is \(actualBlockLength) name is \(self.name.string ?? "(unknown)", privacy: .public)")
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
