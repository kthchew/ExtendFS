//
//  ExtendedAttrBlock.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 9/9/25.
//

import Foundation
import FSKit

struct ExtendedAttrBlock {
    var header: ExtendedAttrHeader
    var entries: [ExtendedAttrEntry]
    var remainingData: Data
    /// The offset in the block at which ``remainingData`` starts, in bytes.
    var remainingDataOffset: UInt32
    
    init?(from data: Data) {
        guard let header = ExtendedAttrHeader(from: data) else { return nil }
        self.header = header
        
        var data = data.advanced(by: 32)
        var offset = 32
        self.entries = []
        while !data.isEmpty {
            guard let entry = ExtendedAttrEntry(from: data) else { break }
            guard entry.nameLength != 0 || entry.namePrefix.rawValue != 0 || entry.valueOffset != 0 || entry.valueInodeNumber != 0 else {
                break
            }
            
            entries.append(entry)
            let advance = (16 + Int(entry.nameLength)).roundUp(toMultipleOf: 4)
            data = data.advanced(by: advance)
            offset += advance
        }
        self.remainingData = data
        self.remainingDataOffset = UInt32(offset)
    }
    
    init?(blockAt blockNumber: UInt32, in volume: Ext4Volume) throws {
        let blockSize = volume.superblock.blockSize
        var blockData = Data(count: blockSize)
        try blockData.withUnsafeMutableBytes { ptr in
            try volume.resource.metadataRead(into: ptr, startingAt: off_t(blockNumber) * off_t(blockSize), length: blockSize)
        }
        guard let header = ExtendedAttrHeader(from: blockData[0..<32]) else { throw POSIXError(.EIO) }
        
        let additionalBlocks = Int(header.diskBlockCount) - 1
        if additionalBlocks > 0 {
            var additionalBlockData = Data(count: blockSize * additionalBlocks)
            try additionalBlockData.withUnsafeMutableBytes { ptr in
                try volume.resource.metadataRead(into: ptr, startingAt: off_t(blockNumber + 1) * off_t(blockSize), length: blockSize * additionalBlocks)
            }
            blockData += additionalBlockData
        }
        
        self.init(from: blockData)
    }
    
    var extendedAttributes: [String: Data] {
        get throws {
            var attrs: [String: Data] = [:]
            for entry in entries {
                let offset = Int(entry.valueOffset) - Int(remainingDataOffset)
                guard offset >= 0 else { throw POSIXError(.EIO) }
                
                attrs[entry.name] = remainingData.subdata(in: offset..<(offset+Int(entry.valueLength)))
            }
            return attrs
        }
    }
    
    func value(for entry: ExtendedAttrEntry) throws -> Data {
        let offset = Int(entry.valueOffset) - Int(remainingDataOffset)
        guard offset >= 0 else { throw POSIXError(.EIO) }
        
        return remainingData.subdata(in: offset..<(offset+Int(entry.valueLength)))
    }
}
