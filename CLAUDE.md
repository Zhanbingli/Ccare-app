# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build for simulator
xcodebuild -scheme ChronicCare -sdk iphonesimulator build

# Run all tests
xcodebuild -scheme ChronicCare -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test (Swift Testing framework)
xcodebuild -scheme ChronicCare -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ChronicCareTests/ChronicCareTests/scheduleComponentsFromUserInfo
```

Requirements: Xcode 15+, iOS 16+ deployment target. HealthKit entitlement must be enabled.

## Architecture

**SwiftUI + Environment Object store (MVVM-lite).** No third-party dependencies.

- `DataStore` (`@MainActor ObservableObject`) is the single source of truth, injected via `.environmentObject()` at the app root. It owns `[Measurement]`, `[Medication]`, and `[IntakeLog]` arrays with debounced JSON persistence to the Documents directory. All mutations go through DataStore's public methods which enforce invariants (e.g., one final intake status per med/time/day).

- `NotificationManager` is a singleton (`shared`) that handles all `UNUserNotificationCenter` interactions: scheduling with deterministic IDs (`medID_yyyyMMdd_HH_MM`), snooze variants, same-day suppression cache, orphan cleanup, and badge computation. It is **not** an actor — called from MainActor context.

- `NotificationHandler` (`UNUserNotificationCenterDelegate`) processes notification action responses (taken/snooze/skip) and holds a weak reference to `DataStore` set during `onAppear`.

- **Views** follow the three-tab shell in `ContentView`: Today (DashboardView — pure action panel), Health (HealthView — medication management + data/trends), Settings (ProfileView). `EnhancedTrendsView` provides KPI grids and charts. Deep-linking from insights uses `NotificationCenter.default` posts with name `"openMedicationDetail"`.

## Data Flow

JSON files in Documents: `measurements.json`, `medications.json`, `intake_logs.json`. Changes are debounced (300ms) via Combine before writing. On launch, DataStore loads all three, then schedules notifications for active medications and cleans orphans. Scene-phase changes to `.active` re-trigger scheduling and orphan cleanup.

## Localization

English + zh-Hans (`zh-Hans.lproj/`). Strings use `NSLocalizedString` directly (no `.strings` catalog). When adding user-facing text, wrap it in `NSLocalizedString(_:comment:)`.

## Testing

Tests use Swift Testing framework (`import Testing`, `@Test`, `#expect`), not XCTest. The test target is `ChronicCareTests`. Current coverage is minimal — focused on notification helper logic.

## Key Conventions

- Notification IDs are deterministic: `"\(medID)_\(yyyyMMdd)_\(HH)_\(MM)"` for scheduled, with snooze variants appending `_snooze`.
- `IntakeLog.scheduleKey` is `"HH:mm"` format, used to match logs to specific dose times.
- `Medication.timesOfDay` is `[DateComponents]` with hour/minute only.
- UserDefaults keys: `hapticsEnabled`, `gracePeriodMinutes`, goal keys for glucose/HR/BP ranges.
- Backward compatibility: `Medication` decoder handles legacy single `timeOfDay` field migrating to `timesOfDay` array.
