// This file is part of ExtendFS which is released under the GNU GPL v3 or later license with an app store exception.
// See the LICENSE file in the root of the repository for full license details.

import Foundation

extension Data.Iterator {
    mutating func nextLittleEndian<T: FixedWidthInteger>() -> T? {
        let size = MemoryLayout<T>.size
        var value: T = 0
        for i in 0..<size {
            guard let nextVal = self.next() else { return nil }
            let next = T(nextVal) << (i*8)
            value |= next
        }
        return value
    }
    
    mutating func nextBigEndian<T: FixedWidthInteger>() -> T? {
        let size = MemoryLayout<T>.size
        var value: T = 0
        for i in 0..<size {
            guard let nextVal = self.next() else { return nil }
            let next = T(nextVal) << ((size-i-1)*8)
            value |= next
        }
        return value
    }
    
    mutating func nextLittleEndian<T: FixedWidthInteger>(as: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        var value: T = 0
        for i in 0..<size {
            guard let nextVal = self.next() else { return nil }
            let next = T(nextVal) << (i*8)
            value |= next
        }
        return value
    }
    
    mutating func nextBigEndian<T: FixedWidthInteger>(as: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        var value: T = 0
        for i in 0..<size {
            guard let nextVal = self.next() else { return nil }
            let next = T(nextVal) << ((size-i-1)*8)
            value |= next
        }
        return value
    }
    
    mutating func nextString<Encoding>(ofMaximumLength length: Int, as encoding: Encoding.Type = UTF8.self) -> String? where Encoding : _UnicodeEncoding, UInt8 == Encoding.CodeUnit {
        guard length > 0 else { return "" }
        var chars: [UInt8] = []
        chars.reserveCapacity(length)
        
        var reachedEnd = false
        for _ in 0..<length {
            guard let nextVal = self.next() else { return nil }
            
            if nextVal == 0 {
                reachedEnd = true
            }
            
            if !reachedEnd {
                chars.append(nextVal)
            }
        }
        return String(decoding: chars, as: encoding)
    }
    
    mutating func nextUUID() -> UUID? {
        var uuidArray: [UInt8] = []
        uuidArray.reserveCapacity(16)
        for _ in 0..<16 {
            guard let b: UInt8 = self.next() else { return nil }
            uuidArray.append(b)
        }
        return uuidArray.withUnsafeBytes { buf in
            let uuidStruct = buf.load(as: uuid_t.self)
            return UUID(uuid: uuidStruct)
        }
    }
}

extension Data {
    func readSmallSection<T>(at offset: off_t) -> T {
        let size = MemoryLayout<T>.size
        let alignment = MemoryLayout<T>.alignment
        return self.withUnsafeBytes { ptr in
            return withUnsafeTemporaryAllocation(byteCount: size, alignment: alignment) { itemPtr in
                itemPtr.copyMemory(from: UnsafeRawBufferPointer(rebasing: ptr[Int(offset)..<Int(Int(offset) + size)]))
                return itemPtr.load(as: T.self)
            }
        }
    }
    
    func readLittleEndian<T: FixedWidthInteger>(at offset: off_t) -> T {
        let number: T = self.readSmallSection(at: offset)
        return number.littleEndian
    }
    
    func readUUID(at offset: off_t) -> UUID {
        let uuid: uuid_t = self.readSmallSection(at: offset)
        return UUID(uuid: uuid)
    }
    
    func readString(at offset: off_t, maxLength: Int) -> String {
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
}
