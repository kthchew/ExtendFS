//
//  Ext4Volume.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/28/25.
//

import Foundation
import FSKit

class Ext4Volume: FSVolume, FSVolume.Operations, FSVolume.PathConfOperations {
    init(resource: FSBlockDeviceResource) {
        self.resource = resource
        self.superblock = Superblock(blockDevice: resource, offset: 1024)
        
        super.init(volumeID: FSVolume.Identifier(uuid: superblock.uuid ?? UUID()), volumeName: FSFileName(string: superblock.volumeName ?? ""))
        
        let endOfSuperblock = superblock.offset + 1024
        // FIXME: if this is nil, that's probably an error
        let blockSize = superblock.blockSize ?? 4096
        let firstBlockAfterSuperblockOffset = Int64(ceil(Double(endOfSuperblock) / Double(blockSize))) * Int64(blockSize)
        self.blockGroupDescriptors = BlockGroupDescriptors(volume: self, offset: firstBlockAfterSuperblockOffset, blockGroupCount: Int(resource.blockCount) / Int(superblock.blocksPerGroup ?? 1))
    }
    
    private lazy var root: FSItem = {
        let item = Ext4Item(name: FSFileName(string: "/"), in: self, inodeNumber: 2)
        item.attributes.parentID = .parentOfRoot
        item.attributes.fileID = .rootDirectory
        item.attributes.uid = 0
        item.attributes.gid = 0
        item.attributes.linkCount = 1
        item.attributes.type = .directory
        item.attributes.mode = UInt32(S_IFDIR | 0b111_000_000)
        item.attributes.allocSize = 1
        item.attributes.size = 1
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
        return
    }
    
    func unmount() async {
        return
    }
    
    func synchronize(flags: FSSyncFlags) async throws {
        return
    }
    
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem) async throws -> FSItem.Attributes {
        throw ExtensionError.notImplemented
    }
    
    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem) async throws -> FSItem.Attributes {
        throw ExtensionError.notImplemented
    }
    
    func lookupItem(named name: FSFileName, inDirectory directory: FSItem) async throws -> (FSItem, FSFileName) {
        throw ExtensionError.notImplemented
    }
    
    func reclaimItem(_ item: FSItem) async throws {
        throw ExtensionError.notImplemented
    }
    
    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        throw ExtensionError.notImplemented
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest) async throws -> (FSItem, FSFileName) {
        throw ExtensionError.notImplemented
    }
    
    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName) async throws -> (FSItem, FSFileName) {
        throw ExtensionError.notImplemented
    }
    
    func createLink(to item: FSItem, named name: FSFileName, inDirectory directory: FSItem) async throws -> FSFileName {
        throw ExtensionError.notImplemented
    }
    
    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem) async throws {
        throw ExtensionError.notImplemented
    }
    
    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?) async throws -> FSFileName {
        throw ExtensionError.notImplemented
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker) async throws -> FSDirectoryVerifier {
        throw ExtensionError.notImplemented
    }
    
    func activate(options: FSTaskOptions) async throws -> FSItem {
        return root
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
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
