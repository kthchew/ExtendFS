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
    
    init(blockDevice: FSBlockDeviceResource, offset: off_t, isLeaf: Bool) {
        // FIXME: handle optional better
        let logicalBlock: UInt32 = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset) ?? 0
        self.logicalBlock = off_t(logicalBlock)
        if isLeaf {
            let length: UInt16 = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4) ?? 0
            if length > 32768 {
                self.lengthInBlocks = length - 32768
                self.type = .zeroFill
            } else {
                self.lengthInBlocks = length
                self.type = .data
            }
            let upperStartBlock: UInt16 = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x6) ?? 0
            let lowerStartBlock: UInt32 = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8) ?? 0
            self.physicalBlock = off_t(UInt64.combine(upper: upperStartBlock, lower: lowerStartBlock))
        } else {
            let lowerStartBlock: UInt32 = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x4) ?? 0
            let upperStartBlock: UInt16 = BlockDeviceReader.readLittleEndian(blockDevice: blockDevice, at: offset + 0x8) ?? 0
            self.physicalBlock = off_t(UInt64.combine(upper: upperStartBlock, lower: lowerStartBlock))
        }
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
