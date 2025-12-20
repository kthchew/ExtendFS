// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import SwiftUI
import FSKit
import ServiceManagement
import StoreKit

enum ExtensionActivationState {
    case inactive
    case active
    case notDetermined
}

struct ContentView: View {
    nonisolated static let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "default")
    
    @AppStorage("lastAskedForRating") private var lastAskedForRating: Date = Date.distantPast
    @Environment(\.requestReview) private var requestReview
    @Environment(\.appearsActive) private var appearsActive
    
    let ext4ExtensionIdentifier = "com.kpchew.ExtendFS.ext4Extension"
    @State private var ext4ExtensionState: ExtensionActivationState = .notDetermined
    
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    
    let timer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            switch ext4ExtensionState {
            case .inactive:
                ScrollView {
                    Text("The file system extension needs to be enabled in System Settings.")
                        .padding()
                    Divider()
                    switch osVersion.majorVersion {
                    case 15:
                        SequoiaEnablementTutorialView()
                            .padding(.bottom)
                    default:
                        TahoeEnablementTutorialView()
                            .padding(.bottom)
                    }
                }
            case .active:
                ExtensionReadyView()
            case .notDetermined:
                ScrollView {
                    if osVersion.majorVersion < 26 {
                        Text("""
                            The file system extension needs to be enabled in System Settings.
                            
                            _This app cannot automatically detect if the extension has been properly enabled on versions of macOS before macOS Tahoe 26.0. However, it will still function if enabled._
                            """)
                            .padding()
                    } else {
                        Text("An error occurred while determining whether the extension is enabled.")
                            .padding()
                    }
                    Divider()
                    switch osVersion.majorVersion {
                    case 15:
                        SequoiaEnablementTutorialView()
                            .padding(.bottom)
                    default:
                        TahoeEnablementTutorialView()
                            .padding(.bottom)
                    }
                }
            }
        }
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
        
        if !isSignedForDirectDistribution() {
            let timeSinceLastAskedForRating = lastAskedForRating.timeIntervalSinceNow.magnitude
            let secondsPerMonth = Double(60 * 60 * 24 * 7 * 30)
            if appearsActive && timeSinceLastAskedForRating > secondsPerMonth {
                lastAskedForRating = Date.now
                requestReview()
            }
        }
    }
    
    func isSignedForDirectDistribution() -> Bool {
        var code: SecCode? = nil
        SecCodeCopySelf(SecCSFlags(), &code)
        guard let code else { return true }
        var staticCode: SecStaticCode? = nil
        SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard let staticCode else { return true }
        var dict: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &dict)
        guard let info = dict as? [CFString: Any], let certificates = info[kSecCodeInfoCertificates] as? [SecCertificate] else {
            return true
        }
        return certificates.contains { cert in
            var commonName: CFString? = nil
            SecCertificateCopyCommonName(cert, &commonName)
            guard let commonName = commonName as? String else { return false }
            return commonName.contains("Developer ID Application")
        }
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
