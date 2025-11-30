// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Algorithms
import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "FileExtentTree")

struct FileExtentTreeLevel {
    var numberOfEntries: UInt16
    var maxNumberOfEntries: UInt16
    var depth: UInt16
    var generation: UInt32
    
    var nodes: [FileExtentNode]
    
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let magic: UInt16 = iterator.nextLittleEndian(), magic == 0xF30A else { return nil }
        guard let numberOfEntries: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.numberOfEntries = numberOfEntries
        guard let maxNumberOfEntries: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.maxNumberOfEntries = maxNumberOfEntries
        guard let depth: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.depth = depth
        guard let generation: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.generation = generation
        
        let headerSize = 12
        var currentData = data.advanced(by: headerSize)
        
        let nodeSize = 12
        self.nodes = []
        self.nodes.reserveCapacity(Int(numberOfEntries))
        for _ in 0..<numberOfEntries {
            let nodeData = currentData.subdata(in: 0..<nodeSize)
            guard let node = FileExtentNode(from: nodeData, isLeaf: isLeaf) else { return nil }
            self.nodes.append(node)
            currentData = currentData.advanced(by: nodeSize)
        }
        guard numberOfEntries == self.nodes.count else {
            logger.error("numberOfEntries did not match node count!")
            return nil
        }
        
        // TODO: checksum
    }
    
    var isLeaf: Bool {
        depth == 0
    }
    
    /// Fetches a list of extents for this tree.
    /// - Parameters:
    ///   - fileBlock: The logical file block to start at.
    ///   - blockLength: A number of blocks, at minimum, that extents should be fetched for, starting at `fileBlock`.
    ///   - volume: The volume for this filesystem.
    ///   - performAdditionalIO: A boolean that determines whether performing additional IO to fetch extents is allowed. If `false`, only extents that do not require performing additional IO to the disk are fetched, if any.
    /// - Returns: An array of extents.
    func findExtentsCovering(_ fileBlock: UInt64, with blockLength: Int, in volume: Ext4Volume, performAdditionalIO: Bool = true) throws -> [FileExtentNode] {
        let firstBlock = fileBlock
        let lastBlock = Int(fileBlock) + blockLength - 1
        
        var result: [FileExtentNode] = []
        guard nodes.count > 0 else {
            return result
        }
        let lastPotentialChildIndex = -1 + nodes.partitioningIndex { element in
            element.logicalBlock > firstBlock
        }
        guard lastPotentialChildIndex >= 0 else {
            logger.fault("Last potential child index was invalid")
            throw POSIXError(.EIO)
        }
        
        for node in nodes[lastPotentialChildIndex..<(Int(numberOfEntries))] {
            if isLeaf {
                guard let lengthInBlocks = node.lengthInBlocks else {
                    logger.fault("Extent node's length was nil, but it is apparently a leaf node")
                    throw POSIXError(.EIO)
                }
                let firstBlockCoveredByExtent = node.logicalBlock
                let lastBlockCoveredByExtent = Int(node.logicalBlock) + Int(lengthInBlocks) - 1
                if lastBlockCoveredByExtent < firstBlock {
                    continue
                }
                if firstBlockCoveredByExtent > lastBlock {
                    break
                }
                
                result.append(node)
            } else if performAdditionalIO {
                let range = node.physicalBlock..<node.physicalBlock+1
                let lowerLevelData = try BlockDeviceReader.fetchExtent(from: volume.resource, blockNumbers: range, blockSize: volume.superblock.blockSize)
                guard let lowerLevel = FileExtentTreeLevel(from: lowerLevelData) else {
                    logger.error("Next level down in file extent tree was not vlaid")
                    throw POSIXError(.EIO)
                }
                let childResult = try lowerLevel.findExtentsCovering(fileBlock, with: blockLength, in: volume)
                if childResult.isEmpty {
                    break
                }
                result += childResult
            } else {
                break
            }
        }
        
        return result
    }
}
