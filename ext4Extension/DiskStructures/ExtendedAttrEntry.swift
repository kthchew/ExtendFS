//
//  ExtendedAttrEntry.swift
//  ExtendFSExtension
//
//  Created by Kenneth Chew on 9/4/25.
//

import Foundation
import DataKit
import CommonCrypto

struct ExtendedAttrEntry: ReadWritable {
    static var format: Format {
        \.nameLength
        \.namePrefix.rawValue
        \.valueOffset
        \.valueInodeNumber
        \.valueLength
        \.hash
        Using(\.nameLength) { length in
            Custom(\.storedName) { read in
                // TODO: throwing?
                let cString = try! read.consume(Int(length)) + [0]
                guard let str = String(data: cString, encoding: .utf8) else {
                    return ""
                }
                return str
            } write: { write, value in
                var data = value.data(using: .utf8)!
                data.removeLast()
                write.append(data)
            }

        }
    }
    
    init(from context: ReadContext<ExtendedAttrEntry>) throws {
        nameLength = try context.read(for: \.nameLength)
        namePrefix = NamePrefix(rawValue: try context.read(for: \.namePrefix.rawValue)) ?? .none
        valueOffset = try context.read(for: \.valueOffset)
        valueInodeNumber = try context.read(for: \.valueInodeNumber)
        valueLength = try context.read(for: \.valueLength)
        hash = try context.read(for: \.hash)
        storedName = try context.read(for: \.storedName)
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
