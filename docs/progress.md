# Progress

## 2026-03-14

### Completed

- Created a fresh iOS 17+ SwiftUI application scaffold with XcodeGen.
- Added a modular source layout:
  - `App`
  - `BLE`
  - `ScalePacketDecoder`
  - `MeasurementModel`
  - `MeasurementStore`
  - `BodyCompositionCalculator`
  - `HealthKitExporter`
  - `UI`
- Implemented CoreBluetooth scanning for Xiaomi S400 advertisements.
- Confirmed the S400 reference path is Xiaomi MiBeacon `FE95` service data, not plain manufacturer data.
- Ported the core S400 decoding logic into Swift:
  - MiBeacon frame parsing
  - AES-CCM decryption for MiBeacon v4/v5
  - `0x6E16` measurement object parsing
  - field extraction for weight, impedance, low-frequency impedance, heart rate, and profile ID
- Implemented finalized measurement aggregation across multiple packets.
- Added local persistence with Core Data.
- Added SwiftUI screens for:
  - scanner/settings
  - live packet monitor
  - last measurement
  - history list
  - debug packet inspection
- Added optional body composition estimates.
- Added optional HealthKit export wiring.
- Added packet decoding documentation in `S400Scale/Docs/PacketDecoding.md`.
- Added a repository `.gitignore`.
- Fixed scan state handling so invalid scanner configuration no longer flashes into a started state and then falls back to a misleading `Scanning stopped.` status.
- Fixed HealthKit authorization handling so cancelled or denied permission sheets no longer appear as successful authorization, and added recovery guidance via App Settings.
- Seeded the app’s default profile with the current scale MAC and BLE bind key, and backfilled those defaults for older saved profiles with empty device fields.
- Added BLE console tracing for raw/decrypted packets plus aggregator wait-state logging to diagnose why a weigh-in is not finalizing.
- Validated against a real `0x30D9` S400 weigh-in session and confirmed the decoder is producing weight plus both impedance values correctly.
- Relaxed finalized-measurement detection so heart rate is optional; some real S400 sessions do not broadcast heart rate even when the weigh-in is otherwise complete.
- Extended HealthKit integration to request read access for height, birth date, and biological sex, then sync those fields into the app profile for local body-fat calculation.
- Switched body-composition defaults to athlete mode and exposed the formula mode in the profile UI so estimates can be compared against the standard path later.
- Reworked the SwiftUI shell into a cleaner multi-tab structure with dedicated Overview, History, Settings, and Debug tabs.
- Redesigned the primary interface into a minimalist card-based layout and moved raw packet details fully into the Debug tab.
- Adopted iOS 26 Liquid Glass styling for cards, buttons, and tab presentation with graceful material fallbacks for older OS versions.
- Removed the redundant action card from the overview and configured the app to attempt BLE scanning automatically on launch when the saved bind key and MAC are valid.

### Verified

- `xcodegen generate` succeeds.
- `xcodebuild -project S400Scale.xcodeproj -scheme S400Scale -destination 'generic/platform=iOS Simulator' build` succeeds.
- Unit tests pass against reference packet samples from the upstream decoder:
  - reference measurement packet
  - low-frequency impedance packet
  - finalized measurement aggregation flow
- Added regression coverage for `AppModel.startScanning()` to ensure missing or malformed bind keys surface their validation error without entering a transient scanning state.

### Current State

- The project builds and tests cleanly.
- The BLE path is validated against a real S400 session for packet decoding and aggregation, with heart rate confirmed to be optional in at least one live packet sequence.
- HealthKit can now populate profile demographics from the user’s Health data, enabling local body-fat estimates without manual entry when those Health fields exist.
- Body-fat estimation now defaults to the athlete-tuned path instead of the generic standard formula.
- The main user-facing flow is now optimized around a clean overview surface, with setup and debugging separated from everyday use.
- The app now auto-starts scanning on launch when its saved BLE configuration is valid, so routine use no longer requires a manual start action.
- The app currently timestamps measurements using packet receive time, matching the reference implementation behavior.

### Remaining / Follow-up

- Confirm whether additional packet heuristics are needed for noisy or repeated broadcast sessions.
- Decide whether the generated `S400Scale.xcodeproj` should remain committed or be regenerated from `project.yml` in CI/local workflows.
- Refine HealthKit UX and permission/error messaging if this is moving beyond a minimal prototype.
