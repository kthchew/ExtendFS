//
//  DirectoryEntry.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit

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
    
    init(volume: Ext4Volume, offset: Int64, inodeParent: UInt32) throws {
        self.volume = volume
        self.offset = offset
        
        self.inodePointee = try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x0)
        self.inodeParent = inodeParent
        self.directoryEntryLength = try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x4)
        self.nameLength = try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x6)
        self.fileType = volume.superblock.featureIncompatibleFlags.contains(.filetype) ? Filetype(rawValue: try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x7)) : nil
        self.name = try BlockDeviceReader.readString(blockDevice: volume.resource, at: offset + 0x8, maxLength: Int(nameLength))
    }
    
    init(volume: Ext4Volume, offset: Int64, inodePointee: UInt32, inodeParent: UInt32, directoryEntryLength: UInt16, nameLength: UInt8, fileType: Filetype? = nil, name: String) {
        self.volume = volume
        self.offset = offset
        self.inodePointee = inodePointee
        self.inodeParent = inodeParent
        self.directoryEntryLength = directoryEntryLength
        self.nameLength = nameLength
        self.fileType = fileType
        self.name = name
    }
    
    var inodePointee: UInt32
    var inodeParent: UInt32
    var directoryEntryLength: UInt16
    var nameLength: UInt8
    var fileType: Filetype?
    var fskitFileType: FSItem.ItemType? {
        guard let fileType else { return nil }
        switch fileType {
        case .unknown:
            return .unknown
        case .regular:
            return .file
        case .directory:
            return .directory
        case .characterDevice:
            return .charDevice
        case .blockDevice:
            return .blockDevice
        case .fifo:
            return .fifo
        case .socket:
            return .socket
        case .symbolicLink:
            return .symlink
        }
    }
    var name: String
    
    func getItem() async throws -> Ext4Item {
        // FIXME: won't be cached
        return try await Ext4Item(name: FSFileName(string: self.name), in: volume, inodeNumber: self.inodePointee, parentInodeNumber: self.inodeParent)
    }
}
