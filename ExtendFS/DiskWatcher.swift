// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import AppKit
import DiskArbitration
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "WatcherModeDelegate")

/// An object that watches a disk and keeps the process alive until it is unmounted.
///
/// For more information about why this is here, see ``ExtendFSApp``.
class DiskWatcher {
    let session: DASession
    let initialBSDName: String
    let queue: dispatch_queue_t
    
    init?(blockDevice: String) {
        self.initialBSDName = blockDevice
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return nil
        }
        self.session = session
        
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, blockDevice) else {
            logger.log("Couldn't create disk from BSD name \(blockDevice)")
            return nil
        }
        let cfDesc = DADiskCopyDescription(disk) as! [String: Any]
        let uuid = cfDesc[String(kDADiskDescriptionVolumeUUIDKey)]
        let bsd = cfDesc[String(kDADiskDescriptionMediaBSDNameKey)]
        let filter = [
            String(kDADiskDescriptionVolumeUUIDKey): uuid,
            String(kDADiskDescriptionMediaBSDNameKey): bsd
        ]
        
        DARegisterDiskUnmountApprovalCallback(session, filter as CFDictionary, { (recvDisk, context) in
            logger.log("Disk is trying to unmount, exiting")
            Task { @MainActor in
                exit(0)
            }
            return nil
        }, nil)
        DARegisterDiskDisappearedCallback(session, filter as CFDictionary, { (recvDisk, context) in
            logger.log("Disk disappeared, exiting")
            Task { @MainActor in
                exit(0)
            }
        }, nil)
        
        self.queue = dispatch_queue_t(label: "com.kpchew.ExtendFS.DiskWatcher")
        DASessionSetDispatchQueue(session, self.queue)
    }
    
    deinit {
        DASessionSetDispatchQueue(session, nil)
    }
    
    /// Unmount the disk this object is watching.
    /// - Parameter force: Whether the volume should be unmounted even if files are still active.
    func unmount(force: Bool = false) {
        let options = DADiskUnmountOptions(force ? kDADiskUnmountOptionForce : kDADiskUnmountOptionDefault)
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, initialBSDName) else {
            return
        }
        
        DADiskUnmount(disk, options, nil, nil)
        
        if let description = DADiskCopyDescription(disk) as? [CFString: Any], let bsd = description[kDADiskDescriptionMediaBSDNameKey] as? String {
            // mark as unmounted so it can be tried to be mounted again later
            logger.log("Creating marker for unmounted disk")
            let empty = Data()
            try? empty.write(to: URL.temporaryDirectory.appending(component: "unmounted-\(bsd)"))
        }
    }
}
