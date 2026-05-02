// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit
import Synchronization
import os.log

fileprivate let capacity = 150_000
fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "DirectoryCache")

public final class DirectoryCache: Sendable {
    struct CacheState {
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
    let state = Mutex<CacheState>(CacheState())
    
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
    
    public func insert(_ entry: DirectoryEntry, forKey key: DirectoryCacheKey) -> DirectoryEntry {
        state.withLock { state in
            if let existingEntry = state.map[key] {
                markAsUsed(existingEntry, state: &state)
                return existingEntry
            } else {
                state.map[key] = entry
                markAsUsed(entry, state: &state)
                
                if state.map.count >= capacity {
                    let evicted = evictLeastRecentlyUsed(state: &state)
                    if !evicted {
                        logger.warning("Reached capacity of dcache but could not evict any entries")
                    }
                }
                return entry
            }
        }
    }
    
    public func insertEmptyEntry(forKey key: DirectoryCacheKey) -> Bool {
        state.withLock { state in
            guard state.map[key] == nil else { return false }
            
            let empty = DirectoryEntry.createEmptyEntry(with: String(data: key.pathComponent, encoding: .utf8) ?? "")
            state.map[key] = empty
            markAsUsed(empty, state: &state)
            
            if state.map.count >= capacity {
                let evicted = evictLeastRecentlyUsed(state: &state)
                if !evicted {
                    logger.warning("Reached capacity of dcache but could not evict any entries")
                }
            }
            return true
        }
    }
    
    public func insert(completeEntryList: ContiguousArray<DirectoryEntry>, forParentDirectoryInode parentInode: UInt32, caseInsensitive: Bool) -> ContiguousArray<DirectoryEntry> {
        state.withLock { state in
            var insertedEntries = ContiguousArray<DirectoryEntry>()
            insertedEntries.reserveCapacity(completeEntryList.count)
            for requestedEntry in completeEntryList {
                let key = DirectoryCacheKey(parentInode: parentInode, pathComponent: (caseInsensitive ? requestedEntry.name.lowercased() : requestedEntry.name).data(using: .utf8)!)
                if let existingEntry = state.map[key] {
                    markAsUsed(existingEntry, state: &state)
                    insertedEntries.append(existingEntry)
                } else {
                    state.map[key] = requestedEntry
                    markAsUsed(requestedEntry, state: &state)
                    insertedEntries.append(requestedEntry)
                }
            }
            // FIXME: what if something was removed while adding
            state.completeDirectoryMapping[parentInode] = (insertedEntries, UInt64.random(in: UInt64.min...UInt64.max))
            return insertedEntries
        }
    }
        
    
    public func lookup(forKey key: DirectoryCacheKey) -> (DirectoryEntry?, Bool) {
        state.withLock { state in
            guard let entry = state.map[key] else { return (nil, state.completeDirectoryMapping[key.parentInode] != nil) }
            markAsUsed(entry, state: &state)
            return (entry, false)
        }
    }
    
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

public struct DirectoryCacheKey: Hashable {
    public var parentInode: UInt32
    public var pathComponent: Data
}
