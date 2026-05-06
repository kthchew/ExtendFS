// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "HashTreeDirectory")

/// An entry in a hash tree representing a hash to logical block mapping.
public struct HashTreeDirectoryEntry: Hashable {
    /// The first hash value which this entry covers. Whether this refers to a major or minor hash depends on the level and depth of the tree.
    public var hash: UInt32
    /// The logical block which this entry maps to.
    public var block: UInt32
    
    public init?(from data: Data) {
        var offset = 0
        guard let hash: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let block: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.hash = hash
        self.block = block
    }
}

/// A structure containing the optional checksum of an htree.
public struct HashTreeDirectoryTail: Hashable {
    var reservedZero: UInt32
    /// The checksum of the directory block.
    public var checksum: UInt32
    
    public init?(from data: Data) {
        var offset = 0
        guard let reservedZero: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let checksum: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.reservedZero = reservedZero
        self.checksum = checksum
    }
}

/// A structure containing information about a hash tree directory root block.
public struct HashTreeDirectoryRootInfo: Hashable {
    var reservedZero: UInt32
    /// The type of hash that should be used in this hash tree.
    public var hashVersion: Superblock.HashVersion
    /// The length of the info field. Should be 8.
    var infoLength: UInt8
    /// The depth of the hash tree.
    public var indirectLevels: UInt8
    /// Unused.
    var flags: UInt8
    
    public init?(from data: Data) {
        var offset = 0
        guard let reservedZero: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let hashVersionRaw: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let infoLength: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let indirectLevels: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let unusedFlags: UInt8 = try? data.readLittleEndian(at: &offset) else { return nil }
        self.reservedZero = reservedZero
        self.hashVersion = Superblock.HashVersion(rawValue: hashVersionRaw) ?? .unknown
        self.infoLength = infoLength
        self.indirectLevels = indirectLevels
        self.flags = unusedFlags
    }
}

/// The root of a hash tree representing a directory.
public struct HashTreeDirectoryRoot {
    /// The directory entry representing `.`, the current directory.
    var dotEntry: DirectoryEntry
    /// The directory entry representing `..`, the parent directory.
    var dotDotEntry: DirectoryEntry
    /// Information about the hash tree.
    public var info: HashTreeDirectoryRootInfo
    /// The maximum ``HashTreeDirectoryEntry`` count that can be stored in this node.
    public var limit: UInt16
    /// The logical block of the next leaf node covering hashes between the start of this node and the first entry in ``entries``.
    public var count: UInt16
    /// The logical block of the next leaf node covering hashes between the start of this node and the first entry in ``entries``.
    public var block: UInt32
    /// A list of hash to logical block mappings, sorted by hash.
    public var entries: ContiguousArray<HashTreeDirectoryEntry>
    /// The tail of this node, or `nil` if checksums are not calculated.
    public var tail: HashTreeDirectoryTail?
    
    public init?(from data: Data, parentInode: UInt32?, hasChecksumTail: Bool) {
        guard data.count > 0 else { return nil }
        guard let dotEntry = DirectoryEntry(from: data.readablePrefix(length: 12), withParentInode: parentInode) else { return nil }
        guard dotEntry.name == Data(".".utf8) else { return nil }
        guard let dotDotEntry = DirectoryEntry(from: data.readableSection(at: 12, length: 12), withParentInode: parentInode) else { return nil }
        guard dotDotEntry.name == Data("..".utf8) else { return nil }
        guard let info = HashTreeDirectoryRootInfo(from: data.readableSection(at: 24, length: 8)) else { return nil }
        guard info.reservedZero == 0, info.infoLength == 8 else {
            logger.error("Hash tree root info was not well formed")
            return nil
        }
        var offset = 32
        guard let limit: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let count: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let block: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard count >= 1, limit >= count else { return nil }
        self.dotEntry = dotEntry
        self.dotDotEntry = dotDotEntry
        self.info = info
        self.limit = limit
        self.count = count
        self.block = block
        
        let tailLength = hasChecksumTail ? 8 : 0
        let parseLimit = max(0, data.count - tailLength)
        let rawEntryCount = max(0, Int(count) - 1)
        let availableEntryCount = max(0, (parseLimit - offset) / 8)
        let entryCount = min(rawEntryCount, availableEntryCount)
        var entries = ContiguousArray<HashTreeDirectoryEntry>()
        entries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard let entry = HashTreeDirectoryEntry(from: data.readableSection(at: offset, length: 8)) else { return nil }
            entries.append(entry)
            offset += 8
        }
        self.entries = entries
        if hasChecksumTail, data.count >= 8 {
            self.tail = HashTreeDirectoryTail(from: data.readableSection(at: data.count - 8, length: 8))
        } else {
            self.tail = nil
        }
    }
}

/// A node in a hash tree, which contains ``HashTreeDirectoryEntry``s mapping hashes to logical blocks of the directory data.
public struct HashTreeDirectoryNode {
    /// A fake directory entry that holds no important data.
    var placeholderEntry: DirectoryEntry
    /// The maximum ``HashTreeDirectoryEntry`` count that can be stored in this node.
    public var limit: UInt16
    /// The actual number of ``HashTreeDirectoryEntry``s stored in this node.
    public var count: UInt16
    /// The logical block of the next leaf node covering hashes between the start of this node and the first entry in ``entries``.
    public var block: UInt32
    /// A list of hash to logical block mappings, sorted by hash.
    public var entries: ContiguousArray<HashTreeDirectoryEntry>
    /// The tail of this node, or `nil` if checksums are not calculated.
    public var tail: HashTreeDirectoryTail?
    
    public init?(from data: Data, hasChecksumTail: Bool) {
        guard data.count > 0 else { return nil }
        guard let placeholderEntry = DirectoryEntry(from: data.readablePrefix(length: 8), withParentInode: nil) else { return nil }
        guard placeholderEntry.inodePointee == 0, placeholderEntry.nameLength == 0 else { return nil }
        var offset = 8
        guard let limit: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let count: UInt16 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard let block: UInt32 = try? data.readLittleEndian(at: &offset) else { return nil }
        guard count >= 1, limit >= count else { return nil }
        self.placeholderEntry = placeholderEntry
        self.limit = limit
        self.count = count
        self.block = block
        
        let tailLength = hasChecksumTail ? 8 : 0
        let parseLimit = max(0, data.count - tailLength)
        let rawEntryCount = max(0, Int(count) - 1)
        let availableEntryCount = max(0, (parseLimit - offset) / 8)
        let entryCount = min(rawEntryCount, availableEntryCount)
        var entries = ContiguousArray<HashTreeDirectoryEntry>()
        entries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard let entry = HashTreeDirectoryEntry(from: data.readableSection(at: offset, length: 8)) else { return nil }
            entries.append(entry)
            offset += 8
        }
        self.entries = entries
        if hasChecksumTail, data.count >= 8 {
            self.tail = HashTreeDirectoryTail(from: data.readableSection(at: data.count - 8, length: 8))
        } else {
            self.tail = nil
        }
    }
}
