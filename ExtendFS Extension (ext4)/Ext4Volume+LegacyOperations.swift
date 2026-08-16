// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")

extension Ext4Volume: FSVolume.Operations {
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem) async throws -> FSItem.Attributes {
        return try await baseAttributes(desiredAttributes, of: item)
    }
    
    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem) async throws -> FSItem.Attributes {
        return try await baseSetAttributes(newAttributes, on: item)
    }
    
    func lookupItem(named name: FSFileName, inDirectory directory: FSItem) async throws -> (FSItem, FSFileName) {
        return try await baseLookupItem(named: name, inDirectory: directory)
    }
    
    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        return try await baseReadSymbolicLink(item)
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest) async throws -> (FSItem, FSFileName) {
        return try await baseCreateItem(named: name, type: type, inDirectory: directory, attributes: newAttributes)
    }
    
    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName) async throws -> (FSItem, FSFileName) {
        return try await baseCreateSymbolicLink(named: name, inDirectory: directory, attributes: newAttributes, linkContents: contents)
    }
    
    func createLink(to item: FSItem, named name: FSFileName, inDirectory directory: FSItem) async throws -> FSFileName {
        return try await baseCreateLink(to: item, named: name, inDirectory: directory)
    }
    
    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem) async throws {
        return try await baseRemoveItem(item, named: name, fromDirectory: directory)
    }
    
    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?) async throws -> FSFileName {
        return try await baseRenameItem(item, inDirectory: sourceDirectory, named: sourceName, to: destinationName, inDirectory: destinationDirectory, overItem: overItem)
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker) async throws -> FSDirectoryVerifier {
        return try await baseEnumerateDirectory(directory, startingAt: cookie, verifier: verifier, attributes: attributes, packer: packer)
    }
    
    func activate(options: FSTaskOptions) async throws -> FSItem {
        return try await baseActivate(options: options)
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
        return try await baseDeactivate(options: options)
    }
}

extension Ext4Volume: FSVolume.ReadWriteOperations {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        return try await baseRead(from: item, at: offset, length: length, into: buffer)
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        return try await baseWrite(contents: contents, to: item, at: offset)
    }
}

extension Ext4Volume: FSVolumeKernelOffloadedIOOperations {
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

extension Ext4Volume: FSVolume.OpenCloseOperations {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        return try await baseOpenItem(item, modes: modes)
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        return try await baseCloseItem(item, modes: modes)
    }
    
    var isOpenCloseInhibited: Bool {
        get {
            true
        }
        set {}
    }
}

extension Ext4Volume: FSVolume.AccessCheckOperations {
    func checkAccess(to theItem: FSItem, requestedAccess access: FSVolume.AccessMask) async throws -> Bool {
        let writeAccess: FSVolume.AccessMask = [.addFile, .addSubdirectory, .appendData, .delete, .deleteChild, .takeOwnership, .writeAttributes, .writeData, .writeSecurity, .writeXattr]
        if readOnly && !access.isDisjoint(with: writeAccess) {
            return false
        }
        
        return try await baseCheckAccess(to: theItem, requestedAccess: access)
    }
    
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

extension Ext4Volume: FSVolume.XattrOperations {
    func xattr(named name: FSFileName, of item: FSItem) async throws -> Data {
        return try await baseGetXattr(named: name, of: item)
    }
    
    func setXattr(named name: FSFileName, to value: Data?, on item: FSItem, policy: FSVolume.SetXattrPolicy) async throws {
        return try await baseSetXattr(named: name, to: value, on: item, policy: policy)
    }
    
    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        return try await baseListXattrs(of: item)
    }
}

extension Ext4Volume: FSVolume.RenameOperations {
    func setVolumeName(_ name: FSFileName) async throws -> FSFileName {
        return try await baseSetVolumeName(name)
    }
    
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

extension Ext4Volume: FSVolume.PreallocateOperations {
    func preallocateSpace(for item: FSItem, at offset: off_t, length: Int, flags: FSVolume.PreallocateFlags) async throws -> Int {
        return try await basePreallocateSpace(for: item, at: offset, length: length, flags: flags)
    }
    
    var isPreallocateInhibited: Bool {
        get {
            true
        }
        set {}
    }
}

extension Ext4Volume: FSVolume.ItemDeactivation {
    var itemDeactivationPolicy: FSVolume.ItemDeactivationOptions {
        []
    }
    
    func deactivateItem(_ item: FSItem) async throws {
        return try await baseDeactivateItem(item)
    }
}
    
