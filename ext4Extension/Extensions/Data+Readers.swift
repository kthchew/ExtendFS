//
//  Data+Readers.swift
//  ExtendFS
//
//  Created by Kenneth Chew on 10/28/25.
//

import Foundation

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
            
            return ""
        }
    }
}
