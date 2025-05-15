//
//  ext4ExtensionFileSystem.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/15/25.
//

import Foundation
import FSKit

@objc
class ext4ExtensionFileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
    func probeResource(resource: FSResource) async throws -> FSProbeResult {
        <#code#>
    }

    func loadResource(resource: FSResource, options: FSTaskOptions) async throws -> FSVolume {
        <#code#>
    }

    func unloadResource(resource: FSResource, options: FSTaskOptions) async throws {
        <#code#>
    }
}
