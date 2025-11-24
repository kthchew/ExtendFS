// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

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
