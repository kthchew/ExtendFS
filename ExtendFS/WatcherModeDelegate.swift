// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import AppKit
import DiskArbitration
import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "WatcherModeDelegate")

/// A delegate that creates a pseudo-headless mode for the app to run in when it is in disk monitoring mode.
///
/// See the documentation for ``ExtendFSApp`` for the reasoning behind this behavior.
///
/// In disk monitoring mode, it is possible for an activation of the app to occur (for example, the user double clicks the app in the Finder and expects the window to open). Thus, this delegate implements behavior that detects this situation and tries to open the appropriate GUI as needed.
class WatcherModeDelegate: NSObject, NSApplicationDelegate {
    var hasFirstActivated = false
    var wasStartedForGUI = false
    var diskWatcher: DiskWatcher?
    
    func getGUIApp() -> NSRunningApplication? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        for app in runningApps {
            if app.activationPolicy != .prohibited {
                return app
            }
        }
        
        return nil
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !wasStartedForGUI else { return }
        
        if hasFirstActivated {
            // user opened app manually but background listener was activated, open a new GUI app
            logger.log("Received activation request in background mode")
            NSApp.deactivate()
            NSApp.hide(nil)
            NSApplication.shared.setActivationPolicy(.prohibited)
            if let app = getGUIApp() {
                logger.log("GUI app found, activating it")
                app.activate()
            } else {
                logger.log("No GUI app found, launching one")
                let appURL = Bundle.main.bundleURL
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                config.activates = true
                Task {
                    let app = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                    app?.activate()
                }
                
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        guard !wasStartedForGUI else { return }
        // something told the app to quit, try to cleanly unmount because this is probably an update
        logger.log("Received request to terminate, trying to unmounting disk")
        diskWatcher?.unmount()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if !wasStartedForGUI {
            return false
        }
        return true
    }
}
