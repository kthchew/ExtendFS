//
//  DirectoryEntry.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import DataKit
import FSKit

struct DirectoryEntry: ReadWritable {
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
    
    static var format: Format {
        \.inodePointee
        \.directoryEntryLength
        \.nameLength
        \.fileType?.rawValue
        Using(\.directoryEntryLength) { len in
            let prevLength = 8
            let remainingLength = Int(len) - prevLength
            Using(\.nameLength) { nameLen in
                Custom(\.name) { read in
                    guard let data = try? read.consume(remainingLength) else {
                        return ""
                    }
                    return data.readString(at: 0, maxLength: Int(nameLen))
                } write: { write, val in
                    let data = val.data(using: .utf8)
                    let size = data?.count ?? 0
                    // FIXME: no check if string is too long
                    write.append(data ?? Data())
                    write.append(Data(count: remainingLength - size))
                }
            }
        }
    }
    
    init(from context: DataKit.ReadContext<DirectoryEntry>) throws {
        self.inodePointee = try context.read(for: \.inodePointee)
        self.directoryEntryLength = try context.read(for: \.directoryEntryLength)
        self.nameLength = try context.read(for: \.nameLength)
        self.fileType = Filetype(rawValue: try context.read(for: \.fileType?.rawValue) ?? Filetype.unknown.rawValue)
        self.name = try context.read(for: \.name)
    }
    
//    init(volume: Ext4Volume, offset: Int64) throws {
//        self.inodePointee = try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x0)
//        self.directoryEntryLength = try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x4)
//        self.nameLength = try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x6)
//        self.fileType = volume.superblock.featureIncompatibleFlags.contains(.filetype) ? Filetype(rawValue: try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x7)) : nil
//        
//        let name = try BlockDeviceReader.readString(blockDevice: volume.resource, at: offset + 0x8, maxLength: Int(nameLength))
//        self.nameArray = try name.inlineArray()
//    }
    
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
