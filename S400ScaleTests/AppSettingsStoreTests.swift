import XCTest
@testable import S400Scale

final class AppSettingsStoreTests: XCTestCase {
    func testLoadProfileReturnsSeededDefaultsWhenNoProfileIsSaved() {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        let profile = store.loadProfile()

        XCTAssertEqual(profile.bindKeyHex, UserProfile.defaultBindKeyHex)
        XCTAssertEqual(profile.scaleMACAddress, UserProfile.defaultScaleMACAddress)
        XCTAssertEqual(profile.bodyCompositionMode, .athlete)
    }

    func testLoadProfileBackfillsDeviceDefaultsWhenSavedProfileHasEmptyFields() throws {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let savedProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bindKeyHex: "",
            scaleMACAddress: ""
        )
        let data = try JSONEncoder().encode(savedProfile)
        defaults.set(data, forKey: "s400.user-profile")

        let store = AppSettingsStore(defaults: defaults)
        let loadedProfile = store.loadProfile()

        XCTAssertEqual(loadedProfile.heightCentimeters, 180)
        XCTAssertEqual(loadedProfile.age, 34)
        XCTAssertEqual(loadedProfile.bindKeyHex, UserProfile.defaultBindKeyHex)
        XCTAssertEqual(loadedProfile.scaleMACAddress, UserProfile.defaultScaleMACAddress)
    }

    func testLoadProfileDecodesLegacyProfileWithoutPersonalCalibration() throws {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let legacyProfile: [String: Any] = [
            "heightCentimeters": 180,
            "age": 34,
            "sex": "male",
            "bodyCompositionMode": "athlete",
            "bindKeyHex": "feedfacefeedfacefeedfacefeedface",
            "scaleMACAddress": "AA:BB:CC:DD:EE:FF"
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyProfile)
        defaults.set(data, forKey: "s400.user-profile")

        let store = AppSettingsStore(defaults: defaults)
        let loadedProfile = store.loadProfile()

        XCTAssertEqual(loadedProfile.bodyCompositionMode, .athlete)
        XCTAssertEqual(loadedProfile.bodyCompositionCalibration, BodyCompositionCalibration())
        XCTAssertEqual(loadedProfile.bindKeyHex, "feedfacefeedfacefeedfacefeedface")
        XCTAssertEqual(loadedProfile.scaleMACAddress, "AA:BB:CC:DD:EE:FF")
    }
}

final class UserProfileTests: XCTestCase {
    func testApplyingHealthKitProfileUpdatesDemographicsWithoutTouchingDeviceSettings() {
        let profile = UserProfile(
            heightCentimeters: 170,
            age: 30,
            sex: .male,
            bindKeyHex: "feedfacefeedfacefeedfacefeedface",
            scaleMACAddress: "AA:BB:CC:DD:EE:FF"
        )

        let snapshot = HealthKitProfileSnapshot(
            heightCentimeters: 182,
            age: 34,
            sex: .female
        )

        let updated = profile.applyingHealthKitProfile(snapshot)

        XCTAssertEqual(updated.heightCentimeters, 182)
        XCTAssertEqual(updated.age, 34)
        XCTAssertEqual(updated.sex, .female)
        XCTAssertEqual(updated.bindKeyHex, "feedfacefeedfacefeedfacefeedface")
        XCTAssertEqual(updated.scaleMACAddress, "AA:BB:CC:DD:EE:FF")
    }

    func testApplyingHealthKitProfileKeepsExistingValuesWhenSnapshotIsPartial() {
        let profile = UserProfile(
            heightCentimeters: 180,
            age: 40,
            sex: .male,
            bindKeyHex: UserProfile.defaultBindKeyHex,
            scaleMACAddress: UserProfile.defaultScaleMACAddress
        )

        let snapshot = HealthKitProfileSnapshot(
            heightCentimeters: nil,
            age: 41,
            sex: nil
        )

        let updated = profile.applyingHealthKitProfile(snapshot)

        XCTAssertEqual(updated.heightCentimeters, 180)
        XCTAssertEqual(updated.age, 41)
        XCTAssertEqual(updated.sex, .male)
    }

    func testAthleteModeProducesLeanerEstimateThanStandardMode() throws {
        let athleteProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bodyCompositionMode: .athlete
        )
        let standardProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bodyCompositionMode: .standard
        )

        let athleteEstimate = BodyCompositionCalculator.estimate(
            weightKg: 78.7,
            impedanceOhms: 423.9,
            profile: athleteProfile
        )
        let standardEstimate = BodyCompositionCalculator.estimate(
            weightKg: 78.7,
            impedanceOhms: 423.9,
            profile: standardProfile
        )

        XCTAssertNotNil(athleteEstimate)
        XCTAssertNotNil(standardEstimate)
        XCTAssertLessThan(
            try XCTUnwrap(athleteEstimate).fatPercentage,
            try XCTUnwrap(standardEstimate).fatPercentage
        )
    }

    func testPersonalModeCanBiasEstimateTowardHigherBodyFat() throws {
        let athleteProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bodyCompositionMode: .athlete
        )
        let personalProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bodyCompositionMode: .personal,
            bodyCompositionCalibration: BodyCompositionCalibration(
                fatPercentageOffset: 2.5,
                impedanceMultiplier: 1,
                leanMassMultiplier: 1
            )
        )

        let athleteEstimate = try XCTUnwrap(
            BodyCompositionCalculator.estimate(
                weightKg: 78.7,
                impedanceOhms: 423.9,
                profile: athleteProfile
            )
        )
        let personalEstimate = try XCTUnwrap(
            BodyCompositionCalculator.estimate(
                weightKg: 78.7,
                impedanceOhms: 423.9,
                profile: personalProfile
            )
        )

        XCTAssertGreaterThan(personalEstimate.fatPercentage, athleteEstimate.fatPercentage)
    }

    func testPersonalModeWithNeutralCalibrationMatchesAthleteMode() throws {
        let athleteProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bodyCompositionMode: .athlete
        )
        let personalProfile = UserProfile(
            heightCentimeters: 180,
            age: 34,
            sex: .male,
            bodyCompositionMode: .personal,
            bodyCompositionCalibration: BodyCompositionCalibration()
        )

        let athleteEstimate = try XCTUnwrap(
            BodyCompositionCalculator.estimate(
                weightKg: 78.7,
                impedanceOhms: 423.9,
                profile: athleteProfile
            )
        )
        let personalEstimate = try XCTUnwrap(
            BodyCompositionCalculator.estimate(
                weightKg: 78.7,
                impedanceOhms: 423.9,
                profile: personalProfile
            )
        )

        XCTAssertEqual(personalEstimate.fatPercentage, athleteEstimate.fatPercentage, accuracy: 0.0001)
        XCTAssertEqual(personalEstimate.leanMassKg, athleteEstimate.leanMassKg, accuracy: 0.0001)
    }
}
