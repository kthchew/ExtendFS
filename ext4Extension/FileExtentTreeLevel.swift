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
    
    var numberOfEntries: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x2) } }
    var maxNumberOfEntries: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4) } }
    var depth: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x6) } }
    var generation: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8) } }
    
    var isLeaf: Bool {
        get throws {
            (try depth) == 0
        }
    }
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int) throws -> [FileExtentNode] {
        let firstBlock = fileBlock
        let lastBlock = Int(fileBlock) + blockLength - 1
        
        var result: [FileExtentNode] = []
        var lastPotentialChildIndex = 0
        
        // TODO: improve efficiency (use binary search or something)
        for index in 0..<Int(try numberOfEntries) {
            if let node = try self[index] {
                if node.logicalBlock <= firstBlock {
                    lastPotentialChildIndex = index
                } else {
                    break
                }
            }
        }
        
        for index in lastPotentialChildIndex..<(Int(try numberOfEntries)) {
            guard let node = try self[Int(index)] else {
                break
            }
            
            if try isLeaf, let lengthInBlocks = node.lengthInBlocks {
                let firstBlockCoveredByExtent = node.logicalBlock
                let lastBlockCoveredByExtent = Int(node.logicalBlock) + Int(lengthInBlocks) - 1
                if lastBlockCoveredByExtent < firstBlock || firstBlockCoveredByExtent > lastBlock {
                    break
                }
                
                result.append(node)
            } else {
                let childResult = try FileExtentTreeLevel(volume: volume, offset: node.physicalBlock * Int64(volume.superblock.blockSize)).findExtentsCovering(fileBlock, with: blockLength)
                if childResult.isEmpty {
                    break
                }
                result += childResult
            }
        }
        
        return result
    }
    
    subscript(index: Int) -> FileExtentNode? {
        get throws {
            guard index < (try numberOfEntries) else {
                return nil
            }
            
            return try FileExtentNode(blockDevice: blockDevice, offset: offset + 12 + (12 * Int64(index)), isLeaf: depth == 0)
        }
    }
}
