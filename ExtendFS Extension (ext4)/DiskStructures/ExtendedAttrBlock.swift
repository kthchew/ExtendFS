// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "ExtendedAttrBlock")

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
        guard let remainingOffset = UInt32(exactly: offset) else {
            logger.error("The remaining data offset can't fit in a 32-bit integer. This should not happen for a well-formed extended attribute block.")
            return nil
        }
        self.remainingDataOffset = remainingOffset
    }
    
    init?(blockAt blockNumber: UInt32, in volume: Ext4Volume) throws {
        let blockSize = volume.superblock.blockSize
        var blockData = Data(count: blockSize)
        try blockData.withUnsafeMutableBytes { ptr in
            try volume.resource.metadataRead(into: ptr, startingAt: off_t(blockNumber) * off_t(blockSize), length: blockSize)
        }
        guard let header = ExtendedAttrHeader(from: blockData[0..<32]) else {
            logger.error("Could not form valid extended attribute block from data because the header was invalid")
            throw POSIXError(.EIO)
        }
        
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
                guard offset >= 0 else {
                    logger.error("Offset for extended attribute entry was negative")
                    throw POSIXError(.EIO)
                }
                
                attrs[entry.name] = remainingData.subdata(in: offset..<(offset+Int(entry.valueLength)))
            }
            return attrs
        }
    }
    
    func value(for entry: ExtendedAttrEntry) throws -> Data {
        let offset = Int(entry.valueOffset) - Int(remainingDataOffset)
        guard offset >= 0 else {
            logger.error("Offset for extended attribute entry was negative")
            throw POSIXError(.EIO)
        }
        
        return remainingData.subdata(in: offset..<(offset+Int(entry.valueLength)))
    }
}
