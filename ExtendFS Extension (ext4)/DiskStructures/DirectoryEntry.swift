// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
#if canImport(FSKit)
import FSKit
#endif

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
        var offset = 0
        
        guard let inodePointee: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.inodePointee = inodePointee
        guard let directoryEntryLength: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.directoryEntryLength = directoryEntryLength
        guard let nameLength: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.nameLength = nameLength
        // FIXME: may be part of the name length
        guard let fileTypeRaw: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.fileType = Filetype(rawValue: fileTypeRaw)
        
        guard let name = try? data.readString(at: &offset, maxLength: Int(nameLength)) else { return nil }
        self.name = name
    }
    
    var inodePointee: UInt32
    var directoryEntryLength: UInt16
    var nameLength: UInt8
    var fileType: Filetype?
    #if canImport(FSKit)
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
    #endif
    var name: String
    
    var checksum: UInt32?
}
