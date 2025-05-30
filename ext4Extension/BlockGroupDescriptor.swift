//
//  BlockGroupDescriptor.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit

extension UInt64 {
    static func combine(upper: UInt32, lower: UInt32) -> UInt64 {
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    static func combine(upper: UInt32?, lower: UInt32?) -> UInt64? {
        guard let lower else { return nil }
        guard let upper else { return UInt64(lower) }
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    
    static func combine(upper: UInt16, lower: UInt32) -> UInt64 {
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    static func combine(upper: UInt16?, lower: UInt32?) -> UInt64? {
        guard let lower else { return nil }
        guard let upper else { return UInt64(lower) }
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    
    static func combine(upper: UInt32, lower: UInt16) -> UInt64 {
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    static func combine(upper: UInt32?, lower: UInt16?) -> UInt64? {
        guard let lower else { return nil }
        guard let upper else { return UInt64(lower) }
        return (UInt64(upper) << 32) | UInt64(lower)
    }
}

extension UInt32 {
    static func combine(upper: UInt16, lower: UInt16) -> UInt32 {
        return (UInt32(upper) << 16) | UInt32(lower)
    }
    
    static func combine(upper: UInt16?, lower: UInt16?) -> UInt32? {
        guard let lower else { return nil }
        guard let upper else { return UInt32(lower) }
        return (UInt32(upper) << 16) | UInt32(lower)
    }
}

struct BlockGroupDescriptor {
    let volume: Ext4Volume
    /// The byte offset on the block device at which the descriptor starts.
    let offset: Int64
    
    struct Flags: OptionSet {
        let rawValue: UInt16
        
        static let inodeTableAndBitmapNotInitialized = Flags(rawValue: 1 << 0)
        static let blockBitmapNotInitialized = Flags(rawValue: 1 << 1)
        static let inodeTableZeroed = Flags(rawValue: 1 << 2)
    }
    
    var lowerBlockBitmapLocation: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x0) } }
    var lowerInodeBitmapLocation: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x4) } }
    var lowerInodeTableLocation: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x8) } }
    var lowerFreeBlockCountLocation: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0xC) } }
    var lowerFreeInodeCountLocation: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0xE) } }
    var lowerUsedDirectoryCountLocation: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x10) } }
    var flags: Flags { get throws { Flags(rawValue: try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x12)) } }
    var lowerSnapshotExclusionBitmapLocation: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x14) } }
    var lowerBlockBitmapChecksum: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x18) } }
    var lowerInodeBitmapChecksum: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x1A) } }
    var lowerUnusedInodeCount: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x1C) } }
    var checksum: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x1E) } }
    
    // MARK: - 64-bit only
    // FIXME: these are not valid if 32-bit is not enabled
    var upperBlockBitmapLocation: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x20) } }
    var upperInodeBitmapLocation: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x24) } }
    var upperInodeTableLocation: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x28) } }
    var upperFreeBlockCountLocation: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x2C) } }
    var upperFreeInodeCountLocation: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x2E) } }
    var upperUsedDirectoryCountLocation: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x30) } }
    var upperUnusedInodeCount: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x32) } }
    var upperSnapshotExclusionBitmapLocation: UInt32? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x34) } }
    var upperBlockBitmapChecksum: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x38) } }
    var upperInodeBitmapChecksum: UInt16? { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x3A) } }
    
    var blockBitmapLocation: UInt64? {
        get throws { try UInt64.combine(upper: upperBlockBitmapLocation, lower: lowerBlockBitmapLocation) }
    }
    var inodeBitmapLocation: UInt64? {
        get throws { try UInt64.combine(upper: upperInodeBitmapLocation, lower: lowerInodeBitmapLocation) }
    }
    var inodeTableLocation: UInt64? {
        get throws { try UInt64.combine(upper: upperInodeTableLocation, lower: lowerInodeTableLocation) }
    }
    var freeBlockCountLocation: UInt32? {
        get throws { try UInt32.combine(upper: upperFreeBlockCountLocation, lower: lowerFreeBlockCountLocation) }
    }
    var freeInodeCountLocation: UInt32? {
        get throws { try UInt32.combine(upper: upperFreeInodeCountLocation, lower: lowerFreeInodeCountLocation) }
    }
    var usedDirectoryCountLocation: UInt32? {
        get throws { try UInt32.combine(upper: upperUsedDirectoryCountLocation, lower: lowerUsedDirectoryCountLocation) }
    }
    var unusedInodeCount: UInt32? {
        get throws { try UInt32.combine(upper: upperUnusedInodeCount, lower: lowerUnusedInodeCount) }
    }
    var snapshotExclusionBitmapLocation: UInt64? {
        get throws { try UInt64.combine(upper: upperSnapshotExclusionBitmapLocation, lower: lowerSnapshotExclusionBitmapLocation) }
    }
    var blockBitmapChecksum: UInt32? {
        get throws { try UInt32.combine(upper: upperBlockBitmapChecksum, lower: lowerBlockBitmapChecksum) }
    }
    var inodeBitmapChecksum: UInt32? {
        get throws { try UInt32.combine(upper: upperInodeBitmapChecksum, lower: lowerInodeBitmapChecksum) }
    }
}
