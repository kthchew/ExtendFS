// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Superblock")

struct Superblock {
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let inodeCount: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.inodeCount = inodeCount
        guard let blockCountLow: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let superUserBlockCountLow: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let freeBlockCountLow: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let freeInodeCount: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.freeInodeCount = freeInodeCount
        guard let firstDataBlock: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.firstDataBlock = firstDataBlock
        guard let logBlockSize: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.logBlockSize = logBlockSize
        guard let logClusterSize: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.logClusterSize = logClusterSize
        guard let blocksPerGroup: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.blocksPerGroup = blocksPerGroup
        guard let clustersPerGroup: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.clustersPerGroup = clustersPerGroup
        guard let inodesPerGroup: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.inodesPerGroup = inodesPerGroup
        guard let mountTimeLow: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.mountTime = UInt64(mountTimeLow)
        guard let writeTimeLow: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.writeTime = UInt64(writeTimeLow)
        guard let mountsSinceLastFsck: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.mountsSinceLastFsck = mountsSinceLastFsck
        guard let maxMountsSinceLastFsck: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.maxMountsSinceLastFsck = maxMountsSinceLastFsck
        guard let magic: UInt16 = iterator.nextLittleEndian(), magic == 0xEF53 else { return nil }
        self.magic = magic
        guard let state: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.state = State(rawValue: state)
        guard let errorPolicy: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.errorPolicy = ErrorPolicy(rawValue: errorPolicy) ?? .unknown
        guard let minorRevisionLevel: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.minorRevisionLevel = minorRevisionLevel
        guard let lastCheckTime: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lastCheckTime = lastCheckTime
        guard let maxSecondsBetweenChecks: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.maxSecondsBetweenChecks = maxSecondsBetweenChecks
        guard let creatorOS: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.creatorOS = FilesystemCreator(rawValue: creatorOS) ?? .unknown
        guard let revisionLevelRaw: UInt32 = iterator.nextLittleEndian() else { return nil }
        let revisionLevel = Revision(rawValue: revisionLevelRaw) ?? .unknown
        self.revisionLevel = revisionLevel
        guard let defaultUidForReservedBlocks: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.defaultUidForReservedBlocks = defaultUidForReservedBlocks
        guard let defaultGidForReservedBlocks: UInt16 = iterator.nextLittleEndian() else { return nil }
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
        guard let firstNonReservedInode: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.firstNonReservedInode = firstNonReservedInode
        guard let inodeSize: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.inodeSize = inodeSize
        guard let blockGroupNumber: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.blockGroupNumber = blockGroupNumber
        guard let compatibleFeaturesRaw: UInt32 = iterator.nextLittleEndian() else { return nil }
        let compatibleFeatures = CompatibleFeatures(rawValue: compatibleFeaturesRaw)
        self.compatibleFeatures = compatibleFeatures
        guard let incompatibleFeaturesRaw: UInt32 = iterator.nextLittleEndian() else { return nil }
        let incompatibleFeatures = IncompatibleFeatures(rawValue: incompatibleFeaturesRaw)
        self.incompatibleFeatures = incompatibleFeatures
        guard let readOnlyCompatibleFeaturesRaw: UInt32 = iterator.nextLittleEndian() else { return nil }
        let readOnlyCompatibleFeatures = ReadOnlyCompatibleFeatures(rawValue: readOnlyCompatibleFeaturesRaw)
        self.readOnlyCompatibleFeatures = readOnlyCompatibleFeatures

        guard let uuid = iterator.nextUUID() else { return nil }
        self.uuid = uuid

        guard let volumeName = iterator.nextString(ofMaximumLength: 16) else { return nil }
        self.volumeName = volumeName

        guard let lastMountDirectory = iterator.nextString(ofMaximumLength: 64) else { return nil }
        self.lastMountDirectory = lastMountDirectory

        guard let compressionAlgorithmUsageBitmap: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.compressionAlgorithmUsageBitmap = compressionAlgorithmUsageBitmap
        
        // MARK: - Performance hints
        guard let preallocateBlocks: UInt8 = iterator.nextLittleEndian() else { return nil }
        guard let preallocateDirectoryBlocks: UInt8 = iterator.nextLittleEndian() else { return nil }
        if compatibleFeatures.contains(.directoryPreallocation) {
            self.preallocateBlocks = preallocateBlocks
            self.preallocateDirectoryBlocks = preallocateDirectoryBlocks
        }
        guard let reservedGDTBlocks: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.reservedGDTBlocks = reservedGDTBlocks
        
        guard let journalUUID = iterator.nextUUID() else { return nil }
        guard let journalInodeNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let journalDeviceNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        if compatibleFeatures.contains(.journal) {
            self.journalUUID = journalUUID
            self.journalInodeNumber = journalInodeNumber
            self.journalDeviceNumber = journalDeviceNumber
        }
        guard let lastOrphan: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lastOrphan = lastOrphan

        var hashSeed: [UInt32] = []
        hashSeed.reserveCapacity(4)
        for _ in 0..<4 {
            guard let v: UInt32 = iterator.nextLittleEndian() else { return nil }
            hashSeed.append(v)
        }
        self.hashSeed = hashSeed

        guard let defaultHashAlgorithm: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.defaultHashAlgorithm = defaultHashAlgorithm
        guard let journalBackupType: UInt8 = iterator.nextLittleEndian() else { return nil }
        if compatibleFeatures.contains(.journal) {
            self.journalBackupType = journalBackupType
        }
        guard let groupDescriptorSizeInBytes: UInt16 = iterator.nextLittleEndian() else { return nil }
        if incompatibleFeatures.contains(.enable64BitSize) {
            self.groupDescriptorSizeInBytes = groupDescriptorSizeInBytes
        }
        guard let defaultMountOptions: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.defaultMountOptions = defaultMountOptions
        guard let firstMetablockBlockGroup: UInt32 = iterator.nextLittleEndian() else { return nil }
        if incompatibleFeatures.contains(.metaBlockGroups) {
            self.firstMetablockBlockGroup = firstMetablockBlockGroup
        }
        guard let mkfsTime: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.mkfsTime = mkfsTime

        var backupJournalBlocks: [UInt32] = []
        backupJournalBlocks.reserveCapacity(17)
        for _ in 0..<17 {
            guard let v: UInt32 = iterator.nextLittleEndian() else { return nil }
            backupJournalBlocks.append(v)
        }
        self.backupJournalBlocks = backupJournalBlocks

        // MARK: - 64-bit support
        guard let blockCountHigh: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let superUserBlockCountHigh: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let freeBlockCountHigh: UInt32 = iterator.nextLittleEndian() else { return nil }
        if incompatibleFeatures.contains(.enable64BitSize) {
            self.blockCount = UInt64.combine(upper: blockCountHigh, lower: blockCountLow)
            self.superUserBlockCount = UInt64.combine(upper: superUserBlockCountHigh, lower: superUserBlockCountLow)
            self.freeBlockCount = UInt64.combine(upper: freeBlockCountHigh, lower: freeBlockCountLow)
        } else {
            self.blockCount = UInt64(blockCountLow)
            self.superUserBlockCount = UInt64(superUserBlockCountLow)
            self.freeBlockCount = UInt64(freeBlockCountLow)
        }
        guard let minimumExtraInodeSize: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.minimumExtraInodeSize = minimumExtraInodeSize
        guard let wantExtraInodeSize: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.wantExtraInodeSize = wantExtraInodeSize
        guard let flags: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.flags = flags
        guard let raidStride: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.raidStride = raidStride
        guard let mmpIntervalInSeconds: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.mmpIntervalInSeconds = mmpIntervalInSeconds
        guard let mmpBlock: UInt64 = iterator.nextLittleEndian() else { return nil }
        self.mmpBlock = mmpBlock
        guard let raidStripeWidth: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.raidStripeWidth = raidStripeWidth
        guard let logGroupsPerFlexibleGroup: UInt8 = iterator.nextLittleEndian() else { return nil }
        if incompatibleFeatures.contains(.flexibleBlockGroups) {
            self.logGroupsPerFlexibleGroup = logGroupsPerFlexibleGroup
        }
        guard let checksumType: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.checksumType = checksumType
        guard let reservedPad: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.reservedPad = reservedPad
        guard let kbytesWritten: UInt64 = iterator.nextLittleEndian() else { return nil }
        self.kbytesWritten = kbytesWritten
        guard let snapshotInodeNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.snapshotInodeNumber = snapshotInodeNumber
        guard let snapshotId: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.snapshotId = snapshotId
        guard let snapshotReservedBlockCount: UInt64 = iterator.nextLittleEndian() else { return nil }
        self.snapshotReservedBlockCount = snapshotReservedBlockCount
        guard let snapshotListInodeNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.snapshotListInodeNumber = snapshotListInodeNumber

        guard let errorCount: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.errorCount = errorCount
        guard let firstErrorTime: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.firstErrorTime = firstErrorTime
        guard let firstErrorInode: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.firstErrorInode = firstErrorInode
        guard let firstErrorBlock: UInt64 = iterator.nextLittleEndian() else { return nil }
        self.firstErrorBlock = firstErrorBlock
        guard let firstErrorFunctionName = iterator.nextString(ofMaximumLength: 32) else { return nil }
        self.firstErrorFunctionName = firstErrorFunctionName
        guard let firstErrorLineNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.firstErrorLineNumber = firstErrorLineNumber
        guard let lastErrorTime: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lastErrorTime = lastErrorTime
        guard let lastErrorInodeNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lastErrorInodeNumber = lastErrorInodeNumber
        guard let lastErrorLine: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lastErrorLine = lastErrorLine
        guard let lastErrorBlock: UInt64 = iterator.nextLittleEndian() else { return nil }
        self.lastErrorBlock = lastErrorBlock
        guard let lastErrorFunctionName = iterator.nextString(ofMaximumLength: 32) else { return nil }
        self.lastErrorFunctionName = lastErrorFunctionName

        guard let mountOptions = iterator.nextString(ofMaximumLength: 64) else { return nil }
        self.mountOptions = mountOptions

        guard let userQuotaInode: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.userQuotaInode = userQuotaInode
        guard let groupQuotaInode: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.groupQuotaInode = groupQuotaInode
        guard let overheadBlocks: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.overheadBlocks = overheadBlocks

        var superblockBackupGroups: [UInt32] = []
        superblockBackupGroups.reserveCapacity(2)
        for _ in 0..<2 {
            guard let v: UInt32 = iterator.nextLittleEndian() else { return nil }
            superblockBackupGroups.append(v)
        }
        self.superblockBackupGroups = superblockBackupGroups

        var encryptionAlgorithms: [UInt8] = []
        encryptionAlgorithms.reserveCapacity(4)
        for _ in 0..<4 {
            guard let b: UInt8 = iterator.nextLittleEndian() else { return nil }
            encryptionAlgorithms.append(b)
        }
        self.encryptionAlgorithms = encryptionAlgorithms

        var encryptionSalt: [UInt8] = []
        encryptionSalt.reserveCapacity(16)
        for _ in 0..<16 {
            guard let b: UInt8 = iterator.nextLittleEndian() else { return nil }
            encryptionSalt.append(b)
        }
        self.encryptionSalt = encryptionSalt

        guard let lostAndFoundInode: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lostAndFoundInode = lostAndFoundInode
        guard let projectQuotaInode: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.projectQuotaInode = projectQuotaInode
        guard let checksumSeed: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.checksumSeed = checksumSeed

        guard let writeTimeHigh: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.writeTimeHigh = writeTimeHigh
        guard let mountTimeHigh: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.mountTimeHigh = mountTimeHigh
        guard let mkfsTimeHigh: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.mkfsTimeHigh = mkfsTimeHigh
        guard let lastCheckTimeHigh: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.lastCheckTimeHigh = lastCheckTimeHigh
        guard let firstErrorTimeHigh: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.firstErrorTimeHigh = firstErrorTimeHigh
        guard let lastErrorTimeHigh: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.lastErrorTimeHigh = lastErrorTimeHigh

        // zero padding
        guard let _: UInt8 = iterator.nextLittleEndian() else { return nil }
        guard let _: UInt8 = iterator.nextLittleEndian() else { return nil }

        var reservedPadding: [UInt32] = []
        reservedPadding.reserveCapacity(96)
        for _ in 0..<96 {
            guard let v: UInt32 = iterator.nextLittleEndian() else { return nil }
            reservedPadding.append(v)
        }
        self.reservedPadding = reservedPadding

        guard let checksum: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.checksum = checksum
    }
    
    init?(blockDevice: FSBlockDeviceResource, offset: Int64) throws {
        let superblockSize = 1024
        var data = Data(count: superblockSize)
        let actuallyRead = try data.withUnsafeMutableBytes { ptr in
            return try blockDevice.read(into: ptr, startingAt: offset, length: 1024)
        }
        guard actuallyRead == superblockSize else {
            logger.error("Expected to read 1024 bytes for superblock, only read \(actuallyRead, privacy: .public) bytes")
            throw POSIXError(.EIO)
        }
        self.init(from: data)
    }
    
    struct State: OptionSet {
        let rawValue: UInt16
        
        static let cleanlyUnmounted = Superblock.State(rawValue: 0x1)
        static let errorsDetected = Superblock.State(rawValue: 0x2)
        static let orphansBeingRecovered = Superblock.State(rawValue: 0x4)
    }
    
    enum ErrorPolicy: UInt16 {
        case `continue` = 1
        case remountReadOnly = 2
        case panic = 3
        case unknown = 65535
    }
    
    enum FilesystemCreator: UInt32 {
        case linux = 0
        case hurd = 1
        case masix = 2
        case freeBSD = 3
        case lites = 4
        case unknown = 4294967295
    }
    
    enum Revision: UInt32, Comparable {
        static func < (lhs: Superblock.Revision, rhs: Superblock.Revision) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        case original = 0
        /// Has dynamic inode sizes.
        case version2 = 1
        case unknown = 4294967295
    }
    
    struct CompatibleFeatures: OptionSet {
        let rawValue: UInt32
        
        static let directoryPreallocation = CompatibleFeatures(rawValue: 1 << 0)
        static let imagicInodes = CompatibleFeatures(rawValue: 1 << 1)
        static let journal = CompatibleFeatures(rawValue: 1 << 2)
        static let extendedAttributes = CompatibleFeatures(rawValue: 1 << 3)
        /// Requires `sparseSuperBlockVersion2`.
        static let reservedGDTBlocksForExpansion = CompatibleFeatures(rawValue: 1 << 4)
        static let directoryIndices = CompatibleFeatures(rawValue: 1 << 5)
        static let lazyBG = CompatibleFeatures(rawValue: 1 << 6)
        /// Not used.
        static let excludeInode = CompatibleFeatures(rawValue: 1 << 7)
        static let excludeBitmap = CompatibleFeatures(rawValue: 1 << 8)
        static let sparseSuperBlockVersion2 = CompatibleFeatures(rawValue: 1 << 9)
    }
    
    struct IncompatibleFeatures: OptionSet {
        let rawValue: UInt32
        
        static let compression = IncompatibleFeatures(rawValue: 0x1)
        /// Directory entries record the file type.
        static let filetype = IncompatibleFeatures(rawValue: 0x2)
        static let needsRecovery = IncompatibleFeatures(rawValue: 0x4)
        static let separateJournalDevice = IncompatibleFeatures(rawValue: 0x8)
        static let metaBlockGroups = IncompatibleFeatures(rawValue: 0x10)
        static let extents = IncompatibleFeatures(rawValue: 0x40)
        static let enable64BitSize = IncompatibleFeatures(rawValue: 0x80)
        static let multipleMountProtection = IncompatibleFeatures(rawValue: 0x100)
        static let flexibleBlockGroups = IncompatibleFeatures(rawValue: 0x200)
        static let inodesCanStoreLargeExtendedAttributes = IncompatibleFeatures(rawValue: 0x400)
        static let dataInDirEntry = IncompatibleFeatures(rawValue: 0x1000)
        static let metadataChecksumSeedInSuperblock = IncompatibleFeatures(rawValue: 0x2000)
        static let largeDirectory = IncompatibleFeatures(rawValue: 0x4000)
        static let inlineDataInInode = IncompatibleFeatures(rawValue: 0x8000)
        static let encryptedInodes = IncompatibleFeatures(rawValue: 0x10000)
        
        /// The set of features supported by the driver.
        ///
        /// If a filesystem enables any features not included in this set, it should not be mounted.
        static let supportedFeatures: IncompatibleFeatures = [.filetype, .extents, .enable64BitSize, .flexibleBlockGroups, .metadataChecksumSeedInSuperblock]
    }
    
    struct ReadOnlyCompatibleFeatures: OptionSet {
        let rawValue: UInt32
        
        static let sparseSuperblocks = ReadOnlyCompatibleFeatures(rawValue: 1 << 0)
        /// This filesystem was used to store a file greater than 2 GiB.
        static let largeFile = ReadOnlyCompatibleFeatures(rawValue: 1 << 1)
        /// Not used in the Linux kernel or e2fsprogs.
        static let btreeDir = ReadOnlyCompatibleFeatures(rawValue: 1 << 2)
        /// This filesystem has files with sizes represented in units of logical blocks, not 512-byte sectors.
        static let hugeFile = ReadOnlyCompatibleFeatures(rawValue: 1 << 3)
        static let groupDescriptorsHaveChecksums = ReadOnlyCompatibleFeatures(rawValue: 1 << 4)
        /// ext3 had a subdirectory limit of 32,000.
        static let ext3SubdirectoryLimitDoesNotApply = ReadOnlyCompatibleFeatures(rawValue: 1 << 5)
        static let largeInodesExist = ReadOnlyCompatibleFeatures(rawValue: 1 << 6)
        static let hasSnapshot = ReadOnlyCompatibleFeatures(rawValue: 1 << 7)
        static let quota = ReadOnlyCompatibleFeatures(rawValue: 1 << 8)
        /// File extents are tracked in units of clusters of blocks instead of blocks.
        static let supportsBigalloc = ReadOnlyCompatibleFeatures(rawValue: 1 << 9)
        /// This implies `groupDescriptorsHaveChecksums`.
        static let supportsMetadataChecksumming = ReadOnlyCompatibleFeatures(rawValue: 1 << 10)
        /// Not supported in the Linux kernel nor e2fsprogs.
        static let supportsReplicas = ReadOnlyCompatibleFeatures(rawValue: 1 << 11)
        static let readOnlyFileSystemImage = ReadOnlyCompatibleFeatures(rawValue: 1 << 12)
        static let tracksProjectQuotas = ReadOnlyCompatibleFeatures(rawValue: 1 << 13)
        
        /// The set of features supported by the driver.
        ///
        /// If a filesystem enables any features not included in this set, it can still mount as read-only.
        static let supportedFeatures: ReadOnlyCompatibleFeatures = []
    }
    
    enum HashVersion: UInt8 {
        case legacy = 0
        case halfMD4 = 1
        case tea = 2
        case legacyUnsigned = 3
        case halfMD4Unsigned = 4
        case teaUnsigned = 5
    }
    
    struct DefaultMountOptions: OptionSet {
        let rawValue: UInt32
        
        static let printDebuggingInfoOnMount = DefaultMountOptions(rawValue: 1 << 0)
        /// As opposed to the fsgid of the current process.
        static let newFilesTakeGidOfContainingDirectory = DefaultMountOptions(rawValue: 1 << 1)
        static let userspaceProvidedExtendedAttributes = DefaultMountOptions(rawValue: 1 << 2)
        static let supportPosixAccessControlLists = DefaultMountOptions(rawValue: 1 << 3)
        static let doNotSupport32BitUIDs = DefaultMountOptions(rawValue: 1 << 4)
        static let commitDataAndMetadataToJournal = DefaultMountOptions(rawValue: 1 << 5)
        static let flushDataBeforeCommittingMetadata = DefaultMountOptions(rawValue: 1 << 6)
        static let dataOrderingNotPreserved = DefaultMountOptions(rawValue: 1 << 7)
        static let disableWriteFlushes = DefaultMountOptions(rawValue: 1 << 8)
        /// Blocks that are metadata should not be used as data blocks.
        static let trackMetadataBlocks = DefaultMountOptions(rawValue: 1 << 9)
        /// The storage device is told about blocks becoming unused.
        static let enabledDiscardSupport = DefaultMountOptions(rawValue: 1 << 10)
        static let disableDelayedAllocation = DefaultMountOptions(rawValue: 1 << 11)
    }
    
    /// Total inode count.
    var inodeCount: UInt32
    /// Total block count.
    var blockCount: UInt64
    /// This number of blocks can only be allocated by the super-user.
    var superUserBlockCount: UInt64
    var freeBlockCount: UInt64
    var freeInodeCount: UInt32
    /// First data block.
    ///
    /// This must be at least 1 for 1k-block filesystems and is typically 0 for all other block sizes.
    var firstDataBlock: UInt32
    /// Block size is 2 ^ (10 + `logBlockSize`).
    var logBlockSize: UInt32
    var blockSize: Int {
        get {
            Int(pow(2, 10 + Double(logBlockSize)))
        }
    }
    /// Cluster size is (2 ^ `logClusterSize`) blocks if bigalloc is enabled. Otherwise `logClusterSize` must equal `logBlockSize`.
    var logClusterSize: UInt32
    var clusterSize: Int {
        get throws {
            Int(pow(2, Double(logClusterSize)))
        }
    }
    var blocksPerGroup: UInt32
    var clustersPerGroup: UInt32
    var inodesPerGroup: UInt32
    /// Mount time, in seconds since the epoch.
    var mountTime: UInt64
    /// Write time, in seconds since the epoch.
    var writeTime: UInt64
    /// Number of mounts since the last `fsck`.
    var mountsSinceLastFsck: UInt16
    /// Number of mounts beyond which a `fsck` is needed.
    var maxMountsSinceLastFsck: UInt16
    /// Magic signature, should be `0xEF53`.
    var magic: UInt16
    var state: State
    var errorPolicy: ErrorPolicy
    var minorRevisionLevel: UInt16
    /// Time of last check, in seconds since the epoch.
    var lastCheckTime: UInt32
    var maxSecondsBetweenChecks: UInt32
    var creatorOS: FilesystemCreator
    var revisionLevel: Revision
    var defaultUidForReservedBlocks: UInt16
    var defaultGidForReservedBlocks: UInt16
    
    // MARK: - `EXT4_DYNAMIC_REV` superblocks only
    var revisionSupportsDynamicInodeSizes: Bool {
        get {
            revisionLevel != .unknown && revisionLevel >= Revision.version2
        }
    }
    var firstNonReservedInode: UInt32
    /// Size of inode structure, in bytes.
    var inodeSize: UInt16
    var blockGroupNumber: UInt16?
    var compatibleFeatures: CompatibleFeatures
    var incompatibleFeatures: IncompatibleFeatures
    var readOnlyCompatibleFeatures: ReadOnlyCompatibleFeatures
    var uuid: UUID?
    /// Volume label, maximum length 16.
    var volumeName: String?
    /// Directory where filesystem was last mounted, maximum length 64.
    var lastMountDirectory: String?
    var compressionAlgorithmUsageBitmap: UInt32?
    
    // MARK: - Performance hints
    var preallocateBlocks: UInt8?
    var preallocateDirectoryBlocks: UInt8?
    var reservedGDTBlocks: UInt16?
    
    // MARK: - Journalling support
    var journalUUID: UUID?
    var journalInodeNumber: UInt32?
    var journalDeviceNumber: UInt32?
    
    var lastOrphan: UInt32?
    var hashSeed: [UInt32]? // size 4
    var defaultHashAlgorithm: UInt8?
    var journalBackupType: UInt8?
    var groupDescriptorSizeInBytes: UInt16?
    var defaultMountOptions: UInt32?
    var firstMetablockBlockGroup: UInt32?
    /// When the filesystem was created, in seconds since the epoch.
    var mkfsTime: UInt32?
    var backupJournalBlocks: [UInt32]? // size 17
    
    // MARK: - 64-bit support
    var blockCountHigh: UInt32?
    var superUserBlockCountHigh: UInt32?
    var freeBlockCountHigh: UInt32?
    /// All inodes have at least `minimumExtraInodeSize` bytes.
    var minimumExtraInodeSize: UInt16?
    /// New inodes should reserve `wantExtraInodeSize` bytes.
    var wantExtraInodeSize: UInt16?
    var flags: UInt32?
    var raidStride: UInt16?
    var mmpIntervalInSeconds: UInt16?
    var mmpBlock: UInt64?
    var raidStripeWidth: UInt32?
    var logGroupsPerFlexibleGroup: UInt8?
    /// The number of block groups in a single logical block group (referred to as a flexible block group).
    ///
    /// The bitmap spaces and the inode table space in the first block group of a given flexible block group are expanded to include the bitmaps and inode tables of all other block groups in that flexible group. For example, group 0 contains the data block bitmaps, inode bitmaps, and inode tables for itself as well as other block groups in its flexible group.
    ///
    /// Backup copies of the superblock and group descriptors will always be at the beginning of block groups even with flexible block groups enabled.
    ///
    /// If flexible block groups are disabled, this returns `nil`.
    var groupsPerFlexibleGroup: UInt64? {
        get {
            guard let logGroupsPerFlexibleGroup = logGroupsPerFlexibleGroup else {
                return nil
            }
            return UInt64(pow(2, Double(logGroupsPerFlexibleGroup)))
        }
    }
    var checksumType: UInt8?
    var reservedPad: UInt16?
    var kbytesWritten: UInt64?
    var snapshotInodeNumber: UInt32?
    var snapshotId: UInt32?
    var snapshotReservedBlockCount: UInt64?
    var snapshotListInodeNumber: UInt32?
    var errorCount: UInt32?
    var firstErrorTime: UInt32?
    var firstErrorInode: UInt32?
    var firstErrorBlock: UInt64?
    var firstErrorFunctionName: String?
    var firstErrorLineNumber: UInt32?
    var lastErrorTime: UInt32?
    var lastErrorInodeNumber: UInt32?
    var lastErrorLine: UInt32?
    var lastErrorBlock: UInt64?
    var lastErrorFunctionName: String?

    var mountOptions: String?

    var userQuotaInode: UInt32?
    var groupQuotaInode: UInt32?
    var overheadBlocks: UInt32?

    var superblockBackupGroups: [UInt32]?
    var encryptionAlgorithms: [UInt8]?
    var encryptionSalt: [UInt8]?

    var lostAndFoundInode: UInt32?
    var projectQuotaInode: UInt32?
    var checksumSeed: UInt32?

    var writeTimeHigh: UInt8?
    var mountTimeHigh: UInt8?
    var mkfsTimeHigh: UInt8?
    var lastCheckTimeHigh: UInt8?
    var firstErrorTimeHigh: UInt8?
    var lastErrorTimeHigh: UInt8?

    var reservedPadding: [UInt32]?

    var checksum: UInt32?
}
