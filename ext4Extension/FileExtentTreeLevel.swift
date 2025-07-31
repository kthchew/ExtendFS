//
//  ExtentTreeLevel.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Algorithms
import Foundation
import FSKit

class FileExtentTreeLevel {
    let volume: Ext4Volume
    let offset: Int64
    
    var blockNumber: Int64 {
        get {
            offset / Int64(volume.superblock.blockSize)
        }
    }
    var offsetInBlock: Int64 {
        get {
            offset % Int64(volume.superblock.blockSize)
        }
    }
    var offsetInInode: Int64 {
        get {
            offsetInBlock % Int64(volume.superblock.inodeSize)
        }
    }
    var inodeOffsetInBlock: Int64 {
        get {
            offsetInBlock - offsetInInode
        }
    }
    
    private var blockDevice: FSBlockDeviceResource {
        volume.resource
    }
    
    var numberOfEntries: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x2) } }
    var maxNumberOfEntries: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x4) } }
    var depth: UInt16 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x6) } }
    var generation: UInt32 { get throws { try BlockDeviceReader.readLittleEndian(blockDevice: volume.resource, at: offset + 0x8) } }
    
    init(volume: Ext4Volume, offset: Int64) async throws {
        self.volume = volume
        self.offset = offset
    }
    
    var isLeaf: Bool {
        get throws {
            try depth == 0
        }
    }
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int) async throws -> [FileExtentNode] {
        let firstBlock = fileBlock
        let lastBlock = Int(fileBlock) + blockLength - 1
        
        var result: [FileExtentNode] = []
        let lastPotentialChildIndex = -1 + self.partitioningIndex { element in
            element!.logicalBlock > firstBlock
        }
        
        for node in self[lastPotentialChildIndex..<(Int(try numberOfEntries))] {
            guard let node else {
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
                let childResult = try await FileExtentTreeLevel(volume: volume, offset: node.physicalBlock * Int64(volume.superblock.blockSize)).findExtentsCovering(fileBlock, with: blockLength)
                if childResult.isEmpty {
                    break
                }
                result += childResult
            }
        }
        
        return result
    }
    
    subscript(index: Int) -> FileExtentNode? {
        get {
            guard let numberOfEntries = try? numberOfEntries else {
                return nil
            }
            guard index < numberOfEntries else {
                return nil
            }
            
            return try? FileExtentNode(blockDevice: blockDevice, offset: offset + 12 + (12 * Int64(index)), isLeaf: depth == 0)
        }
    }
}

extension FileExtentTreeLevel: Collection, RandomAccessCollection {
    var startIndex: Int {
        0
    }
    var endIndex: Int {
        Int((try? numberOfEntries) ?? 0)
    }
}
