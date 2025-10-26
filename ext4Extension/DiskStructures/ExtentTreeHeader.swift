//
//  ExtentTreeHeader.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 7/31/25.
//

import DataKit
import Foundation

struct ExtentTreeHeader: ReadWritable {
    static var format: Format {
        UInt16(0xF30A)
        \.numberOfEntries
        \.maximumEntries
        \.depth
        \.generation
    }
    
    init(from context: DataKit.ReadContext<ExtentTreeHeader>) throws {
        numberOfEntries = try context.read(for: \.numberOfEntries)
        maximumEntries = try context.read(for: \.maximumEntries)
        depth = try context.read(for: \.depth)
        generation = try context.read(for: \.generation)
    }
    
    var numberOfEntries: UInt16
    var maximumEntries: UInt16
    var depth: UInt16
    var generation: UInt32
}
