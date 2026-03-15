@preconcurrency import CoreBluetooth
import Foundation

final class S400ScannerService: NSObject {
    enum Event {
        case packet(S400AdvertisementPacket)
        case stateChanged(String)
        case failure(String)
        case scanningChanged(Bool)
    }

    private var centralManager: CBCentralManager?
    private var shouldScan = false
    private var bindKeyHex = ""
    private var scaleMACAddress = ""

    var onEvent: ((Event) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func configure(bindKeyHex: String, scaleMACAddress: String) {
        self.bindKeyHex = bindKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scaleMACAddress = scaleMACAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func startScanning() {
        shouldScan = true
        guard let centralManager else {
            return
        }
        if centralManager.state == .poweredOn {
            beginScan(with: centralManager)
        } else {
            onEvent?(.stateChanged("Bluetooth is \(centralManager.state.displayTitle.lowercased())."))
        }
    }

    func stopScanning() {
        setScanning(false)
        shouldScan = false
        centralManager?.stopScan()
        onEvent?(.stateChanged("Scanning stopped."))
    }

    private func stopScanningSilently() {
        setScanning(false)
        shouldScan = false
        centralManager?.stopScan()
    }

    private func beginScan(with centralManager: CBCentralManager) {
        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        setScanning(true)
        onEvent?(.stateChanged("Scanning for Xiaomi FE95 advertisements."))
    }

    private func setScanning(_ isScanning: Bool) {
        onEvent?(.scanningChanged(isScanning))
    }
}

extension S400ScannerService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if shouldScan, central.state == .poweredOn {
            beginScan(with: central)
        } else {
            if central.state != .poweredOn {
                setScanning(false)
            }
            onEvent?(.stateChanged("Bluetooth is \(central.state.displayTitle.lowercased())."))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let serviceDataMap = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] else {
            return
        }

        let serviceUUID = CBUUID(string: S400PacketDecoder.miBeaconServiceUUID)
        guard let serviceData = serviceDataMap[serviceUUID] else {
            return
        }

        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        let decoder: S400PacketDecoder
        do {
            decoder = try S400PacketDecoder(bindKeyHex: bindKeyHex, configuredMACAddress: scaleMACAddress)
        } catch let error as S400PacketDecoderError {
            onEvent?(.failure(error.localizedDescription))
            stopScanningSilently()
            return
        } catch {
            onEvent?(.failure("Decoder setup failed."))
            stopScanningSilently()
            return
        }

        do {
            let packet = try decoder.decode(
                serviceData: serviceData,
                observedAt: Date(),
                manufacturerData: manufacturerData,
                rssi: RSSI.intValue
            )
            onEvent?(.packet(packet))
        } catch S400PacketDecoderError.unsupportedDevice,
                S400PacketDecoderError.unsupportedServiceData {
            return
        } catch let error as S400PacketDecoderError {
            onEvent?(.failure(error.localizedDescription))
        } catch {
            onEvent?(.failure("Unexpected packet decoding error."))
        }
    }
}

private extension CBManagerState {
    var displayTitle: String {
        switch self {
        case .unknown:
            "Unknown"
        case .resetting:
            "Resetting"
        case .unsupported:
            "Unsupported"
        case .unauthorized:
            "Unauthorized"
        case .poweredOff:
            "Powered Off"
        case .poweredOn:
            "Powered On"
        @unknown default:
            "Unknown"
        }
    }
}
