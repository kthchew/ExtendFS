//
//  BlockGroupDescriptor.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit

/// A structure that describes a block group.
///
/// There's one descriptor per "real" block group (as opposed to one per flexible block group).
struct BlockGroupDescriptor {
    struct Flags: OptionSet {
        let rawValue: UInt16
        
        static let inodeTableAndBitmapNotInitialized = Flags(rawValue: 1 << 0)
        static let blockBitmapNotInitialized = Flags(rawValue: 1 << 1)
        static let inodeTableZeroed = Flags(rawValue: 1 << 2)
    }
    
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let lowerBlockBitmapLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lowerBlockBitmapLocation = lowerBlockBitmapLocation
        guard let lowerInodeBitmapLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lowerInodeBitmapLocation = lowerInodeBitmapLocation
        guard let lowerInodeTableLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lowerInodeTableLocation = lowerInodeTableLocation
        guard let lowerFreeBlockCountLocation: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.lowerFreeBlockCountLocation = lowerFreeBlockCountLocation
        guard let lowerFreeInodeCountLocation: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.lowerFreeInodeCountLocation = lowerFreeInodeCountLocation
        guard let lowerUsedDirectoryCountLocation: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.lowerUsedDirectoryCountLocation = lowerUsedDirectoryCountLocation
        guard let flags: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.flags = Flags(rawValue: flags)
        guard let lowerSnapshotExclusionBitmapLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.lowerSnapshotExclusionBitmapLocation = lowerSnapshotExclusionBitmapLocation
        guard let lowerBlockBitmapChecksum: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.lowerBlockBitmapChecksum = lowerBlockBitmapChecksum
        guard let lowerInodeBitmapChecksum: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.lowerInodeBitmapChecksum = lowerInodeBitmapChecksum
        guard let lowerUnusedInodeCount: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.lowerUnusedInodeCount = lowerUnusedInodeCount
        guard let checksum: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.checksum = checksum
        
        // MARK: - 64-bit only
        guard let upperBlockBitmapLocation: UInt32 = iterator.nextLittleEndian() else { return }
        self.upperBlockBitmapLocation = upperBlockBitmapLocation
        guard let upperInodeBitmapLocation: UInt32 = iterator.nextLittleEndian() else { return }
        self.upperInodeBitmapLocation = upperInodeBitmapLocation
        guard let upperInodeTableLocation: UInt32 = iterator.nextLittleEndian() else { return }
        self.upperInodeTableLocation = upperInodeTableLocation
        guard let upperFreeBlockCountLocation: UInt16 = iterator.nextLittleEndian() else { return }
        self.upperFreeBlockCountLocation = upperFreeBlockCountLocation
        guard let upperFreeInodeCountLocation: UInt16 = iterator.nextLittleEndian() else { return }
        self.upperFreeInodeCountLocation = upperFreeInodeCountLocation
        guard let upperUsedDirectoryCountLocation: UInt16 = iterator.nextLittleEndian() else { return }
        self.upperUsedDirectoryCountLocation = upperUsedDirectoryCountLocation
        guard let upperUnusedInodeCount: UInt16 = iterator.nextLittleEndian() else { return }
        self.upperUnusedInodeCount = upperUnusedInodeCount
        guard let upperSnapshotExclusionBitmapLocation: UInt32 = iterator.nextLittleEndian() else { return }
        self.upperSnapshotExclusionBitmapLocation = upperSnapshotExclusionBitmapLocation
        guard let upperBlockBitmapChecksum: UInt16 = iterator.nextLittleEndian() else { return }
        self.upperBlockBitmapChecksum = upperBlockBitmapChecksum
        guard let upperInodeBitmapChecksum: UInt16 = iterator.nextLittleEndian() else { return }
        self.upperInodeBitmapChecksum = upperInodeBitmapChecksum
    }
    
    var lowerBlockBitmapLocation: UInt32
    var lowerInodeBitmapLocation: UInt32
    var lowerInodeTableLocation: UInt32
    var lowerFreeBlockCountLocation: UInt16
    var lowerFreeInodeCountLocation: UInt16
    var lowerUsedDirectoryCountLocation: UInt16
    var flags: Flags
    var lowerSnapshotExclusionBitmapLocation: UInt32
    var lowerBlockBitmapChecksum: UInt16
    var lowerInodeBitmapChecksum: UInt16
    var lowerUnusedInodeCount: UInt16
    var checksum: UInt16
    
    // MARK: - 64-bit only
    // FIXME: these are not valid if 32-bit is not enabled
    var upperBlockBitmapLocation: UInt32? = nil
    var upperInodeBitmapLocation: UInt32? = nil
    var upperInodeTableLocation: UInt32? = nil
    var upperFreeBlockCountLocation: UInt16? = nil
    var upperFreeInodeCountLocation: UInt16? = nil
    var upperUsedDirectoryCountLocation: UInt16? = nil
    var upperUnusedInodeCount: UInt16? = nil
    var upperSnapshotExclusionBitmapLocation: UInt32? = nil
    var upperBlockBitmapChecksum: UInt16? = nil
    var upperInodeBitmapChecksum: UInt16? = nil
    
    var blockBitmapLocation: UInt64? {
        get { UInt64.combine(upper: upperBlockBitmapLocation, lower: lowerBlockBitmapLocation) }
    }
    var inodeBitmapLocation: UInt64? {
        get { UInt64.combine(upper: upperInodeBitmapLocation, lower: lowerInodeBitmapLocation) }
    }
    var inodeTableLocation: UInt64? {
        get { UInt64.combine(upper: upperInodeTableLocation, lower: lowerInodeTableLocation) }
    }
    var freeBlockCountLocation: UInt32? {
        get { UInt32.combine(upper: upperFreeBlockCountLocation, lower: lowerFreeBlockCountLocation) }
    }
    var freeInodeCountLocation: UInt32? {
        get { UInt32.combine(upper: upperFreeInodeCountLocation, lower: lowerFreeInodeCountLocation) }
    }
    var usedDirectoryCountLocation: UInt32? {
        get { UInt32.combine(upper: upperUsedDirectoryCountLocation, lower: lowerUsedDirectoryCountLocation) }
    }
    var unusedInodeCount: UInt32? {
        get { UInt32.combine(upper: upperUnusedInodeCount, lower: lowerUnusedInodeCount) }
    }
    var snapshotExclusionBitmapLocation: UInt64? {
        get { UInt64.combine(upper: upperSnapshotExclusionBitmapLocation, lower: lowerSnapshotExclusionBitmapLocation) }
    }
    var blockBitmapChecksum: UInt32? {
        get { UInt32.combine(upper: upperBlockBitmapChecksum, lower: lowerBlockBitmapChecksum) }
    }
    var inodeBitmapChecksum: UInt32? {
        get { UInt32.combine(upper: upperInodeBitmapChecksum, lower: lowerInodeBitmapChecksum) }
    }
}
