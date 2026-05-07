// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
#if canImport(FSKit)
import FSKit
#endif

public class DirectoryEntry {
    public enum Filetype: UInt8, Hashable {
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
    
    public init?(from data: Data, withParentInode parent: UInt32?) {
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
        
        guard let nameData = try? data.readSection(at: &offset, length: Int(nameLength)) else { return nil }
        self.name = nameData
        
        self.parentInode = parent
    }
    
    private init() {
        self.inodePointee = 0
        self.directoryEntryLength = 0
        self.nameLength = 0
        self.fileType = .unknown
        self.name = Data()
        self.referenceCount = 0
        self.parentInode = nil
    }
    
    static public func createEmptyEntry(with name: Data) -> DirectoryEntry {
        let entry = DirectoryEntry()
        entry.name = name
        entry.nameLength = UInt8(clamping: name.count)
        return entry
    }
    
    public func toData() throws -> Data {
        guard name.count == Int(nameLength) else { throw POSIXError(.EIO) }

        let entryLengthInt = Int(directoryEntryLength)
        guard entryLengthInt >= 8 + Int(nameLength) else { throw POSIXError(.EIO) }

        var data = Data()
        data.reserveCapacity(entryLengthInt)
        data.appendLittleEndian(inodePointee)
        data.appendLittleEndian(UInt16(directoryEntryLength))
        data.appendLittleEndian(UInt8(nameLength))
        data.appendLittleEndian(fileType?.rawValue ?? 0)
        data.append(name)
        if data.count < Int(directoryEntryLength) {
            data.append(Data(count: entryLengthInt - data.count))
        }
        guard data.count == entryLengthInt else { throw POSIXError(.EIO) }
        return data
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
    var name: Data
    var nameUTF8: String? {
        String(data: name, encoding: .utf8)
    }
    
    var checksum: UInt32?
    
    // MARK: - dcache properties
    var parentInode: UInt32?
    
    var referenceCount: Int = 0
    
    /// The previous node in the linked list of entries in the cache.
    ///
    /// This value must only be read or modified when you hold the dcache's ``DirectoryCache/state`` lock.
    var lruPrevious: DirectoryEntry?
    /// The previous node in the linked list of entries in the cache.
    ///
    /// This value must only be read or modified when you hold the dcache's ``DirectoryCache/state`` lock.
    var lruNext: DirectoryEntry?
}

extension DirectoryEntry: Equatable {
    public static func == (lhs: DirectoryEntry, rhs: DirectoryEntry) -> Bool {
        return lhs.inodePointee == rhs.inodePointee &&
        lhs.directoryEntryLength == rhs.directoryEntryLength &&
        lhs.nameLength == rhs.nameLength &&
        lhs.fileType == rhs.fileType &&
        lhs.name == rhs.name &&
        lhs.checksum == rhs.checksum &&
        lhs.parentInode == rhs.parentInode &&
        lhs.referenceCount == rhs.referenceCount &&
        lhs.lruPrevious == rhs.lruPrevious &&
        lhs.lruNext == rhs.lruNext
    }
}
