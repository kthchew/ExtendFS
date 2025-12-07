//
//  HTreeHasher.swift
//  ExtendFS Extension (ext4)
//
//  Created by Kenneth Chew on 11/30/25.
//

import Foundation
import CommonCrypto

struct HTreeHasher {
    static func halfMD4(_ name: String) -> UInt64 {
        name.utf8CString.withUnsafeBytes { buf in
            var md = [UInt8](repeating: 0, count: 16)
            CC_MD4(buf.baseAddress, CC_LONG(buf.count), &md)
            // take lower half of the 16 bytes (8 bytes total)
            return (UInt64(md[8]) << 56) | (UInt64(md[9]) << 48) | (UInt64(md[10]) << 40) | (UInt64(md[11]) << 32) | (UInt64(md[12]) << 24) | (UInt64(md[13]) << 16) | (UInt64(md[14]) << 8) | UInt64(md[15])
        }
    }
}
