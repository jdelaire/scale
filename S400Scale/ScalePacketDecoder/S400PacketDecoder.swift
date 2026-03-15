import Foundation

enum S400PacketDecoderError: Error, LocalizedError {
    case missingBindKey
    case invalidBindKey
    case unsupportedServiceData
    case unsupportedDevice(UInt16)
    case missingMACAddress
    case invalidPayload
    case noMeasurementObject
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .missingBindKey:
            "Enter the 16-byte bind key before scanning."
        case .invalidBindKey:
            "The bind key must be exactly 32 hexadecimal characters."
        case .unsupportedServiceData:
            "Advertisement is not a Xiaomi S400 MiBeacon payload."
        case let .unsupportedDevice(deviceID):
            "Unsupported Xiaomi device ID: \(String(format: "0x%04X", deviceID))."
        case .missingMACAddress:
            "This packet omitted the MAC. Add the scale MAC address to settings."
        case .invalidPayload:
            "The MiBeacon payload could not be parsed."
        case .noMeasurementObject:
            "No S400 measurement object was present in the decrypted payload."
        case .decryptionFailed:
            "Failed to decrypt the MiBeacon payload."
        }
    }
}

struct S400PacketDecoder {
    static let miBeaconServiceUUID = "FE95"
    static let measurementObjectType: UInt16 = 0x6E16
    static let supportedDeviceIDs: Set<UInt16> = [0x30D9, 0x3BD5, 0x48CF]

    let bindKey: Data
    let configuredMACAddress: BluetoothAddress?

    init(bindKeyHex: String, configuredMACAddress: String) throws {
        guard !bindKeyHex.isEmpty else {
            throw S400PacketDecoderError.missingBindKey
        }
        guard let bindKey = Data.fromHex(bindKeyHex), bindKey.count == 16 else {
            throw S400PacketDecoderError.invalidBindKey
        }
        self.bindKey = bindKey
        self.configuredMACAddress = BluetoothAddress(string: configuredMACAddress)
    }

    func decode(
        serviceData: Data,
        observedAt: Date,
        manufacturerData: Data?,
        rssi: Int
    ) throws -> S400AdvertisementPacket {
        let reader = BinaryReader(data: serviceData)
        guard serviceData.count >= 5 else {
            throw S400PacketDecoderError.unsupportedServiceData
        }

        let frameControl = reader.uint16LE(at: 0)
        let deviceModelID = reader.uint16LE(at: 2)
        guard Self.supportedDeviceIDs.contains(deviceModelID) else {
            throw S400PacketDecoderError.unsupportedDevice(deviceModelID)
        }

        let packetCounter = serviceData[4]
        var payloadStart = 5

        let objectIncluded = ((frameControl >> 6) & 0x01) != 0
        let capabilityIncluded = ((frameControl >> 5) & 0x01) != 0
        let macIncluded = ((frameControl >> 4) & 0x01) != 0
        let encrypted = ((frameControl >> 3) & 0x01) != 0
        let version = Int(frameControl >> 12)

        guard objectIncluded, encrypted, version >= 4 else {
            throw S400PacketDecoderError.unsupportedServiceData
        }

        var macInPacketOrder: [UInt8]?
        var canonicalMACAddress: BluetoothAddress?

        if macIncluded {
            guard serviceData.count >= payloadStart + 6 else {
                throw S400PacketDecoderError.invalidPayload
            }
            let reversedBytes = Array(serviceData[payloadStart..<(payloadStart + 6)])
            macInPacketOrder = reversedBytes
            canonicalMACAddress = BluetoothAddress(bytes: reversedBytes.reversed())
            payloadStart += 6
        } else if let configuredMACAddress {
            canonicalMACAddress = configuredMACAddress
            macInPacketOrder = configuredMACAddress.reversedBytes
        } else {
            throw S400PacketDecoderError.missingMACAddress
        }

        if capabilityIncluded {
            guard serviceData.count > payloadStart else {
                throw S400PacketDecoderError.invalidPayload
            }
            let capability = serviceData[payloadStart]
            payloadStart += 1
            if (capability & 0x20) != 0 {
                guard serviceData.count > payloadStart else {
                    throw S400PacketDecoderError.invalidPayload
                }
                payloadStart += 1
            }
        }

        guard serviceData.count >= payloadStart + 7 else {
            throw S400PacketDecoderError.invalidPayload
        }

        let nonceTail = Data(serviceData[(serviceData.count - 7)..<(serviceData.count - 4)])
        let mic = Data(serviceData[(serviceData.count - 4)..<serviceData.count])
        let encryptedPayload = Data(serviceData[payloadStart..<(serviceData.count - 7)])

        let nonce = Data(macInPacketOrder ?? [])
            + Data(serviceData[2...4])
            + nonceTail

        let crypto = try MiBeaconCrypto(key: bindKey)
        let decryptedPayload: Data
        do {
            decryptedPayload = try crypto.decryptCCM(
                nonce: nonce,
                ciphertext: encryptedPayload,
                tag: mic,
                associatedData: Data([0x11]),
                messageLength: encryptedPayload.count
            )
        } catch {
            throw S400PacketDecoderError.decryptionFailed
        }

        guard let measurement = parseMeasurementObject(from: decryptedPayload) else {
            throw S400PacketDecoderError.noMeasurementObject
        }

        return S400AdvertisementPacket(
            observedAt: observedAt,
            frameControl: frameControl,
            packetCounter: packetCounter,
            deviceModelID: deviceModelID,
            deviceID: canonicalMACAddress?.stringValue ?? "UNKNOWN",
            profileId: measurement.profileId,
            weightKg: measurement.weightKg,
            impedance: measurement.impedance,
            lowFrequencyImpedance: measurement.lowFrequencyImpedance,
            heartRate: measurement.heartRate,
            rawServiceData: serviceData,
            decryptedPayload: decryptedPayload,
            manufacturerData: manufacturerData,
            rssi: rssi
        )
    }

    private func parseMeasurementObject(from payload: Data) -> ParsedMeasurementObject? {
        let reader = BinaryReader(data: payload)
        var offset = 0

        while payload.count >= offset + 3 {
            let objectType = reader.uint16LE(at: offset)
            let objectLength = Int(payload[offset + 2])
            let objectStart = offset + 3
            let objectEnd = objectStart + objectLength

            guard payload.count >= objectEnd else {
                return nil
            }

            if objectType == Self.measurementObjectType {
                let objectBytes = payload.subdata(in: objectStart..<objectEnd)
                return parseS400Measurement(objectBytes)
            }

            offset = objectEnd
        }

        return nil
    }

    private func parseS400Measurement(_ objectBytes: Data) -> ParsedMeasurementObject? {
        guard objectBytes.count == 9 else {
            return nil
        }

        let reader = BinaryReader(data: objectBytes)
        let profileId = Int(objectBytes[0])
        let packedData = reader.uint32LE(at: 1)

        let massRaw = packedData & 0x7FF
        let heartRateRaw = (packedData >> 11) & 0x7F
        let impedanceRaw = packedData >> 18

        let weightKg = massRaw == 0 ? nil : Double(massRaw) / 10
        let heartRate = (heartRateRaw == 0 || heartRateRaw >= 127) ? nil : Int(heartRateRaw) + 50
        let impedance = massRaw == 0 || impedanceRaw == 0 ? nil : Double(impedanceRaw) / 10
        let lowFrequencyImpedance = massRaw == 0 && impedanceRaw != 0 ? Double(impedanceRaw) / 10 : nil

        return ParsedMeasurementObject(
            profileId: profileId,
            weightKg: weightKg,
            impedance: impedance,
            lowFrequencyImpedance: lowFrequencyImpedance,
            heartRate: heartRate
        )
    }
}

private struct ParsedMeasurementObject {
    let profileId: Int
    let weightKg: Double?
    let impedance: Double?
    let lowFrequencyImpedance: Double?
    let heartRate: Int?
}
