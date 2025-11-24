//
//  ExtendFSApp.swift
//  ExtendFS
//
//  Created by Kenneth Chew on 5/15/25.
//

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
