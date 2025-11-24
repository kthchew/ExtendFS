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
}
