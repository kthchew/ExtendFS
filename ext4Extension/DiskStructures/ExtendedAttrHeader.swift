//
//  ExtendedAttrHeader.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 9/9/25.
//

import Foundation

struct ExtendedAttrHeader {
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let magic: UInt32 = iterator.nextLittleEndian(), magic == 0xEA020000 else { return nil }
        guard let refCount: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.referenceCount = refCount
        guard let diskBlockCount: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.diskBlockCount = diskBlockCount
        guard let hash: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.hash = hash
        guard let checksum: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.checksum = checksum
    }
    
    var referenceCount: UInt32
    var diskBlockCount: UInt32
    var hash: UInt32
    var checksum: UInt32
}
