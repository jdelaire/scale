import Foundation

struct StoredMeasurement: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let weightKg: Double
    let impedance: Double
    let deviceId: String
    let lowFrequencyImpedance: Double?
    let heartRate: Int?
    let profileId: Int?

    init(entity: MeasurementEntity) {
        id = entity.id ?? UUID()
        timestamp = entity.timestamp ?? .distantPast
        weightKg = entity.weightKg
        impedance = entity.impedance
        deviceId = entity.deviceId ?? "Unknown"
        lowFrequencyImpedance = entity.lowFrequencyImpedance > 0 ? entity.lowFrequencyImpedance : nil
        heartRate = entity.heartRate > 0 ? Int(entity.heartRate) : nil
        profileId = entity.profileId >= 0 ? Int(entity.profileId) : nil
    }

    init(measurement: ScaleMeasurement) {
        id = measurement.id
        timestamp = measurement.timestamp
        weightKg = measurement.weightKg
        impedance = measurement.impedance
        deviceId = measurement.deviceId
        lowFrequencyImpedance = measurement.lowFrequencyImpedance
        heartRate = measurement.heartRate
        profileId = measurement.profileId
    }
}
