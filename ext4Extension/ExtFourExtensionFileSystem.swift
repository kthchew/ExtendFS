//
//  ext4ExtensionFileSystem.swift
//  ext4Extension
//
//  Created by Kenneth Chew on 5/15/25.
//

import Foundation
import FSKit

enum ExtensionError: Error {
    case notImplemented
    case resourceUnsupported
    case unloadedResource
}

@objc
class ExtFourExtensionFileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
    let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Ext4Extension")
    
    func asyncProbeResource(resource: FSResource) async throws -> FSProbeResult {
        logger.log("Probing resource")
        guard let resource = resource as? FSBlockDeviceResource else {
            logger.log("Not block device")
            return .notRecognized
        }
        
        let superblock = try Superblock(blockDevice: resource, offset: 1024)
        if superblock.magic == 0xEF53 {
            let name = superblock.volumeName ?? ""
            let uuid = superblock.uuid ?? UUID()
            guard superblock.featureIncompatibleFlags.isSubset(of: Superblock.IncompatibleFeatures.supportedFeatures) else {
                return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
            }
            
            return .usable(name: name, containerID: FSContainerIdentifier(uuid: uuid))
        } else {
            return .notRecognized
        }
    }
    
    func probeResource(resource: FSResource, replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void) {
        logger.log("Probing resource (sync)")
        Task {
            do {
                let result = try await asyncProbeResource(resource: resource)
                replyHandler(result, nil)
            } catch {
                replyHandler(nil, error)
            }
        }
    }

    func asyncLoadResource(resource: FSResource, options: FSTaskOptions) async throws -> FSVolume {
        // FIXME: do I need to check probe result here?
        logger.log("Loading resource")
        let probeResult = try await asyncProbeResource(resource: resource)
        var readOnly: Bool
        switch probeResult.result {
        case .notRecognized:
            logger.log("Invalid resource")
            throw ExtensionError.resourceUnsupported
        case .recognized:
            logger.log("Recognized but can't mount")
            throw ExtensionError.resourceUnsupported
        case .usableButLimited:
            readOnly = true
        case .usable:
            readOnly = true // write not supported atm
        @unknown default:
            logger.log("Unknown probe result")
            throw ExtensionError.resourceUnsupported
        }
        guard probeResult != .notRecognized else {
            logger.log("Invalid resource")
            throw ExtensionError.resourceUnsupported
        }
        
        guard let resource = resource as? FSBlockDeviceResource else {
            logger.log("Not a block resource")
            throw ExtensionError.resourceUnsupported
        }
        
        for option in options.taskOptions {
            switch option {
            case "-f":
                continue
            case "--rdonly":
                readOnly = false
            default:
                continue
            }
        }
        
        let volume = try await Ext4Volume(resource: resource, fileSystem: self, readOnly: readOnly)
        containerStatus = .ready
        logger.log("Container status ready")
        return volume
    }
    
    func loadResource(resource: FSResource, options: FSTaskOptions, replyHandler: @escaping (FSVolume?, (any Error)?) -> Void) {
        logger.log("Loading resource (sync)")
        Task {
            do {
                let volume = try await asyncLoadResource(resource: resource, options: options)
                replyHandler(volume, nil)
            } catch {
                replyHandler(nil, error)
            }
        }
    }

    func unloadResource(resource: FSResource, options: FSTaskOptions) async throws {
        logger.log("Unloading resource")
        containerStatus = .notReady(status: ExtensionError.unloadedResource)
        return
    }
    
    func didFinishLoading() {
        logger.log("did finish loading")
    }
}

extension ExtFourExtensionFileSystem: FSManageableResourceMaintenanceOperations {
    func startCheck(task: FSTask, options: FSTaskOptions) throws -> Progress {
        let progress = Progress(totalUnitCount: 100)
        containerStatus = .active
        Task {
            progress.completedUnitCount = 100
            task.didComplete(error: nil)
            containerStatus = .ready
        }
        return progress
    }
    
    func startFormat(task: FSTask, options: FSTaskOptions) throws -> Progress {
        throw ExtensionError.notImplemented
    }
}
