//
//  NumericalExtensions.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 6/1/25.
//

import Foundation

extension FixedWidthInteger {
    // https://forums.swift.org/t/rounding-numbers-up-down-to-nearest-multiple-and-power/15547
    func roundUp(toMultipleOf powerOfTwo: Self) -> Self {
        // Check that powerOfTwo really is.
        precondition(powerOfTwo > 0 && powerOfTwo & (powerOfTwo &- 1) == 0)
        // Round up and return. This may overflow and trap, but only if the rounded
        // result would have overflowed anyway.
        return (self + (powerOfTwo &- 1)) & (0 &- powerOfTwo)
    }
}

extension UInt64 {
    static func combine(upper: UInt32, lower: UInt32) -> UInt64 {
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    static func combine(upper: UInt32?, lower: UInt32?) -> UInt64? {
        guard let lower else { return nil }
        guard let upper else { return UInt64(lower) }
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    
    static func combine(upper: UInt16, lower: UInt32) -> UInt64 {
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    static func combine(upper: UInt16?, lower: UInt32?) -> UInt64? {
        guard let lower else { return nil }
        guard let upper else { return UInt64(lower) }
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    
    static func combine(upper: UInt32, lower: UInt16) -> UInt64 {
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    static func combine(upper: UInt32?, lower: UInt16?) -> UInt64? {
        guard let lower else { return nil }
        guard let upper else { return UInt64(lower) }
        return (UInt64(upper) << 32) | UInt64(lower)
    }
    
    var upperHalf: UInt32 {
        UInt32(self >> 32)
    }
    
    var lowerHalf: UInt32 {
        UInt32(self & UInt64(UInt32.max))
    }
}

extension UInt32 {
    static func combine(upper: UInt16, lower: UInt16) -> UInt32 {
        return (UInt32(upper) << 16) | UInt32(lower)
    }
    
    static func combine(upper: UInt16?, lower: UInt16?) -> UInt32? {
        guard let lower else { return nil }
        guard let upper else { return UInt32(lower) }
        return (UInt32(upper) << 16) | UInt32(lower)
    }
    
    var upperHalf: UInt16 {
        UInt16(self >> 16)
    }
    
    var lowerHalf: UInt16 {
        UInt16(self & UInt32(UInt16.max))
    }
}
