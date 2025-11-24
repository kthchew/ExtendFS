// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

struct ClassicDirectoryEntryBlock {
    var entries: [DirectoryEntry]
    var checksum: UInt32 {
        // TODO: actual checksum
        return 0
    }
    
    init?(from data: Data) {
        self.entries = []
        var data = data
        while data.count > 0 {
            guard let entry = DirectoryEntry(from: data) else { break }
            self.entries.append(entry)
            data = data.advanced(by: Int(entry.directoryEntryLength))
        }
    }
}
