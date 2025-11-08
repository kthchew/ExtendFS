//
//  StringFixedArray.swift
//  ExtendFS
//
//  Created by Kenneth Chew on 10/28/25.
//

import Foundation

extension String {
    func inlineArray<let length: Int>() throws -> InlineArray<length, CChar> {
        let utf8 = self.utf8CString
        if length < utf8.count {
            throw POSIXError(.ENAMETOOLONG)
        }
        return InlineArray<length, CChar> { index in
            index < utf8.count ? utf8[index] : 0
        }
    }
}

extension InlineArray where Element == CChar {
    func toString() -> String {
        return self.span.withUnsafeBufferPointer { ptr in
            String(cString: ptr.baseAddress!)
        }
    }
}
