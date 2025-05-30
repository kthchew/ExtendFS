//
//  Ext4Volume.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/28/25.
//

import Foundation
import FSKit

class Ext4Volume: FSVolume, FSVolume.Operations, FSVolume.PathConfOperations {
    let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")
    
    init(resource: FSBlockDeviceResource) {
        logger.log("Initializing volume")
        self.resource = resource
        self.superblock = Superblock(blockDevice: resource, offset: 1024)
        
        super.init(volumeID: FSVolume.Identifier(uuid: superblock.uuid ?? UUID()), volumeName: FSFileName(string: superblock.volumeName ?? ""))
        
        let endOfSuperblock = superblock.offset + 1024
        // FIXME: if this is nil, that's probably an error
        let blockSize = superblock.blockSize ?? 4096
        let firstBlockAfterSuperblockOffset = Int64(ceil(Double(endOfSuperblock) / Double(blockSize))) * Int64(blockSize)
        logger.log("first block after superblock: \(firstBlockAfterSuperblockOffset, privacy: .public) \(endOfSuperblock) \(blockSize)")
        self.blockGroupDescriptors = BlockGroupDescriptors(volume: self, offset: firstBlockAfterSuperblockOffset, blockGroupCount: Int(resource.blockCount) / Int(superblock.blocksPerGroup ?? 1))
    }
    
    private lazy var root: FSItem = {
        let item = Ext4Item(name: FSFileName(string: "/"), in: self, inodeNumber: 2, parentInodeNumber: UInt32(FSItem.Identifier.parentOfRoot.rawValue))
        return item
    }()
    
    let resource: FSBlockDeviceResource
    /// The superblock in block group 0.
    var superblock: Superblock
    var blockGroupDescriptors: BlockGroupDescriptors!
    
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let capabilities = SupportedCapabilities()
        return capabilities
    }
    
    var volumeStatistics: FSStatFSResult {
        let statistics = FSStatFSResult(fileSystemTypeName: "ext4")
        statistics.blockSize = superblock.blockSize ?? 0
        statistics.totalBlocks = UInt64(superblock.blockCount ?? 0)
        statistics.freeBlocks = UInt64(superblock.freeBlockCount ?? 0)
        statistics.availableBlocks = UInt64(superblock.freeBlockCount ?? 0)
        statistics.usedBlocks = statistics.totalBlocks - statistics.freeBlocks
        statistics.freeFiles = UInt64(superblock.freeInodeCount ?? 0)
        return statistics
    }
    
    func mount(options: FSTaskOptions) async throws {
        logger.log("mount")
        return
    }
    
    func unmount() async {
        logger.log("unmount")
        return
    }
    
    func synchronize(flags: FSSyncFlags) async throws {
        logger.log("synchronize")
        return
    }
    
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem) async throws -> FSItem.Attributes {
        logger.log("attributes")
        guard let item = item as? Ext4Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        
        return item.getAttributes(desiredAttributes)
    }
    
    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem) async throws -> FSItem.Attributes {
        logger.log("setAttributes")
        throw fs_errorForPOSIXError(POSIXError.ENOSYS.rawValue)
    }
    
    func lookupItem(named name: FSFileName, inDirectory directory: FSItem) async throws -> (FSItem, FSFileName) {
        logger.log("lookupItem with name \(name.string ?? "unknown", privacy: .public)")
        guard let directory = directory as? Ext4Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        
        guard let entries = directory.directoryContents else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        for entry in entries {
            // strings need to be compared, not the names themselves apparently
            if entry.name.string == name.string {
                return (entry, name)
            }
        }
        
        throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
    }
    
    func reclaimItem(_ item: FSItem) async throws {
        logger.log("reclaimItem")
        throw ExtensionError.notImplemented
    }
    
    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        logger.log("readSymbolicLink")
        throw ExtensionError.notImplemented
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest) async throws -> (FSItem, FSFileName) {
        logger.log("createItem")
        throw ExtensionError.notImplemented
    }
    
    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName) async throws -> (FSItem, FSFileName) {
        logger.log("createSymbolicLink")
        throw ExtensionError.notImplemented
    }
    
    func createLink(to item: FSItem, named name: FSFileName, inDirectory directory: FSItem) async throws -> FSFileName {
        logger.log("createLink")
        throw ExtensionError.notImplemented
    }
    
    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem) async throws {
        logger.log("removeItem(_:named:fromDirectory:)")
        throw ExtensionError.notImplemented
    }
    
    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?) async throws -> FSFileName {
        logger.log("renameItem")
        throw ExtensionError.notImplemented
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker) async throws -> FSDirectoryVerifier {
        logger.log("enumerateDirectory")
        guard let directory = directory as? Ext4Item else {
            throw ExtensionError.notImplemented
        }
        
        guard let contents = directory.directoryContents else {
            // TODO: throw or return?
//            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
            return verifier
        }
        
        let start = cookie == .initial ? 0 : cookie.rawValue
        for i in Int(start)..<contents.count {
            if let nameString = contents[i].name.string, attributes != nil && (nameString == "." || nameString == "..") {
                continue
            }
            guard packer.packEntry(name: contents[i].name, itemType: contents[i].filetype, itemID: FSItem.Identifier(rawValue: UInt64(contents[i].inodeNumber)) ?? .invalid, nextCookie: FSDirectoryCookie(rawValue: UInt64(i+1)), attributes: attributes != nil ? contents[i].getAttributes(attributes!) : nil) else {
                break
            }
        }
        return verifier
    }
    
    func activate(options: FSTaskOptions) async throws -> FSItem {
        logger.log("activate")
        return root
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
        logger.log("deactivate")
        return
    }
    
    var maximumLinkCount: Int {
        -1
    }
    
    var maximumNameLength: Int {
        255
    }
    
    var restrictsOwnershipChanges: Bool {
        false
    }
    
    var truncatesLongNames: Bool {
        false
    }
}

extension Ext4Volume: FSVolume.ReadWriteOperations {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        guard let item = item as? Ext4Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        
        guard let blockSize = superblock.blockSize else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        
        let blockOffset = Int(offset) / blockSize
        let blockLength = (Int(offset) + length) / blockSize - blockOffset + 1
        guard let extents = item.extentTreeRoot?.findExtentsCovering(Int64(blockOffset), with: blockLength) else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        var amountRead = 0
        for extent in extents {
            amountRead += try buffer.withUnsafeMutableBytes { ptr in
                // FIXME: this is extremely wrong and will only work for the simplest cases
                return try resource.read(into: ptr, startingAt: extent.physicalBlock * Int64(superblock.blockSize!), length: min(length, Int(extent.lengthInBlocks ?? 1) * superblock.blockSize!))
            }
        }
        return amountRead
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        throw fs_errorForPOSIXError(POSIXError.ENOSYS.rawValue)
    }
}

extension Ext4Volume: FSVolumeKernelOffloadedIOOperations {
    func blockmapFile(_ file: FSItem, offset: off_t, length: Int, flags: FSBlockmapFlags, operationID: FSOperationID, packer: FSExtentPacker) async throws {
        logger.info("blockmapFile")
        guard let file = file as? Ext4Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        if flags.contains(.write) {
            throw fs_errorForPOSIXError(POSIXError.EPERM.rawValue)
        }
        
        guard let blockSize = superblock.blockSize else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        
        let blockOffset = Int(offset) / blockSize
        let blockLength = (Int(offset) + length) / blockSize - blockOffset + 1
        guard let extents = file.extentTreeRoot?.findExtentsCovering(Int64(blockOffset), with: blockLength) else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        for extent in extents {
            guard packer.packExtent(resource: resource, type: extent.type!, logicalOffset: extent.logicalBlock * Int64(blockSize), physicalOffset: extent.physicalBlock * Int64(blockSize), length: Int(extent.lengthInBlocks ?? 1) * Int(blockSize)) else {
                return
            }
        }
    }
    
    func completeIO(for file: FSItem, offset: off_t, length: Int, status: any Error, flags: FSCompleteIOFlags, operationID: FSOperationID) async throws {
        return
    }
    
    func createFile(name: FSFileName, in directory: FSItem, attributes: FSItem.SetAttributesRequest, packer: FSExtentPacker) async throws -> (FSItem, FSFileName) {
        throw fs_errorForPOSIXError(POSIXError.ENOSYS.rawValue)
    }
    
    func lookupItem(name: FSFileName, in directory: FSItem, packer: FSExtentPacker) async throws -> (FSItem, FSFileName) {
        return try await lookupItem(named: name, inDirectory: directory)
    }
}
