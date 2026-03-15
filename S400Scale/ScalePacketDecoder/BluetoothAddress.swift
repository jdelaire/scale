import Foundation

struct BluetoothAddress: Hashable {
    let bytes: [UInt8]

    init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 6 else {
            return nil
        }

        var parsed = [UInt8]()
        parsed.reserveCapacity(6)
        for part in parts {
            guard part.count == 2, let value = UInt8(part, radix: 16) else {
                return nil
            }
            parsed.append(value)
        }
        bytes = parsed
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var reversedBytes: [UInt8] {
        bytes.reversed()
    }

    var stringValue: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
