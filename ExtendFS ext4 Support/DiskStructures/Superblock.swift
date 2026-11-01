// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Superblock")

public struct Superblock {
    public init?(from data: Data) {
        var offset = 0
        func nextLE<T: FixedWidthInteger>() -> T? {
            try? data.readLittleEndian(at: &offset)
        }
        func nextUUID() -> UUID? {
            try? data.readUUID(at: &offset)
        }
        func nextString(maxLength: Int) -> String? {
            try? data.readString(at: &offset, maxLength: maxLength)
        }
        func nextSection(length: Int) -> Data? {
            try? data.readSection(at: &offset, length: length)
        }
        
        guard let inodeCount: UInt32 = nextLE() else { return nil }
        self.inodeCount = inodeCount
        guard let blockCountLow: UInt32 = nextLE() else { return nil }
        guard let superUserBlockCountLow: UInt32 = nextLE() else { return nil }
        guard let freeBlockCountLow: UInt32 = nextLE() else { return nil }
        guard let freeInodeCount: UInt32 = nextLE() else { return nil }
        self.freeInodeCount = freeInodeCount
        guard let firstDataBlock: UInt32 = nextLE() else { return nil }
        self.firstDataBlock = firstDataBlock
        guard let logBlockSize: UInt32 = nextLE() else { return nil }
        self.logBlockSize = logBlockSize
        guard let logClusterSize: UInt32 = nextLE() else { return nil }
        self.logClusterSize = logClusterSize
        guard let blocksPerGroup: UInt32 = nextLE() else { return nil }
        self.blocksPerGroup = blocksPerGroup
        guard let clustersPerGroup: UInt32 = nextLE() else { return nil }
        self.clustersPerGroup = clustersPerGroup
        guard let inodesPerGroup: UInt32 = nextLE() else { return nil }
        self.inodesPerGroup = inodesPerGroup
        guard let mountTimeLow: UInt32 = nextLE() else { return nil }
        self.mountTime = UInt64(mountTimeLow)
        guard let writeTimeLow: UInt32 = nextLE() else { return nil }
        self.writeTime = UInt64(writeTimeLow)
        guard let mountsSinceLastFsck: UInt16 = nextLE() else { return nil }
        self.mountsSinceLastFsck = mountsSinceLastFsck
        guard let maxMountsSinceLastFsck: UInt16 = nextLE() else { return nil }
        self.maxMountsSinceLastFsck = maxMountsSinceLastFsck
        guard let magic: UInt16 = nextLE(), magic == 0xEF53 else { return nil }
        self.magic = magic
        guard let state: UInt16 = nextLE() else { return nil }
        self.state = State(rawValue: state)
        guard let errorPolicy: UInt16 = nextLE() else { return nil }
        self.errorPolicy = ErrorPolicy(rawValue: errorPolicy) ?? .unknown
        guard let minorRevisionLevel: UInt16 = nextLE() else { return nil }
        self.minorRevisionLevel = minorRevisionLevel
        guard let lastCheckTime: UInt32 = nextLE() else { return nil }
        self.lastCheckTime = lastCheckTime
        guard let maxSecondsBetweenChecks: UInt32 = nextLE() else { return nil }
        self.maxSecondsBetweenChecks = maxSecondsBetweenChecks
        guard let creatorOS: UInt32 = nextLE() else { return nil }
        self.creatorOS = FilesystemCreator(rawValue: creatorOS) ?? .unknown
        guard let revisionLevelRaw: UInt32 = nextLE() else { return nil }
        let revisionLevel = Revision(rawValue: revisionLevelRaw) ?? .unknown
        self.revisionLevel = revisionLevel
        guard let defaultUidForReservedBlocks: UInt16 = nextLE() else { return nil }
        self.defaultUidForReservedBlocks = defaultUidForReservedBlocks
        guard let defaultGidForReservedBlocks: UInt16 = nextLE() else { return nil }
        self.defaultGidForReservedBlocks = defaultGidForReservedBlocks

        // MARK: - EXT4_DYNAMIC_REV fields
        let revisionSupportsDynamicInodeSizes = revisionLevel != .unknown && revisionLevel >= Revision.version2
        if !revisionSupportsDynamicInodeSizes {
            self.blockCount = UInt64(blockCountLow)
            self.superUserBlockCount = UInt64(superUserBlockCountLow)
            self.freeBlockCount = UInt64(freeBlockCountLow)
            
            self.firstNonReservedInode = 11
            self.inodeSize = 128
            self.compatibleFeatures = CompatibleFeatures()
            self.incompatibleFeatures = IncompatibleFeatures()
            self.readOnlyCompatibleFeatures = ReadOnlyCompatibleFeatures()
            return
        }
        guard let firstNonReservedInode: UInt32 = nextLE() else { return nil }
        self.firstNonReservedInode = firstNonReservedInode
        guard let inodeSize: UInt16 = nextLE() else { return nil }
        self.inodeSize = inodeSize
        guard let blockGroupNumber: UInt16 = nextLE() else { return nil }
        self.blockGroupNumber = blockGroupNumber
        guard let compatibleFeaturesRaw: UInt32 = nextLE() else { return nil }
        let compatibleFeatures = CompatibleFeatures(rawValue: compatibleFeaturesRaw)
        self.compatibleFeatures = compatibleFeatures
        guard let incompatibleFeaturesRaw: UInt32 = nextLE() else { return nil }
        let incompatibleFeatures = IncompatibleFeatures(rawValue: incompatibleFeaturesRaw)
        self.incompatibleFeatures = incompatibleFeatures
        guard let readOnlyCompatibleFeaturesRaw: UInt32 = nextLE() else { return nil }
        let readOnlyCompatibleFeatures = ReadOnlyCompatibleFeatures(rawValue: readOnlyCompatibleFeaturesRaw)
        self.readOnlyCompatibleFeatures = readOnlyCompatibleFeatures

        guard let uuid = nextUUID() else { return nil }
        self.uuid = uuid

        guard let volumeName = nextSection(length: 16) else { return nil }
        self.volumeName = volumeName

        guard let lastMountDirectory = nextSection(length: 64) else { return nil }
        self.lastMountDirectory = lastMountDirectory

        guard let compressionAlgorithmUsageBitmap: UInt32 = nextLE() else { return nil }
        self.compressionAlgorithmUsageBitmap = compressionAlgorithmUsageBitmap
        
        // MARK: - Performance hints
        guard let preallocateBlocks: UInt8 = nextLE() else { return nil }
        guard let preallocateDirectoryBlocks: UInt8 = nextLE() else { return nil }
        if compatibleFeatures.contains(.directoryPreallocation) {
            self.preallocateBlocks = preallocateBlocks
            self.preallocateDirectoryBlocks = preallocateDirectoryBlocks
        }
        guard let reservedGDTBlocks: UInt16 = nextLE() else { return nil }
        self.reservedGDTBlocks = reservedGDTBlocks
        
        guard let journalUUID = nextUUID() else { return nil }
        guard let journalInodeNumber: UInt32 = nextLE() else { return nil }
        guard let journalDeviceNumber: UInt32 = nextLE() else { return nil }
        if compatibleFeatures.contains(.journal) {
            self.journalUUID = journalUUID
            self.journalInodeNumber = journalInodeNumber
            self.journalDeviceNumber = journalDeviceNumber
        }
        guard let lastOrphan: UInt32 = nextLE() else { return nil }
        self.lastOrphan = lastOrphan

        var hashSeed: [UInt32] = []
        hashSeed.reserveCapacity(4)
        for _ in 0..<4 {
            guard let v: UInt32 = nextLE() else { return nil }
            hashSeed.append(v)
        }
        self.hashSeed = hashSeed

        guard let defaultHashAlgorithmRaw: UInt8 = nextLE() else { return nil }
        let defaultHashAlgorithm = HashVersion(rawValue: defaultHashAlgorithmRaw) ?? .unknown
        self.defaultHashAlgorithm = defaultHashAlgorithm
        guard let journalBackupType: UInt8 = nextLE() else { return nil }
        if compatibleFeatures.contains(.journal) {
            self.journalBackupType = journalBackupType
        }
        guard let groupDescriptorSizeInBytes: UInt16 = nextLE() else { return nil }
        if incompatibleFeatures.contains(.enable64BitSize) {
            self.groupDescriptorSizeInBytes = groupDescriptorSizeInBytes
        }
        guard let defaultMountOptions: UInt32 = nextLE() else { return nil }
        self.defaultMountOptions = defaultMountOptions
        guard let firstMetablockBlockGroup: UInt32 = nextLE() else { return nil }
        if incompatibleFeatures.contains(.metaBlockGroups) {
            self.firstMetablockBlockGroup = firstMetablockBlockGroup
        }
        guard let mkfsTime: UInt32 = nextLE() else { return nil }
        self.mkfsTime = mkfsTime

        var backupJournalBlocks: [UInt32] = []
        backupJournalBlocks.reserveCapacity(17)
        for _ in 0..<17 {
            guard let v: UInt32 = nextLE() else { return nil }
            backupJournalBlocks.append(v)
        }
        self.backupJournalBlocks = backupJournalBlocks

        // MARK: - 64-bit support
        guard let blockCountHigh: UInt32 = nextLE() else { return nil }
        guard let superUserBlockCountHigh: UInt32 = nextLE() else { return nil }
        guard let freeBlockCountHigh: UInt32 = nextLE() else { return nil }
        if incompatibleFeatures.contains(.enable64BitSize) {
            self.blockCount = UInt64.combine(upper: blockCountHigh, lower: blockCountLow)
            self.superUserBlockCount = UInt64.combine(upper: superUserBlockCountHigh, lower: superUserBlockCountLow)
            self.freeBlockCount = UInt64.combine(upper: freeBlockCountHigh, lower: freeBlockCountLow)
        } else {
            self.blockCount = UInt64(blockCountLow)
            self.superUserBlockCount = UInt64(superUserBlockCountLow)
            self.freeBlockCount = UInt64(freeBlockCountLow)
        }
        guard let minimumExtraInodeSize: UInt16 = nextLE() else { return nil }
        self.minimumExtraInodeSize = minimumExtraInodeSize
        guard let wantExtraInodeSize: UInt16 = nextLE() else { return nil }
        self.wantExtraInodeSize = wantExtraInodeSize
        guard let flags: UInt32 = nextLE() else { return nil }
        self.flags = flags
        guard let raidStride: UInt16 = nextLE() else { return nil }
        self.raidStride = raidStride
        guard let mmpIntervalInSeconds: UInt16 = nextLE() else { return nil }
        self.mmpIntervalInSeconds = mmpIntervalInSeconds
        guard let mmpBlock: UInt64 = nextLE() else { return nil }
        self.mmpBlock = mmpBlock
        guard let raidStripeWidth: UInt32 = nextLE() else { return nil }
        self.raidStripeWidth = raidStripeWidth
        guard let logGroupsPerFlexibleGroup: UInt8 = nextLE() else { return nil }
        if incompatibleFeatures.contains(.flexibleBlockGroups) {
            self.logGroupsPerFlexibleGroup = logGroupsPerFlexibleGroup
        }
        guard let checksumType: UInt8 = nextLE() else { return nil }
        self.checksumType = checksumType
        guard let reservedPad: UInt16 = nextLE() else { return nil }
        self.reservedPad = reservedPad
        guard let kbytesWritten: UInt64 = nextLE() else { return nil }
        self.kbytesWritten = kbytesWritten
        guard let snapshotInodeNumber: UInt32 = nextLE() else { return nil }
        self.snapshotInodeNumber = snapshotInodeNumber
        guard let snapshotId: UInt32 = nextLE() else { return nil }
        self.snapshotId = snapshotId
        guard let snapshotReservedBlockCount: UInt64 = nextLE() else { return nil }
        self.snapshotReservedBlockCount = snapshotReservedBlockCount
        guard let snapshotListInodeNumber: UInt32 = nextLE() else { return nil }
        self.snapshotListInodeNumber = snapshotListInodeNumber

        guard let errorCount: UInt32 = nextLE() else { return nil }
        self.errorCount = errorCount
        guard let firstErrorTime: UInt32 = nextLE() else { return nil }
        self.firstErrorTime = firstErrorTime
        guard let firstErrorInode: UInt32 = nextLE() else { return nil }
        self.firstErrorInode = firstErrorInode
        guard let firstErrorBlock: UInt64 = nextLE() else { return nil }
        self.firstErrorBlock = firstErrorBlock
        guard let firstErrorFunctionName = nextString(maxLength: 32) else { return nil }
        self.firstErrorFunctionName = firstErrorFunctionName
        guard let firstErrorLineNumber: UInt32 = nextLE() else { return nil }
        self.firstErrorLineNumber = firstErrorLineNumber
        guard let lastErrorTime: UInt32 = nextLE() else { return nil }
        self.lastErrorTime = lastErrorTime
        guard let lastErrorInodeNumber: UInt32 = nextLE() else { return nil }
        self.lastErrorInodeNumber = lastErrorInodeNumber
        guard let lastErrorLine: UInt32 = nextLE() else { return nil }
        self.lastErrorLine = lastErrorLine
        guard let lastErrorBlock: UInt64 = nextLE() else { return nil }
        self.lastErrorBlock = lastErrorBlock
        guard let lastErrorFunctionName = nextString(maxLength: 32) else { return nil }
        self.lastErrorFunctionName = lastErrorFunctionName

        guard let mountOptions = nextString(maxLength: 64) else { return nil }
        self.mountOptions = mountOptions

        guard let userQuotaInode: UInt32 = nextLE() else { return nil }
        self.userQuotaInode = userQuotaInode
        guard let groupQuotaInode: UInt32 = nextLE() else { return nil }
        self.groupQuotaInode = groupQuotaInode
        guard let overheadBlocks: UInt32 = nextLE() else { return nil }
        self.overheadBlocks = overheadBlocks

        var superblockBackupGroups: [UInt32] = []
        superblockBackupGroups.reserveCapacity(2)
        for _ in 0..<2 {
            guard let v: UInt32 = nextLE() else { return nil }
            superblockBackupGroups.append(v)
        }
        self.superblockBackupGroups = superblockBackupGroups

        var encryptionAlgorithms: [UInt8] = []
        encryptionAlgorithms.reserveCapacity(4)
        for _ in 0..<4 {
            guard let b: UInt8 = nextLE() else { return nil }
            encryptionAlgorithms.append(b)
        }
        self.encryptionAlgorithms = encryptionAlgorithms

        var encryptionSalt: [UInt8] = []
        encryptionSalt.reserveCapacity(16)
        for _ in 0..<16 {
            guard let b: UInt8 = nextLE() else { return nil }
            encryptionSalt.append(b)
        }
        self.encryptionSalt = encryptionSalt

        guard let lostAndFoundInode: UInt32 = nextLE() else { return nil }
        self.lostAndFoundInode = lostAndFoundInode
        guard let projectQuotaInode: UInt32 = nextLE() else { return nil }
        self.projectQuotaInode = projectQuotaInode
        guard let checksumSeed: UInt32 = nextLE() else { return nil }
        self.checksumSeed = checksumSeed

        guard let writeTimeHigh: UInt8 = nextLE() else { return nil }
        self.writeTimeHigh = writeTimeHigh
        guard let mountTimeHigh: UInt8 = nextLE() else { return nil }
        self.mountTimeHigh = mountTimeHigh
        guard let mkfsTimeHigh: UInt8 = nextLE() else { return nil }
        self.mkfsTimeHigh = mkfsTimeHigh
        guard let lastCheckTimeHigh: UInt8 = nextLE() else { return nil }
        self.lastCheckTimeHigh = lastCheckTimeHigh
        guard let firstErrorTimeHigh: UInt8 = nextLE() else { return nil }
        self.firstErrorTimeHigh = firstErrorTimeHigh
        guard let lastErrorTimeHigh: UInt8 = nextLE() else { return nil }
        self.lastErrorTimeHigh = lastErrorTimeHigh
        
        var pad: [UInt8] = []
        pad.reserveCapacity(2)
        for _ in 0..<2 {
            guard let v: UInt8 = nextLE() else { return nil }
            pad.append(v)
        }
        self.pad = pad
        
        guard let encoding: UInt16 = nextLE() else { return nil }
        self.encoding = Encoding(rawValue: encoding)
        guard let encodingFlags: UInt16 = nextLE() else { return nil }
        self.encodingFlags = EncodingFlags(rawValue: encodingFlags)
        guard let orphanFileInodeNumber: UInt32 = nextLE() else { return nil }
        self.orphanFileInodeNumber = orphanFileInodeNumber

        // zero padding
        var reservedPadding: [UInt32] = []
        reservedPadding.reserveCapacity(94)
        for _ in 0..<94 {
            guard let v: UInt32 = nextLE() else { return nil }
            reservedPadding.append(v)
        }
        self.reservedPadding = reservedPadding

        guard let checksum: UInt32 = nextLE() else { return nil }
        self.checksum = checksum
    }
    
    public var initialData: Data?
    
    public init?(blockDevice: FSBlockDeviceResource, offset: Int64) throws {
        let superblockData = try BlockDeviceReader.fetchSuperblockData(from: blockDevice, at: offset)
        self.init(from: superblockData)
        self.initialData = superblockData
    }
    
    public struct State: OptionSet {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        
        public static let cleanlyUnmounted = Superblock.State(rawValue: 0x1)
        public static let errorsDetected = Superblock.State(rawValue: 0x2)
        public static let orphansBeingRecovered = Superblock.State(rawValue: 0x4)
    }
    
    public enum ErrorPolicy: UInt16 {
        case `continue` = 1
        case remountReadOnly = 2
        case panic = 3
        case unknown = 65535
    }
    
    public enum FilesystemCreator: UInt32 {
        case linux = 0
        case hurd = 1
        case masix = 2
        case freeBSD = 3
        case lites = 4
        case unknown = 4294967295
    }
    
    public enum Revision: UInt32, Comparable {
        public static func < (lhs: Superblock.Revision, rhs: Superblock.Revision) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        case original = 0
        /// Has dynamic inode sizes.
        case version2 = 1
        case unknown = 4294967295
    }
    
    public struct CompatibleFeatures: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        
        public static let directoryPreallocation = CompatibleFeatures(rawValue: 1 << 0)
        public static let imagicInodes = CompatibleFeatures(rawValue: 1 << 1)
        public static let journal = CompatibleFeatures(rawValue: 1 << 2)
        public static let extendedAttributes = CompatibleFeatures(rawValue: 1 << 3)
        /// Requires `sparseSuperBlockVersion2`.
        public static let reservedGDTBlocksForExpansion = CompatibleFeatures(rawValue: 1 << 4)
        public static let directoryIndices = CompatibleFeatures(rawValue: 1 << 5)
        public static let lazyBG = CompatibleFeatures(rawValue: 1 << 6)
        /// Not used.
        public static let excludeInode = CompatibleFeatures(rawValue: 1 << 7)
        public static let excludeBitmap = CompatibleFeatures(rawValue: 1 << 8)
        public static let sparseSuperBlockVersion2 = CompatibleFeatures(rawValue: 1 << 9)
        public static let fastCommits = CompatibleFeatures(rawValue: 0x400)
        public static let orphanFileAllocated = CompatibleFeatures(rawValue: 0x1000)
    }
    
    public struct IncompatibleFeatures: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        
        public static let compression = IncompatibleFeatures(rawValue: 0x1)
        /// Directory entries record the file type.
        public static let filetype = IncompatibleFeatures(rawValue: 0x2)
        public static let needsRecovery = IncompatibleFeatures(rawValue: 0x4)
        public static let separateJournalDevice = IncompatibleFeatures(rawValue: 0x8)
        public static let metaBlockGroups = IncompatibleFeatures(rawValue: 0x10)
        public static let extents = IncompatibleFeatures(rawValue: 0x40)
        public static let enable64BitSize = IncompatibleFeatures(rawValue: 0x80)
        public static let multipleMountProtection = IncompatibleFeatures(rawValue: 0x100)
        public static let flexibleBlockGroups = IncompatibleFeatures(rawValue: 0x200)
        public static let inodesCanStoreLargeExtendedAttributes = IncompatibleFeatures(rawValue: 0x400)
        public static let dataInDirEntry = IncompatibleFeatures(rawValue: 0x1000)
        public static let metadataChecksumSeedInSuperblock = IncompatibleFeatures(rawValue: 0x2000)
        public static let largeDirectory = IncompatibleFeatures(rawValue: 0x4000)
        public static let inlineDataInInode = IncompatibleFeatures(rawValue: 0x8000)
        public static let encryptedInodes = IncompatibleFeatures(rawValue: 0x10000)
        public static let directoriesCanBeCaseInsensitive = IncompatibleFeatures(rawValue: 0x20000)
        
        /// The set of features supported by the driver.
        ///
        /// If a filesystem enables any features not included in this set, it should not be mounted.
        public static let supportedFeatures: IncompatibleFeatures = [.filetype, .needsRecovery, .separateJournalDevice, .extents, .enable64BitSize, .multipleMountProtection, .flexibleBlockGroups, .metadataChecksumSeedInSuperblock, .largeDirectory, .inlineDataInInode, .directoriesCanBeCaseInsensitive]
    }
    
    public struct ReadOnlyCompatibleFeatures: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        
        public static let sparseSuperblocks = ReadOnlyCompatibleFeatures(rawValue: 1 << 0)
        /// This filesystem was used to store a file greater than 2 GiB.
        public static let largeFile = ReadOnlyCompatibleFeatures(rawValue: 1 << 1)
        /// Not used in the Linux kernel or e2fsprogs.
        public static let btreeDir = ReadOnlyCompatibleFeatures(rawValue: 1 << 2)
        /// This filesystem has files with sizes represented in units of logical blocks, not 512-byte sectors.
        public static let hugeFile = ReadOnlyCompatibleFeatures(rawValue: 1 << 3)
        public static let groupDescriptorsHaveChecksums = ReadOnlyCompatibleFeatures(rawValue: 1 << 4)
        /// ext3 had a subdirectory limit of 32,000.
        public static let ext3SubdirectoryLimitDoesNotApply = ReadOnlyCompatibleFeatures(rawValue: 1 << 5)
        public static let largeInodesExist = ReadOnlyCompatibleFeatures(rawValue: 1 << 6)
        public static let hasSnapshot = ReadOnlyCompatibleFeatures(rawValue: 1 << 7)
        public static let quota = ReadOnlyCompatibleFeatures(rawValue: 1 << 8)
        /// File extents are tracked in units of clusters of blocks instead of blocks.
        public static let supportsBigalloc = ReadOnlyCompatibleFeatures(rawValue: 1 << 9)
        /// This implies ``Superblock/ReadOnlyCompatibleFeatures/groupDescriptorsHaveChecksums``.
        public static let supportsMetadataChecksumming = ReadOnlyCompatibleFeatures(rawValue: 1 << 10)
        /// Not supported in the Linux kernel nor e2fsprogs.
        public static let supportsReplicas = ReadOnlyCompatibleFeatures(rawValue: 1 << 11)
        public static let readOnlyFileSystemImage = ReadOnlyCompatibleFeatures(rawValue: 1 << 12)
        public static let tracksProjectQuotas = ReadOnlyCompatibleFeatures(rawValue: 1 << 13)
        public static let verityInodes = ReadOnlyCompatibleFeatures(rawValue: 0x8000)
        public static let orphansPresent = ReadOnlyCompatibleFeatures(rawValue: 0x10000)
        
        /// The set of features supported by the driver.
        ///
        /// If a filesystem enables any features not included in this set, it can still mount as read-only.
        public static let supportedFeatures: ReadOnlyCompatibleFeatures = []
    }
    
    public enum HashVersion: UInt8 {
        case legacy = 0
        case halfMD4 = 1
        case tea = 2
        case legacyUnsigned = 3
        case halfMD4Unsigned = 4
        case teaUnsigned = 5
        case sipHash = 6
        case unknown = 255
        
        public var isSigned: Bool {
            switch self {
            case .legacy, .tea, .halfMD4:
                return true
            case .legacyUnsigned, .halfMD4Unsigned, .teaUnsigned, .sipHash:
                return false
            case .unknown:
                return false
            }
        }
    }
    
    public struct DefaultMountOptions: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        
        public static let printDebuggingInfoOnMount = DefaultMountOptions(rawValue: 1 << 0)
        /// As opposed to the fsgid of the current process.
        public static let newFilesTakeGidOfContainingDirectory = DefaultMountOptions(rawValue: 1 << 1)
        public static let userspaceProvidedExtendedAttributes = DefaultMountOptions(rawValue: 1 << 2)
        public static let supportPosixAccessControlLists = DefaultMountOptions(rawValue: 1 << 3)
        public static let doNotSupport32BitUIDs = DefaultMountOptions(rawValue: 1 << 4)
        public static let commitDataAndMetadataToJournal = DefaultMountOptions(rawValue: 1 << 5)
        public static let flushDataBeforeCommittingMetadata = DefaultMountOptions(rawValue: 1 << 6)
        public static let dataOrderingNotPreserved = DefaultMountOptions(rawValue: 1 << 7)
        public static let disableWriteFlushes = DefaultMountOptions(rawValue: 1 << 8)
        /// Blocks that are metadata should not be used as data blocks.
        public static let trackMetadataBlocks = DefaultMountOptions(rawValue: 1 << 9)
        /// The storage device is told about blocks becoming unused.
        public static let enabledDiscardSupport = DefaultMountOptions(rawValue: 1 << 10)
        public static let disableDelayedAllocation = DefaultMountOptions(rawValue: 1 << 11)
    }
    
    /// An encoding used for file names in casefolded directories.
    ///
    /// ext4 on Linux currently only supports UTF-8, so other values will probably not appear. In addition, macOS dislikes file names other than UTF-8 anyway.
    public enum Encoding {
        /// UTF-8 encoding.
        case utf8
        /// Some other encoding.
        case unknown(UInt16)
        
        public init(rawValue: UInt16) {
            switch rawValue {
            case 1:
                self = .utf8
            default:
                self = .unknown(rawValue)
            }
        }
        
        public var rawValue: UInt16 {
            switch self {
            case .utf8:
                1
            case .unknown(let value):
                value
            }
        }
        
        public var encoding: String.Encoding? {
            switch self {
            case .utf8:
                .utf8
            case .unknown:
                nil
            }
        }
    }
    
    /// Options that determine how to interpret encoded file names for casefolding.
    public struct EncodingFlags: OptionSet, Sendable {
        public let rawValue: UInt16
        
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        
        /// Inputted file names that are not in the correct encoding should be rejected.
        public static let strictMode = EncodingFlags(rawValue: 1 << 0)
        /// If a file name is not in the correct encoding, do not fall back to non-casefolded behavior.
        public static let noCompatFallback = EncodingFlags(rawValue: 1 << 1)
    }
    
    /// Total inode count.
    public var inodeCount: UInt32
    /// Total block count.
    public var blockCount: UInt64
    /// This number of blocks can only be allocated by the super-user.
    public var superUserBlockCount: UInt64
    public var freeBlockCount: UInt64
    public var freeInodeCount: UInt32
    /// First data block.
    ///
    /// This must be at least 1 for 1k-block filesystems and is typically 0 for all other block sizes.
    public var firstDataBlock: UInt32
    /// Block size is 2 ^ (10 + `logBlockSize`).
    public var logBlockSize: UInt32
    public var blockSize: Int {
        get {
            Int(pow(2, 10 + Double(logBlockSize)))
        }
    }
    /// Cluster size is (2 ^ `logClusterSize`) blocks if bigalloc is enabled. Otherwise `logClusterSize` must equal `logBlockSize`.
    public var logClusterSize: UInt32
    public var clusterSize: Int {
        get throws {
            Int(pow(2, Double(logClusterSize)))
        }
    }
    public var blocksPerGroup: UInt32
    public var clustersPerGroup: UInt32
    public var inodesPerGroup: UInt32
    /// Mount time, in seconds since the epoch.
    public var mountTime: UInt64
    /// Write time, in seconds since the epoch.
    public var writeTime: UInt64
    /// Number of mounts since the last `fsck`.
    public var mountsSinceLastFsck: UInt16
    /// Number of mounts beyond which a `fsck` is needed.
    public var maxMountsSinceLastFsck: UInt16
    /// Magic signature, should be `0xEF53`.
    public var magic: UInt16
    public var state: State
    public var errorPolicy: ErrorPolicy
    public var minorRevisionLevel: UInt16
    /// Time of last check, in seconds since the epoch.
    public var lastCheckTime: UInt32
    public var maxSecondsBetweenChecks: UInt32
    public var creatorOS: FilesystemCreator
    public var revisionLevel: Revision
    public var defaultUidForReservedBlocks: UInt16
    public var defaultGidForReservedBlocks: UInt16
    
    // MARK: - `EXT4_DYNAMIC_REV` superblocks only
    public var revisionSupportsDynamicInodeSizes: Bool {
        get {
            revisionLevel != .unknown && revisionLevel >= Revision.version2
        }
    }
    public var firstNonReservedInode: UInt32
    /// Size of inode structure, in bytes.
    public var inodeSize: UInt16
    public var blockGroupNumber: UInt16?
    public var compatibleFeatures: CompatibleFeatures
    public var incompatibleFeatures: IncompatibleFeatures
    public var readOnlyCompatibleFeatures: ReadOnlyCompatibleFeatures
    public var uuid: UUID?
    /// Volume label, maximum length 16.
    public var volumeName: Data?
    /// Directory where filesystem was last mounted, maximum length 64.
    public var lastMountDirectory: Data?
    public var compressionAlgorithmUsageBitmap: UInt32?
    
    // MARK: - Performance hints
    public var preallocateBlocks: UInt8?
    public var preallocateDirectoryBlocks: UInt8?
    public var reservedGDTBlocks: UInt16?
    
    // MARK: - Journalling support
    public var journalUUID: UUID?
    public var journalInodeNumber: UInt32?
    public var journalDeviceNumber: UInt32?
    
    public var lastOrphan: UInt32?
    public var hashSeed: [UInt32]? // size 4
    public var defaultHashAlgorithm: HashVersion?
    public var journalBackupType: UInt8?
    public var groupDescriptorSizeInBytes: UInt16?
    public var defaultMountOptions: UInt32?
    public var firstMetablockBlockGroup: UInt32?
    /// When the filesystem was created, in seconds since the epoch.
    public var mkfsTime: UInt32?
    public var backupJournalBlocks: [UInt32]? // size 17
    
    // MARK: - 64-bit support
    /// All inodes have at least `minimumExtraInodeSize` bytes.
    public var minimumExtraInodeSize: UInt16?
    /// New inodes should reserve `wantExtraInodeSize` bytes.
    public var wantExtraInodeSize: UInt16?
    public var flags: UInt32?
    public var raidStride: UInt16?
    public var mmpIntervalInSeconds: UInt16?
    public var mmpBlock: UInt64?
    public var raidStripeWidth: UInt32?
    public var logGroupsPerFlexibleGroup: UInt8?
    /// The number of block groups in a single logical block group (referred to as a flexible block group).
    ///
    /// The bitmap spaces and the inode table space in the first block group of a given flexible block group are expanded to include the bitmaps and inode tables of all other block groups in that flexible group. For example, group 0 contains the data block bitmaps, inode bitmaps, and inode tables for itself as well as other block groups in its flexible group.
    ///
    /// Backup copies of the superblock and group descriptors will always be at the beginning of block groups even with flexible block groups enabled.
    ///
    /// If flexible block groups are disabled, this returns `nil`.
    public var groupsPerFlexibleGroup: UInt64? {
        get {
            guard let logGroupsPerFlexibleGroup = logGroupsPerFlexibleGroup else {
                return nil
            }
            return UInt64(pow(2, Double(logGroupsPerFlexibleGroup)))
        }
    }
    public var checksumType: UInt8?
    public var reservedPad: UInt16?
    public var kbytesWritten: UInt64?
    public var snapshotInodeNumber: UInt32?
    public var snapshotId: UInt32?
    public var snapshotReservedBlockCount: UInt64?
    public var snapshotListInodeNumber: UInt32?
    public var errorCount: UInt32?
    public var firstErrorTime: UInt32?
    public var firstErrorInode: UInt32?
    public var firstErrorBlock: UInt64?
    public var firstErrorFunctionName: String?
    public var firstErrorLineNumber: UInt32?
    public var lastErrorTime: UInt32?
    public var lastErrorInodeNumber: UInt32?
    public var lastErrorLine: UInt32?
    public var lastErrorBlock: UInt64?
    public var lastErrorFunctionName: String?

    public var mountOptions: String?

    public var userQuotaInode: UInt32?
    public var groupQuotaInode: UInt32?
    public var overheadBlocks: UInt32?

    public var superblockBackupGroups: [UInt32]?
    public var encryptionAlgorithms: [UInt8]?
    public var encryptionSalt: [UInt8]?

    public var lostAndFoundInode: UInt32?
    public var projectQuotaInode: UInt32?
    public var checksumSeed: UInt32?

    public var writeTimeHigh: UInt8?
    public var mountTimeHigh: UInt8?
    public var mkfsTimeHigh: UInt8?
    public var lastCheckTimeHigh: UInt8?
    public var firstErrorTimeHigh: UInt8?
    public var lastErrorTimeHigh: UInt8?
    
    public var pad: [UInt8]?
    public var encoding: Encoding?
    public var encodingFlags: EncodingFlags?
    public var orphanFileInodeNumber: UInt32?

    public var reservedPadding: [UInt32]?

    public var checksum: UInt32?
    
    public func toData() throws -> Data {
        var data = Data()
        data.reserveCapacity(1024)
        
        data.appendLittleEndian(inodeCount)
        data.appendLittleEndian(blockCount.lowerHalf)
        data.appendLittleEndian(superUserBlockCount.lowerHalf)
        data.appendLittleEndian(freeBlockCount.lowerHalf)
        data.appendLittleEndian(freeInodeCount)
        data.appendLittleEndian(firstDataBlock)
        data.appendLittleEndian(logBlockSize)
        data.appendLittleEndian(logClusterSize)
        data.appendLittleEndian(blocksPerGroup)
        data.appendLittleEndian(clustersPerGroup)
        data.appendLittleEndian(inodesPerGroup)
        data.appendLittleEndian(mountTime.lowerHalf)
        data.appendLittleEndian(writeTime.lowerHalf)
        data.appendLittleEndian(mountsSinceLastFsck)
        data.appendLittleEndian(maxMountsSinceLastFsck)
        data.appendLittleEndian(magic)
        data.appendLittleEndian(state.rawValue)
        data.appendLittleEndian(errorPolicy.rawValue)
        data.appendLittleEndian(minorRevisionLevel)
        data.appendLittleEndian(lastCheckTime)
        data.appendLittleEndian(maxSecondsBetweenChecks)
        data.appendLittleEndian(creatorOS.rawValue)
        data.appendLittleEndian(revisionLevel.rawValue)
        data.appendLittleEndian(defaultUidForReservedBlocks)
        data.appendLittleEndian(defaultGidForReservedBlocks)
        
        guard revisionLevel == .version2 else {
            // FIXME: padding
            return data
        }
        
        data.appendLittleEndian(firstNonReservedInode)
        data.appendLittleEndian(inodeSize)
        guard let blockGroupNumber else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        data.appendLittleEndian(blockGroupNumber)
        data.appendLittleEndian(compatibleFeatures.rawValue)
        data.appendLittleEndian(incompatibleFeatures.rawValue)
        data.appendLittleEndian(readOnlyCompatibleFeatures.rawValue)
        data.append(uuid: (uuid ?? UUID()))
        data.append(volumeName ?? Data(count: 16))
        data.append(lastMountDirectory ?? Data(count: 64))
        data.appendLittleEndian(compressionAlgorithmUsageBitmap ?? 0)
        data.appendLittleEndian(preallocateBlocks ?? 0)
        data.appendLittleEndian(preallocateDirectoryBlocks ?? 0)
        data.appendLittleEndian(reservedGDTBlocks ?? 0)
        data.append(uuid: journalUUID ?? UUID())
        data.appendLittleEndian(journalInodeNumber ?? 0)
        data.appendLittleEndian(journalDeviceNumber ?? 0)
        data.appendLittleEndian(lastOrphan ?? 0)
        guard let hashSeed, hashSeed.count == 4 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in hashSeed {
            data.appendLittleEndian(i)
        }
        data.appendLittleEndian(defaultHashAlgorithm?.rawValue ?? 0)
        data.appendLittleEndian(journalBackupType ?? 0)
        data.appendLittleEndian(groupDescriptorSizeInBytes ?? 0)
        data.appendLittleEndian(defaultMountOptions ?? 0)
        data.appendLittleEndian(firstMetablockBlockGroup ?? 0)
        data.appendLittleEndian(mkfsTime ?? 0)
        guard let backupJournalBlocks, backupJournalBlocks.count == 17 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in backupJournalBlocks {
            data.appendLittleEndian(i)
        }
        data.appendLittleEndian(blockCount.upperHalf)
        data.appendLittleEndian(superUserBlockCount.upperHalf)
        data.appendLittleEndian(freeBlockCount.upperHalf)
        data.appendLittleEndian(minimumExtraInodeSize ?? 0)
        data.appendLittleEndian(wantExtraInodeSize ?? 0)
        data.appendLittleEndian(flags ?? 0)
        data.appendLittleEndian(raidStride ?? 0)
        data.appendLittleEndian(mmpIntervalInSeconds ?? 0)
        data.appendLittleEndian(mmpBlock ?? 0)
        data.appendLittleEndian(raidStripeWidth ?? 0)
        data.appendLittleEndian(logGroupsPerFlexibleGroup ?? 0)
        data.appendLittleEndian(checksumType ?? 0)
        data.appendLittleEndian(reservedPad ?? 0)
        data.appendLittleEndian(kbytesWritten ?? 0)
        data.appendLittleEndian(snapshotInodeNumber ?? 0)
        data.appendLittleEndian(snapshotId ?? 0)
        data.appendLittleEndian(snapshotReservedBlockCount ?? 0)
        data.appendLittleEndian(snapshotListInodeNumber ?? 0)
        data.appendLittleEndian(errorCount ?? 0)
        data.appendLittleEndian(firstErrorTime ?? 0)
        data.appendLittleEndian(firstErrorInode ?? 0)
        data.appendLittleEndian(firstErrorBlock ?? 0)
        try data.append(cStringFrom: firstErrorFunctionName ?? "", length: 32, useNullTerminator: false)
        data.appendLittleEndian(firstErrorLineNumber ?? 0)
        data.appendLittleEndian(lastErrorTime ?? 0)
        data.appendLittleEndian(lastErrorInodeNumber ?? 0)
        data.appendLittleEndian(lastErrorLine ?? 0)
        data.appendLittleEndian(lastErrorBlock ?? 0)
        try data.append(cStringFrom: lastErrorFunctionName ?? "", length: 32, useNullTerminator: false)
        try data.append(cStringFrom: mountOptions ?? "", length: 64, useNullTerminator: false)
        data.appendLittleEndian(userQuotaInode ?? 0)
        data.appendLittleEndian(groupQuotaInode ?? 0)
        data.appendLittleEndian(overheadBlocks ?? 0)
        guard let superblockBackupGroups, superblockBackupGroups.count == 2 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in superblockBackupGroups {
            data.appendLittleEndian(i)
        }
        guard let encryptionAlgorithms, encryptionAlgorithms.count == 4 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in encryptionAlgorithms {
            data.appendLittleEndian(i)
        }
        guard let encryptionSalt, encryptionSalt.count == 16 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in encryptionSalt {
            data.appendLittleEndian(i)
        }
        data.appendLittleEndian(lostAndFoundInode ?? 0)
        data.appendLittleEndian(projectQuotaInode ?? 0)
        data.appendLittleEndian(checksumSeed ?? 0)
        data.appendLittleEndian(writeTimeHigh ?? 0)
        data.appendLittleEndian(mountTimeHigh ?? 0)
        data.appendLittleEndian(mkfsTimeHigh ?? 0)
        data.appendLittleEndian(lastCheckTimeHigh ?? 0)
        data.appendLittleEndian(firstErrorTimeHigh ?? 0)
        data.appendLittleEndian(lastErrorTimeHigh ?? 0)
        guard let pad, pad.count == 2 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in pad {
            data.appendLittleEndian(i)
        }
        data.appendLittleEndian(encoding?.rawValue ?? 0)
        data.appendLittleEndian(encodingFlags?.rawValue ?? 0)
        data.appendLittleEndian(orphanFileInodeNumber ?? 0)
        guard let reservedPadding, reservedPadding.count == 94 else {
            logger.fault("Superblock state is corrupted")
            throw POSIXError(.EIO)
        }
        for i in reservedPadding {
            data.appendLittleEndian(i)
        }
        data.appendLittleEndian(checksum ?? 0)
        
        guard data.count == 1024 else {
            logger.fault("Attempted to create data from superblock, but it was not 1024 bytes")
            throw POSIXError(.EIO)
        }
        
        return data
    }
    
    public func calculateChecksum() throws -> UInt32 {
        let data = try self.toData().dropLast(MemoryLayout<UInt32>.size)
        
        return ~data.crc32c()
    }
}
