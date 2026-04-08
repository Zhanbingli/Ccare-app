# Repository Guidelines

## Project Structure & Module Organization
`ChronicCare/` contains the app target. Keep app entry and shared infrastructure in top-level files such as `ChronicCareApp.swift`, `ContentView.swift`, `DataStore.swift`, `Models.swift`, and notification or integration helpers like `NotificationManager.swift`, `HealthKitManager.swift`, and `PDFGenerator.swift`. Put screen-level SwiftUI code in `ChronicCare/Views/`. Store localized strings in `ChronicCare/zh-Hans.lproj/`. Assets live in `ChronicCare/Assets.xcassets/`. Unit tests are in `ChronicCareTests/`; UI smoke tests are in `ChronicCareUITests/`.

## Build, Test, and Development Commands
Use Xcode 15+ with the `ChronicCare` scheme.

```bash
xcodebuild -scheme ChronicCare -sdk iphonesimulator build
xcodebuild -scheme ChronicCare -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
xcodebuild -scheme ChronicCare -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ChronicCareTests/ChronicCareTests/scheduleComponentsFromUserInfo
```

`build` validates the app target. `test` runs Swift Testing and UI tests. Use `-only-testing` for tight feedback when changing notification, persistence, or schedule logic.

## Coding Style & Naming Conventions
Match the existing Swift style: 4-space indentation, one primary type per file when practical, and `UpperCamelCase` for types with `lowerCamelCase` for properties and methods. Keep SwiftUI views noun-based (`DashboardView`), managers/service helpers explicit (`NotificationManager`, `AIService`), and user-facing strings wrapped in `NSLocalizedString`. There is no repo formatter or linter config, so rely on Xcode formatting and keep code consistent with nearby files.

## Testing Guidelines
This repo uses Swift Testing, not XCTest. Add focused `@Test` cases in `ChronicCareTests.swift`-style files and prefer descriptive method names such as `outstandingCountHonorsTakenLogPerSchedule`. Current coverage is light, so new work should add tests for `DataStore`, notification scheduling, badge math, and persistence migrations. Add or update `ChronicCareUITests` only for visible flow changes.

## Commit & Pull Request Guidelines
Recent history mixes plain summaries and prefixes like `feat:`. Prefer short imperative commits and standardize on `feat:`, `fix:`, or `refactor:` where possible, for example `fix: preserve deep link selection on active refresh`. PRs should describe behavior changes, list test coverage, link related issues, and include screenshots for SwiftUI UI changes. Call out localization, notification, or HealthKit entitlement impacts explicitly.
