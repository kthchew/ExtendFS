//
//  IndexNode.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 7/31/25.
//

import DataKit
import Foundation
import FSKit
import os.log

struct IndexNode: ReadWritable {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "IndexNode")
    
    static var format: Format {
        Scope {
            \.mode.rawValue
            \.uid.lowerHalf
            \.size.lowerHalf
            \.lastAccessTime.lowerHalf
            \.lastInodeChangeTime.lowerHalf
            \.lastDataModifyTime.lowerHalf
            \.deletionTime
            \.gid.lowerHalf
            \.hardLinkCount
            \.blockCount.lowerHalf
            \.flags.rawValue
            \.osd
            \.block
            \.generation
            \.xattrBlock.lowerHalf
            \.size.upperHalf
            \.fragmentAddress
            \.osd2

            \.extraINodeSize // FIXME: what if this isn't here?
            Using(\.extraINodeSize) { size in
                if size >= 4 { \.upperChecksum } // FIXME: real checksum
                if size >= 8 { \.lastInodeChangeTime.upperHalf }
                if size >= 12 { \.lastDataModifyTime.upperHalf }
                if size >= 16 { \.lastAccessTime.upperHalf }
                if size >= 20 { \.fileCreationTime?.lowerHalf }
                if size >= 24 { \.fileCreationTime?.upperHalf }
                if size >= 28 { \.version.upperHalf }
                if size >= 32 { \.projectID }
            }
        }
        .endianness(.little)
    }
    
    init(from context: DataKit.ReadContext<IndexNode>) throws {
        mode = Mode(rawValue: try context.read(for: \.mode.rawValue))
        uid = try UInt32.combine(upper: context.readIfPresent(for: \.uid.upperHalf) ?? 0, lower: context.read(for: \.uid.lowerHalf))
        size = try UInt64.combine(upper: context.readIfPresent(for: \.size.upperHalf) ?? 0, lower: context.read(for: \.size.lowerHalf))
        // FIXME: in these cases, upper half only uses the lowest 2 bits, then uses the other 30 bits for nanosecond accuracy
        lastAccessTime = try UInt64.combine(upper: (context.readIfPresent(for: \.lastAccessTime.upperHalf) ?? 0) & 0b11, lower: context.read(for: \.lastAccessTime.lowerHalf))
        lastInodeChangeTime = try UInt64.combine(upper: (context.readIfPresent(for: \.lastInodeChangeTime.upperHalf) ?? 0) & 0b11, lower: context.read(for: \.lastInodeChangeTime.lowerHalf))
        lastDataModifyTime = try UInt64.combine(upper: (context.readIfPresent(for: \.lastDataModifyTime.upperHalf) ?? 0) & 0b11, lower: context.read(for: \.lastDataModifyTime.lowerHalf))
        deletionTime = try context.read(for: \.deletionTime)
        gid = try UInt32.combine(upper: context.readIfPresent(for: \.gid.upperHalf) ?? 0, lower: context.read(for: \.gid.lowerHalf))
        hardLinkCount = try context.read(for: \.hardLinkCount)
        blockCount = try UInt64.combine(upper: context.readIfPresent(for: \.blockCount.upperHalf) ?? 0, lower: context.read(for: \.blockCount.lowerHalf))
        flags = Flags(rawValue: try context.read(for: \.flags.rawValue))
        osd = try context.read(for: \.osd)
        block = try context.read(for: \.block)
        generation = try context.read(for: \.generation)
        xattrBlock = try UInt64.combine(upper: context.readIfPresent(for: \.xattrBlock.upperHalf) ?? 0, lower: context.read(for: \.xattrBlock.lowerHalf))
        fragmentAddress = try context.read(for: \.fragmentAddress)
        osd2 = try context.read(for: \.osd2)
        extraINodeSize = try context.readIfPresent(for: \.extraINodeSize) ?? 0
        upperChecksum = try context.readIfPresent(for: \.upperChecksum)
        
        fileCreationTime = try UInt64.combine(upper: (context.readIfPresent(for: \.fileCreationTime?.upperHalf) ?? 0) & 0b11, lower: context.readIfPresent(for: \.fileCreationTime?.lowerHalf))
        version = try UInt64.combine(upper: context.readIfPresent(for: \.version.upperHalf) ?? 0, lower: context.readIfPresent(for: \.version.lowerHalf) ?? 0)
        projectID = try context.readIfPresent(for: \.projectID)
    }
    
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
    
    var mode: Mode
    var uid: UInt32
    var size: UInt64
    /// Last access time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var lastAccessTime: UInt64
    /// Last inode change time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var lastInodeChangeTime: UInt64
    /// Last data modification time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var lastDataModifyTime: UInt64
    var deletionTime: UInt32
    var gid: UInt32
    /// Hard link count.
    ///
    /// Normally, ext4 does not permit an inode to have more than 65,000 hard links. This applies to files as well as directories, which means that there cannot be more than 64,998 subdirectories in a directory (each subdirectory’s `..` entry counts as a hard link, as does the `.` entry in the directory itself). With the `DIR_NLINK` feature enabled, ext4 supports more than 64,998 subdirectories by setting this field to 1 to indicate that the number of hard links is not known.
    var hardLinkCount: UInt16
    var blockCount: UInt64
    var flags: Flags
    var osd: UInt32
    var block: InlineArray<15, UInt32>
    var generation: UInt32
    var xattrBlock: UInt64
    /// Obsolete.
    var fragmentAddress: UInt32
    var osd2: InlineArray<6, UInt16>
    /// The amount of space, in bytes, that this inode occupies past the original ext2 inode size (128 bytes), including this field.
    var extraINodeSize: UInt16
    var upperChecksum: UInt16?
    var fileCreationTime: UInt64?
    var version: UInt64
    var projectID: UInt32?
    
    var filetype: FSItem.ItemType {
        get throws {
            // cases must be in descending order of value because they are mutually exclusive but can still overlap
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
    
    /// Get attributes for the file based on this index node.
    /// 
    /// The following attributes can't be found based purely on the index node: `fileID` and `parentID`.
    /// - Parameter request: The attributes requested.
    /// - Parameter superblock: The superblock of the filesystem.
    /// - Parameter readOnlySystem: Whether the file system is mounted read-only.
    /// - Returns: The requested attributes, minus those stated above.
    func getAttributes(_ request: FSItem.GetAttributesRequest, superblock: Superblock, readOnlySystem: Bool = false) -> FSItem.Attributes {
        let attributes = FSItem.Attributes()
        
        // FIXME: many of these need to properly handle the upper values
        if request.isAttributeWanted(.uid) {
            attributes.uid = UInt32(uid)
        }
        if request.isAttributeWanted(.gid) {
            attributes.gid = UInt32(gid)
        }
        if request.isAttributeWanted(.mode) {
            // FIXME: not correct way to enforce read-only file system but does FSKit currently have a better way?
            let useMode = readOnlySystem ? mode.subtracting([.ownerWrite, .groupWrite, .otherWrite]) : mode
            attributes.mode = UInt32(useMode.rawValue)
        }
        if request.isAttributeWanted(.flags) {
            let fileFlags = flags
            var flags: UInt32 = 0
            if fileFlags.contains(.noDump) { flags |= UInt32(UF_NODUMP) }
            if fileFlags.contains(.immutable) { flags |= UInt32(SF_IMMUTABLE | UF_IMMUTABLE) }
            if fileFlags.contains(.appendOnly) { flags |= UInt32(SF_APPEND | UF_APPEND) }
            // no OPAQUE
            if fileFlags.contains(.compressed) { flags |= UInt32(UF_COMPRESSED) }
            // no TRACKED
            // no DATAVAULT
            // no HIDDEN
            attributes.flags = flags
        }
        if request.isAttributeWanted(.type) {
            attributes.type = (try? filetype) ?? .unknown
        }
        if request.isAttributeWanted(.size) {
            attributes.size = UInt64(size)
        }
        if request.isAttributeWanted(.allocSize) {
            let usesHugeBlocks = superblock.readonlyFeatureCompatibilityFlags.contains(.hugeFile) && flags.contains(.hugeFile)
            attributes.allocSize = (UInt64(blockCount) * UInt64(usesHugeBlocks ? superblock.blockSize : 512))
        }
        if request.isAttributeWanted(.inhibitKernelOffloadedIO) {
            attributes.inhibitKernelOffloadedIO = false
        }
        if request.isAttributeWanted(.accessTime) {
            attributes.accessTime = timespec(tv_sec: Int(lastAccessTime), tv_nsec: 0)
        }
        if request.isAttributeWanted(.changeTime) {
            attributes.changeTime = timespec(tv_sec: Int(lastInodeChangeTime), tv_nsec: 0)
        }
        if request.isAttributeWanted(.modifyTime) {
            attributes.modifyTime = timespec(tv_sec: Int(lastDataModifyTime), tv_nsec: 0)
        }
        if request.isAttributeWanted(.birthTime) {
            attributes.birthTime = timespec(tv_sec: Int(fileCreationTime ?? 0), tv_nsec: 0)
        }
        if request.isAttributeWanted(.addedTime) {
            // TODO: proper implementation
            attributes.addedTime = timespec()
        }
        if request.isAttributeWanted(.linkCount) {
            attributes.linkCount = UInt32(hardLinkCount)
        }
        
        return attributes
    }
}
