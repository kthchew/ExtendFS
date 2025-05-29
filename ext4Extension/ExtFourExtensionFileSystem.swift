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
}

@objc
class ExtFourExtensionFileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
    let logger = Logger(subsystem: "com.kpchew.ExtendFS", category: "Ext4Extension")
    
    func asyncProbeResource(resource: FSResource) async throws -> FSProbeResult {
        logger.log("Probing resource")
        guard let resource = resource as? FSBlockDeviceResource else {
            logger.log("Not block device")
            return .notRecognized
        }
        
        var superblock = Superblock(blockDevice: resource, offset: 1024)
        if let magic = superblock.magic, magic == 0xEF53, let uuid = superblock.uuid, let name = superblock.volumeName {
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
        guard probeResult != .notRecognized else {
            logger.log("Invalid resource")
            throw ExtensionError.resourceUnsupported
        }
        
        guard let resource = resource as? FSBlockDeviceResource else {
            logger.log("Not a block resource")
            throw ExtensionError.resourceUnsupported
        }
        
//        var forcedLoad = false
//        for option in options {
//            if option == "-f" {
//                forcedLoad = true
//            }
//        }
        
        let volume = Ext4Volume(resource: resource)
        containerStatus = .ready
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
        return
    }
    
    func didFinishLoading() {
        logger.log("did finish loading")
    }
}

extension ExtFourExtensionFileSystem: FSManageableResourceMaintenanceOperations {
    func startCheck(task: FSTask, options: FSTaskOptions) throws -> Progress {
        let progress = Progress(totalUnitCount: 100)
        Task {
            progress.becomeCurrent(withPendingUnitCount: 100)
            progress.resignCurrent()
            task.didComplete(error: nil)
        }
        return progress
    }
    
    func startFormat(task: FSTask, options: FSTaskOptions) throws -> Progress {
        throw ExtensionError.notImplemented
    }
}
