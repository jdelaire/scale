import CoreData
import Foundation

@objc(MeasurementEntity)
final class MeasurementEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var timestamp: Date?
    @NSManaged var weightKg: Double
    @NSManaged var impedance: Double
    @NSManaged var deviceId: String?
    @NSManaged var lowFrequencyImpedance: Double
    @NSManaged var heartRate: Int16
    @NSManaged var profileId: Int16
}

extension MeasurementEntity {
    @nonobjc static func fetchRequest() -> NSFetchRequest<MeasurementEntity> {
        NSFetchRequest<MeasurementEntity>(entityName: "MeasurementEntity")
    }
}
