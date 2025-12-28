// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import AppKit
import DiskArbitration
import Combine
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "WatcherModeDelegate")

/// An object that watches a disk and keeps the process alive until it is unmounted.
///
/// For more information about why this is here, see ``ExtendFSApp``.
class DiskWatcher {
    let session: DASession
    let disk: DADisk
    let initialBSDName: String
    var initializeSink: AnyCancellable?
    var initializeGuard: Task<(), any Error>?
    var sink: AnyCancellable?
    
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
        self.disk = disk
        
        let initializeSink = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification).sink { notification in
            if self.startWatchingIfMounted() {
                self.initializeGuard?.cancel()
                self.initializeGuard = nil
                self.initializeSink = nil
            }
        }
        if !self.startWatchingIfMounted() {
            self.initializeGuard = Task {
                try await Task.sleep(for: .seconds(30))
                logger.error("Requested to watch block device but it has not been mounted for 30 seconds. Exiting.")
                exit(0)
            }
            self.initializeSink = initializeSink
        }
    }
    
    deinit {
        DASessionSetDispatchQueue(session, nil)
    }
    
    private func startWatchingIfMounted() -> Bool {
        let cfDesc = DADiskCopyDescription(disk) as! [String: Any]
        guard let diskMountPath = cfDesc[String(kDADiskDescriptionVolumePathKey)] as? URL else {
            return false
        }
        
        self.sink = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification).sink { notification in
            guard let mountPath = notification.userInfo?["NSDevicePath"] as? String else { return }
            if URL(filePath: mountPath).pathComponents == diskMountPath.pathComponents {
                logger.log("Received disk unmount notification, exiting")
                Task { @MainActor in
                    exit(0)
                }
            }
        }
        return true
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
