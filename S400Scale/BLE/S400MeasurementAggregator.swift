import Foundation

final class S400MeasurementAggregator {
    struct DebugState: Hashable {
        let weightKg: Double?
        let impedance: Double?
        let lowFrequencyImpedance: Double?
        let heartRate: Int?
        let profileId: Int?

        var missingFields: [String] {
            var fields: [String] = []
            if weightKg == nil {
                fields.append("weight")
            }
            if impedance == nil {
                fields.append("impedance")
            }
            if lowFrequencyImpedance == nil {
                fields.append("lowFrequencyImpedance")
            }
            return fields
        }

        var isReadyToFinalize: Bool {
            missingFields.isEmpty
        }
    }

    private struct Session {
        var weightKg: Double?
        var impedance: Double?
        var lowFrequencyImpedance: Double?
        var heartRate: Int?
        var profileId: Int?
        var lastSeenAt: Date
    }

    private var sessions: [String: Session] = [:]
    private var recentFinalizations: [String: (weight: Double, impedance: Double, time: Date)] = [:]

    func ingest(_ packet: S400AdvertisementPacket, bodyComposition: BodyCompositionEstimate?) -> ScaleMeasurement? {
        var session = sessions[packet.deviceID] ?? Session(lastSeenAt: packet.observedAt)
        session.lastSeenAt = packet.observedAt

        if let weightKg = packet.weightKg {
            session.weightKg = weightKg
        }
        if let impedance = packet.impedance {
            session.impedance = impedance
        }
        if let lowFrequencyImpedance = packet.lowFrequencyImpedance {
            session.lowFrequencyImpedance = lowFrequencyImpedance
        }
        if let heartRate = packet.heartRate {
            session.heartRate = heartRate
        }
        if let profileId = packet.profileId {
            session.profileId = profileId
        }

        sessions[packet.deviceID] = session

        guard
            let weightKg = session.weightKg,
            let impedance = session.impedance,
            session.lowFrequencyImpedance != nil
        else {
            return nil
        }

        if let recent = recentFinalizations[packet.deviceID] {
            let weightDiff = abs(recent.weight - weightKg)
            let impedanceDiff = abs(recent.impedance - impedance)
            if weightDiff < 0.05, impedanceDiff < 1, packet.observedAt.timeIntervalSince(recent.time) < 10 {
                sessions.removeValue(forKey: packet.deviceID)
                return nil
            }
        }

        recentFinalizations[packet.deviceID] = (weightKg, impedance, packet.observedAt)
        sessions.removeValue(forKey: packet.deviceID)

        return ScaleMeasurement(
            timestamp: packet.observedAt,
            weightKg: weightKg,
            impedance: impedance,
            deviceId: packet.deviceID,
            lowFrequencyImpedance: session.lowFrequencyImpedance,
            heartRate: session.heartRate,
            profileId: session.profileId,
            bodyComposition: bodyComposition
        )
    }

    func debugState(for deviceID: String) -> DebugState? {
        guard let session = sessions[deviceID] else {
            return nil
        }

        return DebugState(
            weightKg: session.weightKg,
            impedance: session.impedance,
            lowFrequencyImpedance: session.lowFrequencyImpedance,
            heartRate: session.heartRate,
            profileId: session.profileId
        )
    }
}
