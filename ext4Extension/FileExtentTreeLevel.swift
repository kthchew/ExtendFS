//
//  ExtentTreeLevel.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit

struct FileExtentTreeLevel {
    let volume: Ext4Volume
    let offset: Int64
    
    private var blockDevice: FSBlockDeviceResource {
        volume.resource
    }
    
    var numberOfEntries: UInt16? { BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x2) }
    var maxNumberOfEntries: UInt16? { BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4) }
    var depth: UInt16? { BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x6) }
    var generation: UInt32? { BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8) }
    
    var isLeaf: Bool? {
        if let depth {
            return depth == 0
        } else {
            return nil
        }
    }
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int) -> [FileExtentNode] {
        let firstBlock = fileBlock
        let lastBlock = Int(fileBlock) + blockLength - 1
        
        var result: [FileExtentNode] = []
        var lastPotentialChildIndex = 0
        
        for index in 0..<Int(numberOfEntries ?? 0) {
            if let node = self[index] {
                if node.logicalBlock < firstBlock {
                    lastPotentialChildIndex = index
                } else {
                    break
                }
            }
        }
        
        for index in lastPotentialChildIndex..<(Int(numberOfEntries ?? 0)) {
            guard let node = self[Int(index)] else {
                break
            }
            
            if let isLeaf, isLeaf, let lengthInBlocks = node.lengthInBlocks {
                let firstBlockCoveredByExtent = node.logicalBlock
                let lastBlockCoveredByExtent = Int(node.logicalBlock) + Int(lengthInBlocks) - 1
                if lastBlockCoveredByExtent < firstBlock || firstBlockCoveredByExtent > lastBlock {
                    break
                }
                
                result.append(node)
            } else {
                let childResult = FileExtentTreeLevel(volume: volume, offset: node.physicalBlock * Int64(volume.superblock.blockSize ?? 4096)).findExtentsCovering(fileBlock, with: blockLength)
                if childResult.isEmpty {
                    break
                }
                result += childResult
            }
        }
        
        return result
    }
    
    subscript(index: Int) -> FileExtentNode? {
        guard let numberOfEntries, index < numberOfEntries, let depth else {
            return nil
        }
        
        return FileExtentNode(blockDevice: blockDevice, offset: offset + 12 + (12 * Int64(index)), isLeaf: depth == 0)
    }
}
