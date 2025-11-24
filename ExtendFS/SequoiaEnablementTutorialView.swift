// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import SwiftUI
import ServiceManagement

struct SequoiaEnablementTutorialView: View {
    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("1")
                    .padding()
                    .overlay(
                        Circle()
                            .stroke()
                    )
                    .accessibilityAddTraits([.isHeader])
                
                Text("Open Login Items & Extensions in System Settings.")
                
                Button("Open System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .padding(.horizontal)
                .focusable(false)
            }
            Divider()
            GridRow {
                Text("2")
                    .padding()
                    .overlay(
                        Circle()
                            .stroke()
                    )
                    .accessibilityAddTraits([.isHeader])
                
                Text("Select \(Image(systemName: "info.circle")) next to File System Extensions.")
                    .accessibilityLabel("Select the Show Detail button next to File System Extensions.")
                
                Image(decorative: "sequoia_loginextension")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 300)
            }
            Divider()
            GridRow {
                Text("3")
                    .padding()
                    .overlay(
                        Circle()
                            .stroke()
                    )
                    .accessibilityAddTraits([.isHeader])
                
                Text("Enable ExtendFS's extensions.")
                
                Image(decorative: "sequoia_fskit_ext")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 300)
            }
        }
        .padding()
    }
}

#Preview {
    SequoiaEnablementTutorialView()
}
