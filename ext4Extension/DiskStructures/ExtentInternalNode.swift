//
//  ExtentInternalNode.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 7/31/25.
//

import Foundation
import DataKit

struct ExtentInternalNode: ReadWritable {
    static var format: Format {
        \.firstBlock
        \.nextLevelBlock.lowerHalf
//        Convert(\.nextLevelBlock.upperHalf) {
//            
//
//        }
        UInt16(0)
    }
    
    init(from context: DataKit.ReadContext<ExtentInternalNode>) throws {
        firstBlock = try context.read(for: \.firstBlock)
        nextLevelBlock = try UInt64.combine(upper: context.read(for: \.nextLevelBlock.upperHalf), lower: context.read(for: \.nextLevelBlock.lowerHalf))
    }
    
    var firstBlock: UInt32
    var nextLevelBlock: UInt64
}
