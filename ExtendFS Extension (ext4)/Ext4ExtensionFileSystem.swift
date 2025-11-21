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
final class Ext4ExtensionFileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations {
    static let logger = Logger(subsystem: "com.kpchew.ExtendFS.ext4Extension", category: "Ext4Extension")
    
    @MainActor weak var resource: FSBlockDeviceResource?
    @MainActor weak var volume: Ext4Volume?
    
    @MainActor func setResources(resource: FSBlockDeviceResource?, volume: Ext4Volume?) {
        self.resource = resource
        self.volume = volume
    }
    
    @MainActor func setContainerStatus(_ status: FSContainerStatus) {
        self.containerStatus = status
    }
    
    func probeResource(resource: FSResource) async throws -> FSProbeResult {
        Self.logger.log("Probing resource")
        guard let resource = resource as? FSBlockDeviceResource else {
            Self.logger.log("Not block device")
            return .notRecognized
        }
        
        let superblock = try Superblock(blockDevice: resource, offset: 1024)
        if superblock.magic == 0xEF53 {
            let name = superblock.volumeName ?? ""
            let uuid = superblock.uuid ?? UUID()
            // seems like recognized and usableButLimited are treated like notRecognized as of macOS 15.6 (24G84)
//            guard superblock.featureIncompatibleFlags.isSubset(of: Superblock.IncompatibleFeatures.supportedFeatures) else {
//                Self.logger.log("Recognized but not usable")
//                return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
//            }
//            guard superblock.readonlyFeatureCompatibilityFlags.isSubset(of: Superblock.ReadOnlyCompatibleFeatures.supportedFeatures) else {
//                Self.logger.log("Usable but limited")
//                return .usableButLimited(name: name, containerID: FSContainerIdentifier(uuid: uuid))
//            }
            
            if superblock.state.contains(.errorsDetected) {
                Self.logger.log("Errors detected on volume.")
                let errorPolicy = try superblock.errors
                switch errorPolicy {
                case .continue:
                    Self.logger.log("Error policy set to continue, continuing as normal.")
                    break
                case .remountReadOnly:
                    Self.logger.log("Error policy set to remount as read-only, indicating usable but limited.")
                    return .usableButLimited(name: name, containerID: FSContainerIdentifier(uuid: uuid))
                case .panic:
                    Self.logger.log("Error policy set to panic, indicating recognized but not usable.")
                    return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
                case .unknown:
                    Self.logger.log("Error policy is not recognized.")
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
        Self.logger.log("Loading resource")
        let probeResult = try await probeResource(resource: resource)
        var readOnly: Bool
        switch probeResult.result {
        case .notRecognized:
            Self.logger.log("Invalid resource")
            throw ExtensionError.resourceUnsupported
        case .recognized:
            Self.logger.log("Recognized but can't mount")
            throw ExtensionError.resourceUnsupported
        case .usableButLimited:
            readOnly = true
        case .usable:
            readOnly = true // write not supported atm
        @unknown default:
            Self.logger.log("Unknown probe result")
            throw ExtensionError.resourceUnsupported
        }
        
        guard let resource = resource as? FSBlockDeviceResource else {
            Self.logger.log("Not a block resource")
            throw ExtensionError.resourceUnsupported
        }
        
        Self.logger.log("load options: \(options.taskOptions, privacy: .public)")
        for option in options.taskOptions {
            switch option {
            case "-f":
                continue
            case "--rdonly":
                Self.logger.log("Read only option provided")
                readOnly = true
            default:
                continue
            }
        }
        
        let volume = try await Ext4Volume(resource: resource, fileSystem: self, readOnly: readOnly)
        await setResources(resource: resource, volume: volume)
        await setContainerStatus(.ready)
        Self.logger.log("Container status ready")
        BlockDeviceReader.useMetadataRead = true
        return volume
    }

    func unloadResource(resource: FSResource, options: FSTaskOptions) async throws {
        Self.logger.log("Unloading resource")
        await setResources(resource: nil, volume: nil)
        await setContainerStatus(.notReady(status: ExtensionError.unloadedResource))
        return
    }
    
    func didFinishLoading() {
        Self.logger.log("did finish loading")
    }
}

extension Ext4ExtensionFileSystem: FSManageableResourceMaintenanceOperations {
    @MainActor private static func quickCheck(volume: Ext4Volume, task: FSTask) throws {
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
                Self.logger.error("Errors deteched on disk, and error policy is to panic.")
                throw POSIXError(.EDEVERR)
            case .unknown:
                Self.logger.error("Errors deteched on disk, and error policy is unknown.")
                throw POSIXError(.EDEVERR)
            }
        }
        
        // TODO: should probably calculate a checksum
    }
    
    func startCheck(task: FSTask, options: FSTaskOptions) throws -> Progress {
        let quick = options.taskOptions.contains("-q")
        let yes = options.taskOptions.contains("-y")
        
        if yes {
            task.logMessage("-y option provided, but ExtendFS is read-only. Ignoring option.")
        }
        if !quick {
            task.logMessage("Full check requested, but ExtendFS only supports simple quick checks. A quick check will be run.")
        }
        
        let progress = Progress(totalUnitCount: 100)
        Task {
            await setContainerStatus(.active)
            guard let volume = await volume else {
                task.didComplete(error: POSIXError(.ENOTSUP))
                await setContainerStatus(.notReady(status: POSIXError(.ENOTSUP)))
                return
            }
            
            defer {
                progress.completedUnitCount = 100
            }
            
            do {
                try await Self.quickCheck(volume: volume, task: task)
                task.didComplete(error: nil)
            } catch {
                task.didComplete(error: error)
            }
            
            await setContainerStatus(.ready)
        }
        return progress
    }
    
    func startFormat(task: FSTask, options: FSTaskOptions) throws -> Progress {
        throw POSIXError(.ENOSYS)
    }
}
