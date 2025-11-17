//
//  ExtentTreeLevel.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Algorithms
import Foundation
import FSKit
import os.log

class FileExtentTreeLevel {
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
            Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "FileExtentTreeLevel").error("numberOfEntries did not match node count!")
            return nil
        }
        
        // TODO: checksum
    }
    
    var isLeaf: Bool {
        depth == 0
    }
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int, in volume: Ext4Volume) throws -> [FileExtentNode] {
        let firstBlock = fileBlock
        let lastBlock = Int(fileBlock) + blockLength - 1
        
        var result: [FileExtentNode] = []
        let lastPotentialChildIndex = -1 + nodes.partitioningIndex { element in
            element.logicalBlock > firstBlock
        }
        
        for node in nodes[lastPotentialChildIndex..<(Int(numberOfEntries))] {
            if isLeaf {
                guard let lengthInBlocks = node.lengthInBlocks else { throw POSIXError(.EIO) }
                let firstBlockCoveredByExtent = node.logicalBlock
                let lastBlockCoveredByExtent = Int(node.logicalBlock) + Int(lengthInBlocks) - 1
                if lastBlockCoveredByExtent < firstBlock {
                    continue
                }
                if firstBlockCoveredByExtent > lastBlock {
                    break
                }
                
                result.append(node)
            } else {
                let range = node.physicalBlock..<node.physicalBlock+1
                let lowerLevelData = try BlockDeviceReader.fetchExtent(from: volume.resource, blockNumbers: range, blockSize: volume.superblock.blockSize)
                guard let lowerLevel = FileExtentTreeLevel(from: lowerLevelData) else { throw POSIXError(.EIO) }
                let childResult = try lowerLevel.findExtentsCovering(fileBlock, with: blockLength, in: volume)
                if childResult.isEmpty {
                    break
                }
                result += childResult
            }
        }
        
        return result
    }
}
