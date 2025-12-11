// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import FSKit

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
        
        guard let superblock = try Superblock(blockDevice: resource, offset: 1024) else {
            Self.logger.error("Could not read superblock from resource")
            return .notRecognized
        }
        if superblock.magic == 0xEF53 {
            let name = superblock.volumeName ?? ""
            let uuid = superblock.uuid ?? UUID()
            // seems like recognized and usableButLimited are treated like notRecognized as of macOS 15.6 (24G84)
//            guard superblock.incompatibleFeatures.isSubset(of: Superblock.IncompatibleFeatures.supportedFeatures) else {
//                Self.logger.log("Recognized but not usable")
//                return .recognized(name: name, containerID: FSContainerIdentifier(uuid: uuid))
//            }
//            guard superblock.readOnlyCompatibleFeatures.isSubset(of: Superblock.ReadOnlyCompatibleFeatures.supportedFeatures) else {
//                Self.logger.log("Usable but limited")
//                return .usableButLimited(name: name, containerID: FSContainerIdentifier(uuid: uuid))
//            }
            
            if superblock.state.contains(.errorsDetected) {
                Self.logger.log("Errors detected on volume.")
                let errorPolicy = superblock.errorPolicy
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
            await setContainerStatus(.blocked(status: FSError(.resourceUnrecognized)))
            throw FSError(.resourceUnrecognized)
        case .recognized:
            Self.logger.log("Recognized but can't mount")
            await setContainerStatus(.blocked(status: FSError(.resourceUnusable)))
            throw FSError(.resourceUnusable)
        case .usableButLimited:
            readOnly = true
        case .usable:
            readOnly = true // write not supported atm
        @unknown default:
            Self.logger.log("Unknown probe result")
            await setContainerStatus(.blocked(status: FSError(.resourceUnrecognized)))
            throw FSError(.resourceUnrecognized)
        }
        
        guard let resource = resource as? FSBlockDeviceResource else {
            Self.logger.log("Not a block resource")
            await setContainerStatus(.blocked(status: FSError(.resourceUnrecognized)))
            throw FSError(.resourceUnrecognized)
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
        await setContainerStatus(.notReady(status: POSIXError(.EAGAIN)))
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
            switch superblock.errorPolicy {
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
                await setContainerStatus(.notReady(status: FSError(.resourceDamaged)))
                task.didComplete(error: FSError(.resourceDamaged))
                return
            }
            
            defer {
                progress.completedUnitCount = 100
            }
            
            do {
                try await Self.quickCheck(volume: volume, task: task)
                await setContainerStatus(.ready)
                task.didComplete(error: nil)
            } catch {
                await setContainerStatus(.notReady(status: FSError(.resourceDamaged)))
                task.didComplete(error: error)
            }
        }
        return progress
    }
    
    func startFormat(task: FSTask, options: FSTaskOptions) throws -> Progress {
        throw POSIXError(.ENOSYS)
    }
}
