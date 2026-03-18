import SwiftUI
import UIKit

// MARK: - Dashboard

struct DashboardView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ZStack {
                ScaleSceneBackground()

                ScrollView {
                    VStack(spacing: 28) {
                        OverviewHeroCard(
                            measurement: model.lastMeasurement,
                            bodyComposition: model.lastMeasurement.flatMap(model.bodyComposition(for:)),
                            isScanning: model.isScanning,
                            statusMessage: model.statusMessage
                        )

                        if let measurement = model.lastMeasurement {
                            OverviewMetricsCard(
                                measurement: measurement,
                                bodyComposition: model.bodyComposition(for: measurement),
                                formulaMode: model.profile.bodyCompositionMode,
                                profile: model.profile
                            )
                        } else {
                            EmptyOverviewCard()
                        }

                        RecentHistoryCard(
                            measurements: Array(model.measurementHistory.prefix(4)),
                            bodyComposition: model.bodyComposition(for:)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                ScaleSceneBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        if model.measurementHistory.isEmpty {
                            ScaleCard {
                                VStack(spacing: 8) {
                                    Text("No weigh-ins yet")
                                        .font(.headline)
                                    Text("Step on the scale to capture a measurement.")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            }
                        } else {
                            ForEach(model.measurementHistory) { measurement in
                                HistoryMeasurementCard(
                                    measurement: measurement,
                                    bodyComposition: model.bodyComposition(for: measurement)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("History")
            .toolbarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ZStack {
                ScaleSceneBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        ScaleCard {
                            SectionHeader(title: "Scale Access", subtitle: "Pairing-free BLE decoding")

                            VStack(spacing: 14) {
                                ScaleField(label: "Bind Key") {
                                    SecureField("32 hex characters", text: $model.profile.bindKeyHex)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }

                                ScaleField(label: "Scale MAC") {
                                    TextField("AA:BB:CC:DD:EE:FF", text: $model.profile.scaleMACAddress)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                }
                            }

                            HStack(spacing: 12) {
                                Button(model.isScanning ? "Stop Scan" : "Start Scan") {
                                    if model.isScanning {
                                        model.stopScanning()
                                    } else {
                                        model.startScanning()
                                    }
                                }
                                .scalePrimaryButtonStyle()

                                Button(model.healthKitAuthorized ? "Sync Health" : "Authorize Health") {
                                    model.syncHealthKit()
                                }
                                .scaleSecondaryButtonStyle()
                            }

                            if !model.statusMessage.isEmpty {
                                Text(model.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            if !model.healthKitAuthorized {
                                Button("Open App Settings") {
                                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                                        return
                                    }
                                    openURL(settingsURL)
                                }
                                .scaleSecondaryButtonStyle()
                            }
                        }

                        ScaleCard {
                            SectionHeader(title: "Body Composition", subtitle: "Used for fat estimation")

                            VStack(spacing: 14) {
                                ScaleField(label: "Height") {
                                    TextField("Height (cm)", value: heightBinding(for: model), format: .number)
                                        .keyboardType(.numberPad)
                                }

                                ScaleField(label: "Age") {
                                    Stepper(value: ageBinding(for: model), in: 1...99) {
                                        Text("\(model.profile.age ?? 30) years")
                                    }
                                }

                                ScaleField(label: "Formula") {
                                    Picker("Formula", selection: $model.profile.bodyCompositionMode) {
                                        ForEach(BodyCompositionMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }

                                if model.profile.bodyCompositionMode == .personal {
                                    ScaleField(label: "Fat Offset") {
                                        TextField(
                                            "0.0",
                                            value: fatPercentageOffsetBinding(for: model),
                                            format: .number.precision(.fractionLength(0...2))
                                        )
                                        .keyboardType(.numbersAndPunctuation)
                                    }

                                    ScaleField(label: "Impedance Multiplier") {
                                        TextField(
                                            "1.00",
                                            value: impedanceMultiplierBinding(for: model),
                                            format: .number.precision(.fractionLength(0...3))
                                        )
                                        .keyboardType(.decimalPad)
                                    }

                                    ScaleField(label: "Lean Mass Multiplier") {
                                        TextField(
                                            "1.00",
                                            value: leanMassMultiplierBinding(for: model),
                                            format: .number.precision(.fractionLength(0...3))
                                        )
                                        .keyboardType(.decimalPad)
                                    }

                                    Text("Personal starts from the Athlete formula, then applies your own corrections. Positive fat offset raises body-fat percentage. Lower impedance or higher lean-mass multipliers make readings leaner.")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                ScaleField(label: "Sex") {
                                    Picker("Sex", selection: $model.profile.sex) {
                                        ForEach(BiologicalSex.allCases) { sex in
                                            Text(sex.title).tag(sex)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }

                        ScaleCard {
                            SectionHeader(title: "Data", subtitle: "Local history only")

                            Button("Clear History", role: .destructive) {
                                model.clearHistory()
                            }
                            .scaleDestructiveButtonStyle()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.large)
        }
    }

    private func heightBinding(for model: AppModel) -> Binding<Int> {
        Binding(
            get: { model.profile.heightCentimeters ?? 170 },
            set: { model.profile.heightCentimeters = $0 }
        )
    }

    private func ageBinding(for model: AppModel) -> Binding<Int> {
        Binding(
            get: { model.profile.age ?? 30 },
            set: { model.profile.age = $0 }
        )
    }

    private func fatPercentageOffsetBinding(for model: AppModel) -> Binding<Double> {
        Binding(
            get: { model.profile.bodyCompositionCalibration.fatPercentageOffset },
            set: { model.profile.bodyCompositionCalibration.fatPercentageOffset = $0 }
        )
    }

    private func impedanceMultiplierBinding(for model: AppModel) -> Binding<Double> {
        Binding(
            get: { model.profile.bodyCompositionCalibration.impedanceMultiplier },
            set: { model.profile.bodyCompositionCalibration.impedanceMultiplier = max($0, 0.5) }
        )
    }

    private func leanMassMultiplierBinding(for model: AppModel) -> Binding<Double> {
        Binding(
            get: { model.profile.bodyCompositionCalibration.leanMassMultiplier },
            set: { model.profile.bodyCompositionCalibration.leanMassMultiplier = max($0, 0.5) }
        )
    }
}

// MARK: - Hero Card

private struct OverviewHeroCard: View {
    let measurement: StoredMeasurement?
    let bodyComposition: BodyCompositionEstimate?
    let isScanning: Bool
    let statusMessage: String

    var body: some View {
        ScaleCard {
            VStack(spacing: 24) {
                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(isScanning ? Color.accent : .white.opacity(0.2))
                        .frame(width: 8, height: 8)

                    Text(isScanning ? "Scanning" : "Standby")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                // Weight display
                VStack(spacing: 4) {
                    if let measurement {
                        Text(measurement.weightKg.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 80, weight: .ultraLight, design: .rounded))
                            .contentTransition(.numericText())
                            .monospacedDigit()

                        Text("kg")
                            .font(.title3.weight(.regular))
                            .foregroundStyle(.tertiary)
                            .tracking(2)
                            .textCase(.uppercase)
                    } else {
                        Text("--.-")
                            .font(.system(size: 80, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(.tertiary)

                        Text("step on scale")
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.quaternary)
                            .tracking(1)
                            .textCase(.uppercase)
                    }
                }
                .frame(maxWidth: .infinity)

                // Info chips
                if measurement != nil || bodyComposition != nil {
                    HairlineDivider()

                    HStack(spacing: 0) {
                        if let measurement {
                            InfoChip(
                                label: "Updated",
                                value: measurement.timestamp.formatted(.dateTime.hour().minute())
                            )
                        }

                        if let bodyComposition {
                            InfoChip(
                                label: "Body Fat",
                                value: "\(bodyComposition.fatPercentage.formatted(.number.precision(.fractionLength(1))))%"
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Metrics Card

private struct OverviewMetricsCard: View {
    let measurement: StoredMeasurement
    let bodyComposition: BodyCompositionEstimate?
    let formulaMode: BodyCompositionMode
    let profile: UserProfile

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    private var heightMeters: Double? {
        guard let heightCentimeters = profile.heightCentimeters, heightCentimeters > 0 else {
            return nil
        }
        return Double(heightCentimeters) / 100
    }

    private var fatMassKg: Double? {
        guard let bodyComposition else {
            return nil
        }
        return max(measurement.weightKg - bodyComposition.leanMassKg, 0)
    }

    private var bmi: Double? {
        guard let heightMeters else {
            return nil
        }
        return measurement.weightKg / (heightMeters * heightMeters)
    }

    private var ffmi: Double? {
        guard let bodyComposition, let heightMeters else {
            return nil
        }
        return bodyComposition.leanMassKg / (heightMeters * heightMeters)
    }

    private var fmi: Double? {
        guard let fatMassKg, let heightMeters else {
            return nil
        }
        return fatMassKg / (heightMeters * heightMeters)
    }

    var body: some View {
        ScaleCard {
            SectionHeader(title: "Composition", subtitle: "\(formulaMode.title) formula")

            LazyVGrid(columns: columns, spacing: 1) {
                MetricTile(
                    title: "Fat",
                    value: bodyComposition.map { $0.fatPercentage.formatted(.number.precision(.fractionLength(1))) } ?? "--",
                    unit: bodyComposition == nil ? nil : "%"
                )

                MetricTile(
                    title: "Lean Mass",
                    value: bodyComposition.map { $0.leanMassKg.formatted(.number.precision(.fractionLength(1))) } ?? "--",
                    unit: bodyComposition == nil ? nil : "kg"
                )

                MetricTile(
                    title: "Fat Mass",
                    value: fatMassKg?.formatted(.number.precision(.fractionLength(1))) ?? "--",
                    unit: fatMassKg == nil ? nil : "kg"
                )

                MetricTile(
                    title: "BMI",
                    value: bmi?.formatted(.number.precision(.fractionLength(1))) ?? "--",
                    unit: nil
                )

                MetricTile(
                    title: "FFMI",
                    value: ffmi?.formatted(.number.precision(.fractionLength(1))) ?? "--",
                    unit: nil
                )

                MetricTile(
                    title: "FMI",
                    value: fmi?.formatted(.number.precision(.fractionLength(1))) ?? "--",
                    unit: nil
                )
            }
            .clipShape(.rect(cornerRadius: 14))
        }
    }
}

private struct EmptyOverviewCard: View {
    var body: some View {
        ScaleCard {
            SectionHeader(title: "Composition", subtitle: "Awaiting first measurement")

            Text("Body composition data will appear here once the scale captures a finalized reading with height, age, and sex configured.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Recent History

private struct RecentHistoryCard: View {
    let measurements: [StoredMeasurement]
    let bodyComposition: (StoredMeasurement) -> BodyCompositionEstimate?

    var body: some View {
        ScaleCard {
            SectionHeader(title: "Recent", subtitle: "Last sessions")

            if measurements.isEmpty {
                Text("No saved sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(measurements.enumerated()), id: \.element.id) { index, measurement in
                        HistoryPreviewRow(
                            measurement: measurement,
                            bodyComposition: bodyComposition(measurement)
                        )

                        if index < measurements.count - 1 {
                            HairlineDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - History Measurement Card

private struct HistoryMeasurementCard: View {
    let measurement: StoredMeasurement
    let bodyComposition: BodyCompositionEstimate?

    var body: some View {
        ScaleCard {
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(measurement.timestamp, format: .dateTime.weekday(.abbreviated).day().month())
                            .font(.headline)
                        Text(measurement.timestamp, format: .dateTime.hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text("\(measurement.weightKg.formatted(.number.precision(.fractionLength(1)))) kg")
                        .font(.title2.weight(.light))
                        .monospacedDigit()
                }

                if bodyComposition != nil || measurement.impedance > 0 {
                    HairlineDivider()

                    HStack(spacing: 0) {
                        if let bodyComposition {
                            CompactMetric(
                                label: "Fat",
                                value: "\(bodyComposition.fatPercentage.formatted(.number.precision(.fractionLength(1))))%"
                            )
                            CompactMetric(
                                label: "Lean",
                                value: "\(bodyComposition.leanMassKg.formatted(.number.precision(.fractionLength(1)))) kg"
                            )
                        }
                        CompactMetric(
                            label: "Impedance",
                            value: "\(measurement.impedance.formatted(.number.precision(.fractionLength(0)))) ohm"
                        )
                    }
                }
            }
        }
    }
}

private struct HistoryPreviewRow: View {
    let measurement: StoredMeasurement
    let bodyComposition: BodyCompositionEstimate?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(measurement.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.subheadline)
                if let bodyComposition {
                    Text("\(bodyComposition.fatPercentage.formatted(.number.precision(.fractionLength(1))))% fat")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text("\(measurement.weightKg.formatted(.number.precision(.fractionLength(1)))) kg")
                .font(.body.weight(.light))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Shared Components

private struct InfoChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.03))
    }
}

private struct ScaleField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(fieldBackground)
        }
    }

    @ViewBuilder
    private var fieldBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(.white.opacity(0.02)), in: .rect(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                }
        }
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.5)
    }
}

@ViewBuilder
func SectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.subheadline.weight(.semibold))
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Card Container

struct ScaleCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .scaleGlassCardStyle()
    }
}

// MARK: - Background

struct ScaleSceneBackground: View {
    var body: some View {
        Color(red: 0.04, green: 0.04, blue: 0.05)
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(Color.accent.opacity(0.08))
                    .frame(width: 400, height: 300)
                    .blur(radius: 100)
                    .offset(y: -120)
            }
            .ignoresSafeArea()
    }
}

// MARK: - Accent Color

private extension Color {
    static let accent = Color(red: 0.35, green: 0.75, blue: 0.72)
}

// MARK: - View Modifiers

private extension View {
    @ViewBuilder
    func scaleGlassCardStyle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 20))
        } else {
            background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    }
            )
        }
    }

    @ViewBuilder
    func scalePrimaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
                .tint(Color(red: 0.35, green: 0.75, blue: 0.72))
        }
    }

    @ViewBuilder
    func scaleSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func scaleDestructiveButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass(.regular.tint(.red)))
        } else {
            buttonStyle(.bordered)
                .tint(.red)
        }
    }
}
