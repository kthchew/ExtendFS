//
//  DirectoryEntryBlock.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 10/30/25.
//

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
