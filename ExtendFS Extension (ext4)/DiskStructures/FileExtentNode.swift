// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

/// A type that represents a node in an ext4 extent tree.
struct FileExtentNode: Hashable, Comparable {
    static func < (lhs: FileExtentNode, rhs: FileExtentNode) -> Bool {
        lhs.logicalBlock < rhs.logicalBlock
    }
    
    init?(from data: Data, isLeaf: Bool) {
        var iterator = data.makeIterator()
        
        guard let logicalBlock: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.logicalBlock = off_t(logicalBlock)
        if isLeaf {
            guard let length: UInt16 = iterator.nextLittleEndian() else { return nil }
            if length > 32768 {
                self.lengthInBlocks = length - 32768
                self.type = .zeroFill
            } else {
                self.lengthInBlocks = length
                self.type = .data
            }
            guard let upperStartBlock: UInt16 = iterator.nextLittleEndian() else { return nil }
            guard let lowerStartBlock: UInt32 = iterator.nextLittleEndian() else { return nil }
            self.physicalBlock = off_t(UInt64.combine(upper: upperStartBlock, lower: lowerStartBlock))
        } else {
            guard let lowerStartBlock: UInt32 = iterator.nextLittleEndian() else { return nil }
            guard let upperStartBlock: UInt16 = iterator.nextLittleEndian() else { return nil }
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
