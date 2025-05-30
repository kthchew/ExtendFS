//
//  ext4Extension.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/15/25.
//

import Foundation
import FSKit

@main
struct ExtFourExtension : UnaryFileSystemExtension {
    var fileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
        Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "start").log("hello world")
        return ExtFourExtensionFileSystem()
    }
}
