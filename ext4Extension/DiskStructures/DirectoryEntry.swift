//
//  DirectoryEntry.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit

struct DirectoryEntry {
    enum Filetype: UInt8 {
        case unknown = 0
        case regular
        case directory
        case characterDevice
        case blockDevice
        case fifo
        case socket
        case symbolicLink
        
        /// If the filetype is this value, this directory entry block is a phony block that contains the checksum.
        case checksum = 0xDE
    }
    
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let inodePointee: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.inodePointee = inodePointee
        guard let directoryEntryLength: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.directoryEntryLength = directoryEntryLength
        guard let nameLength: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.nameLength = nameLength
        // FIXME: may be part of the name length
        guard let fileTypeRaw: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.fileType = Filetype(rawValue: fileTypeRaw)
        
        guard let name = iterator.nextString(ofMaximumLength: Int(nameLength)) else { return nil }
        self.name = name
    }
    
    var inodePointee: UInt32
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
        case .checksum:
            return .unknown
        }
    }
    var name: String
    
    var checksum: UInt32?
}
