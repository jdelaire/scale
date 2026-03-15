import Foundation
import HealthKit

struct HealthKitExportPermissions: Equatable {
    let isAvailable: Bool
    let canWriteWeight: Bool
    let canWriteBodyFat: Bool
    let canWriteLeanMass: Bool
    let canWriteBMI: Bool

    var allowsExport: Bool {
        isAvailable && canWriteWeight
    }

    var enabledExportFields: [String] {
        var fields: [String] = []
        if canWriteWeight {
            fields.append("weight")
        }
        if canWriteBodyFat {
            fields.append("body fat")
        }
        if canWriteLeanMass {
            fields.append("lean mass")
        }
        if canWriteBMI {
            fields.append("BMI")
        }
        return fields
    }

    var disabledOptionalExportFields: [String] {
        var fields: [String] = []
        if !canWriteBodyFat {
            fields.append("body fat")
        }
        if !canWriteLeanMass {
            fields.append("lean mass")
        }
        if !canWriteBMI {
            fields.append("BMI")
        }
        return fields
    }
}

@MainActor
final class HealthKitExporter {
    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        guard isAvailable else {
            return .unknown
        }
        return try await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
    }

    func exportPermissions() -> HealthKitExportPermissions {
        guard isAvailable else {
            return HealthKitExportPermissions(
                isAvailable: false,
                canWriteWeight: false,
                canWriteBodyFat: false,
                canWriteLeanMass: false,
                canWriteBMI: false
            )
        }

        return HealthKitExportPermissions(
            isAvailable: true,
            canWriteWeight: store.authorizationStatus(for: bodyMassType) == .sharingAuthorized,
            canWriteBodyFat: store.authorizationStatus(for: bodyFatType) == .sharingAuthorized,
            canWriteLeanMass: store.authorizationStatus(for: leanBodyMassType) == .sharingAuthorized,
            canWriteBMI: store.authorizationStatus(for: bodyMassIndexType) == .sharingAuthorized
        )
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            return
        }

        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func readProfileSnapshot(referenceDate: Date = .now, calendar: Calendar = .current) async -> HealthKitProfileSnapshot {
        guard isAvailable else {
            return HealthKitProfileSnapshot()
        }

        async let heightCentimeters = latestHeightCentimeters()

        let age: Int? = {
            guard let birthDate = try? store.dateOfBirthComponents() else {
                return nil
            }
            return ageInYears(from: birthDate, referenceDate: referenceDate, calendar: calendar)
        }()

        let sex: BiologicalSex? = {
            guard let biologicalSex = try? store.biologicalSex().biologicalSex else {
                return nil
            }
            switch biologicalSex {
            case .female:
                return .female
            case .male:
                return .male
            default:
                return nil
            }
        }()

        return HealthKitProfileSnapshot(
            heightCentimeters: await heightCentimeters,
            age: age,
            sex: sex
        )
    }

    func export(measurement: ScaleMeasurement, profile: UserProfile) async throws {
        guard isAvailable else {
            return
        }

        let permissions = exportPermissions()
        if permissions.canWriteWeight, await hasSavedMeasurement(id: measurement.id) {
            return
        }

        var samples: [HKSample] = []
        let timestamp = measurement.timestamp
        let metadata = sampleMetadata(for: measurement)

        if permissions.canWriteWeight {
            let bodyMass = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: measurement.weightKg)
            samples.append(HKQuantitySample(type: bodyMassType, quantity: bodyMass, start: timestamp, end: timestamp, metadata: metadata))
        }

        if let bodyComposition = measurement.bodyComposition {
            if permissions.canWriteBodyFat {
                let bodyFat = HKQuantity(unit: .percent(), doubleValue: bodyComposition.fatPercentage / 100)
                samples.append(HKQuantitySample(type: bodyFatType, quantity: bodyFat, start: timestamp, end: timestamp, metadata: metadata))
            }

            if permissions.canWriteLeanMass {
                let leanMass = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: bodyComposition.leanMassKg)
                samples.append(HKQuantitySample(type: leanBodyMassType, quantity: leanMass, start: timestamp, end: timestamp, metadata: metadata))
            }
        }

        if permissions.canWriteBMI, let bmi = bodyMassIndex(measurement: measurement, profile: profile) {
            let bodyMassIndex = HKQuantity(unit: .count(), doubleValue: bmi)
            samples.append(HKQuantitySample(type: bodyMassIndexType, quantity: bodyMassIndex, start: timestamp, end: timestamp, metadata: metadata))
        }

        guard !samples.isEmpty else {
            return
        }

        try await store.save(samples)
    }

    func exportHistory(measurements: [ScaleMeasurement], profile: UserProfile) async throws -> (exported: Int, skipped: Int) {
        var exported = 0
        var skipped = 0

        for measurement in measurements {
            if await hasSavedMeasurement(id: measurement.id) {
                skipped += 1
                continue
            }

            try await export(measurement: measurement, profile: profile)
            exported += 1
        }

        return (exported, skipped)
    }

    private var shareTypes: Set<HKSampleType> {
        [bodyMassType, bodyFatType, leanBodyMassType, bodyMassIndexType]
    }

    private var readTypes: Set<HKObjectType> {
        [
            heightType,
            biologicalSexType,
            dateOfBirthType
        ]
    }

    private var bodyMassType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .bodyMass)!
    }

    private var bodyFatType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
    }

    private var leanBodyMassType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .leanBodyMass)!
    }

    private var bodyMassIndexType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!
    }

    private var heightType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .height)!
    }

    private var biologicalSexType: HKCharacteristicType {
        HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
    }

    private var dateOfBirthType: HKCharacteristicType {
        HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
    }

    private func latestHeightCentimeters() async -> Int? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heightType)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.endDate, order: .reverse)],
            limit: 1
        )

        do {
            let samples = try await descriptor.result(for: store)
            guard let sample = samples.first else {
                return nil
            }
            let heightValue = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
            guard heightValue > 0 else {
                return nil
            }
            return Int(heightValue.rounded())
        } catch {
            return nil
        }
    }

    private func ageInYears(
        from birthDateComponents: DateComponents,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int? {
        guard let birthDate = calendar.date(from: birthDateComponents) else {
            return nil
        }
        let components = calendar.dateComponents([.year], from: birthDate, to: referenceDate)
        guard let years = components.year, years > 0 else {
            return nil
        }
        return years
    }

    private func bodyMassIndex(measurement: ScaleMeasurement, profile: UserProfile) -> Double? {
        guard let heightCentimeters = profile.heightCentimeters, heightCentimeters > 0 else {
            return nil
        }
        let heightMeters = Double(heightCentimeters) / 100
        guard heightMeters > 0 else {
            return nil
        }
        return measurement.weightKg / (heightMeters * heightMeters)
    }

    private func sampleMetadata(for measurement: ScaleMeasurement) -> [String: Any] {
        [
            HKMetadataKeyExternalUUID: measurement.id.uuidString,
            HKMetadataKeyWasUserEntered: false
        ]
    }

    private func hasSavedMeasurement(id: UUID) async -> Bool {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [id.uuidString]
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: !(samples?.isEmpty ?? true))
            }
            store.execute(query)
        }
    }
}
