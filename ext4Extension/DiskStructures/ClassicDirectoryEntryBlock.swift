//
//  DirectoryEntryBlock.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 10/30/25.
//

import Foundation
import DataKit

struct ClassicDirectoryEntryBlock: ReadWritable {
    var entries: [DirectoryEntry]
    var checksum: UInt32 {
        // TODO: actual checksum
        return 0
    }
    
    static var format: Format {
        Convert(\.entries) {
            $0.dynamicCount
        }
        .suffix(nil)
    }
    
    init(from context: ReadContext<Self>) throws {
        self.entries = try context.read(for: \.entries)
    }
}
