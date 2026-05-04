// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import Synchronization
import os.log

fileprivate let capacity = 150_000
fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "DirectoryCache")

/// A cache storing directory entries. 
public final class DirectoryCache: Sendable {
    private struct CacheState {
        var map: [DirectoryCacheKey: DirectoryEntry] = [:]
        /// A set of directory inodes for which we have a complete list of entries, allowing full scans for those directories to be skipped, since we know that if an entry isn't in the cache, it doesn't exist. It also contains a number that changes if the contents of the directory change.
        var completeDirectoryMapping: [UInt32: (ContiguousArray<DirectoryEntry>, UInt64)] = [:]
        
        var lruHead: DirectoryEntry?
        var lruTail: DirectoryEntry?
        
        init() {
            self.map.reserveCapacity(capacity)
        }
    }
    
    // based on tests, Mutex seems to be faster than making DirectoryCache an actor and putting all the state directly in the actor
    private let state = Mutex<CacheState>(CacheState())
    
    public init() {}
    
    private func markAsUsed(_ entry: DirectoryEntry, state: inout CacheState) {
        if state.lruHead === entry {
            return
        }
        
        // Remove from current position in LRU list
        entry.lruPrevious?.lruNext = entry.lruNext
        entry.lruNext?.lruPrevious = entry.lruPrevious
        
        if state.lruTail === entry {
            state.lruTail = entry.lruPrevious
        }
        
        // Insert at head of LRU list
        entry.lruNext = state.lruHead
        entry.lruPrevious = nil
        state.lruHead?.lruPrevious = entry
        state.lruHead = entry
        
        if state.lruTail == nil {
            state.lruTail = entry
        }
    }
    
    /// Inserts a single entry into the cache, evicting least recently used entries if necessary to stay within capacity.
    /// - Parameters:
    ///   - entry: The entry to insert.
    ///   - key: The key to use.
    /// - Returns: The inserted entry, or if the existing entry if an entry already exists for the given key. In the case that an existing entry is returned, no entry is inserted.
    public func insert(_ entry: DirectoryEntry, forKey key: DirectoryCacheKey) -> DirectoryEntry? {
        state.withLock { state in
            if let existingEntry = state.map[key] {
                markAsUsed(existingEntry, state: &state)
                return existingEntry
            } else {
                if state.map.count >= capacity {
                    let evicted = evictLeastRecentlyUsed(state: &state)
                    guard evicted else {
                        logger.warning("Reached capacity of dcache but could not evict any entries")
                        return nil
                    }
                }
                
                state.map[key] = entry
                markAsUsed(entry, state: &state)
                
                return entry
            }
        }
    }
    
    /// Inserts a negative lookup entry for a key, i.e. that the file does not exist.
    /// - Parameter key: The key to use.
    /// - Returns: Whether or not the entry was successfully inserted.
    public func insertEmptyEntry(forKey key: DirectoryCacheKey) -> Bool {
        state.withLock { state in
            guard state.map[key] == nil else { return false }
            
            if state.map.count >= capacity {
                let evicted = evictLeastRecentlyUsed(state: &state)
                guard evicted else {
                    logger.warning("Reached capacity of dcache but could not evict any entries")
                    return false
                }
            }
            
            let empty = DirectoryEntry.createEmptyEntry(with: String(data: key.pathComponent, encoding: .utf8) ?? "")
            state.map[key] = empty
            markAsUsed(empty, state: &state)
            return true
        }
    }
    
    /// Inserts a list of entries into the cache, representing the entire contents of a given directory.
    /// - Parameters:
    ///   - completeEntryList: The list of all entries for a given directory.
    ///   - parentInode: The inode number of the directory containing these entries.
    ///   - caseInsensitive: Whether names should be treated as case-insenstitive, i.e. whether this directory has the casefold feature enabled.
    /// - Returns: The inputted `completeEntryList`, but if an equivalent cached entry exists for any item in the list, that item is replaced with the cached version. The number is some arbitrary value indicating the version of this directory, and changes if the directory's contents change. If the full list couldn't be inserted into the cache, the number is `nil`.
    public func insert(completeEntryList: ContiguousArray<DirectoryEntry>, forParentDirectoryInode parentInode: UInt32, caseInsensitive: Bool) -> (ContiguousArray<DirectoryEntry>, UInt64?) {
        state.withLock { state in
            var insertedEntries = ContiguousArray<DirectoryEntry>()
            insertedEntries.reserveCapacity(completeEntryList.count)
            let canFitAllEntries = completeEntryList.count <= capacity
            var completed = true
            for requestedEntry in completeEntryList {
                let key = DirectoryCacheKey(parentInode: parentInode, pathComponent: (caseInsensitive ? requestedEntry.name.lowercased() : requestedEntry.name).data(using: .utf8)!)
                if let existingEntry = state.map[key] {
                    markAsUsed(existingEntry, state: &state)
                    insertedEntries.append(existingEntry)
                } else {
                    if state.map.count >= capacity {
                        let evicted = evictLeastRecentlyUsed(state: &state)
                        if !evicted {
                            logger.warning("Reached capacity of dcache but could not evict any entries")
                            completed = false
                        }
                    }
                    if completed {
                        state.map[key] = requestedEntry
                        markAsUsed(requestedEntry, state: &state)
                    }
                    insertedEntries.append(requestedEntry)
                }
            }
            
            if canFitAllEntries && completed {
                let verifier = UInt64.random(in: 1...UInt64.max)
                state.completeDirectoryMapping[parentInode] = (insertedEntries, verifier)
                return (insertedEntries, verifier)
            }
            return (insertedEntries, nil)
        }
    }
        
    
    /// Get the entry for a provided key, if it exists in the cache.
    /// - Parameter key: The key to lookup.
    /// - Returns: The entry if it exists, and a boolean indicating whether or not the lack of a returned entry means that the file definitively doesn't exist. The boolean has no meaning if the returned ``DirectoryEntry`` is not `nil`.
    public func lookup(forKey key: DirectoryCacheKey) -> (DirectoryEntry?, Bool) {
        state.withLock { state in
            guard let entry = state.map[key] else { return (nil, state.completeDirectoryMapping[key.parentInode] != nil) }
            markAsUsed(entry, state: &state)
            return (entry, false)
        }
    }
    
    /// Gets the full contents of a given directory if they all exist in the cache.
    /// - Parameter directoryInode: The inode number of the directory.
    /// - Returns: A list of entries in the directory and a version number that will be different if the contents of the directory change. Note that a change in the contents guarantees that the version number changes, but a change in the version number does not guarantee that the directory contents have changed. If the full contents of the directory are not cached (even if some contents are), `nil` is returned.
    public func fetchAllEntriesInDirectory(directoryInode: UInt32) -> (ContiguousArray<DirectoryEntry>, UInt64)? {
        return state.withLock { (state) -> (ContiguousArray<DirectoryEntry>, UInt64)? in // why does this need an explicit return type...
            guard let (entries, version) = state.completeDirectoryMapping[directoryInode] else { return nil }
            for entry in entries {
                markAsUsed(entry, state: &state)
            }
            return (entries, version)
        }
    }
    
    private func remove(_ entry: DirectoryEntry, state: inout CacheState) {
        if let parentInode = entry.parentInode {
            state.completeDirectoryMapping[parentInode] = nil
        }
        let keyToRemove = DirectoryCacheKey(parentInode: entry.parentInode ?? 0, pathComponent: Data(entry.name.utf8))
        state.map[keyToRemove] = nil
        
        entry.lruPrevious?.lruNext = entry.lruNext
        entry.lruNext?.lruPrevious = entry.lruPrevious
        
        if state.lruTail === entry {
            state.lruTail = entry.lruPrevious
        }
        if state.lruHead === entry {
            state.lruHead = entry.lruNext
        }
        
        entry.lruPrevious = nil
        entry.lruNext = nil
    }
    
    private func evictLeastRecentlyUsed(state: inout CacheState) -> Bool {
        guard let tail = state.lruTail else { return false }
        
        var toRemove = tail
        while toRemove.referenceCount > 0 {
            guard let previous = toRemove.lruPrevious else {
                // All entries in the cache are still in use, so we can't evict anything
                return false
            }
            toRemove = previous
        }
        remove(toRemove, state: &state)
        
        return true
    }
}

/// A key that can be used to lookup or save an entry in the directory cache.
public struct DirectoryCacheKey: Hashable {
    /// The inode number of the parent directory of the file that this key represents.
    public var parentInode: UInt32
    /// The name of the file in its directory, such as `some file.txt`, in binary form.
    public var pathComponent: Data
}
