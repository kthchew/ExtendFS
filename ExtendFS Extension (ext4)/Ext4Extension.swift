// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

@main
struct Ext4Extension: UnaryFileSystemExtension {
    let fileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations = Ext4ExtensionFileSystem()
}
