import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    var profile: UserProfile {
        didSet {
            settingsStore.saveProfile(profile)
        }
    }
    var isScanning = false
    var statusMessage = "Enter your bind key and scale MAC, then start scanning."
    var lastMeasurement: StoredMeasurement?
    var measurementHistory: [StoredMeasurement]
    var debugPackets: [DebugPacketRecord] = []
    var healthKitAuthorized = false

    private let scanner = S400ScannerService()
    private let measurementStore: MeasurementStore
    private let settingsStore: AppSettingsStore
    private let aggregator = S400MeasurementAggregator()
    private let healthKitExporter: HealthKitExporter
    private var lastPacketTimeByDevice: [String: Date] = [:]
    private let bleLogger = Logger(subsystem: "com.jdelaire.S400Scale", category: "BLE")

    init(
        measurementStore: MeasurementStore = MeasurementStore(),
        settingsStore: AppSettingsStore = AppSettingsStore(),
        healthKitExporter: HealthKitExporter = HealthKitExporter()
    ) {
        self.measurementStore = measurementStore
        self.settingsStore = settingsStore
        self.healthKitExporter = healthKitExporter
        self.profile = settingsStore.loadProfile()
        self.measurementHistory = measurementStore.fetchMeasurements()
        self.lastMeasurement = measurementHistory.first
        scanner.onEvent = { [weak self] event in
            self?.handle(event)
        }
        Task {
            await refreshHealthKitAuthorizationState()
        }
        startScanningOnLaunchIfPossible()
    }

    func startScanning() {
        do {
            _ = try S400PacketDecoder(
                bindKeyHex: profile.bindKeyHex,
                configuredMACAddress: profile.scaleMACAddress
            )
        } catch let error as S400PacketDecoderError {
            isScanning = false
            statusMessage = error.localizedDescription
            return
        } catch {
            isScanning = false
            statusMessage = "Scanner configuration is invalid."
            return
        }

        scanner.configure(bindKeyHex: profile.bindKeyHex, scaleMACAddress: profile.scaleMACAddress)
        scanner.startScanning()
    }

    func stopScanning() {
        scanner.stopScanning()
    }

    func authorizeHealthKit() {
        Task {
            await refreshHealthKitAuthorizationState(promptIfNeeded: true)
        }
    }

    func syncHealthKit() {
        Task {
            await syncHealthKitNow()
        }
    }

    func clearHistory() {
        do {
            try measurementStore.deleteAll()
            measurementHistory = []
            lastMeasurement = nil
        } catch {
            statusMessage = "Failed to clear history: \(error.localizedDescription)"
        }
    }

    func bodyComposition(for measurement: StoredMeasurement) -> BodyCompositionEstimate? {
        BodyCompositionCalculator.estimate(
            weightKg: measurement.weightKg,
            impedanceOhms: measurement.impedance,
            profile: profile
        )
    }

    private func handle(_ event: S400ScannerService.Event) {
        switch event {
        case let .stateChanged(message):
            statusMessage = message
            bleLogger.notice("\(message, privacy: .public)")
        case let .failure(message):
            statusMessage = message
            bleLogger.error("\(message, privacy: .public)")
        case let .scanningChanged(scanning):
            isScanning = scanning
        case let .packet(packet):
            handle(packet)
        }
    }

    private func handle(_ packet: S400AdvertisementPacket) {
        let frequency = packetFrequency(for: packet)
        debugPackets.insert(
            DebugPacketRecord(
                observedAt: packet.observedAt,
                deviceId: packet.deviceID,
                deviceModelID: String(format: "0x%04X", packet.deviceModelID),
                packetCounter: Int(packet.packetCounter),
                frameControl: String(format: "0x%04X", packet.frameControl),
                frequencyHz: frequency,
                weightKg: packet.weightKg,
                impedance: packet.impedance,
                lowFrequencyImpedance: packet.lowFrequencyImpedance,
                heartRate: packet.heartRate,
                profileId: packet.profileId,
                rawServiceDataHex: packet.rawServiceData.hexString,
                decryptedPayloadHex: packet.decryptedPayload.hexString,
                manufacturerDataHex: packet.manufacturerData?.hexString
            ),
            at: 0
        )
        debugPackets = Array(debugPackets.prefix(40))

        let bodyComposition: BodyCompositionEstimate? = {
            guard let weightKg = packet.weightKg else {
                return nil
            }
            guard let sourceImpedance = packet.impedance ?? packet.lowFrequencyImpedance else {
                return nil
            }
            return BodyCompositionCalculator.estimate(
                weightKg: weightKg,
                impedanceOhms: sourceImpedance,
                profile: profile
            )
        }()

        bleLogger.notice("\(self.packetDebugLog(for: packet), privacy: .public)")

        statusMessage = "Decoded packet \(packet.packetCounter) from \(packet.deviceID)."

        guard let finalized = aggregator.ingest(packet, bodyComposition: bodyComposition) else {
            if let state = aggregator.debugState(for: packet.deviceID) {
                bleLogger.notice("\(self.aggregationDebugLog(for: packet.deviceID, state: state), privacy: .public)")
            } else {
                bleLogger.notice("Aggregator cleared session for \(packet.deviceID, privacy: .public) without finalizing. Duplicate suppression or session reset is likely.")
            }
            return
        }

        bleLogger.notice("\(self.finalizedMeasurementLog(for: finalized), privacy: .public)")

        do {
            let stored = try measurementStore.save(finalized)
            measurementHistory.insert(stored, at: 0)
            lastMeasurement = stored
            statusMessage = "Finalized \(String(format: "%.1f", stored.weightKg)) kg measurement from \(stored.deviceId)."
        } catch {
            statusMessage = "Failed to save measurement: \(error.localizedDescription)"
        }

        guard healthKitAuthorized else {
            return
        }

        Task {
            do {
                try await healthKitExporter.export(measurement: finalized, profile: profile)
            } catch {
                statusMessage = "HealthKit export failed: \(error.localizedDescription)"
            }
        }
    }

    private func packetFrequency(for packet: S400AdvertisementPacket) -> Double? {
        let previous = lastPacketTimeByDevice[packet.deviceID]
        lastPacketTimeByDevice[packet.deviceID] = packet.observedAt
        guard let previous else {
            return nil
        }
        let delta = packet.observedAt.timeIntervalSince(previous)
        guard delta > 0 else {
            return nil
        }
        return 1 / delta
    }

    private func refreshHealthKitAuthorizationState(promptIfNeeded: Bool = false) async {
        do {
            let requestStatus = try await healthKitExporter.authorizationRequestStatus()

            if promptIfNeeded, requestStatus == .shouldRequest {
                try await healthKitExporter.requestAuthorization()
            }

            let syncedFields = await syncProfileFromHealthKit()
            let permissions = healthKitExporter.exportPermissions()
            healthKitAuthorized = permissions.allowsExport

            if !promptIfNeeded {
                return
            }

            var statusParts: [String] = []

            if !permissions.isAvailable {
                statusParts.append("HealthKit is not available on this device.")
            } else if !permissions.allowsExport {
                if requestStatus == .shouldRequest {
                    statusParts.append("HealthKit access was not enabled. If iOS no longer shows the sheet, enable access in the Health app or App Settings.")
                } else {
                    statusParts.append("HealthKit access is currently disabled. Enable it in the Health app or App Settings, then return here.")
                }
            } else {
                statusParts.append("HealthKit can save \(humanReadableList(permissions.enabledExportFields)).")
                if !permissions.disabledOptionalExportFields.isEmpty {
                    statusParts.append("Still disabled: \(humanReadableList(permissions.disabledOptionalExportFields)).")
                }
            }

            if syncedFields.isEmpty {
                statusParts.append("No Health profile fields were available to sync.")
            } else {
                statusParts.append("Synced \(humanReadableList(syncedFields)) from HealthKit.")
                if profile.bodyCompositionReady {
                    statusParts.append("Body-fat calculation is ready.")
                }
            }

            statusMessage = statusParts.joined(separator: " ")
        } catch {
            healthKitAuthorized = false
            statusMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }

    private func syncHealthKitNow() async {
        do {
            let requestStatus = try await healthKitExporter.authorizationRequestStatus()

            if requestStatus == .shouldRequest {
                try await healthKitExporter.requestAuthorization()
            }

            let syncedFields = await syncProfileFromHealthKit()
            let permissions = healthKitExporter.exportPermissions()
            healthKitAuthorized = permissions.allowsExport

            guard permissions.isAvailable else {
                statusMessage = "HealthKit is not available on this device."
                return
            }

            guard permissions.allowsExport else {
                if requestStatus == .shouldRequest {
                    statusMessage = "HealthKit access was not enabled. If iOS no longer shows the sheet, enable access in the Health app or App Settings."
                } else {
                    statusMessage = "HealthKit access is currently disabled. Enable it in the Health app or App Settings, then return here."
                }
                return
            }

            let savedMeasurements = measurementHistory
                .reversed()
                .map(scaleMeasurementForHealthKitExport(_:))

            let exportResult = try await healthKitExporter.exportHistory(
                measurements: savedMeasurements,
                profile: profile
            )

            var statusParts: [String] = [
                "HealthKit can save \(humanReadableList(permissions.enabledExportFields))."
            ]

            if !permissions.disabledOptionalExportFields.isEmpty {
                statusParts.append("Still disabled: \(humanReadableList(permissions.disabledOptionalExportFields)).")
            }

            if savedMeasurements.isEmpty {
                statusParts.append("No saved sessions to export.")
            } else {
                statusParts.append("Exported \(exportResult.exported) saved session\(exportResult.exported == 1 ? "" : "s") to Health.")
                if exportResult.skipped > 0 {
                    statusParts.append("Skipped \(exportResult.skipped) already synced session\(exportResult.skipped == 1 ? "" : "s").")
                }
            }

            if syncedFields.isEmpty {
                statusParts.append("No Health profile fields were available to sync.")
            } else {
                statusParts.append("Synced \(humanReadableList(syncedFields)) from HealthKit.")
            }

            statusMessage = statusParts.joined(separator: " ")
        } catch {
            healthKitAuthorized = false
            statusMessage = "Health sync failed: \(error.localizedDescription)"
        }
    }

    private func syncProfileFromHealthKit() async -> [String] {
        let snapshot = await healthKitExporter.readProfileSnapshot()
        guard !snapshot.isEmpty else {
            return []
        }

        let existingProfile = profile
        let updatedProfile = existingProfile.applyingHealthKitProfile(snapshot)
        let changedFields = changedHealthProfileFields(
            from: existingProfile,
            to: updatedProfile,
            snapshot: snapshot
        )

        if !changedFields.isEmpty {
            profile = updatedProfile
        }

        return changedFields
    }

    private func changedHealthProfileFields(
        from oldProfile: UserProfile,
        to newProfile: UserProfile,
        snapshot: HealthKitProfileSnapshot
    ) -> [String] {
        var fields: [String] = []

        if snapshot.heightCentimeters != nil, oldProfile.heightCentimeters != newProfile.heightCentimeters {
            fields.append("height")
        }
        if snapshot.age != nil, oldProfile.age != newProfile.age {
            fields.append("age")
        }
        if snapshot.sex != nil, oldProfile.sex != newProfile.sex {
            fields.append("sex")
        }

        return fields
    }

    private func humanReadableList(_ items: [String]) -> String {
        guard !items.isEmpty else {
            return ""
        }
        if items.count == 1 {
            return items[0]
        }
        if items.count == 2 {
            return "\(items[0]) and \(items[1])"
        }
        let prefix = items.dropLast().joined(separator: ", ")
        return "\(prefix), and \(items[items.count - 1])"
    }

    private func scaleMeasurementForHealthKitExport(_ measurement: StoredMeasurement) -> ScaleMeasurement {
        ScaleMeasurement(
            id: measurement.id,
            timestamp: measurement.timestamp,
            weightKg: measurement.weightKg,
            impedance: measurement.impedance,
            deviceId: measurement.deviceId,
            lowFrequencyImpedance: measurement.lowFrequencyImpedance,
            heartRate: measurement.heartRate,
            profileId: measurement.profileId,
            bodyComposition: bodyComposition(for: measurement)
        )
    }

    private func startScanningOnLaunchIfPossible() {
        guard scannerConfigurationIsValid else {
            return
        }
        startScanning()
    }

    private var scannerConfigurationIsValid: Bool {
        do {
            _ = try S400PacketDecoder(
                bindKeyHex: profile.bindKeyHex,
                configuredMACAddress: profile.scaleMACAddress
            )
            return true
        } catch {
            return false
        }
    }

    private func packetDebugLog(for packet: S400AdvertisementPacket) -> String {
        [
            "[S400 PACKET]",
            "time=\(packet.observedAt.ISO8601Format())",
            "device=\(packet.deviceID)",
            "model=\(String(format: "0x%04X", packet.deviceModelID))",
            "counter=\(packet.packetCounter)",
            "frameControl=\(String(format: "0x%04X", packet.frameControl))",
            "rssi=\(packet.rssi)",
            "weightKg=\(optionalString(packet.weightKg))",
            "impedance=\(optionalString(packet.impedance))",
            "lowFrequencyImpedance=\(optionalString(packet.lowFrequencyImpedance))",
            "heartRate=\(optionalString(packet.heartRate))",
            "profileId=\(optionalString(packet.profileId))",
            "serviceData=\(packet.rawServiceData.hexString)",
            "decryptedPayload=\(packet.decryptedPayload.hexString)",
            "manufacturerData=\(packet.manufacturerData?.hexString ?? "nil")"
        ].joined(separator: " ")
    }

    private func aggregationDebugLog(for deviceID: String, state: S400MeasurementAggregator.DebugState) -> String {
        [
            "[S400 AGGREGATOR]",
            "device=\(deviceID)",
            "ready=\(state.isReadyToFinalize)",
            "missing=\(state.missingFields.joined(separator: ","))",
            "weightKg=\(optionalString(state.weightKg))",
            "impedance=\(optionalString(state.impedance))",
            "lowFrequencyImpedance=\(optionalString(state.lowFrequencyImpedance))",
            "heartRate=\(optionalString(state.heartRate))",
            "profileId=\(optionalString(state.profileId))"
        ].joined(separator: " ")
    }

    private func finalizedMeasurementLog(for measurement: ScaleMeasurement) -> String {
        [
            "[S400 FINALIZED]",
            "time=\(measurement.timestamp.ISO8601Format())",
            "device=\(measurement.deviceId)",
            "weightKg=\(measurement.weightKg)",
            "impedance=\(measurement.impedance)",
            "lowFrequencyImpedance=\(optionalString(measurement.lowFrequencyImpedance))",
            "heartRate=\(optionalString(measurement.heartRate))",
            "profileId=\(optionalString(measurement.profileId))"
        ].joined(separator: " ")
    }

    private func optionalString<T>(_ value: T?) -> String {
        guard let value else {
            return "nil"
        }
        return String(describing: value)
    }
}
