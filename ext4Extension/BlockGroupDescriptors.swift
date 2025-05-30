//
//  BlockGroupDescriptors.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation

class BlockGroupDescriptors {
    let volume: Ext4Volume
    /// An offset pointing to the first descriptor in this block group, starting from the start of the disk.
    let offset: Int64
    let blockGroupCount: Int
    
    init(volume: Ext4Volume, offset: Int64, blockGroupCount: Int) {
        self.volume = volume
        self.offset = offset
        self.blockGroupCount = blockGroupCount
    }
    
    subscript(index: Int) -> BlockGroupDescriptor? {
        get throws {
            guard index >= 0 && index < blockGroupCount else {
                return nil
            }
            
            let descriptorSizeBytes = try volume.superblock.descriptorSize
            return BlockGroupDescriptor(volume: volume, offset: offset + Int64(index) * Int64(descriptorSizeBytes))
        }
    }
}
