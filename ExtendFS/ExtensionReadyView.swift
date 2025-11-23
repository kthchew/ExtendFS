//
//  ExtensionReadyView.swift
//  ExtendFS
//
//  Created by Kenneth Chew on 11/22/25.
//

import SwiftUI

struct ExtensionReadyView: View {
    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(.green)
                .padding()
            
            Text("The ExtendFS filesystem extension is enabled and ready to use. This app does not need to be running to mount disks.")
        }
        .padding()
        .frame(minWidth: 300, minHeight: 250)
    }
}

#Preview {
    ExtensionReadyView()
}
