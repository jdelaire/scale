import Foundation

struct ScaleMeasurement: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let weightKg: Double
    let impedance: Double
    let deviceId: String
    let lowFrequencyImpedance: Double?
    let heartRate: Int?
    let profileId: Int?
    let bodyComposition: BodyCompositionEstimate?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        weightKg: Double,
        impedance: Double,
        deviceId: String,
        lowFrequencyImpedance: Double? = nil,
        heartRate: Int? = nil,
        profileId: Int? = nil,
        bodyComposition: BodyCompositionEstimate? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.weightKg = weightKg
        self.impedance = impedance
        self.deviceId = deviceId
        self.lowFrequencyImpedance = lowFrequencyImpedance
        self.heartRate = heartRate
        self.profileId = profileId
        self.bodyComposition = bodyComposition
    }
}
