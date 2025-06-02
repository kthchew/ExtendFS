//
//  DirectoryEntry.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation

struct DirectoryEntry {
    let volume: Ext4Volume
    let offset: Int64
    
    enum Filetype: UInt8 {
        case unknown = 0
        case regular
        case directory
        case characterDevice
        case blockDevice
        case fifo
        case socket
        case symbolicLink
    }
    
    var inodePointee: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x0) } }
    var directoryEntryLength: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x4) } }
    var nameLength: UInt8 {
        get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x6) }
    }
    var fileType: Filetype! {
        get throws {
            guard volume.superblock.featureIncompatibleFlags.contains(.filetype) else { return nil }
            return Filetype(rawValue: try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x7))
        }
        
    }
    var name: String! { get throws { try BlockDeviceReader.readString(blockDevice: volume.resource, at: offset + 0x8, maxLength: Int(nameLength)) } }
}
