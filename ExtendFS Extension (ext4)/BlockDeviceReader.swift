// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import os.log

struct BlockDeviceReader {
    static private let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "BlockDeviceReader")
    nonisolated(unsafe) static var useMetadataRead = false
    
    static func fetchExtent(from device: FSBlockDeviceResource, blockNumbers: Range<off_t>, blockSize: Int) throws -> Data {
        var data = Data(count: blockNumbers.count * blockSize)
        let startReadAt = Int64(blockNumbers.lowerBound) * Int64(blockSize)
        let length = Int(blockNumbers.count) * Int(blockSize)
        try data.withUnsafeMutableBytes { ptr in
            if useMetadataRead {
                try device.metadataRead(into: ptr, startingAt: startReadAt, length: length)
            } else {
                let actuallyRead = try device.read(into: ptr, startingAt: startReadAt, length: length)
                guard actuallyRead == length else {
                    logger.error("Expected to read \(length) bytes, actually read \(actuallyRead)")
                    throw POSIXError(.EIO)
                }
            }
        }
        
        return data
    }
    
    static func fetchSuperblockData(from device: FSBlockDeviceResource, at offset: Int64) throws -> Data {
        let superblockSize: Int64 = 1024
        let physicalBlockSize = Int64(device.physicalBlockSize)
        let toRead = max(superblockSize, physicalBlockSize)
        let startReadAt = offset % physicalBlockSize == 0 ? offset : (offset / physicalBlockSize) * physicalBlockSize
        var data = Data(count: Int(toRead))
        let actuallyRead = try data.withUnsafeMutableBytes { ptr in
            let actuallyRead: Int
            do {
                actuallyRead = try device.read(into: ptr, startingAt: startReadAt, length: Int(toRead))
            } catch {
                logger.critical("Tried to read from the block device starting at \(startReadAt, privacy: .public) with length \(toRead, privacy: .public), but this is failed with error \(error, privacy: .public). It is likely incompatible with the device's sector size of \(physicalBlockSize, privacy: .public). Please report this as a bug.")
                throw error
            }
            return actuallyRead
        }
        guard actuallyRead == toRead else {
            logger.error("Expected to read \(toRead, privacy: .public) bytes for superblock, only read \(actuallyRead, privacy: .public) bytes")
            throw POSIXError(.EIO)
        }
        let offsetInData = Int(offset - startReadAt)
        let superblockData = data.subdata(in: (offsetInData)..<(offsetInData + Int(superblockSize)))
        return superblockData
    }
}
