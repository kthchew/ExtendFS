// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")

/// An object representing an ext2, ext3, or ext4 volume that conforms to FSKit's various Handler protocols.
@available(macOS 27.0, *)
final class Ext4Volume: Ext4VolumeBase {}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.Handler {
    func activate(options: FSTaskOptions) async throws -> FSActivateResult {
        let root = try await baseActivate(options: options)
        guard let result = FSActivateResult(rootItem: root) else {
            logger.error("Failed to create activate result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
        try await baseDeactivate(options: options)
    }
    
    func mount(options: FSTaskOptions) async throws {
        try await baseMount(options: options)
    }
    
    func unmount() async {
        await baseUnmount()
    }
    
    func synchronize(flags: FSSyncFlags) async throws {
        try await baseSynchronize(flags: flags)
    }
    
    func lookupItem(named name: FSFileName, in directory: FSItem, context: FSContext) async throws -> FSLookupItemResult {
        let (item, itemName) = try await baseLookupItem(named: name, inDirectory: directory)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let attributes = item.getAttributes(FSLookupItemResult.requestedAttributes)
        guard let result = FSLookupItemResult(foundItem: item, itemName: itemName, itemAttributes: attributes) else {
            logger.error("Failed to create lookup item result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func reclaimItem(_ item: FSItem) async throws {
        try await baseReclaimItem(item)
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, in directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, context: FSContext) async throws -> FSCreateItemResult {
        let (item, itemName) = try await baseCreateItem(named: name, type: type, inDirectory: directory, attributes: newAttributes)
        guard let directory = directory as? Ext4Item else { throw POSIXError(.EIO) }
        let directoryAttributes = directory.getAttributes(FSCreateItemResult.requestedAttributes)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let itemAttributes = item.getAttributes(FSCreateItemResult.requestedAttributes)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSCreateItemResult(newItem: item, newItemName: itemName, newItemAttributes: itemAttributes, directoryAttributes: directoryAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create create item result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func createSymbolicLink(named name: FSFileName, in directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName, context: FSContext) async throws -> FSCreateSymlinkResult {
        let (item, itemName) = try await baseCreateSymbolicLink(named: name, inDirectory: directory, attributes: newAttributes, linkContents: contents)
        guard let directory = directory as? Ext4Item else { throw POSIXError(.EIO) }
        let directoryAttributes = directory.getAttributes(FSCreateSymlinkResult.requestedAttributes)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let itemAttributes = item.getAttributes(FSCreateSymlinkResult.requestedAttributes)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSCreateSymlinkResult(newItem: item, newItemName: itemName, newItemAttributes: itemAttributes, directoryAttributes: directoryAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create create symlink result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func createLink(to item: FSItem, named name: FSFileName, in directory: FSItem, context: FSContext) async throws -> FSCreateLinkResult {
        let name = try await baseCreateLink(to: item, named: name, inDirectory: directory)
        guard let directory = directory as? Ext4Item else { throw POSIXError(.EIO) }
        let directoryAttributes = directory.getAttributes(FSCreateLinkResult.requestedAttributes)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let linkAttributes = item.getAttributes(FSCreateLinkResult.requestedAttributes)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSCreateLinkResult(linkName: name, linkAttributes: linkAttributes, directoryAttributes: directoryAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create create link result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?, context: FSContext) async throws -> FSRenameItemResult {
        let newName = try await baseRenameItem(item, inDirectory: sourceDirectory, named: sourceName, to: destinationName, inDirectory: destinationDirectory, overItem: overItem)
        guard let sourceDirectory = sourceDirectory as? Ext4Item else { throw POSIXError(.EIO) }
        let sourceDirectoryAttributes = sourceDirectory.getAttributes(FSRenameItemResult.requestedAttributes)
        guard let destinationDirectory = destinationDirectory as? Ext4Item else { throw POSIXError(.EIO) }
        let destinationDirectoryAttributes = destinationDirectory.getAttributes(FSRenameItemResult.requestedAttributes)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let renamedItemAttributes = item.getAttributes(FSRenameItemResult.requestedAttributes)
        let overItemAttributes: FSItem.Attributes?
        if let overItem {
            guard let overItem = overItem as? Ext4Item else { throw POSIXError(.EIO) }
            overItemAttributes = overItem.getAttributes(FSRenameItemResult.requestedAttributes)
        } else {
            overItemAttributes = nil
        }
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSRenameItemResult(newName: newName, renamedItemAttributes: renamedItemAttributes, sourceDirectoryAttributes: sourceDirectoryAttributes, destinationDirectoryAttributes: destinationDirectoryAttributes, overItemAttributes: overItemAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create rename item result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func removeItem(_ item: FSItem, named name: FSFileName, from directory: FSItem, context: FSContext) async throws -> FSRemoveItemResult {
        try await baseRemoveItem(item, named: name, fromDirectory: directory)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let itemAttributes = item.getAttributes(FSRemoveItemResult.requestedAttributes)
        guard let directory = directory as? Ext4Item else { throw POSIXError(.EIO) }
        let directoryAttributes = directory.getAttributes(FSRemoveItemResult.requestedAttributes)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSRemoveItemResult(itemAttributes: itemAttributes, directoryAttributes: directoryAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create remove item result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem, context: FSContext) async throws -> FSGetAttributesResult {
        let attributes = try await baseAttributes(desiredAttributes, of: item)
        guard let result = FSGetAttributesResult(attributes: attributes) else {
            logger.error("Failed to create get attributes result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem, context: FSContext) async throws -> FSSetAttributesResult {
        let newAttributes = try await baseSetAttributes(newAttributes, on: item)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSSetAttributesResult(attributes: newAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create set attributes result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker, context: FSContext) async throws -> FSEnumerateDirectoryResult {
        let newVerifier = try await baseEnumerateDirectory(directory, startingAt: cookie, verifier: verifier, attributes: attributes, packer: packer)
        guard let result = FSEnumerateDirectoryResult(verifier: newVerifier.rawValue) else {
            logger.error("Failed to create enumerate directory result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func readSymbolicLink(_ item: FSItem, context: FSContext) async throws -> FSReadSymlinkResult {
        let location = try await baseReadSymbolicLink(item)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let attributes = item.getAttributes(FSReadSymlinkResult.requestedAttributes)
        guard let result = FSReadSymlinkResult(contents: location, symlinkAttributes: attributes) else {
            logger.error("Failed to create read symlink result")
            throw POSIXError(.EIO)
        }
        return result
    }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.KernelOffloadedIOHandler {
    func blockmapFile(_ file: FSItem, offset: off_t, length: Int, flags: FSBlockmapFlags, operationID: FSOperationID, packer: FSExtentPacker) async throws -> FSBlockmapResult {
        try await baseBlockmapFile(file, offset: offset, length: length, flags: flags, operationID: operationID, packer: packer)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSBlockmapResult(freeSpace: newFreeSpace) else {
            logger.error("Failed to create blockmap file result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func completeIO(for file: FSItem, offset: off_t, length: Int, status: any Error, flags: FSCompleteIOFlags, operationID: FSOperationID) async throws -> FSCompleteIOResult {
        try await baseCompleteIO(for: file, offset: offset, length: length, status: status, flags: flags, operationID: operationID)
        guard let file = file as? Ext4Item else { throw POSIXError(.EIO) }
        let attributes = file.getAttributes(FSCompleteIOResult.requestedAttributes)
        guard let result = FSCompleteIOResult(itemAttributes: attributes) else {
            logger.error("Failed to create complete IO result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func createFile(named name: FSFileName, in directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, packer: FSExtentPacker, context: FSContext) async throws -> FSCreateFileKOIOResult {
        let (item, itemName) = try await baseCreateFileAndPackEntries(name: name, in: directory, attributes: newAttributes, packer: packer)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let attributes = item.getAttributes(FSCreateFileKOIOResult.requestedAttributes)
        guard let directory = directory as? Ext4Item else { throw POSIXError(.EIO) }
        let directoryAttributes = directory.getAttributes(FSCreateFileKOIOResult.requestedAttributes)
        let newFreeSpace: FSFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSCreateFileKOIOResult(newItem: item, newItemName: itemName, newItemAttributes: attributes, directoryAttributes: directoryAttributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create create file (KOIO) result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func lookupItem(named name: FSFileName, in directory: FSItem, packer: FSExtentPacker, context: FSContext) async throws -> FSLookupItemKOIOResult {
        let (item, itemName) = try await baseLookupItemAndPackEntries(name: name, in: directory, packer: packer)
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let attributes = item.getAttributes(FSLookupItemKOIOResult.requestedAttributes)
        guard let result = FSLookupItemKOIOResult(foundItem: item, itemName: itemName, itemAttributes: attributes) else {
            logger.error("Failed to create lookup item (KOIO) result")
            throw POSIXError(.EIO)
        }
        return result
    }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.XattrHandler {
    func xattr(named name: FSFileName, of item: FSItem, context: FSContext) async throws -> FSGetXattrResult {
        let data = try await baseGetXattr(named: name, of: item)
        guard let result = FSGetXattrResult(xattrValue: data) else {
            logger.error("Failed to create get xattr result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func setXattr(named name: FSFileName, to value: Data?, on item: FSItem, policy: FSVolume.SetXattrPolicy, context: FSContext) async throws -> FSSetXattrResult {
        try await baseSetXattr(named: name, to: value, on: item, policy: policy)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSSetXattrResult(freeSpace: newFreeSpace) else {
            logger.error("Failed to create set xattr result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func xattrs(of item: FSItem, context: FSContext) async throws -> FSListXattrsResult {
        let xattrNames = try await baseListXattrs(of: item)
        guard let result = FSListXattrsResult(xattrNames: xattrNames) else {
            logger.error("Failed to create list xattrs result")
            throw POSIXError(.EIO)
        }
        return result
    }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.OpenCloseHandler {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes, context: FSContext) async throws {
        try await baseOpenItem(item, modes: modes)
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes, context: FSContext) async throws {
        try await baseCloseItem(item, modes: modes)
    }
    
    var isOpenCloseInhibited: Bool { true }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.ReadWriteHandler {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> FSReadFileResult {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let amountRead = try await baseRead(from: item, at: offset, length: length, into: buffer)
        let attributes = item.getAttributes(FSReadFileResult.requestedAttributes)
        guard let result = FSReadFileResult(bytesRead: amountRead, itemAttributes: attributes) else {
            logger.error("Failed to create read result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> FSWriteFileResult {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let amountWritten = try await baseWrite(contents: contents, to: item, at: offset)
        let attributes = item.getAttributes(FSWriteFileResult.requestedAttributes)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSWriteFileResult(bytesWritten: amountWritten, itemAttributes: attributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create write result")
            throw POSIXError(.EIO)
        }
        return result
    }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.AccessCheckHandler {
    func checkAccess(to theItem: FSItem, requestedAccess access: FSVolume.AccessMask, context: FSContext) async throws -> FSCheckAccessResult {
        let hasAccess = try await baseCheckAccess(to: theItem, requestedAccess: access)
        guard let result = FSCheckAccessResult(accessAllowed: hasAccess) else {
            logger.error("Failed to create check access result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    var isAccessCheckInhibited: Bool { true }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.RenameHandler {
    func setVolumeName(_ name: FSFileName, context: FSContext) async throws -> FSVolumeRenameResult {
        let newName = try await baseSetVolumeName(name)
        guard let result = FSVolumeRenameResult(newName: newName) else {
            logger.error("Failed to create volume rename result")
            throw POSIXError(.EIO)
        }
        return result
    }
    
    var isVolumeRenameInhibited: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.PreallocateHandler {
    func preallocateSpace(for item: FSItem, at offset: off_t, length: Int, flags: FSVolume.PreallocateFlags, context: FSContext) async throws -> FSPreallocateResult {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        let allocated = try await basePreallocateSpace(for: item, at: offset, length: length, flags: flags)
        let attributes = item.getAttributes(FSPreallocateResult.requestedAttributes)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSPreallocateResult(bytesAllocated: allocated, itemAttributes: attributes, freeSpace: newFreeSpace) else {
            logger.error("Failed to create preallocate result")
            throw POSIXError(.EIO)
        }
        return result
    }
}

@available(macOS 27.0, *)
extension Ext4Volume: FSVolume.ItemDeactivationHandler {
    var itemDeactivationPolicy: FSVolume.ItemDeactivationOptions {
        []
    }
    
    func deactivateItem(_ item: FSItem, context: FSContext) async throws -> FSDeactivateItemResult {
        try await baseDeactivateItem(item)
        let newFreeSpace = FSFreeSpace.noUpdate
        guard let result = FSDeactivateItemResult(freeSpace: newFreeSpace) else {
            logger.error("Failed to create deactivate item result")
            throw POSIXError(.EIO)
        }
        return result
    }
}
