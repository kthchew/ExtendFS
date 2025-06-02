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
    
    struct Mode: OptionSet {
        let rawValue: UInt16
        
        static let otherExecute = Mode(rawValue: 1 << 0)
        static let otherWrite = Mode(rawValue: 1 << 1)
        static let otherRead = Mode(rawValue: 1 << 2)
        static let groupExecute = Mode(rawValue: 1 << 3)
        static let groupWrite = Mode(rawValue: 1 << 4)
        static let groupRead = Mode(rawValue: 1 << 5)
        static let ownerExecute = Mode(rawValue: 1 << 6)
        static let ownerWrite = Mode(rawValue: 1 << 7)
        static let ownerRead = Mode(rawValue: 1 << 8)
        static let sticky = Mode(rawValue: 1 << 9)
        static let setGID = Mode(rawValue: 1 << 10)
        static let setUID = Mode(rawValue: 1 << 11)
        
        // MARK: - Mutually exclusive file types
        static let fifoType = Mode(rawValue: 0x1000)
        static let characterDeviceType = Mode(rawValue: 0x2000)
        static let directoryType = Mode(rawValue: 0x4000)
        static let blockDeviceType = Mode(rawValue: 0x6000)
        static let regularFileType = Mode(rawValue: 0x8000)
        static let symbolicLinkType = Mode(rawValue: 0xA000)
        static let socketType = Mode(rawValue: 0xC000)
    }
    struct Flags: OptionSet {
        let rawValue: UInt32
        
        static let requiresSecureDeletion = Flags(rawValue: 1 << 0)
        static let shouldPreserve = Flags(rawValue: 1 << 1)
        static let compressed = Flags(rawValue: 1 << 2)
        static let allWritesAreSynchronous = Flags(rawValue: 1 << 3)
        static let immutable = Flags(rawValue: 1 << 4)
        static let appendOnly = Flags(rawValue: 1 << 5)
        static let noDump = Flags(rawValue: 1 << 6)
        static let noAccessTime = Flags(rawValue: 1 << 7)
        static let dirtyCompressedFile = Flags(rawValue: 1 << 8)
        static let hasCompressedClusters = Flags(rawValue: 1 << 9)
        static let doNotCompress = Flags(rawValue: 1 << 10)
        static let encrypted = Flags(rawValue: 1 << 11)
        static let hashedIndices = Flags(rawValue: 1 << 12)
        static let afsMagicDirectory = Flags(rawValue: 1 << 13)
        static let writeFileDataThroughJournal = Flags(rawValue: 1 << 14)
        static let tailMustNotBeMerged = Flags(rawValue: 1 << 15)
        static let directoryEntryDataWritesAreSynchronoous = Flags(rawValue: 1 << 16)
        static let topOfDirectoryHierarchy = Flags(rawValue: 1 << 17)
        static let hugeFile = Flags(rawValue: 1 << 18)
        static let usesExtents = Flags(rawValue: 1 << 19)
        static let largeXattrInDataBlocks = Flags(rawValue: 0x200000)
        static let blocksAllocatedPastEOF = Flags(rawValue: 0x400000)
        static let isSnapshot = Flags(rawValue: 0x01000000)
        static let snapshotIsBeingDeleted = Flags(rawValue: 0x04000000)
        static let snapshotShrinkCompleted = Flags(rawValue: 0x08000000)
        static let inodeHasInlineData = Flags(rawValue: 0x10000000)
        static let createChildrenWithSameProjectID = Flags(rawValue: 0x20000000)
        static let reserved = Flags(rawValue: 0x80000000)
        
        static let aggregateUserVisibleMask = Flags(rawValue: 0x4BDFFF)
        static let aggregateUserModifiableMask = Flags(rawValue: 0x4B80FF)
    }
    
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
            logger.log("Getting block group descriptor \((try? self.blockGroupNumber).debugDescription), inode number is \(self.inodeNumber)")
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
            // FIXME: not all inode entries are necessarily the same size - see https://www.kernel.org/doc/html/v4.19/filesystems/ext4/ondisk/index.html#inode-size
            // this might be correct though since the records should be the correct size?
            UInt64(groupInodeTableIndex) * UInt64(containingVolume.superblock.inodeSize)
        }
    }
    /// The offset of the inode table entry on the disk.
    var inodeLocation: Int64 {
        get throws {
            guard let inodeTableLocation = try blockGroupDescriptor?.inodeTableLocation else {
                throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
            }
            return try Int64((inodeTableLocation * UInt64(containingVolume.superblock.blockSize)) + inodeTableOffset)
        }
    }
    
    let name: FSFileName
    let attributes = FSItem.Attributes()
    
    init(name: FSFileName, in volume: Ext4Volume, inodeNumber: UInt32, parentInodeNumber: UInt32) {
        self.name = name
        self.containingVolume = volume
        self.inodeNumber = inodeNumber
        self.parentInodeNumber = parentInodeNumber
    }
    
    var mode: Mode {
        get throws {
            try Mode(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x0))
        }
    }
    var lowerUID: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x2) } }
    var lowerSize: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x4) } }
    /// Last access time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var storedAccessTime: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x8) } }
    /// Last inode change time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var storedChangeTime: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0xC) } }
    /// Last data modification time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var storedModificationTime: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x10) } }
    var deletionTime: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x14) } }
    var lowerGID: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x18) } }
    /// Hard link count.
    ///
    /// Normally, ext4 does not permit an inode to have more than 65,000 hard links. This applies to files as well as directories, which means that there cannot be more than 64,998 subdirectories in a directory (each subdirectory’s `..` entry counts as a hard link, as does the `.` entry in the directory itself). With the `DIR_NLINK` feature enabled, ext4 supports more than 64,998 subdirectories by setting this field to 1 to indicate that the number of hard links is not known.
    var hardLinkCount: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x1A) } }
    var lowerBlockCount: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x1C) } }
    var flags: Flags {
        get throws {
            Flags(rawValue: try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x20))
        }
    }
    var fileGenerationForNFS: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x64) } }
    var lowerExtendedAttributeBlock: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x68) } }
    var upperSize: UInt32? {
        get throws {
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x6C)
        }
    }
    var size: UInt64 {
        get throws {
            try UInt64.combine(upper: upperSize ?? 0, lower: lowerSize)
        }
    }
    // MARK: - Extended fields beyond original ext2 inode format
    /// The amount of space, in bytes, that this inode occupies past the original ext2 inode size (128 bytes), including this field.
    var extraInodeSize: UInt16 {
        get throws {
            guard containingVolume.superblock.inodeSize >= 128 + 2 else { return 0 }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x80)
        }
    }
    var upperChecksum: UInt16? {
        get throws {
            guard try extraInodeSize >= 4 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x82)
        }
    }
    var extraChangeTimeBits: UInt32? {
        get throws {
            guard try extraInodeSize >= 8 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x84)
        }
    }
    var extraModificationTimeBits: UInt32? {
        get throws {
            guard try extraInodeSize >= 12 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x88)
        }
    }
    var extraAccessTimeBits: UInt32? {
        get throws {
            guard try extraInodeSize >= 16 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x8C)
        }
    }
    var storedCreationTime: UInt32? {
        get throws {
            guard try extraInodeSize >= 20 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x90)
        }
    }
    var extraCreationTimeBits: UInt32? {
        get throws {
            guard try extraInodeSize >= 24 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x94)
        }
    }
    var upperVersion: UInt32? {
        get throws {
            guard try extraInodeSize >= 28 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x98)
        }
    }
    var projectId: UInt32? {
        get throws {
            guard try extraInodeSize >= 32 else { return nil }
            return try BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x9C)
        }
    }
    
    var filetype: FSItem.ItemType {
        get throws {
            // cases must be in descending order of value because they are mutually exclusive but can still overlap
            switch try mode {
            case let mode where mode.contains(.socketType):
                return .socket
            case let mode where mode.contains(.symbolicLinkType):
                return .symlink
            case let mode where mode.contains(.regularFileType):
                logger.log("is regular")
                return .file
            case let mode where mode.contains(.blockDeviceType):
                return .blockDevice
            case let mode where mode.contains(.directoryType):
                logger.log("is directory")
                return .directory
            case let mode where mode.contains(.characterDeviceType):
                return .charDevice
            case let mode where mode.contains(.fifoType):
                return .fifo
            default:
                return .unknown
            }
        }
    }
    
    // TODO: extra bits from extended fields, actual file contents, osd values
    
    var extentTreeRoot: FileExtentTreeLevel? {
        get throws {
            guard try flags.contains(.usesExtents) else { return nil }
            return try FileExtentTreeLevel(volume: containingVolume, offset: try inodeLocation + 0x28)
        }
    }
    
    var directoryContents: [Ext4Item]? {
        get throws {
            guard try filetype == .directory else { return nil }
            let extents = try findExtentsCovering(0, with: Int.max)
            var contents = [Ext4Item]()
            for extent in extents {
                let byteOffset = extent.physicalBlock * Int64(containingVolume.superblock.blockSize)
                var currentOffset = 0
                while currentOffset < Int(extent.lengthInBlocks!) * containingVolume.superblock.blockSize {
                    let directoryEntry = DirectoryEntry(volume: containingVolume, offset: byteOffset + Int64(currentOffset))
                    guard try directoryEntry.inodePointee != 0, try directoryEntry.nameLength != 0 else { break }
                    contents.append(Ext4Item(name: FSFileName(string: try directoryEntry.name ?? ""), in: containingVolume, inodeNumber: try directoryEntry.inodePointee, parentInodeNumber: inodeNumber))
                    currentOffset += Int(try directoryEntry.directoryEntryLength)
                }
            }
            
            return contents
        }
    }
    
    var symbolicLinkTarget: String? {
        get throws {
            guard try filetype == .symlink else { return nil }
            if try size < 60 {
                return try BlockDeviceReader.readString(blockDevice: containingVolume.resource, at: inodeLocation + 0x28, maxLength: 60)
            } else {
                let extents = try findExtentsCovering(0, with: Int.max)
                let data = try extents.reduce(into: (Data(), size)) { result, extent in
                    let remainingSectorAligned = result.1.roundUp(toMultipleOf: containingVolume.resource.physicalBlockSize)
                    let toActuallyRead = min(Int(remainingSectorAligned), Int(Int(extent.lengthInBlocks ?? 1) * containingVolume.superblock.blockSize))
                    var extentData = Data(count: Int(extent.lengthInBlocks ?? 1) * containingVolume.superblock.blockSize)
                    try extentData.withUnsafeMutableBytes { ptr in
                        let read = try containingVolume.resource.read(into: ptr, startingAt: extent.physicalBlock * Int64(containingVolume.superblock.blockSize), length: toActuallyRead)
                        result.1 -= min(result.1, UInt64(read))
                    }
                    result.0 += extentData
                }
                
                return String(data: data.0, encoding: .utf8)
            }
        }
    }
    
    func getAttributes(_ request: GetAttributesRequest) -> FSItem.Attributes {
        let attributes = FSItem.Attributes()
        
        // FIXME: many of these need to properly handle the upper values
        if request.isAttributeWanted(.uid) {
            attributes.uid = UInt32((try? lowerUID) ?? 0)
        }
        if request.isAttributeWanted(.gid) {
            attributes.gid = UInt32((try? lowerGID) ?? 0)
        }
        if request.isAttributeWanted(.mode) {
            attributes.mode = UInt32((try? mode)?.rawValue ?? 0o777)
        }
        if request.isAttributeWanted(.flags), let fileFlags = try? flags {
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
            attributes.size = UInt64((try? size) ?? 0)
        }
        if request.isAttributeWanted(.allocSize) {
            let usesHugeBlocks = (try? containingVolume.superblock.readonlyFeatureCompatibilityFlags.contains(.hugeFile) && flags.contains(.hugeFile)) ?? false
            attributes.allocSize = (UInt64((try? lowerBlockCount) ?? 0) * UInt64(usesHugeBlocks ? containingVolume.superblock.blockSize : 512))
        }
        if request.isAttributeWanted(.inhibitKernelOffloadedIO) {
            attributes.inhibitKernelOffloadedIO = false
        }
        if request.isAttributeWanted(.accessTime) {
            attributes.accessTime = timespec(tv_sec: Int((try? storedAccessTime) ?? 0), tv_nsec: 0)
        }
        if request.isAttributeWanted(.changeTime) {
            attributes.changeTime = timespec(tv_sec: Int((try? storedChangeTime) ?? 0), tv_nsec: 0)
        }
        if request.isAttributeWanted(.modifyTime) {
            attributes.modifyTime = timespec(tv_sec: Int((try? storedModificationTime) ?? 0), tv_nsec: 0)
        }
        if request.isAttributeWanted(.birthTime) {
            attributes.birthTime = timespec(tv_sec: Int((try? storedCreationTime) ?? 0), tv_nsec: 0)
        }
        if request.isAttributeWanted(.linkCount) {
            attributes.linkCount = UInt32((try? hardLinkCount) ?? 1)
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
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int) throws -> [FileExtentNode] {
        if let extentTreeRoot = try extentTreeRoot {
            return try extentTreeRoot.findExtentsCovering(fileBlock, with: blockLength)
        } else {
            let actualBlockLength = try min(blockLength, Int((Double(size) / Double(containingVolume.superblock.blockSize)).rounded(.up)))
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
