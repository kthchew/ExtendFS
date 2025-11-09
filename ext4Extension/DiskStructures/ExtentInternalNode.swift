//
//  ExtentInternalNode.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 7/31/25.
//

import Foundation

struct ExtentInternalNode {
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let block: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.firstBlock = block
        guard let leafLower: UInt32 = iterator.nextLittleEndian() else { return nil }
        guard let leafUpper: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.nextLevelBlock = UInt64.combine(upper: leafUpper, lower: leafLower)
    }
    
    var firstBlock: UInt32
    var nextLevelBlock: UInt64
}
