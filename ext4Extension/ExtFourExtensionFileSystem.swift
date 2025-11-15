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
    
    var resource: FSBlockDeviceResource?
    var volume: Ext4Volume?
    
    func probeResource(resource: FSResource) async throws -> FSProbeResult {
        logger.log("Probing resource")
        guard let resource = resource as? FSBlockDeviceResource else {
            logger.log("Not block device")
            return .notRecognized
        }
        
        let superblock = try Superblock(blockDevice: resource, offset: 1024)
        if superblock.magic == 0xEF53 {
            let name = superblock.volumeName ?? ""
            let uuid = superblock.uuid ?? UUID()
            // seems like recognized and usableButLimited are treated like notRecognized as of macOS 15.6 (24G84)
//            guard superblock.featureIncompatibleFlags.isSubset(of: Superblock.IncompatibleFeatures.supportedFeatures) else {
//                logger.log("Recognized but not usable")
//                return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
//            }
//            guard superblock.readonlyFeatureCompatibilityFlags.isSubset(of: Superblock.ReadOnlyCompatibleFeatures.supportedFeatures) else {
//                logger.log("Usable but limited")
//                return .usableButLimited(name: name, containerID: FSContainerIdentifier(uuid: uuid))
//            }
            
            if superblock.state.contains(.errorsDetected) {
                logger.log("Errors detected on volume.")
                let errorPolicy = try superblock.errors
                switch errorPolicy {
                case .continue:
                    logger.log("Error policy set to continue, continuing as normal.")
                    break
                case .remountReadOnly:
                    logger.log("Error policy set to remount as read-only, indicating usable but limited.")
                    return .usableButLimited(name: name, containerID: FSContainerIdentifier(uuid: uuid))
                case .panic:
                    logger.log("Error policy set to panic, indicating recognized but not usable.")
                    return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
                case .unknown:
                    logger.log("Error policy is not recognized.")
                    return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
                }
            }
            
            return .usable(name: name, containerID: FSContainerIdentifier(uuid: uuid))
        } else {
            return .notRecognized
        }
    }

    func loadResource(resource: FSResource, options: FSTaskOptions) async throws -> FSVolume {
        // FIXME: do I need to check probe result here?
        logger.log("Loading resource")
        let probeResult = try await probeResource(resource: resource)
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
        
        guard let resource = resource as? FSBlockDeviceResource else {
            logger.log("Not a block resource")
            throw ExtensionError.resourceUnsupported
        }
        
        logger.log("options: \(options.taskOptions, privacy: .public)")
        for option in options.taskOptions {
            switch option {
            case "-f":
                continue
            case "--rdonly":
                logger.log("Read only option provided")
                readOnly = true
            default:
                continue
            }
        }
        
        let volume = try await Ext4Volume(resource: resource, fileSystem: self, readOnly: readOnly)
        self.resource = resource
        self.volume = volume
        containerStatus = .ready
        logger.log("Container status ready")
        BlockDeviceReader.useMetadataRead = true
        return volume
    }

    func unloadResource(resource: FSResource, options: FSTaskOptions) async throws {
        logger.log("Unloading resource")
        self.resource = nil
        self.volume = nil
        containerStatus = .notReady(status: ExtensionError.unloadedResource)
        return
    }
    
    func didFinishLoading() {
        logger.log("did finish loading")
    }
}

extension ExtFourExtensionFileSystem: FSManageableResourceMaintenanceOperations {
    private func quickCheck(volume: Ext4Volume, task: FSTask) throws {
        let superblock = volume.superblock
        guard superblock.magic == 0xEF53 else {
            task.logMessage("Magic value in superblock did not match expectation. Is this an ext volume?")
            throw POSIXError(.EDEVERR)
        }
        
        if superblock.state.contains(.errorsDetected) {
            switch try superblock.errors {
            case .continue:
                break
            case .remountReadOnly:
                break
            case .panic:
                throw POSIXError(.EDEVERR)
            case .unknown:
                throw POSIXError(.EDEVERR)
            }
        }
        
        // TODO: should probably calculate a checksum
    }
    
    func startCheck(task: FSTask, options: FSTaskOptions) throws -> Progress {
        guard let volume else { throw POSIXError(.ENOTSUP) }
        
        let quick = options.taskOptions.contains("-q")
        let yes = options.taskOptions.contains("-y")
        
        if yes {
            task.logMessage("-y option provided, but ExtendFS is read-only. Ignoring option.")
        }
        if !quick {
            task.logMessage("Full check requested, but ExtendFS only supports simple quick checks. A quick check will be run.")
        }
        
        let progress = Progress(totalUnitCount: 100)
        containerStatus = .active
        Task {
            defer {
                progress.completedUnitCount = 100
                containerStatus = .ready
            }
            
            do {
                try quickCheck(volume: volume, task: task)
                task.didComplete(error: nil)
            } catch {
                task.didComplete(error: error)
            }
        }
        return progress
    }
    
    func startFormat(task: FSTask, options: FSTaskOptions) throws -> Progress {
        throw POSIXError(.ENOSYS)
    }
}
