import XCTest
@testable import S400Scale

@MainActor
final class AppModelTests: XCTestCase {
    func testStartScanningWithMissingBindKeyShowsValidationError() {
        let model = makeModel()
        model.profile.bindKeyHex = ""
        model.profile.scaleMACAddress = "8C:D0:B2:F6:BE:EF"

        model.startScanning()

        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(
            model.statusMessage,
            S400PacketDecoderError.missingBindKey.localizedDescription
        )
    }

    func testStartScanningWithInvalidBindKeyShowsValidationError() {
        let model = makeModel()
        model.profile.bindKeyHex = "1234"
        model.profile.scaleMACAddress = "8C:D0:B2:F6:BE:EF"

        model.startScanning()

        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(
            model.statusMessage,
            S400PacketDecoderError.invalidBindKey.localizedDescription
        )
    }

    func testModelDoesNotStartScanningOnLaunchWhenSavedConfigurationIsInvalid() {
        let suiteName = "S400ScaleTests.InvalidLaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let invalidProfile = UserProfile(
            heightCentimeters: nil,
            age: nil,
            sex: .male,
            bodyCompositionMode: .athlete,
            bindKeyHex: "1234",
            scaleMACAddress: "8C:D0:B2:F6:BE:EF"
        )
        let data = try! JSONEncoder().encode(invalidProfile)
        defaults.set(data, forKey: "s400.user-profile")

        let measurementStore = MeasurementStore(
            container: MeasurementPersistenceController.makeContainer(inMemory: true)
        )

        let model = AppModel(
            measurementStore: measurementStore,
            settingsStore: AppSettingsStore(defaults: defaults),
            healthKitExporter: HealthKitExporter()
        )

        XCTAssertFalse(model.isScanning)
    }

    private func makeModel() -> AppModel {
        let suiteName = "S400ScaleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let measurementStore = MeasurementStore(
            container: MeasurementPersistenceController.makeContainer(inMemory: true)
        )

        return AppModel(
            measurementStore: measurementStore,
            settingsStore: AppSettingsStore(defaults: defaults),
            healthKitExporter: HealthKitExporter()
        )
    }
}
