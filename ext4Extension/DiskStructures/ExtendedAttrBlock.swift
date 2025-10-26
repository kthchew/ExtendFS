//
//  ExtendedAttrBlock.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 9/9/25.
//

import Foundation
import FSKit
import DataKit

struct ExtendedAttrBlock: ReadWritable {
    var header: ExtendedAttrHeader
    var entries: [ExtendedAttrEntry]
    var remainingData: Data
    /// The offset in the block at which ``remainingData`` starts.
    var remainingDataOffset: UInt32
    
    var blockNumber: UInt32
    
    static var format: Format {
        \.header
        
        Convert(\.entries) {
            $0.dynamicCount
        }
        .suffix(0 as UInt64)
        
        Custom(\.remainingDataOffset) { read in
            return UInt32(read.index)
        } write: { write, val in
            try val.write(to: &write)
        }
        
        Custom(\.remainingData) { read in
            return read.remainingData
        } write: { write, val in
            write.append(val)
        }
    }
    
    init(from context: ReadContext<ExtendedAttrBlock>) throws {
        self.header = try context.read(for: \.header)
        self.entries = try context.read(for: \.entries)
        self.remainingData = try context.read(for: \.remainingData)
        self.remainingDataOffset = try context.read(for: \.remainingDataOffset)
        
        self.blockNumber = try context.readIfPresent(for: \.blockNumber) ?? 0
    }
    
    init(blockAt blockNumber: UInt32, in volume: Ext4Volume) throws {
        let blockSize = volume.superblock.blockSize
        var blockData = Data(count: blockSize)
        try blockData.withUnsafeMutableBytes { ptr in
            try volume.resource.metadataRead(into: ptr, startingAt: off_t(blockNumber) * off_t(blockSize), length: blockSize)
        }
        let header = try ExtendedAttrHeader(blockData[0..<32])
        
        let additionalBlocks = Int(header.diskBlockCount) - 1
        if additionalBlocks > 0 {
            var additionalBlockData = Data(count: blockSize * additionalBlocks)
            try additionalBlockData.withUnsafeMutableBytes { ptr in
                try volume.resource.metadataRead(into: ptr, startingAt: off_t(blockNumber + 1) * off_t(blockSize), length: blockSize * additionalBlocks)
            }
            blockData += additionalBlockData
        }
        
        try self.init(blockData)
        
        self.blockNumber = blockNumber
    }
}
