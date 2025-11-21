//
//  BlockGroupDescriptors.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 5/29/25.
//

import Foundation
import FSKit
import os.log

final class BlockGroupDescriptors: Sendable {
    /// An offset pointing to the first descriptor in this block group, starting from the start of the disk.
    let offset: Int64
    let blockGroupCount: Int
    
    let data: Data
    
    private let descriptorSizeInBytes: UInt16
    
    init(resource: FSBlockDeviceResource, superblock: Superblock, offset: Int64, blockGroupCount: Int) throws {
        self.offset = offset
        self.blockGroupCount = blockGroupCount
        self.descriptorSizeInBytes = superblock.featureIncompatibleFlags.contains(.enable64BitSize) ? superblock.descriptorSize : 32
        
        let descriptorSizeBytes = superblock.featureIncompatibleFlags.contains(.enable64BitSize) ? superblock.descriptorSize : 32
        let totalSize = (blockGroupCount * Int(descriptorSizeBytes)).roundUp(toMultipleOf: superblock.blockSize)
        
        var data = Data(count: totalSize)
        try data.withUnsafeMutableBytes { ptr in
            if BlockDeviceReader.useMetadataRead {
                try resource.metadataRead(into: ptr, startingAt: offset, length: totalSize)
            } else {
                let actuallyRead = try resource.read(into: ptr, startingAt: offset, length: totalSize)
                guard actuallyRead == totalSize else { throw POSIXError(.EIO) }
            }
        }
        self.data = data
    }
    
    subscript(index: Int) -> BlockGroupDescriptor? {
        get throws {
            guard index >= 0 && index < blockGroupCount else {
                return nil
            }
            
            let start = Int(index) * Int(descriptorSizeInBytes)
            let descriptorData = data.subdata(in: start..<(start+Int(descriptorSizeInBytes)))
            return BlockGroupDescriptor(from: descriptorData)
        }
    }
}
