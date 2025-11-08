//
//  Superblock.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/15/25.
//

import Foundation
import FSKit
import zlib

struct BlockDeviceReader {
    static private let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "BlockDeviceReader")
    nonisolated(unsafe) static var useMetadataRead = false
    
    static func fetchExtent(from device: FSBlockDeviceResource, blockNumbers: Range<off_t>, blockSize: Int) throws -> Data {
        var data = Data(count: blockNumbers.count * blockSize)
        let startReadAt = Int64(blockNumbers.lowerBound) * Int64(blockSize)
        let length = Int(blockNumbers.count) * Int(blockSize)
        try data.withUnsafeMutableBytes { ptr in
            if useMetadataRead {
                try device.metadataRead(into: ptr, startingAt: startReadAt, length: length)
            } else {
                let actuallyRead = try device.read(into: ptr, startingAt: startReadAt, length: length)
                guard actuallyRead == length else {
                    logger.error("Expected to read \(length) bytes, actually read \(actuallyRead)")
                    throw POSIXError(.EIO)
                }
            }
        }
        
        return data
    }
    
    static func readSmallSection<T>(blockDevice: FSBlockDeviceResource, at offset: off_t) throws -> T? {
        var item: T?
        let blockSize = off_t(blockDevice.physicalBlockSize)
        let startReadAt = (offset / blockSize) * blockSize
        let targetContentOffset = Int(offset - startReadAt)
        let targetContentEnd = Int(targetContentOffset) + MemoryLayout<T>.size
        let readLength = targetContentEnd < blockSize ? Int(blockSize) : Int(blockSize) * 2
        try withUnsafeTemporaryAllocation(byteCount: readLength, alignment: 1) { ptr in
            if useMetadataRead {
                try blockDevice.metadataRead(into: ptr, startingAt: startReadAt, length: readLength)
            } else {
                let actuallyRead = try blockDevice.read(into: ptr, startingAt: startReadAt, length: readLength)
                guard actuallyRead == readLength else {
                    logger.error("Expected to read \(readLength) bytes, actually read \(actuallyRead)")
                    throw POSIXError(.EIO)
                }
            }
            withUnsafeTemporaryAllocation(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment) { itemPtr in
                itemPtr.copyMemory(from: UnsafeRawBufferPointer(rebasing: ptr[targetContentOffset..<targetContentEnd]))
                item = itemPtr.load(as: T.self)
            }
        }
        guard let item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        return item
    }
    static func readLittleEndian<T: FixedWidthInteger>(blockDevice: FSBlockDeviceResource, at offset: off_t) throws -> T {
        guard let item: T = try readSmallSection(blockDevice: blockDevice, at: offset) else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        return item.littleEndian
    }
    
    static func readBigEndian<T: FixedWidthInteger>(blockDevice: FSBlockDeviceResource, at offset: off_t) throws -> T {
        guard let item: T = try readSmallSection(blockDevice: blockDevice, at: offset) else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        return item.bigEndian
    }
    
    static func readUUID(blockDevice: FSBlockDeviceResource, at offset: off_t) throws -> UUID {
        guard let uuid: uuid_t = try readSmallSection(blockDevice: blockDevice, at: offset) else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        
        return UUID(uuid: uuid)
    }
    
    static func readString(blockDevice: FSBlockDeviceResource, at offset: off_t, maxLength: Int) throws -> String {
        // FIXME: do this better
        let startReadAt = (offset / off_t(blockDevice.physicalBlockSize)) * off_t(blockDevice.physicalBlockSize)
        let targetContentOffset = Int(offset - startReadAt)
        let targetContentEnd = Int(targetContentOffset) + maxLength
        let readLength = targetContentEnd < blockDevice.physicalBlockSize ? Int(blockDevice.physicalBlockSize) : Int(blockDevice.physicalBlockSize) * 2
        var string: String?
        try withUnsafeTemporaryAllocation(byteCount: readLength, alignment: 1) { ptr in
            if useMetadataRead {
                try blockDevice.metadataRead(into: ptr, startingAt: startReadAt, length: readLength)
            } else {
                let actuallyRead = try blockDevice.read(into: ptr, startingAt: startReadAt, length: readLength)
                guard actuallyRead == readLength else {
                    logger.error("Expected to read \(readLength) bytes, actually read \(actuallyRead)")
                    throw POSIXError(.EIO)
                }
            }
            let stringStart = ptr.baseAddress!.assumingMemoryBound(to: CChar.self) + targetContentOffset
            var cString = [CChar]()
            for i in 0..<maxLength {
                let char = (stringStart + i).pointee
                if char == 0 {
                    break
                }
                cString.append(char)
            }
            cString.append(0)
            // FIXME: UTF8?
            string = String(cString: cString, encoding: .utf8)
        }
        guard let string else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        return string
    }
}

struct Superblock {
    let blockDevice: FSBlockDeviceResource
    /// The byte offset on the block device at which the superblock starts.
    let offset: Int64
    
    private var data: Data
    
    init(blockDevice: FSBlockDeviceResource, offset: Int64) throws {
        self.blockDevice = blockDevice
        self.offset = offset
        
        let superblockSize = 1024
        self.data = Data(count: superblockSize)
        let actuallyRead = try self.data.withUnsafeMutableBytes { ptr in
            return try blockDevice.read(into: ptr, startingAt: offset, length: 1024)
        }
        guard actuallyRead == superblockSize else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
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
    var inodeCount: UInt32 { get { data.readLittleEndian(at: 0x0) } }
    /// Total block count.
    var blockCount: UInt32 { get { data.readLittleEndian(at: 0x4) } }
    /// This number of blocks can only be allocated by the super-user.
    var superUserBlockCount: UInt32 { get { data.readLittleEndian(at: 0x8) } }
    var freeBlockCount: UInt32 { get { data.readLittleEndian(at: 0xC) } }
    var freeInodeCount: UInt32 { get { data.readLittleEndian(at: 0x10) } }
    /// First data block.
    ///
    /// This must be at least 1 for 1k-block filesystems and is typically 0 for all other block sizes.
    var firstDataBlock: UInt32 { get { data.readLittleEndian(at: 0x14) } }
    /// Block size is 2 ^ (10 + `logBlockSize`).
    var logBlockSize: UInt32 { get { data.readLittleEndian(at: 0x18) } }
    var blockSize: Int {
        get {
            Int(pow(2, 10 + Double(logBlockSize)))
        }
    }
    /// Cluster size is (2 ^ `logClusterSize`) blocks if bigalloc is enabled. Otherwise `logClusterSize` must equal `logBlockSize`.
    var logClusterSize: UInt32 { get { data.readLittleEndian(at: 0x1C) } }
    var clusterSize: Int {
        get throws {
            Int(pow(2, Double(logClusterSize)))
        }
    }
    var blocksPerGroup: UInt32 { get { data.readLittleEndian(at: 0x20) } }
    var clustersPerGroup: UInt32 { get { data.readLittleEndian(at: 0x24) } }
    var inodesPerGroup: UInt32 { get { data.readLittleEndian(at: 0x28) } }
    /// Mount time, in seconds since the epoch.
    var mountTime: UInt32 { get { data.readLittleEndian(at: 0x2C) } }
    /// Write time, in seconds since the epoch.
    var writeTime: UInt32 { get { data.readLittleEndian(at: 0x30) } }
    /// Number of mounts since the last `fsck`.
    var mountCount: UInt16 { get { data.readLittleEndian(at: 0x34) } }
    /// Number of mounts beyond which a `fsck` is needed.
    var maxMountCount: UInt16 { get { data.readLittleEndian(at: 0x36) } }
    /// Magic signature, should be `0xEF53`.
    var magic: UInt16 { get { data.readLittleEndian(at: 0x38) } }
    var state: State { get { Superblock.State(rawValue: data.readLittleEndian(at: 0x3A)) } }
    var errors: ErrorPolicy { get throws { ErrorPolicy(rawValue: data.readLittleEndian(at: 0x3C)) ?? .unknown } }
    var minorRevisionLevel: UInt16 { get { data.readLittleEndian(at: 0x3E) } }
    /// Time of last check, in seconds since the epoch.
    var lastCheckTime: UInt32 { get { data.readLittleEndian(at: 0x40) } }
    var checkInterval: UInt32 { get { data.readLittleEndian(at: 0x44) } }
    var creatorOS: FilesystemCreator { get { FilesystemCreator(rawValue: data.readLittleEndian(at: 0x48)) ?? .unknown } }
    var revisionLevel: Revision { get { Revision(rawValue: data.readLittleEndian(at: 0x4C)) ?? .unknown } }
    var defaultReservedUid: UInt16 { get { data.readLittleEndian(at: 0x50) } }
    var defaultReservedGid: UInt16 { get { data.readLittleEndian(at: 0x52) } }
    
    // MARK: - `EXT4_DYNAMIC_REV` superblocks only
    var revisionSupportsDynamicInodeSizes: Bool {
        get {
            revisionLevel != .unknown && revisionLevel >= Revision.version2
        }
    }
    var firstNonReservedInode: UInt32 {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return 11
            }
            return data.readLittleEndian(at: 0x54)
        }
    }
    /// Size of inode structure, in bytes.
    var inodeSize: UInt16 {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return 128
            }
            return data.readLittleEndian(at: 0x58)
        }
    }
    var blockGroupNumber: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(at: 0x5A)
        }
    }
    var featureCompatibilityFlags: CompatibleFeatures {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return CompatibleFeatures()
            }
            return CompatibleFeatures(
                rawValue: data.readLittleEndian(
                    at: 0x5C
                )
            )
        }
    }
    var featureIncompatibleFlags: IncompatibleFeatures {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return IncompatibleFeatures()
            }
            return IncompatibleFeatures(
                rawValue: data.readLittleEndian(
                        at: 0x60
                    )
            )
        }
    }
    var readonlyFeatureCompatibilityFlags: ReadOnlyCompatibleFeatures {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return ReadOnlyCompatibleFeatures()
            }
            return ReadOnlyCompatibleFeatures(
                rawValue: data.readLittleEndian(
                        at: 0x64
                    )
            ) 
        }
    }
    var uuid: UUID? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readUUID(at: 0x68)
        }
    }
    /// Volume label, maximum length 16.
    var volumeName: String? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readString(
                    at: 0x78,
                    maxLength: 16
                )
        }
    }
    /// Directory where filesystem was last mounted, maximum length 64.
    var lastMountedDirectory: String? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readString(
                    at: 0x88,
                    maxLength: 64
                )
        }
    }
    var algorithmUsageBitmap: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data
                .readLittleEndian(at: 0xC8)
        }
    }
    
    // MARK: - Performance hints
    var preallocateBlocks: UInt8? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.directoryPreallocation) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xCC
            )
        }
    }
    var preallocateDirectoryBlock: UInt8? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.directoryPreallocation) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xCD
            )
        }
    }
    var reservedGDTblocks: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.directoryPreallocation) else {
                return nil
            }
            return data.readLittleEndian(at: 0xCE)
        }
    }
    
    // MARK: - Journalling support
    var journalUUID: UUID? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readUUID(
                at: 0xD0
            )
        }
    }
    var journalInodeNumber: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xE0
            )
        }
    }
    var journalDeviceNumber: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xE4
            )
        }
    }
    
    var lastOrphan: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xE8
            )
        }
    }
    //    var hashSeed: [UInt32] // size 4
    var defaultHashVersion: UInt8? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xFC
            )
        }
    }
    var journalBackupType: UInt8? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0xFD
            )
        }
    }
    var descriptorSize: UInt16 {
        get {
            guard revisionSupportsDynamicInodeSizes && featureIncompatibleFlags.contains(.enable64BitSize) else {
                return 32
            }
            return data.readLittleEndian(
                at: 0xFE
            )
        }
    }
    var defaultMountOptions: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x100
            )
        }
    }
    var firstMetablockBlockGroup: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x104
            )
        }
    }
    /// When the filesystem was created, in seconds since the epoch.
    var mkfsTime: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureCompatibilityFlags.contains(.journal) else {
                return nil
            }
            return data.readLittleEndian(at: 0x108)
        }
    }
//    var journalBlocks: [UInt32] // size 17
    
    // MARK: - 64-bit support
    var blocksCountHigh: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureIncompatibleFlags.contains(.enable64BitSize) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x150
            )
        }
    }
    var reservedBlocksCountHigh: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureIncompatibleFlags.contains(.enable64BitSize) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x154
            )
        }
    }
    var freeBlocksCountHigh: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureIncompatibleFlags.contains(.enable64BitSize) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x158
            )
        }
    }
    /// All inodes have at least `minimumExtraInodeSize` bytes.
    var minimumExtraInodeSize: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x15C
            )
        }
    }
    /// New inodes should reserve `wantExtraInodeSize` bytes.
    var wantExtraInodeSize: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x15E
            )
        }
    }
    var flags: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x160
            )
        }
    }
    var raidStride: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x164
            )
        }
    }
    var mmpInternal: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x166
            )
        }
    }
    var mmpBlock: UInt64? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x168
            )
        }
    }
    var raidStripeWidth: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x170
            )
        }
    }
    var logGroupsPerFlexibleGroup: UInt8? {
        get {
            guard revisionSupportsDynamicInodeSizes && featureIncompatibleFlags.contains(.flexibleBlockGroups) else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x174
            )
        }
    }
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
    var checksumType: UInt8? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x175
            )
        }
    }
    var reservedPad: UInt16? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x176
            )
        }
    }
    var kbytesWritten: UInt64? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x178
            )
        }
    }
    var snapshotInodeNumber: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x180
            )
        }
    }
    var snapshotId: UInt32? {
        get {
            guard revisionSupportsDynamicInodeSizes else {
                return nil
            }
            return data.readLittleEndian(
                at: 0x184
            )
        }
    }
}
