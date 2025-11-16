//
//  Ext4Volume.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/28/25.
//

import Algorithms
import Foundation
import FSKit

actor VolumeCache {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")
    
    /// The key is the block containing the relevant inode entries.
    var usedItemsInInodeTable = [Int64: Set<UInt32>]()
    func addInode(inodeNumber: UInt32, blockNumber: Int64) {
        usedItemsInInodeTable[blockNumber, default: []].insert(inodeNumber)
    }
    func removeInode(inodeNumber: UInt32, blockNumber: Int64) {
        usedItemsInInodeTable[blockNumber]?.remove(inodeNumber)
        items[inodeNumber] = nil
        if let usedItems = usedItemsInInodeTable[blockNumber], usedItems.isEmpty {
            Self.logger.debug("Last inode in block \(blockNumber, privacy: .public) freed")
            usedItemsInInodeTable[blockNumber] = nil
            inodeTableBlocks[blockNumber] = nil
        }
    }
    /// The key is the block for the given inode table.
    var inodeTableBlocks = [Int64: Data]()
    func setInodeTableBlock(_ data: Data?, forBlock blockNumber: Int64) {
        inodeTableBlocks[blockNumber] = data
    }
    
    /// The key is the inode number.
    var items = [UInt32: Ext4Item]()
    func setItem(_ item: Ext4Item?, forInodeNumber inodeNumber: UInt32) {
        items[inodeNumber] = item
    }
    func fetchItem(forInodeNumber inodeNumber: UInt32) -> Ext4Item? {
        return items[inodeNumber]
    }
}

class Ext4Volume: FSVolume, FSVolume.Operations, FSVolume.PathConfOperations {
    let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")
    
    init(resource: FSBlockDeviceResource, fileSystem: FSUnaryFileSystem, readOnly: Bool) async throws {
        logger.log("Initializing volume")
        self.resource = resource
        self.fileSystem = fileSystem
        self.superblock = try Superblock(blockDevice: resource, offset: 1024)
        self.readOnly = readOnly
        
        super.init(volumeID: FSVolume.Identifier(uuid: superblock.uuid ?? UUID()), volumeName: FSFileName(string: superblock.volumeName ?? ""))
        
        let endOfSuperblock = superblock.offset + 1024
        let blockSize = superblock.blockSize
        let firstBlockAfterSuperblockOffset = Int64(ceil(Double(endOfSuperblock) / Double(blockSize))) * Int64(blockSize)
        self.blockGroupDescriptors = try BlockGroupDescriptors(volume: self, offset: firstBlockAfterSuperblockOffset, blockGroupCount: Int(resource.blockCount) / Int(superblock.blocksPerGroup))
        
        let root = try await Ext4Item(volume: self, inodeNumber: 2)
        self.root = root
        
        await cache.addInode(inodeNumber: 2, blockNumber: try self.root.inodeBlockLocation)
        await cache.setItem(root, forInodeNumber: 2)
    }
    
    private var root: Ext4Item!
    
    weak var fileSystem: FSUnaryFileSystem?
    let resource: FSBlockDeviceResource
    /// The superblock in block group 0.
    var superblock: Superblock
    var blockGroupDescriptors: BlockGroupDescriptors!
    
    let cache = VolumeCache()
    
    /// Returns the block number for the block containing the given inode on disk.
    /// - Parameter inodeNumber: The inode number.
    /// - Returns: The block number, and the byte offset into that block at which you'll find the inode.
    func blockNumber(forBlockContainingInode inodeNumber: UInt32) throws -> (Int64, Int64) {
        let blockGroup = Int((inodeNumber - 1) / superblock.inodesPerGroup)
        guard let groupDescriptor = try blockGroupDescriptors[blockGroup], let tableLocation = groupDescriptor.inodeTableLocation else {
            throw POSIXError(.EIO)
        }
        let tableIndex = (inodeNumber - 1) % superblock.inodesPerGroup
        let blockOffset = Int64(tableIndex) * Int64(superblock.inodeSize) / Int64(superblock.blockSize)
        let offsetInBlock = Int64(tableIndex) * Int64(superblock.inodeSize) % Int64(superblock.blockSize)
        return (Int64(tableLocation) + blockOffset, offsetInBlock)
    }
    
    func data(forInode inodeNumber: UInt32) async throws -> Data {
        let blockNumber = try self.blockNumber(forBlockContainingInode: inodeNumber)
        let blockSize = superblock.blockSize
        var data = Data(count: blockSize)
        if let cachedData = await cache.inodeTableBlocks[blockNumber.0] {
            return cachedData.subdata(in: Int(blockNumber.1)..<Int((blockNumber.1 + Int64(superblock.inodeSize))))
        }
        try data.withUnsafeMutableBytes { ptr in
            try self.resource.metadataRead(into: ptr, startingAt: blockNumber.0 * Int64(superblock.blockSize), length: superblock.blockSize)
        }
        await cache.setInodeTableBlock(data, forBlock: blockNumber.0)
        return data.subdata(in: Int(blockNumber.1)..<Int((blockNumber.1 + Int64(superblock.inodeSize))))
    }
    
    func item(forInode inodeNumber: UInt32, withParentInode parentInode: UInt32, withName name: FSFileName) async throws -> Ext4Item {
        let blockNumber = try blockNumber(forBlockContainingInode: inodeNumber)
        
        if let item = await cache.fetchItem(forInodeNumber: inodeNumber) {
            return item
        }
        
        let item = try await Ext4Item(volume: self, inodeNumber: inodeNumber, inodeData: data(forInode: inodeNumber))
        await cache.addInode(inodeNumber: inodeNumber, blockNumber: blockNumber.0)
        await cache.setItem(item, forInodeNumber: inodeNumber)
        return item
    }
    
    let readOnly: Bool
    
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let capabilities = SupportedCapabilities()
        capabilities.caseFormat = .sensitive
        capabilities.supportsHardLinks = true
        capabilities.supportsSymbolicLinks = true
        capabilities.supportsPersistentObjectIDs = true
        capabilities.supportsZeroRuns = true
        capabilities.supports2TBFiles = true
        capabilities.supportsHiddenFiles = false
        capabilities.supportsFastStatFS = true
        return capabilities
    }
    
    var volumeStatistics: FSStatFSResult {
        let statistics = FSStatFSResult(fileSystemTypeName: "ExtendFS")
        statistics.blockSize = superblock.blockSize
        statistics.totalBlocks = UInt64(superblock.blockCount)
        statistics.freeBlocks = UInt64(superblock.freeBlockCount)
        statistics.availableBlocks = UInt64(superblock.freeBlockCount)
        statistics.usedBlocks = statistics.totalBlocks - statistics.freeBlocks
        statistics.freeFiles = UInt64(superblock.freeInodeCount)
        statistics.totalFiles = UInt64(superblock.inodeCount)
        statistics.ioSize = superblock.blockSize
        
        if superblock.featureIncompatibleFlags.contains(.extents) {
            statistics.fileSystemSubType = ExtendedFilesystemTypes.ext4.rawValue
        } else if superblock.featureCompatibilityFlags.contains(.journal) {
            statistics.fileSystemSubType = ExtendedFilesystemTypes.ext3.rawValue
        } else {
            statistics.fileSystemSubType = ExtendedFilesystemTypes.ext2.rawValue
        }
        return statistics
    }
    
    func mount(options: FSTaskOptions) async throws {
        logger.log("mount options: \(options.taskOptions, privacy: .public)")
        return
    }
    
    func unmount() async {
        logger.log("unmount")
        return
    }
    
    func synchronize(flags: FSSyncFlags) async throws {
        return
    }
    
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem) async throws -> FSItem.Attributes {
        logger.debug("attributes")
        guard let item = item as? Ext4Item else {
            throw POSIXError(.ENOENT)
        }
        
        let attrs = try item.getAttributes(desiredAttributes)
        if desiredAttributes.isAttributeWanted(.parentID) {
            attrs.parentID = .invalid
        }
        return attrs
    }
    
    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem) async throws -> FSItem.Attributes {
        logger.debug("setAttributes")
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func lookupItem(named name: FSFileName, inDirectory directory: FSItem) async throws -> (FSItem, FSFileName) {
        logger.debug("lookupItem with name \(name.string ?? "(unknown)")")
        guard let directory = directory as? Ext4Item else {
            throw POSIXError(.ENOENT)
        }
        
        if let item = try await directory.findItemInDirectory(named: name) {
            return (item, name)
        }
        
        throw POSIXError(.ENOENT)
    }
    
    func reclaimItem(_ item: FSItem) async throws {
        guard let item = item as? Ext4Item else {
            throw POSIXError(.ENOSYS)
        }
        let blockNumber = try blockNumber(forBlockContainingInode: item.inodeNumber)
        
        let inodeNumber = item.inodeNumber
        await cache.removeInode(inodeNumber: inodeNumber, blockNumber: blockNumber.0)
        
        return
    }
    
    
    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        logger.debug("readSymbolicLink")
        guard let item = item as? Ext4Item else {
            throw POSIXError(.EIO)
        }
        guard let target = try await item.symbolicLinkTarget else {
            throw POSIXError(.EIO)
        }
        return FSFileName(string: target)
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest) async throws -> (FSItem, FSFileName) {
        logger.debug("createItem")
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName) async throws -> (FSItem, FSFileName) {
        logger.debug("createSymbolicLink")
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func createLink(to item: FSItem, named name: FSFileName, inDirectory directory: FSItem) async throws -> FSFileName {
        logger.debug("createLink")
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem) async throws {
        logger.debug("removeItem(_:named:fromDirectory:)")
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?) async throws -> FSFileName {
        logger.debug("renameItem")
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker) async throws -> FSDirectoryVerifier {
        logger.debug("enumerateDirectory")
        // the cookie refers to the index of the directory content array
        guard let directory = directory as? Ext4Item else {
            throw POSIXError(.ENOSYS)
        }
        
        guard let (contents, currentVerifier) = try await directory.directoryContents else {
            throw POSIXError(.EIO)
        }
        
        let attributesAccessibleWithoutLoading: FSItem.Attribute = [.type, .fileID, .parentID]
        let startIndex = cookie == .initial ? contents.startIndex : Int(cookie.rawValue)
        for i in startIndex..<contents.endIndex {
            let content = contents[i]
            if attributes != nil && (content.name == "." || content.name == "..") {
                continue
            }
            let fileAttributes: FSItem.Attributes?
            if let attributes, attributes.wantedAttributes.isSubset(of: attributesAccessibleWithoutLoading) {
                fileAttributes = FSItem.Attributes()
                fileAttributes?.type = content.fskitFileType ?? .unknown
                fileAttributes?.fileID = FSItem.Identifier(rawValue: UInt64(content.inodePointee)) ?? .invalid
                fileAttributes?.parentID = FSItem.Identifier(rawValue: UInt64(directory.inodeNumber)) ?? .invalid
            } else if let attributes {
                let inodeData = try await data(forInode: UInt32(content.inodePointee))
                guard let inode = IndexNode(from: inodeData, creator: superblock.creatorOS) else { throw POSIXError(.EIO) }
                fileAttributes = inode.getAttributes(attributes, superblock: superblock, readOnlySystem: readOnly)
                
                fileAttributes?.fileID = FSItem.Identifier(rawValue: UInt64(content.inodePointee)) ?? .invalid
                fileAttributes?.parentID = FSItem.Identifier(rawValue: UInt64(directory.inodeNumber)) ?? .invalid
            } else {
                fileAttributes = nil
            }
            guard packer.packEntry(name: FSFileName(string: content.name), itemType: content.fskitFileType ?? .unknown, itemID: FSItem.Identifier(rawValue: UInt64(content.inodePointee)) ?? .invalid, nextCookie: FSDirectoryCookie(rawValue: UInt64(i + 1)), attributes: fileAttributes) else {
                break
            }
            
        }
        
        return currentVerifier
    }
    
    func activate(options: FSTaskOptions) async throws -> FSItem {
        logger.log("activate options: \(options.taskOptions, privacy: .public)")
        fileSystem?.containerStatus = .active
        return root
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
        logger.log("deactivate")
        fileSystem?.containerStatus = .ready
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
    
    var isVolumeRenameInhibited: Bool = false
    var isPreallocateInhibited: Bool = false
}

extension Ext4Volume: FSVolume.ReadWriteOperations {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        guard let item = item as? Ext4Item else {
            throw POSIXError(.EIO)
        }
        
        let blockSize = superblock.blockSize
        let blockOffset = Int(offset) / blockSize
        let blockLength = Int((Double(length) / Double(blockSize)).rounded(.up))
        let extents = try await item.findExtentsCovering(Int64(blockOffset), with: blockLength)
        let firstLogicalBlock = offset / Int64(blockSize)
        // TODO: do read requests align to blocks? if not this offset is needed but that makes things more annoying
//        let offsetWithinFirstBlock = offset % Int64(try superblock.blockSize)
        var amountRead = 0
        let remainingLengthInFile = off_t(try item.indexNode.size) - offset
        let actualLengthToRead = min(length, Int(remainingLengthInFile.roundUp(toMultipleOf: off_t(blockSize))))
        for extent in extents {
            guard amountRead < actualLengthToRead else {
                break
            }
            
            let startingAtLogicalBlock = amountRead == 0 ? firstLogicalBlock : extent.logicalBlock
            let startingAtPhysicalBlock = extent.physicalBlock + (startingAtLogicalBlock - extent.logicalBlock)
            let startingAtPhysicalByte = startingAtPhysicalBlock * Int64(superblock.blockSize)
            let blockLengthConsidered = Int(extent.lengthInBlocks ?? 1) - Int(startingAtLogicalBlock - extent.logicalBlock)
            let readFromThisExtent = min(actualLengthToRead - amountRead, blockLengthConsidered * superblock.blockSize)
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
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
}

extension Ext4Volume: FSVolumeKernelOffloadedIOOperations {
    func blockmapFile(_ file: FSItem, offset: off_t, length: Int, flags: FSBlockmapFlags, operationID: FSOperationID, packer: FSExtentPacker) async throws {
        logger.debug("blockmapFile")
        guard let file = file as? Ext4Item else {
            throw POSIXError(.EIO)
        }
        if flags.contains(.write) {
            throw POSIXError(.EPERM)
        }
        
        let blockSize = superblock.blockSize
        
        let blockOffset = Int(offset) / blockSize
        let blockLength = (Int(offset) + length) / blockSize - blockOffset + 1
        let extents = try await file.findExtentsCovering(Int64(blockOffset), with: blockLength)
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
        if readOnly {
            throw POSIXError(.EROFS)
        }
        throw POSIXError(.ENOSYS)
    }
    
    func lookupItem(name: FSFileName, in directory: FSItem, packer: FSExtentPacker) async throws -> (FSItem, FSFileName) {
        return try await lookupItem(named: name, inDirectory: directory)
    }
}

extension Ext4Volume: FSVolume.OpenCloseOperations {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        if modes.contains(.write) {
            if readOnly {
                throw POSIXError(.EROFS)
            }
            throw POSIXError(.ENOSYS)
        }
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        
    }
}

extension Ext4Volume: FSVolume.AccessCheckOperations {
    func checkAccess(to theItem: FSItem, requestedAccess access: FSVolume.AccessMask) async throws -> Bool {
        let writeAccess: FSVolume.AccessMask = [.addFile, .addSubdirectory, .appendData, .delete, .deleteChild, .takeOwnership, .writeAttributes, .writeData, .writeSecurity, .writeXattr]
        if readOnly && !access.isDisjoint(with: writeAccess) {
            return false
        }
        
        return true
    }
}

extension Ext4Volume: FSVolume.XattrOperations {
    func xattr(named name: FSFileName, of item: FSItem) async throws -> Data {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        guard let toFind = name.string else { throw POSIXError(.EINVAL) }
        
        if let embeddedEntries = try item.indexNode.embeddedExtendedAttributes {
            let found = embeddedEntries.filter { entry in
                entry.name == toFind
            }
            if let first = found.first {
                return try item.getValueForEmbeddedAttribute(first) ?? Data()
            }
        }
        
        if let block = try item.extendedAttributeBlock {
            let index = block.entries.partitioningIndex { entry in
                entry.name >= toFind
            }
            if index != block.entries.endIndex && block.entries[index].name == toFind {
                return try block.value(for: block.entries[index])
            }
        }
        
        throw POSIXError(.ENOATTR)
    }
    
    func setXattr(named name: FSFileName, to value: Data?, on item: FSItem, policy: FSVolume.SetXattrPolicy) async throws {
        throw POSIXError(.ENOSYS)
    }
    
    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        
        var attrs: [String] = []
        if let embeddedEntries = try item.indexNode.embeddedExtendedAttributes {
            let names = embeddedEntries.map { $0.name }
            attrs.append(contentsOf: names)
        }
        
        if let block = try item.extendedAttributeBlock {
            attrs.append(contentsOf: try block.extendedAttributes.keys)
        }
        
        return attrs.map { FSFileName(string: $0) }
    }
}

extension Ext4Volume: FSVolume.RenameOperations {
    func setVolumeName(_ name: FSFileName) async throws -> FSFileName {
        throw POSIXError(.ENOSYS)
    }
}

extension Ext4Volume: FSVolume.PreallocateOperations {
    func preallocateSpace(for item: FSItem, at offset: off_t, length: Int, flags: FSVolume.PreallocateFlags) async throws -> Int {
        throw POSIXError(.ENOSYS)
    }
}

extension Ext4Volume: FSVolume.ItemDeactivation {
    var itemDeactivationPolicy: FSVolume.ItemDeactivationOptions {
        []
    }
    
    func deactivateItem(_ item: FSItem) async throws {
        throw POSIXError(.ENOSYS)
    }
}
