import Foundation

enum BodyCompositionMode: String, CaseIterable, Codable, Identifiable {
    case athlete
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .athlete:
            "Athlete"
        case .standard:
            "Standard"
        }
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
