//
//  IndirectBlockAddress.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 11/16/25.
//

import Foundation
import FSKit

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "IndirectBlockMap")

/// A mapping of file block numbers to logical block numbers used by ext2/3.
struct IndirectBlockMap {
    /// A direct map to file blocks 0 through 11.
    var directMap: [UInt32]
    private var singleIndirectBlock: IndirectBlock?
    var indirectBlockLocation: UInt32
    private var doubleIndirectBlock: IndirectBlock?
    var doubleIndirectBlockLocation: UInt32
    private var tripleIndirectBlock: IndirectBlock?
    var tripleIndirectBlockLocation: UInt32
    
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        directMap = []
        directMap.reserveCapacity(12)
        for _ in 0...11 {
            guard let blk: UInt32 = iterator.nextLittleEndian() else { return nil }
            directMap.append(blk)
        }
        guard let indirectBlockLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.indirectBlockLocation = indirectBlockLocation
        guard let doubleIndirectBlockLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.doubleIndirectBlockLocation = doubleIndirectBlockLocation
        guard let tripleIndirectBlockLocation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.tripleIndirectBlockLocation = tripleIndirectBlockLocation
    }
    
    mutating func getPhysicalBlockLocations(for logicalBlock: UInt64, blockDevice: FSBlockDeviceResource, blockSize: Int) throws -> UInt64 {
        guard let logicalBlock = UInt32(exactly: logicalBlock) else {
            logger.error("Trying to use indirect block map to get logical block number \(logicalBlock, privacy: .public), which is too large")
            throw POSIXError(.EFBIG)
        }
        let coveredPerLevelOfIndirection = UInt32(blockSize / 4)
        
        let level1End: UInt32 = 11
        let level2End = level1End + coveredPerLevelOfIndirection
        let level3End = level2End + UInt32(pow(Double(coveredPerLevelOfIndirection), 2))
        let level4End = level3End + UInt32(pow(Double(coveredPerLevelOfIndirection), 3)) + 1
        switch logicalBlock {
        case 0...level1End:
            return UInt64(directMap[Int(logicalBlock)])
        case (level1End + 1)...(level2End):
            if singleIndirectBlock == nil {
                let data = try BlockDeviceReader.fetchExtent(from: blockDevice, blockNumbers: off_t(indirectBlockLocation)..<Int64(indirectBlockLocation)+1, blockSize: blockSize)
                self.singleIndirectBlock = IndirectBlock(from: data, startingAt: UInt32(level1End) + 1, depth: 0)
            }
            guard let location = try singleIndirectBlock?.getPhysicalBlockLocation(for: UInt64(logicalBlock), blockDevice: blockDevice, blockSize: blockSize) else {
                logger.fault("Single indirect block was nil even after setting it")
                throw POSIXError(.EIO)
            }
            return location
        case (level2End + 1)...(level3End):
            if doubleIndirectBlock == nil {
                let data = try BlockDeviceReader.fetchExtent(from: blockDevice, blockNumbers: off_t(doubleIndirectBlockLocation)..<Int64(doubleIndirectBlockLocation)+1, blockSize: blockSize)
                self.doubleIndirectBlock = IndirectBlock(from: data, startingAt: UInt32(level2End) + 1, depth: 1)
            }
            guard let location = try doubleIndirectBlock?.getPhysicalBlockLocation(for: UInt64(logicalBlock), blockDevice: blockDevice, blockSize: blockSize) else {
                logger.fault("Double indirect block was nil even after setting it")
                throw POSIXError(.EIO)
            }
            return location
        case (level3End + 1)...(level4End):
            if tripleIndirectBlock == nil {
                let data = try BlockDeviceReader.fetchExtent(from: blockDevice, blockNumbers: off_t(tripleIndirectBlockLocation)..<Int64(tripleIndirectBlockLocation)+1, blockSize: blockSize)
                self.tripleIndirectBlock = IndirectBlock(from: data, startingAt: UInt32(level3End) + 1, depth: 0)
            }
            guard let location = try tripleIndirectBlock?.getPhysicalBlockLocation(for: UInt64(logicalBlock), blockDevice: blockDevice, blockSize: blockSize) else {
                logger.fault("Triple indirect block was nil even after setting it")
                throw POSIXError(.EIO)
            }
            return location
        default:
            logger.error("Trying to use indirect block map but the requested logical block \(logicalBlock, privacy: .public) is too large")
            throw POSIXError(.EFBIG)
        }
    }
}

struct IndirectBlock {
    let startingBlock: UInt32
    /// 0 represent a block that points directly to data blocks, 1 represents a block pointing to blocks with depth of 0, etc.
    let depth: UInt
    /// Indirect blocks mapping to the `logicalBlockNumbers`. Only non-nil if `depth != 0`.
    private var indirectBlocks: [IndirectBlock?]?
    /// If depth is 0, this contains physical data block numbers. Otherwise, it contains the physical block numbers of another layer of indirect blocks.
    var blockNumbers: [UInt32]
    
    init(from data: Data, startingAt startingBlock: UInt32, depth: UInt) {
        self.startingBlock = startingBlock
        
        var iterator = data.makeIterator()
        var nums: [UInt32] = []
        nums.reserveCapacity(data.count / MemoryLayout<UInt32>.size)
        while let num: UInt32 = iterator.nextLittleEndian() {
            nums.append(num)
        }
        
        self.blockNumbers = nums
        self.depth = depth
        if depth > 0 {
            self.indirectBlocks = [IndirectBlock?](repeating: nil, count: blockNumbers.count)
        }
    }
    
    mutating func getPhysicalBlockLocation(for logicalBlock: UInt64, blockDevice: FSBlockDeviceResource, blockSize: Int) throws -> UInt64 {
        guard logicalBlock >= startingBlock else {
            let startingBlock = self.startingBlock
            logger.fault("Tried to get physical block location for logical block \(logicalBlock, privacy: .public), but it is smaller than the starting block \(startingBlock, privacy: .public)")
            throw POSIXError(.EIO)
        }
        if depth <= 0 {
            let blockOffset = Int(logicalBlock) - Int(startingBlock)
            guard blockOffset < blockNumbers.count else {
                let count = blockNumbers.count
                let startingBlock = self.startingBlock
                logger.error("Block offset \(blockOffset, privacy: .public) is out of range for block numbers (count \(count, privacy: .public)) for indirect block starting at \(startingBlock, privacy: .public)")
                throw POSIXError(.EIO)
            }
            return UInt64(blockNumbers[blockOffset])
        }
        
        let coveredPerLevelOfIndirection = blockSize / 4
        let blocksCoveredPerItem = Int(pow(Double(coveredPerLevelOfIndirection), Double(depth)))
        let blockOffset = logicalBlock - UInt64(startingBlock)
        let index = Int(blockOffset) / blocksCoveredPerItem
        
        guard let indirectBlocks, index < indirectBlocks.count, index < blockNumbers.count else {
            let startingBlock = self.startingBlock
            let depth = self.depth
            logger.error("Trying to get indirect block index \(index, privacy: .public) for indirect block starting at \(startingBlock, privacy: .public), depth \(depth, privacy: .public), but it is past the end")
            throw POSIXError(.EIO)
        }
        var indirectBlock: IndirectBlock
        if let cached = indirectBlocks[index] {
            indirectBlock = cached
        } else {
            let lowerLevelLocation = blockNumbers[index]
            let lowerLevelData = try BlockDeviceReader.fetchExtent(from: blockDevice, blockNumbers: off_t(lowerLevelLocation)..<off_t(lowerLevelLocation)+1, blockSize: blockSize)
            guard let blockIndex = UInt32(exactly: index * blocksCoveredPerItem) else {
                logger.error("Trying to get index \(index, privacy: .public) for indirect block, but it is too large")
                throw POSIXError(.EFBIG)
            }
            indirectBlock = IndirectBlock(from: lowerLevelData, startingAt: startingBlock + blockIndex, depth: depth - 1)
            self.indirectBlocks?[index] = indirectBlock
        }
        return try indirectBlock.getPhysicalBlockLocation(for: logicalBlock, blockDevice: blockDevice, blockSize: blockSize)
    }
}
