import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    static func fromHex(_ value: String) -> Data? {
        let sanitized = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard sanitized.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(sanitized.count / 2)

        var index = sanitized.startIndex
        while index < sanitized.endIndex {
            let next = sanitized.index(index, offsetBy: 2)
            guard let byte = UInt8(sanitized[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }

        return Data(bytes)
    }
}
