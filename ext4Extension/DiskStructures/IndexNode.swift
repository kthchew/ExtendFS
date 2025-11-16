//
//  IndexNode.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 7/31/25.
//

import Foundation
import FSKit
import os.log

struct IndexNode {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "IndexNode")
    
    struct Osd2 {
        var blockCountUpper: UInt16 = 0
        var extAttrBlockUpper: UInt16 = 0
        var uidUpper: UInt16 = 0
        var gidUpper: UInt16 = 0
        var checksumLower: UInt16 = 0
        var modeUpper: UInt16 = 0
        var author: UInt32 = 0
        
        init?(from data: Data, creator: Superblock.FilesystemCreator) {
            var iterator = data.makeIterator()
            
            switch creator {
            case .linux:
                guard let blockCountUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.blockCountUpper = blockCountUpper
                guard let extAttrBlockUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.extAttrBlockUpper = extAttrBlockUpper
                guard let uidUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.uidUpper = uidUpper
                guard let gidUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.gidUpper = gidUpper
                guard let checksumLower: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.checksumLower = checksumLower
            case .hurd:
                guard let _: UInt16 = iterator.nextLittleEndian() else { return nil }
                guard let modeUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.modeUpper = modeUpper
                guard let uidUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.uidUpper = uidUpper
                guard let gidUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.gidUpper = gidUpper
                guard let author: UInt32 = iterator.nextLittleEndian() else { return nil }
                self.author = author
            case .masix:
                guard let _: UInt16 = iterator.nextLittleEndian() else { return nil }
                guard let extAttrBlockUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
                self.extAttrBlockUpper = extAttrBlockUpper
            case .freeBSD:
                return nil
            case .lites:
                return nil
            case .unknown:
                return nil
            }
        }
    }
    
    init?(from data: Data, creator: Superblock.FilesystemCreator) {
        var iterator = data.makeIterator()
        
        guard let modeRaw: UInt16 = iterator.nextLittleEndian() else { return nil }
        guard let uidLower: UInt16 = iterator.nextLittleEndian() else { return nil }
        guard let sizeLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let accessLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let changeLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let modifyLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let deletion: UInt32 = iterator.nextLittleEndian() else { return nil }
        // unlike the other times, deletion time is not widened to 64 bits
        self.deletionTime = timespec(tv_sec: __darwin_time_t(deletion), tv_nsec: 0)
        guard let gidLower: UInt16 = iterator.nextLittleEndian() else { return nil }
        guard let hardLinks: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.hardLinkCount = hardLinks
        guard let blockCountLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let flags: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.flags = Flags(rawValue: flags)
        guard let osd: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.osd = osd
        
        block = Data(capacity: 60)
        for _ in 0..<60 {
            guard let next = iterator.next() else { return nil }
            block.append(next)
        }
        
        guard let generation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.generation = generation
        guard let xattrLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let sizeUpper: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.size = UInt64.combine(upper: sizeUpper, lower: sizeLower)
        guard let fragmentAddress: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.fragmentAddress = fragmentAddress
        
        var osd2Data = Data(capacity: 12)
        for _ in 0..<12 {
            guard let next = iterator.next() else { return nil }
            osd2Data.append(next)
        }
        if let osd2 = Osd2(from: osd2Data, creator: creator) {
            self.osd2 = osd2
        }
        self.blockCount = UInt64.combine(upper: osd2?.blockCountUpper ?? 0, lower: blockCountLower)
        self.uid = UInt32.combine(upper: osd2?.uidUpper ?? 0, lower: uidLower)
        self.gid = UInt32.combine(upper: osd2?.gidUpper ?? 0, lower: gidLower)
        self.xattrBlock = UInt64.combine(upper: osd2?.extAttrBlockUpper ?? 0, lower: xattrLower)
        self.mode = Mode(rawValue: UInt32.combine(upper: osd2?.modeUpper ?? 0, lower: modeRaw))
        
        self.extraINodeSize = iterator.nextLittleEndian() ?? 0
        if extraINodeSize >= 4 {
            upperChecksum = iterator.nextLittleEndian()
        }
        
        // in these cases, upper half only uses the lowest 2 bits, then uses the other 30 bits for nanosecond accuracy
        let changeUpper: UInt32? = extraINodeSize >= 8 ? iterator.nextLittleEndian() : nil
        self.lastInodeChangeTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (changeUpper ?? 0) & 0b11, lower: changeLower)), tv_nsec: Int(changeUpper ?? 0) >> 2)
        let modifyUpper: UInt32? = extraINodeSize >= 12 ? iterator.nextLittleEndian() : nil
        self.lastDataModifyTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (modifyUpper ?? 0) & 0b11, lower: modifyLower)), tv_nsec: Int(modifyUpper ?? 0) >> 2)
        let accessUpper: UInt32? = extraINodeSize >= 16 ? iterator.nextLittleEndian() : nil
        self.lastAccessTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (accessUpper ?? 0) & 0b11, lower: accessLower)), tv_nsec: Int(accessUpper ?? 0) >> 2)
        let creationLower: UInt32? = extraINodeSize >= 20 ? iterator.nextLittleEndian() : nil
        let creationUpper: UInt32? = extraINodeSize >= 24 ? iterator.nextLittleEndian() : nil
        if let creationLower {
            self.fileCreationTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (creationUpper ?? 0) & 0b11, lower: creationLower)), tv_nsec: Int(creationUpper ?? 0) >> 2)
        }
        let versionUpper: UInt32? = extraINodeSize >= 32 ? iterator.nextLittleEndian() : nil
        // FIXME: completely wrong
        self.version = UInt64(versionUpper ?? 0)
        self.projectID = extraINodeSize >= 32 ? iterator.nextLittleEndian() : nil
        
        var possibleExtAttr = data.advanced(by: 128 + Int(extraINodeSize))
        guard possibleExtAttr.count >= 4 else { return }
        let magic: UInt32 = possibleExtAttr.readLittleEndian(at: 0)
        guard magic == 0xEA020000 else { return }
        
        possibleExtAttr = possibleExtAttr.advanced(by: 4)
        self.embeddedExtendedAttributes = []
        var totalAdvance = 0
        while !possibleExtAttr.isEmpty {
            guard let entry = ExtendedAttrEntry(from: possibleExtAttr) else { break }
            guard entry.nameLength != 0 || entry.namePrefix.rawValue != 0 || entry.valueOffset != 0 || entry.valueInodeNumber != 0 else {
                break
            }
            
            embeddedExtendedAttributes?.append(entry)
            let advance = (16 + Int(entry.nameLength)).roundUp(toMultipleOf: 4)
            totalAdvance += advance
            possibleExtAttr = possibleExtAttr.advanced(by: advance)
        }
        self.embeddedXattrEntryBytes = UInt16(totalAdvance)
        self.remainingData = possibleExtAttr
    }
    
    struct Mode: OptionSet {
        let rawValue: UInt32
        
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
    /// Last access time, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var lastAccessTime: timespec
    /// Last inode change time, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var lastInodeChangeTime: timespec
    /// Last data modification time, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var lastDataModifyTime: timespec
    var deletionTime: timespec
    var gid: UInt32
    /// Hard link count.
    ///
    /// Normally, ext4 does not permit an inode to have more than 65,000 hard links. This applies to files as well as directories, which means that there cannot be more than 64,998 subdirectories in a directory (each subdirectory’s `..` entry counts as a hard link, as does the `.` entry in the directory itself). With the `DIR_NLINK` feature enabled, ext4 supports more than 64,998 subdirectories by setting this field to 1 to indicate that the number of hard links is not known.
    var hardLinkCount: UInt16
    var blockCount: UInt64
    var flags: Flags
    var osd: UInt32
    var block: Data
    var generation: UInt32
    var xattrBlock: UInt64
    /// Obsolete.
    var fragmentAddress: UInt32
    var osd2: Osd2?
    /// The amount of space, in bytes, that this inode occupies past the original ext2 inode size (128 bytes), including this field.
    var extraINodeSize: UInt16
    var upperChecksum: UInt16?
    var fileCreationTime: timespec?
    var version: UInt64
    var projectID: UInt32?
    
    var embeddedExtendedAttributes: [ExtendedAttrEntry]?
    var embeddedXattrEntryBytes: UInt16 = 0
    var remainingData: Data = Data()
    
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
            attributes.accessTime = lastAccessTime
        }
        if request.isAttributeWanted(.changeTime) {
            attributes.changeTime = lastInodeChangeTime
        }
        if request.isAttributeWanted(.modifyTime) {
            attributes.modifyTime = lastDataModifyTime
        }
        if request.isAttributeWanted(.birthTime) {
            attributes.birthTime = fileCreationTime ?? timespec(tv_sec: 0, tv_nsec: 0)
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
