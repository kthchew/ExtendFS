//
//  ext4Extension.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/15/25.
//

import Foundation
import FSKit

@main
struct Ext4Extension: UnaryFileSystemExtension {
    let fileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations = Ext4ExtensionFileSystem()
}
