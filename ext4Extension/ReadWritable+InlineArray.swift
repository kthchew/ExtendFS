//
//  ReadWritable+InlineArray.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 10/25/25.
//

import Foundation
import DataKit

extension InlineArray: @retroactive Writable where Element: Writable {
    public static var writeFormat: WriteFormat<Self> {
        for i in 0..<count {
            \.[i]
        }
    }
}

extension InlineArray: @retroactive Readable where Element: Readable {
    public init(from context: DataKit.ReadContext<Self>) throws {
        try self.init { index in
            return try context.read(for: \.[index])
        }
    }
    
    public static var readFormat: ReadFormat<Self> {
        for i in 0..<count {
            \.[i]
        }
    }
}

extension InlineArray: @retroactive ReadWritable where Element: ReadWritable {
    public static var format: Format {
        Format(read: readFormat, write: writeFormat)
    }
}
