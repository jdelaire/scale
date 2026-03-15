import CoreData
import Foundation

enum MeasurementPersistenceController {
    static func makeContainer(inMemory: Bool = false) -> NSPersistentContainer {
        let model = managedObjectModel()
        let container = NSPersistentContainer(name: "S400Scale", managedObjectModel: model)

        let description = NSPersistentStoreDescription()
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directoryURL = baseURL.appendingPathComponent("S400Scale", isDirectory: true)
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            description.url = directoryURL.appendingPathComponent("Measurements.sqlite")
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load Core Data store: \(error)")
            }
        }
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private static func managedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "MeasurementEntity"
        entity.managedObjectClassName = NSStringFromClass(MeasurementEntity.self)

        entity.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "timestamp", type: .dateAttributeType),
            attribute(name: "weightKg", type: .doubleAttributeType),
            attribute(name: "impedance", type: .doubleAttributeType),
            attribute(name: "deviceId", type: .stringAttributeType),
            optionalAttribute(name: "lowFrequencyImpedance", type: .doubleAttributeType),
            optionalAttribute(name: "heartRate", type: .integer16AttributeType),
            optionalAttribute(name: "profileId", type: .integer16AttributeType),
        ]

        model.entities = [entity]
        return model
    }

    private static func attribute(name: String, type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        return attribute
    }

    private static func optionalAttribute(name: String, type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = nil
        return attribute
    }
}
