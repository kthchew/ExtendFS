// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Algorithms
import Foundation
import FSKit

actor VolumeCache {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")
    
    /// The key is the block containing the relevant inode entries.
    var usedItemsInInodeTable = [UInt64: Set<UInt32>]()
    func addInode(inodeNumber: UInt32, blockNumber: UInt64) {
        usedItemsInInodeTable[blockNumber, default: []].insert(inodeNumber)
    }
    func removeInode(inodeNumber: UInt32, blockNumber: UInt64) {
        usedItemsInInodeTable[blockNumber]?.remove(inodeNumber)
        if let usedItems = usedItemsInInodeTable[blockNumber], usedItems.isEmpty {
            Self.logger.debug("Last inode in block \(blockNumber, privacy: .public) freed")
            if let firstInode = inodeTableBlocks[blockNumber]?.first?.inodeNumber, let lastInode = inodeTableBlocks[blockNumber]?.first?.inodeNumber {
                for inode in firstInode...lastInode {
                    items[inode] = nil
                }
            }
            usedItemsInInodeTable[blockNumber] = nil
            inodeTableBlocks[blockNumber] = nil
        }
    }
    /// The key is the block for the given inode table.
    var inodeTableBlocks = [UInt64: [Ext4Item]]()
    func setInodeTableBlock(_ items: [Ext4Item]?, forBlock blockNumber: UInt64) {
        inodeTableBlocks[blockNumber] = items
    }
    func getItems(fromInodeTableBlockNumber blockNumber: UInt64) -> [Ext4Item]? {
        return inodeTableBlocks[blockNumber]
    }
    
    /// The key is the inode number.
    var items = [UInt32: Ext4Item]()
    func setItem(_ item: Ext4Item?, forInodeNumber inodeNumber: UInt32) {
        items[inodeNumber] = item
    }
    func fetchItem(forInodeNumber inodeNumber: UInt32) -> Ext4Item? {
        return items[inodeNumber]
    }
    
    var root: Ext4Item!
    func setRoot(_ root: Ext4Item) {
        self.root = root
    }
    
    func clearAllCaches() {
        usedItemsInInodeTable = [:]
        inodeTableBlocks = [:]
        items = [:]
    }
}

final class Ext4Volume: FSVolume, FSVolume.Operations, FSVolume.PathConfOperations {
    let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Volume")
    
    init(resource: FSBlockDeviceResource, fileSystem: Ext4ExtensionFileSystem, readOnly: Bool) async throws {
        logger.log("Initializing volume")
        self.resource = resource
        self.fileSystem = fileSystem
        guard let superblock = try Superblock(blockDevice: resource, offset: 1024) else {
            logger.error("Superblock could not be parsed")
            throw POSIXError(.EIO)
        }
        self.superblock = superblock
        self.readOnly = readOnly
        
        logger.log("""
            Superblock contents:
                Inode count: \(superblock.inodeCount, privacy: .public)
                Block count: \(superblock.blockCount, privacy: .public)
                Root-only block count: \(superblock.superUserBlockCount, privacy: .public)
                Free block count: \(superblock.freeBlockCount, privacy: .public)
                Free inode count: \(superblock.freeInodeCount, privacy: .public)
                First data block: \(superblock.firstDataBlock, privacy: .public)
                Log block size: \(superblock.logBlockSize, privacy: .public)
                Log cluster size: \(superblock.logClusterSize, privacy: .public)
                Blocks per group: \(superblock.blocksPerGroup, privacy: .public)
                Clusters per group: \(superblock.clustersPerGroup, privacy: .public)
                Inodes per group: \(superblock.inodesPerGroup, privacy: .public)
                Mount time: \(superblock.mountTime, privacy: .public)
                Write time: \(superblock.writeTime, privacy: .public)
                Mount count: \(superblock.mountsSinceLastFsck, privacy: .public)
                Max mount count: \(superblock.maxMountsSinceLastFsck, privacy: .public)
                Magic: \(superblock.magic, privacy: .public)
                State: \(superblock.state.rawValue, privacy: .public)
                Error behavior: \(String(describing: superblock.errorPolicy), privacy: .public)
                Minor revision level: \(superblock.minorRevisionLevel, privacy: .public)
                Last check: \(superblock.lastCheckTime, privacy: .public)
                Check interval: \(superblock.maxSecondsBetweenChecks, privacy: .public)
                Creator OS: \(superblock.creatorOS.rawValue, privacy: .public)
                Revision level: \(superblock.revisionLevel.rawValue, privacy: .public)
                Default UID: \(superblock.defaultUidForReservedBlocks, privacy: .public)
                Default GID: \(superblock.defaultGidForReservedBlocks, privacy: .public)
                First non-reserved inode: \(superblock.firstNonReservedInode, privacy: .public)
                Inode size: \(superblock.inodeSize, privacy: .public)
                Block group of this superblock: \(String(describing: superblock.blockGroupNumber), privacy: .public)
                Compat features: \(superblock.compatibleFeatures.rawValue, privacy: .public)
                Incompat features: \(superblock.incompatibleFeatures.rawValue, privacy: .public)
                Readonly compat features: \(superblock.readOnlyCompatibleFeatures.rawValue, privacy: .public)
                UUID: \(superblock.uuid?.uuidString ?? "")
                Volume name: \(superblock.volumeName ?? "")
                Last mounted directory: \(superblock.lastMountDirectory ?? "")
                Compresion algo use bitmap: \(String(describing: superblock.compressionAlgorithmUsageBitmap), privacy: .public)
                
                Min extra inode size: \(String(describing: superblock.minimumExtraInodeSize), privacy: .public)
                Want extra inode size: \(String(describing: superblock.wantExtraInodeSize), privacy: .public)
                Flags: \(String(describing: superblock.flags), privacy: .public)
            
                Log groups per flex: \(String(describing: superblock.logGroupsPerFlexibleGroup), privacy: .public)
            """)
        
        let endOfSuperblock = 1024 + 1024
        let blockSize = superblock.blockSize
        let firstBlockAfterSuperblockOffset = Int64(ceil(Double(endOfSuperblock) / Double(blockSize))) * Int64(blockSize)
        let blockGroupCount = (Int(resource.blockCount) + Int(superblock.blocksPerGroup) - 1) / Int(superblock.blocksPerGroup)
        self.blockGroupDescriptors = try BlockGroupDescriptorManager(resource: resource, superblock: superblock, offset: firstBlockAfterSuperblockOffset, blockGroupCount: blockGroupCount)
        
        super.init(volumeID: FSVolume.Identifier(uuid: superblock.uuid ?? UUID()), volumeName: FSFileName(string: superblock.volumeName ?? ""))
        
        let root = try await Ext4Item(volume: self, inodeNumber: 2)
        await cache.setRoot(root)
        
        await cache.addInode(inodeNumber: 2, blockNumber: try cache.root.inodeBlockLocation)
        await cache.setItem(root, forInodeNumber: 2)
    }
    
    let fileSystem: Ext4ExtensionFileSystem
    let resource: FSBlockDeviceResource
    /// The superblock in block group 0.
    let superblock: Superblock
    let blockGroupDescriptors: BlockGroupDescriptorManager
    
    let cache = VolumeCache()
    
    /// Returns the block number for the block containing the given inode on disk.
    /// - Parameter inodeNumber: The inode number.
    /// - Returns: The block number, and the index into that block at which you'll find the inode.
    func blockNumber(forBlockContainingInode inodeNumber: UInt32) throws -> (UInt64, UInt32) {
        guard inodeNumber != 0 else {
            logger.error("Tried to get block number for inode number 0")
            throw POSIXError(.EINVAL)
        }
        let blockGroup = Int((inodeNumber - 1) / superblock.inodesPerGroup)
        guard let groupDescriptor = try blockGroupDescriptors[blockGroup], let tableLocation = groupDescriptor.inodeTableLocation else {
            logger.error("Failed to fetch data from block group descriptors while looking for block containing inode \(inodeNumber, privacy: .public)")
            throw POSIXError(.EIO)
        }
        let tableIndex = (inodeNumber - 1) % superblock.inodesPerGroup
        let blockOffset = UInt64(tableIndex) * UInt64(superblock.inodeSize) / UInt64(superblock.blockSize)
        return (tableLocation + blockOffset, tableIndex - UInt32(blockOffset * UInt64(superblock.blockSize) / UInt64(superblock.inodeSize)))
    }
    
    /// Loads all items associated with the inodes located at the given block number.
    /// - Parameter blockNumber: The block number of part of the inode table to load.
    func loadItems(from blockNumber: UInt64) async throws -> [Ext4Item] {
        if let items = await cache.getItems(fromInodeTableBlockNumber: blockNumber) {
            return items
        }
        guard let blockGroup = UInt32(exactly: blockNumber / UInt64(superblock.blocksPerGroup)) else {
            logger.error("Block group for \(blockNumber) is too large to fit in a 32-bit integer - should not happen")
            throw POSIXError(.EIO)
        }
        guard let groupDescriptor = try blockGroupDescriptors[Int(blockGroup)], let tableLocation = groupDescriptor.inodeTableLocation else {
            logger.error("Failed to fetch data from block group descriptors while loading inodes at block \(blockNumber, privacy: .public)")
            throw POSIXError(.EIO)
        }
        guard blockNumber >= tableLocation else {
            logger.error("Trying to load inodes at block \(blockNumber, privacy: .public), but the inode table starts later (at \(tableLocation, privacy: .public))")
            throw POSIXError(.EIO)
        }
        guard let blockOffset = UInt32(exactly: blockNumber - tableLocation) else {
            logger.error("Inodes at block \(blockNumber, privacy: .public) are way too far from the table starting at \(tableLocation, privacy: .public)")
            throw POSIXError(.EIO)
        }
        let firstInodeOfGroup = blockGroup * superblock.inodesPerGroup + 1
        let inodesPerBlock = UInt32(superblock.blockSize) / UInt32(superblock.inodeSize)
        let firstInodeInBlock = firstInodeOfGroup + (blockOffset * inodesPerBlock)
        let lastInodeInBlock = firstInodeInBlock + inodesPerBlock - 1
        
        logger.debug("Loading inodes \(firstInodeInBlock, privacy: .public) through \(lastInodeInBlock, privacy: .public) at block number \(blockNumber, privacy: .public) from disk")
        var data = try BlockDeviceReader.fetchExtent(from: resource, blockNumbers: off_t(blockNumber)..<Int64(blockNumber)+1, blockSize: superblock.blockSize)
        var items: [Ext4Item] = []
        for inode in firstInodeInBlock...lastInodeInBlock {
            let inodeData = data.subdata(in: 0..<Int(superblock.inodeSize))
            let item = try await Ext4Item(volume: self, inodeNumber: inode, inodeData: inodeData)
            
            items.append(item)
            await cache.setItem(item, forInodeNumber: inode)
            data = data.advanced(by: Int(superblock.inodeSize))
        }
        await cache.setInodeTableBlock(items, forBlock: blockNumber)
        
        return items
    }
    
    func item(forInode inodeNumber: UInt32) async throws -> Ext4Item {
        let blockNumber = try blockNumber(forBlockContainingInode: inodeNumber)
        await cache.addInode(inodeNumber: inodeNumber, blockNumber: blockNumber.0)
        let items = try await loadItems(from: UInt64(blockNumber.0))
        return items[Int(blockNumber.1)]
    }
    
    let readOnly: Bool
    
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let capabilities = SupportedCapabilities()
        capabilities.caseFormat = .sensitive
        capabilities.supportsHardLinks = true
        capabilities.supportsSymbolicLinks = true
        capabilities.supportsPersistentObjectIDs = true
        capabilities.supportsSparseFiles = true
        capabilities.supportsZeroRuns = true
        capabilities.supports2TBFiles = true
        capabilities.supportsHiddenFiles = false
        capabilities.supportsFastStatFS = true
        return capabilities
    }
    
    var volumeStatistics: FSStatFSResult {
        let statistics = FSStatFSResult(fileSystemTypeName: "ExtendFS")
        statistics.blockSize = superblock.blockSize
        statistics.totalBlocks = superblock.blockCount
        statistics.freeBlocks = superblock.freeBlockCount
        statistics.availableBlocks = superblock.freeBlockCount >= superblock.superUserBlockCount ? superblock.freeBlockCount - superblock.superUserBlockCount : 0
        statistics.usedBlocks = statistics.totalBlocks - statistics.freeBlocks
        statistics.freeFiles = UInt64(superblock.freeInodeCount)
        statistics.totalFiles = UInt64(superblock.inodeCount)
        statistics.ioSize = superblock.blockSize * 4
        
        if superblock.incompatibleFeatures.contains(.extents) {
            statistics.fileSystemSubType = ExtendedFilesystemTypes.ext4.rawValue
        } else if superblock.compatibleFeatures.contains(.journal) {
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
        logger.log("unmounting")
        await cache.clearAllCaches()
        return
    }
    
    func synchronize(flags: FSSyncFlags) async throws {
        return
    }
    
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem) async throws -> FSItem.Attributes {
        guard let item = item as? Ext4Item else {
            throw POSIXError(.ENOENT)
        }
        logger.debug("attributes for \(item.inodeNumber, privacy: .public)")
        
        let attrs = try await item.getAttributes(desiredAttributes)
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
        guard let directory = directory as? Ext4Item else {
            throw POSIXError(.ENOENT)
        }
        logger.debug("Looking up item with name \(name.string ?? "(unknown)") in directory (inode \(directory.inodeNumber))")
        
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
        guard let item = item as? Ext4Item else {
            throw POSIXError(.EIO)
        }
        guard let target = try await item.symbolicLinkTarget else {
            logger.fault("Symbolic link request for item with inode \(item.inodeNumber) but symbolic link target was nil")
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
            logger.error("Could not read directory contents")
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
                let blockNumber = try self.blockNumber(forBlockContainingInode: content.inodePointee)
                let items = try await loadItems(from: UInt64(blockNumber.0))
                let item = items[Int(blockNumber.1)]
                fileAttributes = try await item.getAttributes(attributes)
                
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
        fileSystem.containerStatus = .active
        return await cache.root
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
        logger.log("deactivate")
        fileSystem.containerStatus = .ready
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
    
    var isVolumeRenameInhibited: Bool {
        get {
            true
        }
        set {}
    }
    var isPreallocateInhibited: Bool {
        get {
            true
        }
        set {}
    }
    var isOpenCloseInhibited: Bool {
        get {
            true
        }
        set {}
    }
}

extension Ext4Volume: FSVolume.ReadWriteOperations {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        guard let item = item as? Ext4Item else {
            throw POSIXError(.EIO)
        }
        
        let blockSize = superblock.blockSize
        let blockOffset = Int(offset) / blockSize
        let blockLength = Int((Double(length) / Double(blockSize)).rounded(.up))
        let extents = try await item.findExtentsCovering(UInt64(blockOffset), with: blockLength)
        let firstLogicalBlock = offset / Int64(blockSize)
        var amountRead = 0
        let remainingLengthInFile = await off_t(try item.indexNode.size) - offset
        let actualLengthToRead = min(length, Int(remainingLengthInFile.roundUp(toMultipleOf: off_t(blockSize))))
        for extent in extents {
            let startingAtLogicalBlock = min(max(firstLogicalBlock, extent.logicalBlock), Int64(actualLengthToRead - amountRead))
            if amountRead + Int(offset) < Int(extent.logicalBlock) * blockSize {
                let zerosCount = (Int(extent.logicalBlock) * blockSize) - (amountRead + Int(offset))
                let data = Data(count: zerosCount)
                buffer.withUnsafeMutableBytes { buf in
                    (buf[amountRead...]).copyBytes(from: data)
                }
                amountRead += zerosCount
            }
            
            guard amountRead < actualLengthToRead else {
                break
            }
            
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
        if amountRead < actualLengthToRead {
            let zerosCount = actualLengthToRead - amountRead
            let data = Data(count: zerosCount)
            buffer.withUnsafeMutableBytes { buf in
                (buf[amountRead...]).copyBytes(from: data)
            }
            amountRead += zerosCount
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
        if flags.contains(.write) && readOnly {
            throw POSIXError(.EROFS)
        }
        
        let blockSize = superblock.blockSize
        
        let blockOffset = Int(offset) / blockSize
        let blockLength = (Int(offset) + length) / blockSize - blockOffset + 1
        let extents = try await file.findExtentsCovering(UInt64(blockOffset), with: blockLength)
        
        let end = Int(offset) + length
        var current = offset
        for extent in extents {
            let extentStartInBytes = extent.logicalBlock * Int64(blockSize)
            let extentLengthInBytes = Int(extent.lengthInBlocks ?? 1) * Int(blockSize)
            if current < extentStartInBytes {
                if flags.contains(.write) {
                    throw POSIXError(.EROFS)
                } else {
                    let zeros = Int(extentStartInBytes - current)
                    guard packer.packExtent(resource: resource, type: .zeroFill, logicalOffset: current, physicalOffset: off_t.min, length: zeros) else {
                        return
                    }
                    current += Int64(zeros)
                }
            }
            
            guard packer.packExtent(resource: resource, type: extent.type!, logicalOffset: extentStartInBytes, physicalOffset: extent.physicalBlock * Int64(blockSize), length: extentLengthInBytes) else {
                return
            }
            
            current += Int64(extentLengthInBytes)
        }
        if current < end {
            if flags.contains(.write) {
                throw POSIXError(.EROFS)
            } else {
                guard packer.packExtent(resource: resource, type: .zeroFill, logicalOffset: current, physicalOffset: off_t.min, length: end - Int(current)) else {
                    return
                }
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
        let (item, name) = try await lookupItem(named: name, inDirectory: directory)
        
        guard let item = item as? Ext4Item else {
            throw POSIXError(.EIO)
        }
        do {
            let extents = try await item.findExtentsCovering(0, with: Int(item.indexNode.size) / superblock.blockSize, performAdditionalIO: false)
            for extent in extents {
                guard let type = extent.type, let lengthInBlocks = extent.lengthInBlocks else {
                    logger.fault("Got extent while looking up item, but it had no type and/or length")
                    continue
                }
                
                guard packer.packExtent(resource: resource, type: type, logicalOffset: extent.logicalBlock, physicalOffset: extent.physicalBlock, length: Int(lengthInBlocks)) else {
                    break
                }
            }
        } catch {
            logger.error("Failed to prefetch extents while looking up item: \(error)")
        }
        
        return (item, name)
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
        
        if let embeddedEntries = try await item.indexNode.embeddedExtendedAttributes {
            let found = embeddedEntries.filter { entry in
                entry.name == toFind
            }
            if let first = found.first {
                return try await item.getValueForEmbeddedAttribute(first) ?? Data()
            }
        }
        
        if let block = try await item.extendedAttributeBlock {
            let index = block.entries.partitioningIndex { entry in
                entry.name >= toFind
            }
            if index != block.entries.endIndex && block.entries[index].name == toFind {
                return try block.value(for: block.entries[index])
            }
        }
        
        if let value = await item.cache.getTemporaryXattr(toFind) {
            return value
        }
        
        logger.info("No xattr named \(toFind, privacy: .public)")
        throw POSIXError(.ENOATTR)
    }
    
    func setXattr(named name: FSFileName, to value: Data?, on item: FSItem, policy: FSVolume.SetXattrPolicy) async throws {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        guard let nameString = name.string else { throw POSIXError(.EINVAL) }
        if nameString.starts(with: "com.apple.") {
            switch policy {
            case .alwaysSet:
                await item.cache.setTemporaryXattr(value, for: nameString)
            case .mustCreate:
                guard await item.cache.getTemporaryXattr(nameString) == nil else {
                    throw POSIXError(.EEXIST)
                }
                await item.cache.setTemporaryXattr(value, for: nameString)
            case .mustReplace:
                guard await item.cache.getTemporaryXattr(nameString) != nil else {
                    throw POSIXError(.ENOENT)
                }
                await item.cache.setTemporaryXattr(value, for: nameString)
            case .delete:
                guard await item.cache.getTemporaryXattr(nameString) != nil else {
                    throw POSIXError(.ENOENT)
                }
                await item.cache.setTemporaryXattr(nil, for: nameString)
            @unknown default:
                throw POSIXError(.ENOSYS)
            }
        }
        
        throw POSIXError(.ENOSYS)
    }
    
    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        guard let item = item as? Ext4Item else { throw POSIXError(.EIO) }
        
        var attrs: [String] = []
        if let embeddedEntries = try await item.indexNode.embeddedExtendedAttributes {
            let names = embeddedEntries.map { $0.name }
            attrs.append(contentsOf: names)
        }
        
        if let block = try await item.extendedAttributeBlock {
            attrs.append(contentsOf: try block.extendedAttributes.keys)
        }
        
        for temporaryXattr in await item.cache.temporaryXattrs {
            attrs.append(temporaryXattr.key)
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
