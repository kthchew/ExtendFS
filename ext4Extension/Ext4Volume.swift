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
    
    init(resource: FSBlockDeviceResource) throws {
        logger.log("Initializing volume")
        self.resource = resource
        self.superblock = try Superblock(blockDevice: resource, offset: 1024)
        
        try super.init(volumeID: FSVolume.Identifier(uuid: superblock.uuid ?? UUID()), volumeName: FSFileName(string: superblock.volumeName ?? ""))
        
        let endOfSuperblock = superblock.offset + 1024
        // FIXME: if this is nil, that's probably an error
        let blockSize = try superblock.blockSize
        let firstBlockAfterSuperblockOffset = Int64(ceil(Double(endOfSuperblock) / Double(blockSize))) * Int64(blockSize)
        logger.log("first block after superblock: \(firstBlockAfterSuperblockOffset, privacy: .public) \(endOfSuperblock) \(blockSize)")
        self.blockGroupDescriptors = try BlockGroupDescriptors(volume: self, offset: firstBlockAfterSuperblockOffset, blockGroupCount: Int(resource.blockCount) / Int(superblock.blocksPerGroup))
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
        capabilities.caseFormat = .sensitive
        return capabilities
    }
    
    var volumeStatistics: FSStatFSResult {
        let statistics = FSStatFSResult(fileSystemTypeName: "Linux Filesystem")
        do {
            statistics.blockSize = try superblock.blockSize
            statistics.totalBlocks = try UInt64(superblock.blockCount)
            statistics.freeBlocks = try UInt64(superblock.freeBlockCount)
            statistics.availableBlocks = try UInt64(superblock.freeBlockCount)
            statistics.usedBlocks = statistics.totalBlocks - statistics.freeBlocks
            statistics.freeFiles = try UInt64(superblock.freeInodeCount)
            statistics.ioSize = try superblock.blockSize
            
            if try superblock.featureIncompatibleFlags.contains(.extents) {
                statistics.fileSystemSubType = ExtendedFilesystemTypes.ext4.rawValue
            } else if try superblock.featureCompatibilityFlags.contains(.journal) {
                statistics.fileSystemSubType = ExtendedFilesystemTypes.ext3.rawValue
            } else {
                statistics.fileSystemSubType = ExtendedFilesystemTypes.ext2.rawValue
            }
            return statistics
        } catch {
            return statistics
        }
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
        
        guard let entries = try directory.directoryContents else {
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
        guard let item = item as? Ext4Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        guard let target = try item.symbolicLinkTarget else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        return FSFileName(string: target)
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
        
        guard let contents = try directory.directoryContents else {
            // TODO: throw or return?
//            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
            return verifier
        }
        
        let start = cookie == .initial ? 0 : cookie.rawValue
        for i in Int(start)..<contents.count {
            if let nameString = contents[i].name.string, attributes != nil && (nameString == "." || nameString == "..") {
                continue
            }
            guard packer.packEntry(name: contents[i].name, itemType: try contents[i].filetype, itemID: FSItem.Identifier(rawValue: UInt64(contents[i].inodeNumber)) ?? .invalid, nextCookie: FSDirectoryCookie(rawValue: UInt64(i+1)), attributes: attributes != nil ? contents[i].getAttributes(attributes!) : nil) else {
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
        
        let blockSize = try superblock.blockSize
        let blockOffset = Int(offset) / blockSize
        let blockLength = Int((Double(length) / Double(blockSize)).rounded(.up))
        let extents = try item.findExtentsCovering(Int64(blockOffset), with: blockLength)
        let firstLogicalBlock = offset / Int64(blockSize)
        // TODO: do read requests align to blocks? if not this offset is needed but that makes things more annoying
//        let offsetWithinFirstBlock = offset % Int64(try superblock.blockSize)
        var amountRead = 0
        let remainingLengthInFile = try off_t(item.size) - offset
        let actualLengthToRead = min(length, Int(remainingLengthInFile.roundUp(toMultipleOf: off_t(blockSize))))
        for extent in extents {
            guard amountRead < actualLengthToRead else {
                break
            }
            
            let startingAtLogicalBlock = amountRead == 0 ? firstLogicalBlock : extent.logicalBlock
            let startingAtPhysicalBlock = extent.physicalBlock + (startingAtLogicalBlock - extent.logicalBlock)
            let startingAtPhysicalByte = try startingAtPhysicalBlock * Int64(superblock.blockSize)
            let blockLengthConsidered = Int(extent.lengthInBlocks ?? 1) - Int(startingAtLogicalBlock - extent.logicalBlock)
            let readFromThisExtent = try min(actualLengthToRead - amountRead, blockLengthConsidered * superblock.blockSize)
            if let type = extent.type, type == .zeroFill {
                amountRead += readFromThisExtent
                continue
            }
            amountRead += try buffer.withUnsafeMutableBytes { ptr in
                return try resource.read(into: UnsafeMutableRawBufferPointer(rebasing: ptr[amountRead...]), startingAt: startingAtPhysicalByte, length: readFromThisExtent)
            }
        }
        return min(amountRead, Int(remainingLengthInFile))
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
        
        let blockSize = try superblock.blockSize
        
        let blockOffset = Int(offset) / blockSize
        let blockLength = (Int(offset) + length) / blockSize - blockOffset + 1
        let extents = try file.findExtentsCovering(Int64(blockOffset), with: blockLength)
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
