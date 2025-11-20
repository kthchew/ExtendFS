//
//  ContentView.swift
//  ExtendFS
//
//  Created by Kenneth Chew on 5/15/25.
//

import SwiftUI
import FSKit
import ServiceManagement

enum ExtensionActivationState {
    case inactive
    case active
    case notDetermined
}

struct ContentView: View {
    nonisolated static let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "default")
    
    let ext4ExtensionIdentifier = "com.kpchew.ExtendFS.ext4Extension"
    @State private var ext4ExtensionState: ExtensionActivationState = .notDetermined
    
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    
    let timer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            switch ext4ExtensionState {
            case .inactive:
                Text("Extension needs to be enabled in System Settings")
                Button("Open System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            case .active:
                Text("Extension is active and ready")
            case .notDetermined:
                if osVersion.majorVersion < 26 {
                    Text("The app cannot tell if the extension is enabled on versions of macOS before macOS Tahoe 26.0. However, it will still function if enabled.")
                } else {
                    Text("An error occurred while determining whether the extension is enabled.")
                }
                Button("Open System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
        .padding()
        .onReceive(timer) { _ in
            Task {
                await updateExtensionEnablementState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification), perform: { output in
            Task {
                await updateExtensionEnablementState()
            }
        })
        .task {
            await updateExtensionEnablementState()
        }
    }
    
    func updateExtensionEnablementState() async {
        let states = await checkExtensionEnablementState()
        
        self.ext4ExtensionState = states[ext4ExtensionIdentifier] ?? .notDetermined
    }
    
    nonisolated func checkExtensionEnablementState() async -> [String: ExtensionActivationState] {
        var states = [
            ext4ExtensionIdentifier: ExtensionActivationState.notDetermined
        ]
        do {
            let extensions = try await FSClient.shared.installedExtensions
            
            let ext4Ext = extensions.first { $0.bundleIdentifier == ext4ExtensionIdentifier }
            if let ext4Ext {
                states[ext4ExtensionIdentifier] = ext4Ext.isEnabled ? .active : .inactive
            }
        } catch {
            Self.logger.error("Failed to fetch installed FSKit extensions: \(error)")
        }
        
        return states
    }
}

#Preview {
    ContentView()
}
