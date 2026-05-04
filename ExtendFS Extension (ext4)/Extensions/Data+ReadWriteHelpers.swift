// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation
import GoogleCRC32C

extension Data {
    func readSection(at offset: Self.Index, length: Int) throws -> Data {
        guard length >= 0, offset >= 0, offset + length <= count else {
            throw POSIXError(.EIO)
        }
        return self.subdata(in: offset..<(offset + length))
    }

    func readSection(at offset: inout Self.Index, length: Int) throws -> Data {
        let section = try readSection(at: offset, length: length)
        offset += length
        return section
    }

    func readSmallSection<T>(at offset: Self.Index) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= count else { throw POSIXError(.EIO) }
        return self.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }
    
    func readSmallSection<T>(at offset: inout Self.Index) throws -> T {
        let value: T = try readSmallSection(at: offset)
        offset += MemoryLayout<T>.size
        return value
    }
    
    func readLittleEndian<T: FixedWidthInteger>(at offset: Self.Index) throws -> T {
        let number: T = try self.readSmallSection(at: offset)
        return T(littleEndian: number)
    }

    func readLittleEndian<T: FixedWidthInteger>(at offset: inout Self.Index) throws -> T {
        let number: T = try readLittleEndian(at: offset)
        offset += MemoryLayout<T>.size
        return number
    }

    func readBigEndian<T: FixedWidthInteger>(at offset: Self.Index) throws -> T {
        let number: T = try self.readSmallSection(at: offset)
        return T(bigEndian: number)
    }

    func readBigEndian<T: FixedWidthInteger>(at offset: inout Self.Index) throws -> T {
        let number: T = try readBigEndian(at: offset)
        offset += MemoryLayout<T>.size
        return number
    }
    
    func readUUID(at offset: Self.Index) throws -> UUID {
        let uuid: uuid_t = try self.readSmallSection(at: offset)
        return UUID(uuid: uuid)
    }

    func readUUID(at offset: inout Self.Index) throws -> UUID {
        let uuid = try readUUID(at: offset)
        offset += MemoryLayout<uuid_t>.size
        return uuid
    }
    
    func readString(at offset: Self.Index, maxLength: Int) -> String {
        guard maxLength >= 0, offset >= 0, offset + maxLength <= count else { return "" }
        return self.withUnsafeBytes { ptr in
            guard let stringStart = ptr.baseAddress?.assumingMemoryBound(to: CChar.self).advanced(by: Int(offset)) else {
                return ""
            }
            
            var cString = [CChar]()
            for i in 0..<maxLength {
                let char = (stringStart + i).pointee
                cString.append(char)
                if char == 0 {
                    return String(cString: cString, encoding: .utf8) ?? ""
                }
            }
            cString.append(0)
            
            return String(cString: cString, encoding: .utf8) ?? ""
        }
    }

    func readString(at offset: inout Self.Index, maxLength: Int) throws -> String {
        guard maxLength >= 0, offset >= 0, offset + maxLength <= count else {
            throw POSIXError(.EIO)
        }
        let result = readString(at: offset, maxLength: maxLength)
        offset += maxLength
        return result
    }
    
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ number: T) {
        var little = number.littleEndian
        Swift.withUnsafeBytes(of: &little) { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            self.append(ptr, count: buf.count)
        }
    }
    
    mutating func append(uuid: UUID) {
        let u = uuid.uuid
        let array = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        self.append(contentsOf: array)
    }
    
    mutating func append(cStringFrom string: String, using encoding: String.Encoding = .utf8, length: Int, useNullTerminator: Bool = true) throws {
        guard let cString = string.cString(using: encoding) else {
            throw POSIXError(.EINVAL)
        }
        let actualLength = useNullTerminator ? cString.count : cString.count - 1
        guard actualLength <= length else {
            throw POSIXError(.EINVAL)
        }
        
        let bytes = cString.compactMap { int in
            (useNullTerminator || int != 0) ? UInt8(bitPattern: int) : nil
        }
        self.append(contentsOf: bytes)
        let padding = [UInt8](repeating: 0, count: length - bytes.count)
        self.append(contentsOf: padding)
    }
    
    public func readablePrefix(length: Int) -> Data {
        guard length <= count else { return Data() }
        return subdata(in: 0..<length)
    }
    
    public func readableSection(at offset: Int, length: Int) -> Data {
        guard offset >= 0, length >= 0, offset + length <= count else { return Data() }
        return subdata(in: offset..<(offset + length))
    }
    
    func crc32c(seed: UInt32? = nil) -> UInt32 {
        self.withUnsafeBytes { buf in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            if let seed {
                return crc32c_extend(seed, base, buf.count)
            } else {
                return crc32c_value(base, buf.count)
            }
        }
    }
}
