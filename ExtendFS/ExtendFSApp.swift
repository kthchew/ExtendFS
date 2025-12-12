// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import SwiftUI
import os.log

/// Implements two modes for the main app to run in: a GUI enablement guide, and a pseudo-headless disk watcher.
///
/// ExtendFS (the main app) runs in two modes: a standard SwiftUI app that guides the user on how to enable the file system extension, and a background process that runs until a particular disk is unmounted. As of writing, the behavior is that if the app is deleted or updated by TestFlight or the App Store, all disks abruptly dismount (FB21287341, FB21287688). As a workaround, if the main app is open, high-level systems like this are supposed to avoid removing the app in this manner (https://developer.apple.com/forums/thread/809747?answerId=869012022#869012022). These two modes should not be conflated in the same running instance of the app.
///
/// The standard GUI mode is used when the user "normally" opens the app, such as via the Finder. The disk watcher mode is used when a URL of the form `extendfs-internal-diskwatch:/dev/diskXsY` is opened in a **new instance** of the app. This enables a sandboxed process, which cannot pass arguments via LaunchServices, to provide this information, and is used by the file system extension when a volume mounts, and is the reason that the SwiftUI lifecycle is still used in this mode rather than modifying the `main` entry point.
///
/// The exception to this is when disk watcher processes were previously told to quit, which usually indicates an App Store update where the user chose to quit the app. In this case, the process attempts to unmount the relevant disks. On the next "normal" open, which is likely initiated by the App Store, it attempts to remount these disks and then exit.
@main
struct ExtendFSApp: App {
    @NSApplicationDelegateAdaptor private var delegate: WatcherModeDelegate
    
    @State private var hasOpenedURL = false
    
    @Environment(\.dismissWindow) private var dismissWindow
    
    let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "QuitHandler")
    
    init() {
        // handle unmounted disks that were previously unmounted during a quit event, probably indicating an App Store update relaunch
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: URL.temporaryDirectory, includingPropertiesForKeys: nil) {
            let bsdList = contents
                .filter({ $0.lastPathComponent.starts(with: "unmounted-") })
            guard bsdList.count > 0 else {
                return
            }
            guard let session = DASessionCreate(kCFAllocatorDefault) else {
                return
            }
            var couldCleanAllItems = true
            for name in bsdList {
                var bsd = name.lastPathComponent
                bsd.removeFirst("unmounted-".count)
                logger.log("\(bsd, privacy: .public) unmounted during a previous quit event, trying to remount it")
                
                if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsd) {
                    let options = DADiskMountOptions(kDADiskMountOptionDefault)
                    DADiskMount(disk, nil, options, nil, nil)
                } else {
                    logger.error("Couldn't create disk from BSD name \(bsd, privacy: .public)")
                }
                
                do {
                    try FileManager.default.removeItem(at: name)
                } catch {
                    logger.error("Couldn't clean up unmount marker \(name.lastPathComponent, privacy: .public)")
                    couldCleanAllItems = false
                }
            }
            
            if couldCleanAllItems {
                NSApp.terminate(nil)
            }
        }
    }
    
    var body: some Scene {
        Window("ExtendFS", id: "main") {
            ContentView()
                .onOpenURL { url in
                    guard !delegate.wasStartedForGUI, url.scheme == "extendfs-internal-diskwatch" else { return }
                    
                    dismissWindow(id: "main")
                    let devNode = url.path(percentEncoded: false)
                    NSApp.hide(nil)
                    NSApplication.shared.setActivationPolicy(.prohibited)
                    guard let watcher = DiskWatcher(blockDevice: devNode) else {
                        logger.error("Couldn't make watcher for \(devNode, privacy: .public)")
                        NSApp.terminate(nil)
                        return
                    }
                    self.delegate.diskWatcher = watcher
                    self.delegate.hasFirstActivated = true
                    hasOpenedURL = true
                }
                .task {
                    guard !delegate.wasStartedForGUI else { return }
                    guard !hasOpenedURL else {
                        dismissWindow(id: "main")
                        return
                    }
                    do {
                        try Task.checkCancellation()
                        delegate.wasStartedForGUI = true
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate()
                    } catch {}
                }
        }
        .defaultLaunchBehavior(hasOpenedURL ? .suppressed : .automatic)
        .commands {
            CommandGroup(replacing: .help) {
                Link("ExtendFS Support", destination: URL(string: "https://github.com/kthchew/ExtendFS/blob/main/SUPPORT.md")!)
                
                Section {
                    Link("Privacy Policy", destination: URL(string: "https://github.com/kthchew/ExtendFS/blob/main/PRIVACY.md")!)
                }
            }
        }
    }
}
