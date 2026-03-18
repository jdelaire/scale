import Foundation

enum BodyCompositionMode: String, CaseIterable, Codable, Identifiable {
    case athlete
    case personal
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .athlete:
            "Athlete"
        case .personal:
            "Personal"
        case .standard:
            "Standard"
        }
    }
}

struct BodyCompositionCalibration: Codable, Equatable {
    var fatPercentageOffset: Double = 0
    var impedanceMultiplier: Double = 1
    var leanMassMultiplier: Double = 1

    var hasEffect: Bool {
        abs(fatPercentageOffset) > 0.001
            || abs(impedanceMultiplier - 1) > 0.001
            || abs(leanMassMultiplier - 1) > 0.001
    }
}

struct HealthKitProfileSnapshot: Equatable {
    var heightCentimeters: Int?
    var age: Int?
    var sex: BiologicalSex?

    var importedFields: [String] {
        var fields: [String] = []
        if heightCentimeters != nil {
            fields.append("height")
        }
        if age != nil {
            fields.append("age")
        }
        if sex != nil {
            fields.append("sex")
        }
        return fields
    }

    var isEmpty: Bool {
        importedFields.isEmpty
    }
}

struct UserProfile: Codable, Equatable {
    static let defaultBindKeyHex = BuildSecrets.defaultBindKeyHex
    static let defaultScaleMACAddress = BuildSecrets.defaultScaleMACAddress

    var heightCentimeters: Int?
    var age: Int?
    var sex: BiologicalSex = .male
    var bodyCompositionMode: BodyCompositionMode = .athlete
    var bodyCompositionCalibration: BodyCompositionCalibration = BodyCompositionCalibration()
    var bindKeyHex: String = Self.defaultBindKeyHex
    var scaleMACAddress: String = Self.defaultScaleMACAddress

    var bodyCompositionReady: Bool {
        guard let heightCentimeters, let age else {
            return false
        }
        return heightCentimeters > 0 && age > 0
    }

    func applyingDeviceDefaults() -> UserProfile {
        var profile = self
        if profile.bindKeyHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.bindKeyHex = Self.defaultBindKeyHex
        }
        if profile.scaleMACAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.scaleMACAddress = Self.defaultScaleMACAddress
        }
        return profile
    }

    func applyingHealthKitProfile(_ snapshot: HealthKitProfileSnapshot) -> UserProfile {
        var profile = self
        if let heightCentimeters = snapshot.heightCentimeters {
            profile.heightCentimeters = heightCentimeters
        }
        if let age = snapshot.age {
            profile.age = age
        }
        if let sex = snapshot.sex {
            profile.sex = sex
        }
        return profile
    }
}

extension UserProfile {
    private enum CodingKeys: String, CodingKey {
        case heightCentimeters
        case age
        case sex
        case bodyCompositionMode
        case bodyCompositionCalibration
        case bindKeyHex
        case scaleMACAddress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heightCentimeters = try container.decodeIfPresent(Int.self, forKey: .heightCentimeters)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        sex = try container.decodeIfPresent(BiologicalSex.self, forKey: .sex) ?? .male
        bodyCompositionMode = try container.decodeIfPresent(BodyCompositionMode.self, forKey: .bodyCompositionMode) ?? .athlete
        bodyCompositionCalibration =
            try container.decodeIfPresent(BodyCompositionCalibration.self, forKey: .bodyCompositionCalibration)
            ?? BodyCompositionCalibration()
        bindKeyHex = try container.decodeIfPresent(String.self, forKey: .bindKeyHex) ?? Self.defaultBindKeyHex
        scaleMACAddress =
            try container.decodeIfPresent(String.self, forKey: .scaleMACAddress) ?? Self.defaultScaleMACAddress
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(heightCentimeters, forKey: .heightCentimeters)
        try container.encodeIfPresent(age, forKey: .age)
        try container.encode(sex, forKey: .sex)
        try container.encode(bodyCompositionMode, forKey: .bodyCompositionMode)
        try container.encode(bodyCompositionCalibration, forKey: .bodyCompositionCalibration)
        try container.encode(bindKeyHex, forKey: .bindKeyHex)
        try container.encode(scaleMACAddress, forKey: .scaleMACAddress)
    }
}
