import CoreData
import Foundation

@MainActor
final class MeasurementStore {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer = MeasurementPersistenceController.makeContainer()) {
        self.container = container
    }

    func fetchMeasurements() -> [StoredMeasurement] {
        let request = MeasurementEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MeasurementEntity.timestamp, ascending: false)]
        let entities = (try? container.viewContext.fetch(request)) ?? []
        return entities.map(StoredMeasurement.init(entity:))
    }

    @discardableResult
    func save(_ measurement: ScaleMeasurement) throws -> StoredMeasurement {
        let entity = MeasurementEntity(context: container.viewContext)
        entity.id = measurement.id
        entity.timestamp = measurement.timestamp
        entity.weightKg = measurement.weightKg
        entity.impedance = measurement.impedance
        entity.deviceId = measurement.deviceId
        entity.lowFrequencyImpedance = measurement.lowFrequencyImpedance ?? 0
        entity.heartRate = Int16(measurement.heartRate ?? 0)
        entity.profileId = Int16(measurement.profileId ?? -1)
        try container.viewContext.save()
        return StoredMeasurement(entity: entity)
    }

    func deleteAll() throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "MeasurementEntity")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try container.persistentStoreCoordinator.execute(deleteRequest, with: container.viewContext)
        try container.viewContext.save()
    }
}
