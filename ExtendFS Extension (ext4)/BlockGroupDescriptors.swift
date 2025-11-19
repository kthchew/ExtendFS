//
//  BlockGroupDescriptors.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import os.log

class BlockGroupDescriptors {
    let volume: Ext4Volume
    /// An offset pointing to the first descriptor in this block group, starting from the start of the disk.
    let offset: Int64
    let blockGroupCount: Int
    
    var data: Data
    
    init(volume: Ext4Volume, offset: Int64, blockGroupCount: Int) throws {
        self.volume = volume
        self.offset = offset
        self.blockGroupCount = blockGroupCount
        
        let descriptorSizeBytes = volume.superblock.featureIncompatibleFlags.contains(.enable64BitSize) ? volume.superblock.descriptorSize : 32
        let totalSize = (blockGroupCount * Int(descriptorSizeBytes)).roundUp(toMultipleOf: volume.superblock.blockSize)
        
        self.data = Data(count: totalSize)
        try self.data.withUnsafeMutableBytes { ptr in
            if BlockDeviceReader.useMetadataRead {
                try volume.resource.metadataRead(into: ptr, startingAt: offset, length: totalSize)
            } else {
                let actuallyRead = try volume.resource.read(into: ptr, startingAt: offset, length: totalSize)
                guard actuallyRead == totalSize else { throw POSIXError(.EIO) }
            }
        }
    }
    
    subscript(index: Int) -> BlockGroupDescriptor? {
        get throws {
            guard index >= 0 && index < blockGroupCount else {
                return nil
            }
            
            let descriptorSizeBytes = volume.superblock.featureIncompatibleFlags.contains(.enable64BitSize) ? volume.superblock.descriptorSize : 32
            let start = Int(index) * Int(descriptorSizeBytes)
            let descriptorData = data.subdata(in: start..<(start+Int(descriptorSizeBytes)))
            return BlockGroupDescriptor(from: descriptorData)
        }
    }
}
