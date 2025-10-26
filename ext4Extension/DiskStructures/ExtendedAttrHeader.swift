//
//  ExtendedAttrHeader.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 9/9/25.
//

import Foundation
import DataKit

struct ExtendedAttrHeader: ReadWritable {
    static var format: Format {
        UInt32(0xEA020000)
        \.referenceCount
        \.diskBlockCount
        \.hash
        \.checksum
        UInt32(0x0)
        UInt32(0x0)
        UInt32(0x0)
    }
    
    init(from context: ReadContext<ExtendedAttrHeader>) throws {
        referenceCount = try context.read(for: \.referenceCount)
        diskBlockCount = try context.read(for: \.diskBlockCount)
        hash = try context.read(for: \.hash)
        checksum = try context.read(for: \.checksum)
    }
    
    var referenceCount: UInt32
    var diskBlockCount: UInt32
    var hash: UInt32
    var checksum: UInt32
}
