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
