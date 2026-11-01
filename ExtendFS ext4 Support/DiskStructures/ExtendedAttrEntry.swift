// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

public struct ExtendedAttrEntry {
    public init?(from data: Data) {
        var offset = 0
        
        guard let nameLen: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.nameLength = nameLen
        guard let namePrefixRaw: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.namePrefix = NamePrefix(rawValue: namePrefixRaw) ?? .none
        guard let valueOffset: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.valueOffset = valueOffset
        guard let valueInodeNumber: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.valueInodeNumber = valueInodeNumber
        guard let valueLength: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.valueLength = valueLength
        guard let hash: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.hash = hash
        guard let storedName = try? data.readString(at: &offset, maxLength: Int(nameLen)) else { return nil }
        self.storedName = storedName
    }
    
    public var nameLength: UInt8
    
    public enum NamePrefix: UInt8 {
        case none = 0
        case user = 1
        case posixAclAccess = 2
        case posixAclDefault = 3
        case trusted = 4
        case security = 6
        case system = 7
        case richAcl = 8
        
        public var prefix: String {
            switch self {
            case .none:
                ""
            case .user:
                "user."
            case .posixAclAccess:
                "system.posix_acl_access"
            case .posixAclDefault:
                "system.posix_acl_default"
            case .trusted:
                "trusted."
            case .security:
                "security."
            case .system:
                "system."
            case .richAcl:
                "system.richacl"
            }
        }
    }
    public var namePrefix: NamePrefix
    
    public var valueOffset: UInt16
    public var valueInodeNumber: UInt32
    public var valueLength: UInt32
    
    public var hash: UInt32
    public var storedName: String
    
    public var name: String {
        namePrefix.prefix + storedName
    }
}
