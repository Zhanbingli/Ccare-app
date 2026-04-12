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

Requirements: Xcode 15+, iOS 16+ deployment target. HealthKit entitlement must be enabled. Notification permission required for reminder testing.

## Architecture

**SwiftUI + Environment Object store (MVVM-lite).** No third-party dependencies. Privacy-first: all data stored locally on device.

### Data layer

- `DataStore` (`@MainActor ObservableObject`) is the single source of truth, injected via `.environmentObject()` at the app root. It owns `[Measurement]`, `[Medication]`, `[IntakeLog]`, `EmergencyInfo?`, and `[CaregiverContact]` with debounced (300ms) JSON persistence to the Documents directory via Combine. All mutations go through DataStore's public methods which enforce invariants (e.g., one final intake status per med/time/day).

- JSON files in Documents: `measurements.json`, `medications.json`, `intake_logs.json`, `emergency_info.json`, `caregivers.json`. On launch, DataStore loads all files, then schedules notifications for active medications and cleans orphans. Scene-phase changes to `.active` re-trigger scheduling and orphan cleanup.

- `BackupManager` handles full app backup/restore (versioned `AppBackup` struct including medication images). `PDFGenerator` exports health reports.

### Notifications

- `NotificationManager` is a singleton (`shared`) that handles all `UNUserNotificationCenter` interactions: scheduling with deterministic IDs, snooze variants, same-day suppression cache, orphan cleanup, and badge computation. Called from MainActor context (not an actor).

- `NotificationHandler` (`UNUserNotificationCenterDelegate`) processes notification action responses (taken/snooze/skip) and holds a weak reference to `DataStore` set during `onAppear`.

- `AdaptiveReminderEngine` computes risk-based reminder strategies from adherence profiles (miss rate, snooze rate, delay patterns).

### Views

Three-tab shell in `ContentView`: **Today** (DashboardView — daily check-in for due/overdue/snoozed doses), **Medications** (MedicationsView — medication management with deep-link support), **Insights** (InsightsView — trends, adherence, and analytics). First launch shows `OnboardingView` (gated by `hasCompletedOnboarding` UserDefaults key).

Supporting views: `HealthView`, `MeasurementsView`, `EnhancedTrendsView` (KPI grids + Swift Charts), `ProfileView`, `CaregiversView`, `EmergencyInfoView`, `DrugInteractionView`, `AdherenceCalendarView`.

Deep-linking from insights uses `NotificationCenter.default` posts with name `"openMedicationDetail"`.

### Design system

`DesignSystem.swift` provides reusable `Card` view wrapper, `AppBackground`, and `Typography`/`AppFontStyle` for consistent styling. All views use these shared components.

### Integrations

- `HealthKitManager` — import/export for health measurements.
- `MedicationOCRService` — camera-based OCR for medication label scanning (suggestions only; user must confirm).
- `AIService` — API key stored in Keychain via `KeychainHelper`. Not required for core functionality.

## Localization

English + zh-Hans (`zh-Hans.lproj/Localizable.strings`). Strings use `NSLocalizedString(_:comment:)` directly (no `.strings` catalog). When adding user-facing text, always wrap it in `NSLocalizedString`.

## Testing

Tests use Swift Testing framework (`import Testing`, `@Test`, `#expect`), **not** XCTest. The test target is `ChronicCareTests`. Current coverage is minimal — focused on notification helper logic. Use `-only-testing` for tight feedback loops.

## Key Conventions

- Notification IDs are deterministic: `"\(medID)_\(yyyyMMdd)_\(HH)_\(MM)"` for scheduled, with snooze variants appending `_snooze`.
- `IntakeLog.scheduleKey` is `"HH:mm"` format, used to match logs to specific dose times.
- `Medication.timesOfDay` is `[DateComponents]` with hour/minute only.
- Backward compatibility: `Medication` decoder handles legacy single `timeOfDay` field migrating to `timesOfDay` array.
- `MedicationCategory` has correlated measurement types (e.g., antihypertensive → blood pressure + heart rate) used for context in detail views.
- UserDefaults keys: `hapticsEnabled`, `gracePeriodMinutes`, `hasCompletedOnboarding`, goal keys for glucose/HR/BP ranges.

## Commit Style

Use short imperative commits with conventional prefixes: `feat:`, `fix:`, `refactor:`. Call out localization, notification, or HealthKit entitlement impacts in PR descriptions.
