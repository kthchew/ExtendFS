//
//  Ext4Item.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/28/25.
//

import Foundation
import FSKit

class Ext4Item: FSItem {
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
    
    var blockGroupNumber: UInt32? {
        if let inodesPerGroup = containingVolume.superblock.inodesPerGroup {
            (inodeNumber - 1) / inodesPerGroup
        } else {
            nil
        }
    }
    var blockGroupDescriptor: BlockGroupDescriptor? {
        if let blockGroupNumber {
            containingVolume.blockGroupDescriptors[Int(blockGroupNumber)]
        } else {
            nil
        }
    }
    var groupInodeTableIndex: UInt32? {
        if let inodesPerGroup = containingVolume.superblock.inodesPerGroup {
            (inodeNumber - 1) % inodesPerGroup
        } else {
            nil
        }
    }
    var inodeTableOffset: UInt64? {
        // FIXME: not all inode entries are necessarily the same size - see https://www.kernel.org/doc/html/v4.19/filesystems/ext4/ondisk/index.html#inode-size
        // this might be correct though since the records should be the correct size?
        if let groupInodeTableIndex, let inodeSize = containingVolume.superblock.inodeSize {
            UInt64(groupInodeTableIndex) * UInt64(inodeSize)
        } else {
            nil
        }
    }
    /// The offset of the inode table entry on the disk.
    // FIXME: should not force unwrap
    var inodeLocation: Int64! {
        if let inodeTableOffset, let inodeTableLocation = blockGroupDescriptor?.inodeTableLocation {
            Int64(inodeTableLocation + inodeTableOffset)
        } else {
            nil
        }
    }
    
    let name: FSFileName
    let attributes = FSItem.Attributes()
    
    init(name: FSFileName, in volume: Ext4Volume, inodeNumber: UInt32) {
        self.name = name
        self.containingVolume = volume
        self.inodeNumber = inodeNumber
    }
    
    var mode: Mode? {
        if let inodeLocation {
            Mode(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x0) ?? 0)
        } else {
            nil
        }
    }
    var lowerUID: UInt16? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x2) }
    var lowerSize: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x4) }
    /// Last access time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var storedAccessTime: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x8) }
    /// Last inode change time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var storedChangeTime: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0xC) }
    /// Last data modification time in seconds since the epoch, or the checksum of the value if the `largeXattrInDataBlocks` flag is set.
    var storedModificationTime: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x10) }
    var deletionTime: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x14) }
    var lowerGID: UInt16? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x18) }
    /// Hard link count.
    ///
    /// Normally, ext4 does not permit an inode to have more than 65,000 hard links. This applies to files as well as directories, which means that there cannot be more than 64,998 subdirectories in a directory (each subdirectory’s `..` entry counts as a hard link, as does the `.` entry in the directory itself). With the `DIR_NLINK` feature enabled, ext4 supports more than 64,998 subdirectories by setting this field to 1 to indicate that the number of hard links is not known.
    var hardLinkCount: UInt16? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x1A) }
    var lowerBlockCount: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x1C) }
    var flags: Flags? {
        if let inodeLocation {
            Flags(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x20) ?? 0)
        } else {
            nil
        }
    }
    var fileGenerationForNFS: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x64) }
    var lowerExtendedAttributeBlock: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x68) }
    var upperSize: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: containingVolume.resource, at: inodeLocation + 0x1A) }
    
    // TODO: extra bits from extended fields, actual file contents, osd values
}
