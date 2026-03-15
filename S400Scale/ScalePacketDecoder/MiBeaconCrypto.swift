import CommonCrypto
import Foundation

enum MiBeaconCryptoError: Error {
    case invalidKeyLength
    case invalidNonceLength
    case authenticationFailed
    case cryptorFailure(Int)
}

struct MiBeaconCrypto {
    private let key: Data

    init(key: Data) throws {
        guard key.count == kCCKeySizeAES128 else {
            throw MiBeaconCryptoError.invalidKeyLength
        }
        self.key = key
    }

    func decryptCCM(
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        associatedData: Data,
        messageLength: Int
    ) throws -> Data {
        let q = 15 - nonce.count
        guard (7...13).contains(nonce.count), (2...8).contains(q) else {
            throw MiBeaconCryptoError.invalidNonceLength
        }

        let plaintext = try ctrCrypt(
            nonce: nonce,
            input: ciphertext,
            q: q,
            startingCounter: 1
        )

        let expectedTag = try authTag(
            nonce: nonce,
            plaintext: plaintext,
            associatedData: associatedData,
            q: q,
            tagLength: tag.count
        )

        guard expectedTag == tag else {
            throw MiBeaconCryptoError.authenticationFailed
        }

        guard plaintext.count == messageLength else {
            throw MiBeaconCryptoError.authenticationFailed
        }

        return plaintext
    }

    private func authTag(
        nonce: Data,
        plaintext: Data,
        associatedData: Data,
        q: Int,
        tagLength: Int
    ) throws -> Data {
        var flags = UInt8((q - 1) & 0x07)
        if !associatedData.isEmpty {
            flags |= 0x40
        }
        flags |= UInt8(((tagLength - 2) / 2) << 3)

        var b0 = Data([flags])
        b0.append(nonce)
        b0.append(encodedLength(plaintext.count, q: q))

        var macInput = Data()
        macInput.append(b0)
        macInput.append(encodedAssociatedData(associatedData))
        macInput.append(padded(plaintext))

        let y = try cbcMac(macInput)

        let s0 = try ctrBlock(nonce: nonce, q: q, counter: 0)
        return xor(Data(y.prefix(tagLength)), with: Data(s0.prefix(tagLength)))
    }

    private func encodedAssociatedData(_ data: Data) -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        var encoded = Data()
        if data.count < 0xFF00 {
            encoded.append(UInt8((data.count >> 8) & 0xFF))
            encoded.append(UInt8(data.count & 0xFF))
        } else {
            encoded.append(contentsOf: [0xFF, 0xFE])
            encoded.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).bigEndian, Array.init))
        }
        encoded.append(data)
        return padded(encoded)
    }

    private func encodedLength(_ value: Int, q: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: q)
        var remaining = value
        for index in stride(from: q - 1, through: 0, by: -1) {
            bytes[index] = UInt8(remaining & 0xFF)
            remaining >>= 8
        }
        return Data(bytes)
    }

    private func padded(_ data: Data) -> Data {
        let remainder = data.count % kCCBlockSizeAES128
        guard remainder != 0 else {
            return data
        }
        return data + Data(repeating: 0, count: kCCBlockSizeAES128 - remainder)
    }

    private func ctrCrypt(
        nonce: Data,
        input: Data,
        q: Int,
        startingCounter: Int
    ) throws -> Data {
        var output = Data(capacity: input.count)
        var counter = startingCounter
        var offset = 0

        while offset < input.count {
            let block = try ctrBlock(nonce: nonce, q: q, counter: counter)
            let blockLength = min(kCCBlockSizeAES128, input.count - offset)
            let chunk = xor(
                input.subdata(in: offset..<(offset + blockLength)),
                with: block.prefix(blockLength)
            )
            output.append(chunk)
            offset += blockLength
            counter += 1
        }

        return output
    }

    private func ctrBlock(nonce: Data, q: Int, counter: Int) throws -> Data {
        var block = Data([UInt8((q - 1) & 0x07)])
        block.append(nonce)
        block.append(encodedLength(counter, q: q))
        return try aesEncrypt(block)
    }

    private func cbcMac(_ data: Data) throws -> Data {
        var state = Data(repeating: 0, count: kCCBlockSizeAES128)

        var offset = 0
        while offset < data.count {
            let block = data.subdata(in: offset..<(offset + kCCBlockSizeAES128))
            state = try aesEncrypt(xor(state, with: block))
            offset += kCCBlockSizeAES128
        }

        return state
    }

    private func aesEncrypt(_ block: Data) throws -> Data {
        var outLength = 0
        var output = Data(repeating: 0, count: kCCBlockSizeAES128)
        let outputCapacity = output.count

        let status = output.withUnsafeMutableBytes { outputBytes in
            block.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        inputBytes.baseAddress,
                        block.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw MiBeaconCryptoError.cryptorFailure(Int(status))
        }

        output.count = outLength
        return output
    }

    private func xor<T: DataProtocol>(_ lhs: Data, with rhs: T) -> Data {
        Data(zip(lhs, rhs).map(^))
    }
}
