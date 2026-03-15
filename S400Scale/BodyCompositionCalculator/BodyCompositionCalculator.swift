import Foundation

enum BodyCompositionCalculator {
    static func estimate(
        weightKg: Double,
        impedanceOhms: Double,
        profile: UserProfile
    ) -> BodyCompositionEstimate? {
        guard
            let height = profile.heightCentimeters,
            let age = profile.age,
            height > 0,
            age > 0,
            (10...200).contains(weightKg),
            impedanceOhms > 0
        else {
            return nil
        }

        let sex = profile.sex
        let lbmCoefficient = leanBodyMassCoefficient(
            weightKg: weightKg,
            heightCentimeters: Double(height),
            age: Double(age),
            impedanceOhms: impedanceOhms
        )

        let fatPercentage = bodyFatPercentage(
            weightKg: weightKg,
            heightCentimeters: Double(height),
            age: Double(age),
            sex: sex,
            mode: profile.bodyCompositionMode,
            lbmCoefficient: lbmCoefficient
        )

        let leanMass = max(weightKg * (1 - fatPercentage / 100), 0)

        return BodyCompositionEstimate(
            fatFreeMassKg: leanMass,
            fatPercentage: fatPercentage,
            leanMassKg: leanMass
        )
    }

    private static func leanBodyMassCoefficient(
        weightKg: Double,
        heightCentimeters: Double,
        age: Double,
        impedanceOhms: Double
    ) -> Double {
        var value = (heightCentimeters * 9.058 / 100) * (heightCentimeters / 100)
        value += weightKg * 0.32 + 12.226
        value -= impedanceOhms * 0.0068
        value -= age * 0.0542
        return value
    }

    private static func bodyFatPercentage(
        weightKg: Double,
        heightCentimeters: Double,
        age: Double,
        sex: BiologicalSex,
        mode: BodyCompositionMode,
        lbmCoefficient: Double
    ) -> Double {
        let constant: Double
        switch (sex, age) {
        case (.female, ...49):
            constant = 9.25
        case (.female, _):
            constant = 7.25
        default:
            constant = 0.8
        }

        var coefficient = 1.0
        switch sex {
        case .male where weightKg < 61:
            coefficient = 0.98
        case .female where weightKg > 60:
            coefficient = heightCentimeters > 160 ? 0.96 * 1.03 : 0.96
        case .female where weightKg < 50:
            coefficient = heightCentimeters > 160 ? 1.02 * 1.03 : 1.02
        default:
            coefficient = 1.0
        }

        let athleteAdjustment = athleteAdjustment(for: sex, mode: mode)
        let adjustedLbmCoefficient = lbmCoefficient * athleteAdjustment.leanMassMultiplier
        let adjustedConstant = constant + athleteAdjustment.constantOffset
        let adjustedCoefficient = coefficient * athleteAdjustment.coefficientMultiplier

        let value = (1 - (((adjustedLbmCoefficient - adjustedConstant) * adjustedCoefficient) / weightKg)) * 100
        return min(max(value, 5), 75)
    }

    private static func athleteAdjustment(
        for sex: BiologicalSex,
        mode: BodyCompositionMode
    ) -> (leanMassMultiplier: Double, constantOffset: Double, coefficientMultiplier: Double) {
        guard mode == .athlete else {
            return (1.0, 0.0, 1.0)
        }

        switch sex {
        case .male:
            return (1.03, -1.8, 1.01)
        case .female:
            return (1.025, -1.2, 1.01)
        }
    }
}
