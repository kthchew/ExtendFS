// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import SwiftUI

@main
struct ExtendFSApp: App {
    var body: some Scene {
        Window("ExtendFS", id: "main") {
            ContentView()
        }
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
