import SwiftUI

struct DebugView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                ScaleSceneBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        ScaleCard {
                            SectionHeader(title: "Decoder Notes", subtitle: "Protocol details")

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Raw packets are FE95 Xiaomi MiBeacon service data. Manufacturer data is only shown when CoreBluetooth exposes it.")
                                    .font(.caption)
                                Text("Finalization requires mass, impedance, and low-frequency impedance. Heart rate is stored when present.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if model.debugPackets.isEmpty {
                            ScaleCard {
                                VStack(spacing: 8) {
                                    Text("No decoded packets")
                                        .font(.headline)
                                    Text("Start scanning and step on the scale.")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            }
                        } else {
                            ForEach(model.debugPackets) { packet in
                                DebugPacketCard(packet: packet)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Debug")
            .toolbarTitleDisplayMode(.large)
        }
    }
}

private struct DebugPacketCard: View {
    let packet: DebugPacketRecord

    var body: some View {
        ScaleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(packet.observedAt, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()

                    Spacer()

                    Text("Counter \(packet.packetCounter)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HairlineDivider()

                HStack(spacing: 16) {
                    debugMetric("Weight", value: formatValue(packet.weightKg, suffix: "kg"))
                    debugMetric("Impedance", value: formatValue(packet.impedance, suffix: "Ω"))
                    debugMetric("Low Freq", value: formatValue(packet.lowFrequencyImpedance, suffix: "Ω"))
                }

                HStack(spacing: 16) {
                    debugMetric("HR", value: packet.heartRate.map(String.init) ?? "--")
                    debugMetric("Device", value: packet.deviceId)
                    debugMetric("Model", value: packet.deviceModelID)
                }

                if let frequency = packet.frequencyHz {
                    Text("\(frequency.formatted(.number.precision(.fractionLength(2)))) Hz")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HairlineDivider()

                hexBlock(title: "Service Data", value: packet.rawServiceDataHex)
                hexBlock(title: "Decrypted", value: packet.decryptedPayloadHex)

                if let manufacturerDataHex = packet.manufacturerDataHex {
                    hexBlock(title: "Manufacturer", value: manufacturerDataHex)
                }
            }
        }
    }

    private func formatValue(_ number: Double?, suffix: String) -> String {
        guard let number else { return "--" }
        return "\(number.formatted(.number.precision(.fractionLength(1)))) \(suffix)"
    }

    @ViewBuilder
    private func debugMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func hexBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
