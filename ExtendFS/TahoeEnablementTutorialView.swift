// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import SwiftUI
import ServiceManagement

struct TahoeEnablementTutorialView: View {
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
                
                    Text(
                        """
                        Select the \(Image(systemName: "info.circle")) next to File System Extensions.
                        
                        _Note that in current versions of macOS, you may need to first look at extensions 'by category' in order to enable FSKit extensions. Enabling the toggle while sorted 'by app' might not work._
                        """
                    )
                
                Image(decorative: "tahoe_loginextension_category")
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
                
                Image(decorative: "tahoe_fskit_ext_category")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 300)
            }
        }
        .padding()
    }
}

#Preview {
    TahoeEnablementTutorialView()
}
