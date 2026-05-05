// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import os.log

public struct IndexNode {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "IndexNode")
    
    public struct Osd2 {
        public var blockCountUpper: UInt16 = 0
        public var extAttrBlockUpper: UInt16 = 0
        public var uidUpper: UInt16 = 0
        public var gidUpper: UInt16 = 0
        public var checksumLower: UInt16 = 0
        public var modeUpper: UInt16 = 0
        public var author: UInt32 = 0
        
        init?(from data: Data, creator: Superblock.FilesystemCreator) {
            var offset = 0
            func nextLE<T: FixedWidthInteger>() -> T? {
                try? data.readLittleEndian(at: &offset)
            }
            
            switch creator {
            case .linux:
                guard let blockCountUpper: UInt16 = nextLE() else { return nil }
                self.blockCountUpper = blockCountUpper
                guard let extAttrBlockUpper: UInt16 = nextLE() else { return nil }
                self.extAttrBlockUpper = extAttrBlockUpper
                guard let uidUpper: UInt16 = nextLE() else { return nil }
                self.uidUpper = uidUpper
                guard let gidUpper: UInt16 = nextLE() else { return nil }
                self.gidUpper = gidUpper
                guard let checksumLower: UInt16 = nextLE() else { return nil }
                self.checksumLower = checksumLower
            case .hurd:
                guard let _: UInt16 = nextLE() else { return nil }
                guard let modeUpper: UInt16 = nextLE() else { return nil }
                self.modeUpper = modeUpper
                guard let uidUpper: UInt16 = nextLE() else { return nil }
                self.uidUpper = uidUpper
                guard let gidUpper: UInt16 = nextLE() else { return nil }
                self.gidUpper = gidUpper
                guard let author: UInt32 = nextLE() else { return nil }
                self.author = author
            case .masix:
                guard let _: UInt16 = nextLE() else { return nil }
                guard let extAttrBlockUpper: UInt16 = nextLE() else { return nil }
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
    
    init() {
        self.inodeNumber = 0
        self.mode = Mode()
        self.uid = 0
        self.size = 0
        self.lastAccessTime = timespec()
        self.lastInodeChangeTime = timespec()
        self.lastDataModifyTime = timespec()
        self.deletionTime = timespec()
        self.gid = 0
        self.hardLinkCount = 0
        self.blockCount = 0
        self.flags = Flags()
        self.osd = 0
        self.block = Data()
        self.generation = 0
        self.xattrBlock = 0
        self.fragmentAddress = 0
        self.extraINodeSize = 0
        self.version = 0
        self.metadataChecksumSeed = nil
    }
    
    init?(from data: Data, creator: Superblock.FilesystemCreator, inodeNumber: UInt32, fsMetadataSeed: UInt32?) {
        self.inodeNumber = inodeNumber
        
        var offset = 0
        func nextLE<T: FixedWidthInteger>() -> T? {
            try? data.readLittleEndian(at: &offset)
        }
        func nextSection(length: Int) -> Data? {
            try? data.readSection(at: &offset, length: length)
        }
        
        guard let modeRaw: UInt16 = nextLE() else { return nil }
        guard let uidLower: UInt16 = nextLE() else { return nil }
        guard let sizeLower: UInt32 = nextLE() else { return nil }
        guard let accessLower: UInt32 = nextLE() else { return nil }
        guard let changeLower: UInt32 = nextLE() else { return nil }
        guard let modifyLower: UInt32 = nextLE() else { return nil }
        guard let deletion: UInt32 = nextLE() else { return nil }
        // unlike the other times, deletion time is not widened to 64 bits
        self.deletionTime = timespec(tv_sec: __darwin_time_t(deletion), tv_nsec: 0)
        guard let gidLower: UInt16 = nextLE() else { return nil }
        guard let hardLinks: UInt16 = nextLE() else { return nil }
        self.hardLinkCount = hardLinks
        guard let blockCountLower: UInt32 = nextLE() else { return nil }
        guard let flags: UInt32 = nextLE() else { return nil }
        self.flags = Flags(rawValue: flags)
        guard let osd: UInt32 = nextLE() else { return nil }
        self.osd = osd
        
        guard let block = nextSection(length: 60) else { return nil }
        self.block = block
        
        guard let generation: UInt32 = nextLE() else { return nil }
        self.generation = generation
        if let fsMetadataSeed {
            var seedCsumData = Data()
            seedCsumData.appendLittleEndian(inodeNumber)
            seedCsumData.appendLittleEndian(generation)
            self.metadataChecksumSeed = seedCsumData.crc32c(seed: fsMetadataSeed)
        } else {
            self.metadataChecksumSeed = nil
        }
        guard let xattrLower: UInt32 = nextLE() else { return nil }
        guard let sizeUpper: UInt32 = nextLE() else { return nil }
        self.size = UInt64.combine(upper: sizeUpper, lower: sizeLower)
        guard let fragmentAddress: UInt32 = nextLE() else { return nil }
        self.fragmentAddress = fragmentAddress
        
        guard let osd2Data = nextSection(length: 12) else { return nil }
        if let osd2 = Osd2(from: osd2Data, creator: creator) {
            self.osd2 = osd2
        }
        self.blockCount = UInt64.combine(upper: osd2?.blockCountUpper ?? 0, lower: blockCountLower)
        self.uid = UInt32.combine(upper: osd2?.uidUpper ?? 0, lower: uidLower)
        self.gid = UInt32.combine(upper: osd2?.gidUpper ?? 0, lower: gidLower)
        self.xattrBlock = UInt64.combine(upper: osd2?.extAttrBlockUpper ?? 0, lower: xattrLower)
        self.mode = Mode(rawValue: UInt32.combine(upper: osd2?.modeUpper ?? 0, lower: modeRaw))
        
        self.extraINodeSize = nextLE() ?? 0
        if extraINodeSize >= 4 {
            upperChecksum = nextLE()
        }
        
        // in these cases, upper half only uses the lowest 2 bits, then uses the other 30 bits for nanosecond accuracy
        let changeUpper: UInt32? = extraINodeSize >= 8 ? nextLE() : nil
        self.lastInodeChangeTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (changeUpper ?? 0) & 0b11, lower: changeLower)), tv_nsec: Int(changeUpper ?? 0) >> 2)
        let modifyUpper: UInt32? = extraINodeSize >= 12 ? nextLE() : nil
        self.lastDataModifyTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (modifyUpper ?? 0) & 0b11, lower: modifyLower)), tv_nsec: Int(modifyUpper ?? 0) >> 2)
        let accessUpper: UInt32? = extraINodeSize >= 16 ? nextLE() : nil
        self.lastAccessTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (accessUpper ?? 0) & 0b11, lower: accessLower)), tv_nsec: Int(accessUpper ?? 0) >> 2)
        let creationLower: UInt32? = extraINodeSize >= 20 ? nextLE() : nil
        let creationUpper: UInt32? = extraINodeSize >= 24 ? nextLE() : nil
        if let creationLower {
            self.fileCreationTime = timespec(tv_sec: __darwin_time_t(UInt64.combine(upper: (creationUpper ?? 0) & 0b11, lower: creationLower)), tv_nsec: Int(creationUpper ?? 0) >> 2)
        }
        let versionUpper: UInt32? = extraINodeSize >= 32 ? nextLE() : nil
        // FIXME: completely wrong
        self.version = UInt64(versionUpper ?? 0)
        self.projectID = extraINodeSize >= 32 ? nextLE() : nil
        
        var possibleExtAttr = data.advanced(by: 128 + Int(extraINodeSize))
        guard possibleExtAttr.count >= 4 else { return }
        let magic: UInt32 = (try? possibleExtAttr.readLittleEndian(at: 0)) ?? 0
        guard magic == 0xEA020000 else { return }
        
        possibleExtAttr = possibleExtAttr.advanced(by: 4)
        self.embeddedExtendedAttributes = []
        var totalAdvance = 0
        while !possibleExtAttr.isEmpty {
            guard let entry = ExtendedAttrEntry(from: possibleExtAttr) else { break }
            guard entry.nameLength != 0 || entry.namePrefix.rawValue != 0 || entry.valueOffset != 0 else {
                possibleExtAttr = possibleExtAttr.advanced(by: 4)
                totalAdvance += 4
                break
            }
            
            embeddedExtendedAttributes?.append(entry)
            let advance = (16 + Int(entry.nameLength)).roundUp(toMultipleOf: 4)
            totalAdvance += advance
            possibleExtAttr = possibleExtAttr.advanced(by: advance)
        }
        guard let embeddedByteCount = UInt16(exactly: totalAdvance) else {
            Self.logger.error("Embedded byte count can't fit in a 16-bit integer. This should not happen for a well-formed inode.")
            return nil
        }
        self.embeddedXattrEntryBytes = embeddedByteCount
        self.remainingData = possibleExtAttr
    }
    
    public struct Mode: OptionSet {
        public let rawValue: UInt32
        
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static public let otherExecute = Mode(rawValue: 1 << 0)
        static public let otherWrite = Mode(rawValue: 1 << 1)
        static public let otherRead = Mode(rawValue: 1 << 2)
        static public let groupExecute = Mode(rawValue: 1 << 3)
        static public let groupWrite = Mode(rawValue: 1 << 4)
        static public let groupRead = Mode(rawValue: 1 << 5)
        static public let ownerExecute = Mode(rawValue: 1 << 6)
        static public let ownerWrite = Mode(rawValue: 1 << 7)
        static public let ownerRead = Mode(rawValue: 1 << 8)
        static public let sticky = Mode(rawValue: 1 << 9)
        static public let setGID = Mode(rawValue: 1 << 10)
        static public let setUID = Mode(rawValue: 1 << 11)
        
        // MARK: - Mutually exclusive file types
        static public let fifoType = Mode(rawValue: 0x1000)
        static public let characterDeviceType = Mode(rawValue: 0x2000)
        static public let directoryType = Mode(rawValue: 0x4000)
        static public let blockDeviceType = Mode(rawValue: 0x6000)
        static public let regularFileType = Mode(rawValue: 0x8000)
        static public let symbolicLinkType = Mode(rawValue: 0xA000)
        static public let socketType = Mode(rawValue: 0xC000)
    }
    public struct Flags: OptionSet {
        public let rawValue: UInt32
        
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static public let requiresSecureDeletion = Flags(rawValue: 1 << 0)
        static public let shouldPreserve = Flags(rawValue: 1 << 1)
        static public let compressed = Flags(rawValue: 1 << 2)
        static public let allWritesAreSynchronous = Flags(rawValue: 1 << 3)
        static public let immutable = Flags(rawValue: 1 << 4)
        static public let appendOnly = Flags(rawValue: 1 << 5)
        static public let noDump = Flags(rawValue: 1 << 6)
        static public let noAccessTime = Flags(rawValue: 1 << 7)
        static public let dirtyCompressedFile = Flags(rawValue: 1 << 8)
        static public let hasCompressedClusters = Flags(rawValue: 1 << 9)
        static public let doNotCompress = Flags(rawValue: 1 << 10)
        static public let encrypted = Flags(rawValue: 1 << 11)
        /// This is a directory, and has hashed indices (is a hash tree directory).
        static public let hashedIndices = Flags(rawValue: 1 << 12)
        static public let afsMagicDirectory = Flags(rawValue: 1 << 13)
        static public let writeFileDataThroughJournal = Flags(rawValue: 1 << 14)
        static public let tailMustNotBeMerged = Flags(rawValue: 1 << 15)
        static public let directoryEntryDataWritesAreSynchronoous = Flags(rawValue: 1 << 16)
        static public let topOfDirectoryHierarchy = Flags(rawValue: 1 << 17)
        static public let hugeFile = Flags(rawValue: 1 << 18)
        static public let usesExtents = Flags(rawValue: 1 << 19)
        static public let largeXattrInDataBlocks = Flags(rawValue: 0x200000)
        static public let blocksAllocatedPastEOF = Flags(rawValue: 0x400000)
        static public let isSnapshot = Flags(rawValue: 0x01000000)
        static public let snapshotIsBeingDeleted = Flags(rawValue: 0x04000000)
        static public let snapshotShrinkCompleted = Flags(rawValue: 0x08000000)
        static public let inodeHasInlineData = Flags(rawValue: 0x10000000)
        static public let createChildrenWithSameProjectID = Flags(rawValue: 0x20000000)
        static public let caseInsensitiveDirectoryContents = Flags(rawValue: 0x40000000)
        static public let reserved = Flags(rawValue: 0x80000000)
        
        static public let aggregateUserVisibleMask = Flags(rawValue: 0x4BDFFF)
        static public let aggregateUserModifiableMask = Flags(rawValue: 0x4B80FF)
    }
    
    public let inodeNumber: UInt32
    
    public var mode: Mode
    public var uid: UInt32
    public var size: UInt64
    /// Last access time, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    public var lastAccessTime: timespec
    /// Last inode change time, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    public var lastInodeChangeTime: timespec
    /// Last data modification time, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    public var lastDataModifyTime: timespec
    public var deletionTime: timespec
    public var gid: UInt32
    /// Hard link count.
    ///
    /// Normally, ext4 does not permit an inode to have more than 65,000 hard links. This applies to files as well as directories, which means that there cannot be more than 64,998 subdirectories in a directory (each subdirectory’s `..` entry counts as a hard link, as does the `.` entry in the directory itself). With the `DIR_NLINK` feature enabled, ext4 supports more than 64,998 subdirectories by setting this field to 1 to indicate that the number of hard links is not known.
    public var hardLinkCount: UInt16
    public var blockCount: UInt64
    public var flags: Flags
    public var osd: UInt32
    public var block: Data
    public var generation: UInt32
    public var xattrBlock: UInt64
    /// Obsolete.
    public var fragmentAddress: UInt32
    public var osd2: Osd2?
    /// The amount of space, in bytes, that this inode occupies past the original ext2 inode size (128 bytes), including this field.
    public var extraINodeSize: UInt16
    public var upperChecksum: UInt16?
    public var fileCreationTime: timespec?
    public var version: UInt64
    public var projectID: UInt32?
    
    var embeddedExtendedAttributes: [ExtendedAttrEntry]?
    public var embeddedXattrEntryBytes: UInt16 = 0
    public var remainingData: Data = Data()
    
    /// A value to use as the metadata checksum seed for data structures that use this inode's number and generation as part of the input.
    ///
    /// If the volume doesn't support metadata checksumming, this will be `nil`.
    public let metadataChecksumSeed: UInt32?
    
    public var filetype: FSItem.ItemType {
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
    public func getAttributes(_ request: FSItem.GetAttributesRequest, superblock: Superblock, readOnlySystem: Bool = false) -> FSItem.Attributes {
        let attributes = FSItem.Attributes()
        
        if request.isAttributeWanted(.uid) {
            attributes.uid = uid
        }
        if request.isAttributeWanted(.gid) {
            attributes.gid = gid
        }
        if request.isAttributeWanted(.mode) {
            // FIXME: not correct way to enforce read-only file system but does FSKit currently have a better way?
            let useMode = readOnlySystem ? mode.subtracting([.ownerWrite, .groupWrite, .otherWrite]) : mode
            attributes.mode = useMode.rawValue
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
            attributes.size = size
        }
        if request.isAttributeWanted(.allocSize) {
            let usesHugeBlocks = superblock.readOnlyCompatibleFeatures.contains(.hugeFile) && flags.contains(.hugeFile)
            attributes.allocSize = (blockCount * UInt64(usesHugeBlocks ? superblock.blockSize : 512))
        }

        // Gating behind isAttributeWanted causes this to never work
        // Kernel offloaded IO does not work here because inline data is not sector aligned
        attributes.inhibitKernelOffloadedIO = flags.contains(.inodeHasInlineData)
        
        if request.isAttributeWanted(.supportsLimitedXAttrs) {
            attributes.supportsLimitedXAttrs = false
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
            // not supported by ext
            attributes.addedTime = timespec(tv_sec: 0, tv_nsec: 0)
        }
        if request.isAttributeWanted(.linkCount) {
            attributes.linkCount = UInt32(hardLinkCount)
        }
        
        return attributes
    }
}
