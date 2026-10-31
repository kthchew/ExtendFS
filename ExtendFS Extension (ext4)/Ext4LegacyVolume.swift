// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")

/// An object representing an ext2, ext3, or ext4 volume that conforms to FSKit's various Operations protocols.
///
/// This object is for use in versions of macOS prior to 27.0, where the Operations protocols were deprecated in favor of the Handler protocols.
/// It is separated from ``Ext4Volume`` to avoid compiler issues (FB24356249).
@available(macOS, deprecated: 27.0, renamed: "Ext4Volume")
class Ext4LegacyVolume: Ext4VolumeBase {}

extension Ext4LegacyVolume: FSVolume.Operations {}

extension Ext4LegacyVolume: FSVolume.ReadWriteOperations {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        return try await baseRead(from: item, at: offset, length: length, into: buffer)
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        return try await baseWrite(contents: contents, to: item, at: offset)
    }
}

extension Ext4LegacyVolume: FSVolumeKernelOffloadedIOOperations {
    func blockmapFile(_ file: FSItem, offset: off_t, length: Int, flags: FSBlockmapFlags, operationID: FSOperationID, packer: FSExtentPacker) async throws {
        return try await baseBlockmapFile(file, offset: offset, length: length, flags: flags, operationID: operationID, packer: packer)
    }
    
    func completeIO(for file: FSItem, offset: off_t, length: Int, status: any Error, flags: FSCompleteIOFlags, operationID: FSOperationID) async throws {
        return try await baseCompleteIO(for: file, offset: offset, length: length, status: status, flags: flags, operationID: operationID)
    }
    
    func createFile(name: FSFileName, in directory: FSItem, attributes: FSItem.SetAttributesRequest, packer: FSExtentPacker) async throws -> (FSItem, FSFileName) {
        return try await baseCreateFileAndPackEntries(name: name, in: directory, attributes: attributes, packer: packer)
    }
    
    func lookupItem(name: FSFileName, in directory: FSItem, packer: FSExtentPacker) async throws -> (FSItem, FSFileName) {
        return try await baseLookupItemAndPackEntries(name: name, in: directory, packer: packer)
    }
}

extension Ext4LegacyVolume: FSVolume.OpenCloseOperations {
    var isOpenCloseInhibited: Bool {
        get {
            true
        }
        set {}
    }
}

extension Ext4LegacyVolume: FSVolume.AccessCheckOperations {
    var isAccessCheckInhibited: Bool {
        get {
            // current implementation is just to work around an inability to really mark the volume as read-only
            // before macOS 26.5
            if #available(macOS 26.5, *) {
                return true
            }
            
            return false
        }
        set {}
    }
}

extension Ext4LegacyVolume: FSVolume.XattrOperations {}

extension Ext4LegacyVolume: FSVolume.RenameOperations {
    var isVolumeRenameInhibited: Bool {
        get {
            #if DEBUG
            false
            #else
            true
            #endif
        }
        set {}
    }
}

extension Ext4LegacyVolume: FSVolume.PreallocateOperations {
    var isPreallocateInhibited: Bool {
        get {
            true
        }
        set {}
    }
}

extension Ext4LegacyVolume: FSVolume.ItemDeactivation {}

