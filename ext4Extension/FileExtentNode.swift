//
//  FileExtent.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit

/// A type that represents a node in an ext4 extent tree.
struct FileExtentNode: Hashable, Comparable {
    static func < (lhs: FileExtentNode, rhs: FileExtentNode) -> Bool {
        lhs.logicalBlock < rhs.logicalBlock
    }
    
    init(blockDevice: FSBlockDeviceResource, offset: off_t, isLeaf: Bool) throws {
        let logicalBlock: UInt32 = try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset)
        self.logicalBlock = off_t(logicalBlock)
        if isLeaf {
            let length: UInt16 = try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4)
            if length > 32768 {
                self.lengthInBlocks = length - 32768
                self.type = .zeroFill
            } else {
                self.lengthInBlocks = length
                self.type = .data
            }
            let upperStartBlock: UInt16 = try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x6)
            let lowerStartBlock: UInt32 = try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8)
            self.physicalBlock = off_t(UInt64.combine(upper: upperStartBlock, lower: lowerStartBlock))
        } else {
            let lowerStartBlock: UInt32 = try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4)
            let upperStartBlock: UInt16 = try BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8)
            self.physicalBlock = off_t(UInt64.combine(upper: upperStartBlock, lower: lowerStartBlock))
        }
    }
    
    /// Directly create a node representing a file extent.
    /// - Parameters:
    ///   - physicalBlock: The offset of the data block on the physical disk, in blocks.
    ///   - logicalBlock: The offset within the file, in blocks.
    ///   - lengthInBlocks: The length that this extent covers, in blocks.
    ///   - type: The type of extent, indicating whether it contains valid data.
    init(physicalBlock: off_t, logicalBlock: off_t, lengthInBlocks: UInt16, type: FSExtentType) {
        self.physicalBlock = physicalBlock
        self.logicalBlock = logicalBlock
        self.lengthInBlocks = lengthInBlocks
        self.type = type
    }
    
    /// The extent offset on disk, in blocks, or the block number of the child level.
    var physicalBlock: off_t
    /// The extent offset within the file, in blocks.
    var logicalBlock: off_t
    /// The extent length, in blocks, if this is a leaf node.
    var lengthInBlocks: UInt16?
    /// The type of extent, indicating whether it contains valid data, if this is a leaf node.
    var type: FSExtentType?
}
