import Foundation

enum BiologicalSex: String, CaseIterable, Codable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:
            "Male"
        case .female:
            "Female"
        }
    }
}
