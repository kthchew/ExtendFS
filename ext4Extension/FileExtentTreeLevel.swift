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
    
    var numberOfEntries: UInt16 { get { data.readLittleEndian(at: offsetInInode + 0x2) } }
    var maxNumberOfEntries: UInt16 { get { data.readLittleEndian(at: offsetInInode + 0x4) } }
    var depth: UInt16 { get { data.readLittleEndian(at: offsetInInode + 0x6) } }
    var generation: UInt32 { get { data.readLittleEndian(at: offsetInInode + 0x8) } }
    
    private var data: Data
    
    init(volume: Ext4Volume, offset: Int64) async throws {
        self.volume = volume
        self.offset = offset
        self.data = Data() // get the compiler to stop complaining
        let pointer = UnsafeMutableRawBufferPointer.allocate(byteCount: volume.superblock.blockSize, alignment: MemoryLayout<UInt8>.alignment)
        if BlockDeviceReader.useMetadataRead {
            try volume.resource.metadataRead(into: pointer, startingAt: blockNumber * Int64(volume.superblock.blockSize), length: volume.superblock.blockSize)
        } else {
            let actuallyRead = try await volume.resource.read(into: pointer, startingAt: blockNumber * Int64(volume.superblock.blockSize), length: volume.superblock.blockSize)
            guard actuallyRead == volume.superblock.blockSize else {
                throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
            }
        }
        self.data = Data(bytesNoCopy: pointer.baseAddress!, count: volume.superblock.blockSize, deallocator: .free)
    }
    
    init(volume: Ext4Volume, offset: Int64, data: Data) {
        self.volume = volume
        self.offset = offset
        self.data = data
    }
    
    var isLeaf: Bool {
        get {
            depth == 0
        }
    }
    
    func findExtentsCovering(_ fileBlock: Int64, with blockLength: Int) async throws -> [FileExtentNode] {
        let firstBlock = fileBlock
        let lastBlock = Int(fileBlock) + blockLength - 1
        
        var result: [FileExtentNode] = []
        let lastPotentialChildIndex = -1 + self.partitioningIndex { element in
            element!.logicalBlock > firstBlock
        }
        
        for node in self[lastPotentialChildIndex..<(Int(numberOfEntries))] {
            guard let node else {
                break
            }
            
            if isLeaf, let lengthInBlocks = node.lengthInBlocks {
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
            guard index < numberOfEntries else {
                return nil
            }
            
            return FileExtentNode(data: data, offset: offsetInInode + 12 + (12 * Int64(index)), isLeaf: depth == 0)
        }
    }
}

extension FileExtentTreeLevel: Collection, RandomAccessCollection {
    var startIndex: Int {
        0
    }
    var endIndex: Int {
        Int(numberOfEntries)
    }
}
