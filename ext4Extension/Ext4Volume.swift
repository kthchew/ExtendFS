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
        let item = Ext4Item(name: FSFileName(string: "/"), in: self, inodeNumber: 2)
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
