// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

struct ExtentTreeHeader {
    
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let magic: UInt16 = iterator.nextLittleEndian(), magic == 0xF30A else { return nil }
        guard let numEntries: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.numberOfEntries = numEntries
        guard let maxEntries: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.maximumEntries = maxEntries
        guard let depth: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.depth = depth
        guard let gen: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.generation = gen
    }
    
    var numberOfEntries: UInt16
    var maximumEntries: UInt16
    var depth: UInt16
    var generation: UInt32
}
