//
//  ExtendedAttrEntry.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 9/4/25.
//

import Foundation
import CommonCrypto

struct ExtendedAttrEntry {
    init?(from data: Data) {
        var iterator = data.makeIterator()
        
        guard let nameLen: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.nameLength = nameLen
        guard let namePrefixRaw: UInt8 = iterator.nextLittleEndian() else { return nil }
        self.namePrefix = NamePrefix(rawValue: namePrefixRaw) ?? .none
        guard let valueOffset: UInt16 = iterator.nextLittleEndian() else { return nil }
        self.valueOffset = valueOffset
        guard let valueInodeNumber: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.valueInodeNumber = valueInodeNumber
        guard let valueLength: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.valueLength = valueLength
        guard let hash: UInt32 = iterator.nextLittleEndian() else { return nil }
        self.hash = hash
        guard let storedName = iterator.nextString(ofMaximumLength: Int(nameLen)) else { return nil }
        self.storedName = storedName
    }
    
    var nameLength: UInt8
    
    enum NamePrefix: UInt8 {
        case none = 0
        case user = 1
        case posixAclAccess = 2
        case posixAclDefault = 3
        case trusted = 4
        case security = 6
        case system = 7
        case richAcl = 8
        
        var prefix: String {
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
    var namePrefix: NamePrefix
    
    var valueOffset: UInt16
    var valueInodeNumber: UInt32
    var valueLength: UInt32
    
    var hash: UInt32
    var storedName: String
    
    var name: String {
        namePrefix.prefix + storedName
    }
}
