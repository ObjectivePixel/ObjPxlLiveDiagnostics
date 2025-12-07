# Repository Guidelines

Concise contributor guide for maintaining the LiveDiagnosticViewer prototype and keeping iOS telemetry tooling consistent.

## Project Structure & Module Organization
- App lives in `prototype/RemindfulTelemetryVerify/RemindfulTelemetryVerify.xcodeproj` with SwiftUI sources under `RemindfulTelemetryVerify/` (UI, CloudKit client, schema helpers).
- Unit tests: `RemindfulTelemetryVerifyTests/`; UI tests: `RemindfulTelemetryVerifyUITests/`.
- `src/` is currently empty/reserved for future viewer modules; keep new runtime code here and mirror test coverage in a sibling `Tests` folder.
- `docs/` is free for design notes and operational runbooks; include dated updates when adding references.

## Build, Test, and Development Commands
- Open in Xcode for primary development: `open prototype/RemindfulTelemetryVerify/RemindfulTelemetryVerify.xcodeproj`.
- CLI build (adjust simulator as needed):  
  `xcodebuild -scheme RemindfulTelemetryVerify -destination "platform=iOS Simulator,name=iPhone 15" build`
- Run all tests (unit + UI):  
  `xcodebuild test -scheme RemindfulTelemetryVerify -destination "platform=iOS Simulator,name=iPhone 15"`
- Regenerate derived data if builds drift: delete `~/Library/Developer/Xcode/DerivedData/RemindfulTelemetryVerify*` then rebuild.

## Coding Style & Naming Conventions
- Swift/SwiftUI with 4-space indentation; favor `private`/`fileprivate` for helpers and `struct` over `class` where value semantics fit.
- Use clear async naming (`fetchAllRecords()`, `deleteAllRecords()`) and prefer `async/await` over completion handlers.
- UI components: keep one view per file; name with suffix `View` and avoid embedding logic beyond view state.
- Logs should be short and searchable; prefix debug prints with emoji tags already present (e.g., `🗑️`).

## Testing Guidelines
- Use XCTest; keep test names descriptive (`test_fetchAllRecordsReturnsNewestFirst`).
- Add UI tests when changing navigation or CloudKit flows; prefer deterministic data by stubbing `CKContainer` where possible.
- Before merging, run `xcodebuild test` on the primary simulator target; note any flakes and mark them with `XCTExpectFailure` only when justified.

## Commit & Pull Request Guidelines
- Follow short, imperative commit subjects mirroring history (e.g., `Add prototype`, `Update CloudKit client`); group related file changes.
- PRs should state scope, simulator/device tested, and any CloudKit container or entitlement changes; include screenshots for UI shifts.
- Link issues or TODOs in the description; keep open questions inline with the diff using code comments when context is not obvious.

## CloudKit & Environment Tips
- Default environment detection runs at launch; confirm you are in Development before deleting records.
- Avoid using personal iCloud containers; match the entitlements in `RemindfulTelemetryVerify.entitlements` and document any provisioning updates in `docs/`.
