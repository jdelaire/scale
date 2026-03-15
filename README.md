# S400Scale

Minimal iOS 17+ app for scanning Xiaomi Body Composition Scale S400 BLE advertisements, decoding measurements locally, storing them on device, and optionally exporting finalized results to Apple Health.

## Decoder Source Of Truth

The packet format and scaling in this project come from:

- [export2garmin](https://github.com/RobertWojtowicz/export2garmin)
- [xiaomi-ble](https://github.com/Bluetooth-Devices/xiaomi-ble)

`export2garmin` delegates S400 decoding to `xiaomi-ble`, so both repositories were used to reproduce the same MiBeacon V5 parsing and `0x6E16` S400 payload decoding logic in Swift.

## Local Requirements

The S400 payload is encrypted. As in the upstream reference implementation, this app needs:

- the scale BLE bind key
- the scale BLE MAC address

You can retrieve both from Xiaomi Home using the workflow documented in [PacketDecoding.md](./S400Scale/Docs/PacketDecoding.md).

Short version:

1. Add the S400 to Xiaomi Home and complete at least one measurement
2. Run [Xiaomi Cloud Tokens Extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) with the same Xiaomi account and region
3. Find your `Xiaomi Body Composition Scale S400` device in the output
4. Copy its MAC address and BLE encryption key
5. Put them into `.env` as `DEFAULT_SCALE_MAC_ADDRESS` and `DEFAULT_BIND_KEY_HEX`

Different tools use different names for the same secret. In this repo:

- `BLE key`
- `bind key`
- `BLE encryption key`

all refer to the same 16-byte key used to decrypt the scale advertisements.

## Local BLE Secrets

The default bind key and scale MAC are intentionally not hardcoded in Swift source anymore.

1. Copy `.env.example` to `.env`
2. Set your own values for:
   - `DEFAULT_BIND_KEY_HEX`
   - `DEFAULT_SCALE_MAC_ADDRESS`
3. Keep `.env` local only. It is ignored by git and should never be committed.

Expected formats:

- `DEFAULT_BIND_KEY_HEX`: 32 hexadecimal characters
- `DEFAULT_SCALE_MAC_ADDRESS`: `AA:BB:CC:DD:EE:FF`

During each build, the app generates [BuildSecrets.swift](./S400Scale/Generated/BuildSecrets.swift) from `.env` in a pre-build step. If `.env` is missing or malformed, the build fails fast with a clear error.

Important operational notes:

- If you remove and re-add the scale in Xiaomi Home, Xiaomi may generate a new BLE key. Update `.env` if decoding suddenly stops working.
- When testing this app, fully quit Xiaomi Home first. The scale often connects to Xiaomi Home immediately, which prevents local apps from seeing the short encrypted broadcast window reliably.

Because that generated file lives in the source tree for Xcode compilation, reset it back to the placeholder version before committing or pushing:

```bash
SRCROOT="$PWD" ./scripts/reset_build_secrets_placeholder.sh
```

Before publishing the repository, verify these files are not carrying your real values:

- `.env`
- `S400Scale/Generated/BuildSecrets.swift`

## Project Layout

- `S400Scale/BLE`: CoreBluetooth scanner and session aggregation
- `S400Scale/ScalePacketDecoder`: MiBeacon parsing, AES-CCM, S400 field extraction
- `S400Scale/MeasurementModel`: measurement and settings models
- `S400Scale/MeasurementStore`: Core Data persistence
- `S400Scale/BodyCompositionCalculator`: local body composition estimates
- `S400Scale/HealthKitExporter`: Apple Health export
- `S400Scale/UI`: SwiftUI screens

## Build

```bash
cp .env.example .env
xcodegen generate
xcodebuild -project S400Scale.xcodeproj -scheme S400Scale -destination 'platform=iOS Simulator,name=iPhone 16' build
```
