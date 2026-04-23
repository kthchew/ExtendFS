// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

struct HTreeHasher {
    /// Returns the hash value for the provided file name for use in a hash tree directory.
    /// - Parameters:
    ///   - name: The file name. The UTF-8 encoding will be used to create the hash.
    ///   - hashType: The hash version to use.
    /// - Returns: The hash as a 64-bit integer, where the upper half is the major part and the lower half is the minor part. `nil` if hashing fails (such as if the provided hash algorithm is unsupported).
    static func hash(name: String, hashType: Superblock.HashVersion) -> UInt64? {
        var major: UInt32 = 0
        var minor: UInt32 = 0
        let result = name.withCString { strPtr in
            ext2_htree_hash(strPtr, Int32(name.lengthOfBytes(using: .utf8)), nil, Int32(hashType.rawValue), &major, &minor)
        }
        guard result == 0 else { return nil }
        return UInt64.combine(upper: major, lower: minor)
    }
}
