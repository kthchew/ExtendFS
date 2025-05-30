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
    static func readSmallSection<T>(blockDevice: FSBlockDeviceResource, at offset: off_t) throws -> T? {
        // FIXME: do this better (can the read be cached?)
        var item: T?
        let startReadAt = (offset / off_t(blockDevice.physicalBlockSize)) * off_t(blockDevice.physicalBlockSize)
        let targetContentOffset = Int(offset - startReadAt)
        let targetContentEnd = Int(targetContentOffset) + MemoryLayout<T>.size
        let readLength = targetContentEnd < blockDevice.physicalBlockSize ? Int(blockDevice.physicalBlockSize) : Int(blockDevice.physicalBlockSize) * 2
        Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item").log("reading small section at \(offset)\n\(startReadAt) \(targetContentOffset) \(targetContentEnd) \(readLength)")
        try withUnsafeTemporaryAllocation(byteCount: readLength, alignment: 1) { ptr in
            let read = try blockDevice.read(into: ptr, startingAt: startReadAt, length: readLength)
            Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item").log("read \(read)")
            if read >= targetContentEnd {
                withUnsafeTemporaryAllocation(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment) { itemPtr in
                    itemPtr.copyMemory(from: UnsafeRawBufferPointer(rebasing: ptr[targetContentOffset..<targetContentEnd]))
                    item = itemPtr.load(as: T.self)
                    Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item").log("copied item")
                }
                Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Item").log("item is now \(item.debugDescription, privacy: .public)")
//                let loaded = ptr.load(fromByteOffset: targetContentOffset, as: T.self)
            }
        }
        return item
    }
    static func readLittleEndian<T: FixedWidthInteger>(blockDevice: FSBlockDeviceResource, at offset: off_t) -> T? {
        do {
//            var item: T = 0
//            let bytesRead = try withUnsafeMutableBytes(of: &item) { ptr in
//                return try blockDevice.read(into: ptr, startingAt: offset, length: MemoryLayout<T>.size)
//            }
//            guard bytesRead == MemoryLayout<T>.size else {
//                return nil
//            }
//            return item.littleEndian
            
            let item: T? = try readSmallSection(blockDevice: blockDevice, at: offset)
            return item?.littleEndian
        } catch {
            return nil
        }
    }
    
    static func readBigEndian<T: FixedWidthInteger>(blockDevice: FSBlockDeviceResource, at offset: off_t) -> T? {
        do {
//            var item: T?
//            let bytesRead = try withUnsafeMutableBytes(of: &item) { ptr in
//                return try blockDevice.read(into: ptr, startingAt: offset, length: MemoryLayout<T>.size)
//            }
//            guard bytesRead == MemoryLayout<T>.size else {
//                return nil
//            }
//            return item?.bigEndian
            
            let item: T? = try readSmallSection(blockDevice: blockDevice, at: offset)
            return item?.bigEndian
        } catch {
            return nil
        }
    }
    
    static func readUUID(blockDevice: FSBlockDeviceResource, at offset: off_t) -> UUID? {
        do {
//            var uuid: uuid_t?
//            let bytesRead = try withUnsafeMutableBytes(of: &uuid) { ptr in
//                return try blockDevice.read(into: ptr, startingAt: offset, length: MemoryLayout<uuid_t>.size)
//            }
//            guard let uuid, bytesRead == MemoryLayout<uuid_t>.size else {
//                return nil
//            }
//            return UUID(uuid: uuid)
            
            let uuid: uuid_t? = try readSmallSection(blockDevice: blockDevice, at: offset)
            if let uuid {
                return UUID(uuid: uuid)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
    static func readString(blockDevice: FSBlockDeviceResource, at offset: off_t, maxLength: Int) -> String? {
        do {
//            let chars = try [CChar](unsafeUninitializedCapacity: length) { buffer, initializedCount in
//                let readBytes = try blockDevice.read(into: UnsafeMutableRawBufferPointer(buffer), startingAt: offset, length: length)
//                initializedCount = readBytes
//            }
//            return String(cString: chars + [0x0], encoding: .utf8)
            
            // FIXME: do this better
            let startReadAt = (offset / off_t(blockDevice.physicalBlockSize)) * off_t(blockDevice.physicalBlockSize)
            let targetContentOffset = Int(offset - startReadAt)
            let targetContentEnd = Int(targetContentOffset) + maxLength
            let readLength = targetContentEnd < blockDevice.physicalBlockSize ? Int(blockDevice.physicalBlockSize) : Int(blockDevice.physicalBlockSize) * 2
            var string: String?
            try withUnsafeTemporaryAllocation(byteCount: readLength, alignment: 1) { ptr in
                let read = try blockDevice.read(into: ptr, startingAt: startReadAt, length: readLength)
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
                if read >= targetContentEnd {
                    // FIXME: UTF8?
                    string = String(cString: cString, encoding: .utf8)
                }
            }
            return string
        } catch {
            return nil
        }
    }
}

struct Superblock {
    let blockDevice: FSBlockDeviceResource
    /// The byte offset on the block device at which the superblock starts.
    let offset: Int64
    
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
    }
    
    enum FilesystemCreator: UInt32 {
        case linux = 0
        case hurd = 1
        case masix = 2
        case freeBSD = 3
        case lites = 4
    }
    
    enum Revision: UInt32 {
        case original = 0
        /// Has dynamic inode sizes.
        case version2 = 1
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
        
        static let compression = IncompatibleFeatures(rawValue: 1 << 0)
        /// Directory entries record the file type.
        static let filetype = IncompatibleFeatures(rawValue: 1 << 1)
        static let needsRecovery = IncompatibleFeatures(rawValue: 1 << 2)
        static let separateJournalDevice = IncompatibleFeatures(rawValue: 1 << 3)
        static let metaBlockGroups = IncompatibleFeatures(rawValue: 1 << 4)
        static let extents = IncompatibleFeatures(rawValue: 1 << 5)
        static let enable64BitSize = IncompatibleFeatures(rawValue: 1 << 6)
        static let multipleMountProtection = IncompatibleFeatures(rawValue: 1 << 7)
        static let flexibleBlockGroups = IncompatibleFeatures(rawValue: 1 << 8)
        static let inodesCanStoreLargeExtendedAttributes = IncompatibleFeatures(rawValue: 1 << 9)
        static let dataInDirEntry = IncompatibleFeatures(rawValue: 1 << 10)
        static let metadataChecksumSeedInSuperblock = IncompatibleFeatures(rawValue: 1 << 11)
        static let largeDirectory = IncompatibleFeatures(rawValue: 1 << 12)
        static let inlineDataInInode = IncompatibleFeatures(rawValue: 1 << 13)
        static let encryptedInodes = IncompatibleFeatures(rawValue: 1 << 14)
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
    lazy var inodeCount: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x0)
    /// Total block count.
    lazy var blockCount: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4)
    /// This number of blocks can only be allocated by the super-user.
    lazy var superUserBlockCount: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8)
    lazy var freeBlockCount: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xC)
    lazy var freeInodeCount: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x10)
    /// First data block.
    ///
    /// This must be at least 1 for 1k-block filesystems and is typically 0 for all other block sizes.
    lazy var firstDataBlock: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x14)
    /// Block size is 2 ^ (10 + `logBlockSize`).
    var logBlockSize: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x18) }
    var blockSize: Int? {
        if let logBlockSize {
            Int(pow(2, 10 + Double(logBlockSize)))
        } else {
            nil
        }
    }
    /// Cluster size is (2 ^ `logClusterSize`) blocks if bigalloc is enabled. Otherwise `logClusterSize` must equal `logBlockSize`.
    var logClusterSize: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x1C) }
    var clusterSize: Int? {
        if let logClusterSize {
            Int(pow(2, Double(logClusterSize)))
        } else {
            nil
        }
    }
    lazy var blocksPerGroup: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x20)
    lazy var clustersPerGroup: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x24)
    lazy var inodesPerGroup: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x28)
    /// Mount time, in seconds since the epoch.
    lazy var mountTime: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x2C)
    /// Write time, in seconds since the epoch.
    lazy var writeTime: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x30)
    /// Number of mounts since the last `fsck`.
    lazy var mountCount: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x34)
    /// Number of mounts beyond which a `fsck` is needed.
    lazy var maxMountCount: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x36)
    /// Magic signature, should be `0xEF53`.
    lazy var magic: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x38)
    lazy var state: State = Superblock.State(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x3A) ?? 0)
    lazy var errors: ErrorPolicy? = ErrorPolicy(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x3C) ?? 0)
    lazy var minorRevisionLevel: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x3E)
    /// Time of last check, in seconds since the epoch.
    lazy var lastCheckTime: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x40)
    lazy var checkInterval: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x44)
    lazy var creatorOS: FilesystemCreator? = FilesystemCreator(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x48) ?? UInt32.max)
    lazy var revisionLevel: Revision? = Revision(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4C) ?? UInt32.max)
    lazy var defaultReservedUid: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x50)
    lazy var defaultReservedGid: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x52)
    
    // MARK: - `EXT4_DYNAMIC_REV` superblocks only
    lazy var firstNonReservedInode: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x54)
    /// Size of inode structure, in bytes.
    lazy var inodeSize: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x58)
    lazy var blockGroupNumber: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x5A)
    lazy var featureCompatibilityFlags: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x5C)
    lazy var featureIncompatibleFlags: IncompatibleFeatures? = IncompatibleFeatures(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x60) ?? 0)
    lazy var readonlyFeatureCompatibilityFlags: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x64)
    lazy var uuid: UUID? = BlockDeviceReader.readUUID(blockDevice: blockDevice, at: offset + 0x68)
    /// Volume label, maximum length 16.
    lazy var volumeName: String? = BlockDeviceReader.readString(blockDevice: blockDevice, at: offset + 0x78, maxLength: 16)
    /// Directory where filesystem was last mounted, maximum length 64.
    lazy var lastMounted: String? = BlockDeviceReader.readString(blockDevice: blockDevice, at: offset + 0x88, maxLength: 64)
    lazy var algorithmUsageBitmap: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xC8)
    
    // MARK: - Performance hints
    lazy var preallocateBlocks: UInt8? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xCC)
    lazy var preallocateDirectoryBlock: UInt8? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xCD)
    lazy var reservedGDTblocks: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xCE)
    
    // MARK: - Journalling support
    lazy var journalUUID: UUID? = BlockDeviceReader.readUUID(blockDevice: blockDevice, at: offset + 0xD0)
    lazy var journalInodeNumber: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xE0)
    lazy var journalDeviceNumber: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xE4)
    
    lazy var lastOrphan: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xE8)
//    lazy var hashSeed: [UInt32] // size 4
    lazy var defaultHashVersion: UInt8? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xFC)
    lazy var journalBackupType: UInt8? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xFD)
    lazy var descriptorSize: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0xFE)
    lazy var defaultMountOptions: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x100)
    lazy var firstMetablockBlockGroup: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x104)
    /// When the filesystem was created, in seconds since the epoch.
    lazy var mkfsTime: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x108)
//    lazy var journalBlocks: [UInt32] // size 17
    
    // MARK: - 64-bit support
    lazy var blocksCountHigh: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x150)
    lazy var reservedBlocksCountHigh: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x154)
    lazy var freeBlocksCountHigh: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x158)
    /// All inodes have at least `minimumExtraInodeSize` bytes.
    lazy var minimumExtraInodeSize: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x15C)
    /// New inodes should reserve `wantExtraInodeSize` bytes.
    lazy var wantExtraInodeSize: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x15E)
    lazy var flags: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x160)
    lazy var raidStride: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x164)
    lazy var mmpInternal: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x166)
    lazy var mmpBlock: UInt64? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x168)
    lazy var raidStripeWidth: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x170)
    lazy var logGroupsPerFlexibleGroup: UInt8? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x174)
    lazy var checksumType: UInt8? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x175)
    lazy var reservedPad: UInt16? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x176)
    lazy var kbytesWritten: UInt64? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x178)
    lazy var snapshotInodeNumber: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x180)
    lazy var snapshotId: UInt32? = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x184)
}
