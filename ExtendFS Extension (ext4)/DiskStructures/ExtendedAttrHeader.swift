// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

struct ExtendedAttrHeader {
    init?(from data: Data) {
        var offset = 0
        
        guard let magic: UInt32 = try? data.readLittleEndian(at: &offset), magic == 0xEA020000 else { return nil }
        guard let refCount: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.referenceCount = refCount
        // FIXME: currently nothing cares about the actual disk block count, it just assumes 1 block
        guard let diskBlockCount: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.diskBlockCount = diskBlockCount
        guard let hash: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.hash = hash
        guard let checksum: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.checksum = checksum
    }
    
    var referenceCount: UInt32
    var diskBlockCount: UInt32
    var hash: UInt32
    var checksum: UInt32
}
