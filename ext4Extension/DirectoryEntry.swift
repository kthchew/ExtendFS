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
    let usesFiletype: Bool
    
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
    
    var inodePointee: UInt32! { BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x0) }
    var directoryEntryLength: UInt16! { BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x4) }
    var nameLength: UInt8! {
        BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x6)
    }
    var fileType: Filetype! {
        guard usesFiletype else { return nil }
        return Filetype(rawValue: BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x7)!)
        
    }
    var name: String! { BlockDeviceReader.readString(blockDevice: volume.resource, at: offset + 0x8, maxLength: Int(nameLength)) }
}
