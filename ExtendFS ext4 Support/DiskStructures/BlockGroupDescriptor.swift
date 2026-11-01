// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

/// A structure that describes a block group.
///
/// There's one descriptor per "real" block group (as opposed to one per flexible block group).
public struct BlockGroupDescriptor {
    public struct Flags: OptionSet {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        
        public static let inodeTableAndBitmapNotInitialized = Flags(rawValue: 1 << 0)
        public static let blockBitmapNotInitialized = Flags(rawValue: 1 << 1)
        public static let inodeTableZeroed = Flags(rawValue: 1 << 2)
    }
    
    public init?(from data: Data) {
        var offset = 0
        
        guard let lowerBlockBitmapLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerBlockBitmapLocation = lowerBlockBitmapLocation
        guard let lowerInodeBitmapLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerInodeBitmapLocation = lowerInodeBitmapLocation
        guard let lowerInodeTableLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerInodeTableLocation = lowerInodeTableLocation
        guard let lowerFreeBlockCountLocation: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerFreeBlockCountLocation = lowerFreeBlockCountLocation
        guard let lowerFreeInodeCountLocation: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerFreeInodeCountLocation = lowerFreeInodeCountLocation
        guard let lowerUsedDirectoryCountLocation: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerUsedDirectoryCountLocation = lowerUsedDirectoryCountLocation
        guard let flags: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.flags = Flags(rawValue: flags)
        guard let lowerSnapshotExclusionBitmapLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerSnapshotExclusionBitmapLocation = lowerSnapshotExclusionBitmapLocation
        guard let lowerBlockBitmapChecksum: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerBlockBitmapChecksum = lowerBlockBitmapChecksum
        guard let lowerInodeBitmapChecksum: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerInodeBitmapChecksum = lowerInodeBitmapChecksum
        guard let lowerUnusedInodeCount: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.lowerUnusedInodeCount = lowerUnusedInodeCount
        guard let checksum: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.checksum = checksum
        
        // MARK: - 64-bit only
        guard let upperBlockBitmapLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperBlockBitmapLocation = upperBlockBitmapLocation
        guard let upperInodeBitmapLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperInodeBitmapLocation = upperInodeBitmapLocation
        guard let upperInodeTableLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperInodeTableLocation = upperInodeTableLocation
        guard let upperFreeBlockCountLocation: UInt16 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperFreeBlockCountLocation = upperFreeBlockCountLocation
        guard let upperFreeInodeCountLocation: UInt16 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperFreeInodeCountLocation = upperFreeInodeCountLocation
        guard let upperUsedDirectoryCountLocation: UInt16 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperUsedDirectoryCountLocation = upperUsedDirectoryCountLocation
        guard let upperUnusedInodeCount: UInt16 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperUnusedInodeCount = upperUnusedInodeCount
        guard let upperSnapshotExclusionBitmapLocation: UInt32 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperSnapshotExclusionBitmapLocation = upperSnapshotExclusionBitmapLocation
        guard let upperBlockBitmapChecksum: UInt16 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperBlockBitmapChecksum = upperBlockBitmapChecksum
        guard let upperInodeBitmapChecksum: UInt16 = try? data.readLittleEndian(at: &offset) else { return }
        self.upperInodeBitmapChecksum = upperInodeBitmapChecksum
    }
    
    public var lowerBlockBitmapLocation: UInt32
    public var lowerInodeBitmapLocation: UInt32
    public var lowerInodeTableLocation: UInt32
    public var lowerFreeBlockCountLocation: UInt16
    public var lowerFreeInodeCountLocation: UInt16
    public var lowerUsedDirectoryCountLocation: UInt16
    public var flags: Flags
    public var lowerSnapshotExclusionBitmapLocation: UInt32
    public var lowerBlockBitmapChecksum: UInt16
    public var lowerInodeBitmapChecksum: UInt16
    public var lowerUnusedInodeCount: UInt16
    public var checksum: UInt16
    
    // MARK: - 64-bit only
    public var upperBlockBitmapLocation: UInt32? = nil
    public var upperInodeBitmapLocation: UInt32? = nil
    public var upperInodeTableLocation: UInt32? = nil
    public var upperFreeBlockCountLocation: UInt16? = nil
    public var upperFreeInodeCountLocation: UInt16? = nil
    public var upperUsedDirectoryCountLocation: UInt16? = nil
    public var upperUnusedInodeCount: UInt16? = nil
    public var upperSnapshotExclusionBitmapLocation: UInt32? = nil
    public var upperBlockBitmapChecksum: UInt16? = nil
    public var upperInodeBitmapChecksum: UInt16? = nil
    
    public var blockBitmapLocation: UInt64? {
        get { UInt64.combine(upper: upperBlockBitmapLocation, lower: lowerBlockBitmapLocation) }
    }
    public var inodeBitmapLocation: UInt64? {
        get { UInt64.combine(upper: upperInodeBitmapLocation, lower: lowerInodeBitmapLocation) }
    }
    public var inodeTableLocation: UInt64? {
        get { UInt64.combine(upper: upperInodeTableLocation, lower: lowerInodeTableLocation) }
    }
    public var freeBlockCountLocation: UInt32? {
        get { UInt32.combine(upper: upperFreeBlockCountLocation, lower: lowerFreeBlockCountLocation) }
    }
    public var freeInodeCountLocation: UInt32? {
        get { UInt32.combine(upper: upperFreeInodeCountLocation, lower: lowerFreeInodeCountLocation) }
    }
    public var usedDirectoryCountLocation: UInt32? {
        get { UInt32.combine(upper: upperUsedDirectoryCountLocation, lower: lowerUsedDirectoryCountLocation) }
    }
    public var unusedInodeCount: UInt32? {
        get { UInt32.combine(upper: upperUnusedInodeCount, lower: lowerUnusedInodeCount) }
    }
    public var snapshotExclusionBitmapLocation: UInt64? {
        get { UInt64.combine(upper: upperSnapshotExclusionBitmapLocation, lower: lowerSnapshotExclusionBitmapLocation) }
    }
    public var blockBitmapChecksum: UInt32? {
        get { UInt32.combine(upper: upperBlockBitmapChecksum, lower: lowerBlockBitmapChecksum) }
    }
    public var inodeBitmapChecksum: UInt32? {
        get { UInt32.combine(upper: upperInodeBitmapChecksum, lower: lowerInodeBitmapChecksum) }
    }
}
