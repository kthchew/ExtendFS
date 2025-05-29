//
//  ContentView.swift
//  ExtendFS
//
//  Created by Kenneth Chew on 5/15/25.
//

import SwiftUI
import FSKit

struct ContentView: View {
    @State private var modules: [FSModuleIdentity] = []
    
    var body: some View {
        VStack {
            ForEach(modules) {
                Text($0.description)
                Text($0.bundleIdentifier)
            }
            Button("Reload") {
                FSClient.shared.fetchInstalledExtensions { modules, err in
                    if let modules {
                        self.modules = modules
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
