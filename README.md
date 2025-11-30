# ChronicCare (Ccare)

ChronicCare is a SwiftUI app for medication reminders, health measurements, and actionable insights. It is offline-first, resilient to notification edge cases, and offers heuristic (non-clinical) effectiveness signals with clear confidence cues.

## Highlights

- **Focused shell**: Home (dashboard + insights), Medications, More (tools/settings). Consistent design system with cards, chips, and dynamic typography.
- **Resilient reminders**: time-sensitive categories, snooze without stacking, grace-aware badges, orphan cleanup, and auto-rescheduling on app foreground/day/timezone changes.
- **Local-first data**: debounced JSON persistence, one-final-status per med/time/day, backup/restore, and PDF export.
- **Insights that deep-link**: Smart Insights surface skips/low adherence/time drift and jump straight to the medication list for action.
- **Heuristic effectiveness with confidence**: per-dose deltas + moving averages + adherence gate, now with trimmed medians, bootstrap CIs, and confidence dampening when evidence is weak.
- **HealthKit & sharing**: import 30-day measurements, export to PDF, share backups; haptics, grace period, and effectiveness sensitivity are user-tunable.
- **Custom categories**: built-in classes plus user-defined category names for medications.

## Technology Stack

| Layer | Technology |
| --- | --- |
| UI | SwiftUI, SF Symbols, custom components in `DesignSystem.swift` |
| Data | `DataStore` (Combine + Codable JSON persistence) |
| Notifications | `UNUserNotificationCenter`, time-sensitive categories, suppression cache, orphan cleanup |
| Charts | Swift Charts (iOS 16+) for KPI grids and trend visuals |
| Integrations | HealthKit read/write, PDFKit report generation, Share sheet wrappers |
| Feedback | Haptics helpers (`UINotificationFeedbackGenerator`, `UIImpactFeedbackGenerator`) |
| Architecture | Environment-object store + domain helpers (MVVM-lite) |

## Project Layout

```
ChronicCare/
 ├── ChronicCareApp.swift        # App entry: injects DataStore, registers notification delegate
 ├── ContentView.swift           # Tab shell + scene-phase scheduling refresh + deep-links
 ├── DataStore.swift             # Actor-like store: persistence, stats, intake upserts
 ├── Models.swift                # Measurement, Medication, IntakeLog definitions
 ├── Views/                      # SwiftUI screens (Dashboard, Medications, More, Trends)
 ├── NotificationManager.swift   # Scheduling, snoozes, suppression, badge updates, orphan cleanup
 ├── NotificationHandler.swift   # Responds to notification actions (taken/snooze/skip)
 ├── EffectivenessEvaluator.swift# Heuristic medication-effectiveness evaluation with CIs
 ├── HealthKitManager.swift      # Authorization, import/export helpers
 ├── PDFGenerator.swift          # PDF report generation (measurements, meds, adherence)
 ├── DesignSystem.swift          # Reusable Card, TintedCard, Section headers, chips, action tiles
 ├── Typography.swift            # Rounded font definitions with dynamic type bounds
 └── AppBackground.swift         # Gradient background convenience view
```

## Core Features

- **Data flow & persistence**: Loads JSON snapshots on launch, debounced saves, guarantees a single final intake per med/time/day, and trims backups.
- **Notifications**: Deterministic IDs (`medID_yyyyMMdd_HH_MM`), suppression cache, snooze IDs per med/time, badge respects grace and snooze, cleans orphaned pending/delivered requests, rehydrates on scene changes/day/timezone.
- **Measurements & Trends**: Supports BP, glucose (mg/dL↔mmol/L), weight, heart rate. Dashboard shows recents; EnhancedTrends provides KPIs/charts/insights with goal shading and out-of-range markers.
- **Medications**: Filters (All/Active/Paused/Attention), reminder toggles, latest intake state, effectiveness pill. Custom category names supported.
- **Smart Insights**: Skips/low adherence/time drift/effectiveness alerts with deep-link actions to the medication list so users can adjust reminders quickly.
- **Effectiveness (heuristic)**: Per-dose pre/post windows, 14-day moving deltas, adherence gate, trimmed medians, bootstrap 90% CI, confidence dampening when evidence is weak; unsupported/custom categories return “not applicable”.
- **More hub**: Quick actions (HealthKit import/export, PDF, backup/restore, clear), preferences (haptics, grace, effectiveness knobs), goals (glucose/HR/BP), knowledge (“How it works”), and privacy/about.
- **Localization & accessibility**: English + zh-Hans, dynamic type `.medium ... .accessibility5`, accessible values on rings/badges.

## Build & Run

```bash
xcodebuild -scheme ChronicCare -sdk iphonesimulator build
```

Requirements:
- Xcode 15+, iOS 16+ deployment target.
- Enable HealthKit entitlement and set `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in `Info.plist`.

## Maintenance Notes

- **Schema changes**: Update `DataStore` load/save and migrate persisted JSON when models change.
- **Notification horizon**: Default 14 days; adjust if users need longer planning.
- **Algorithm tuning**: `EffectivenessEvaluator.settings()` controls thresholds/min samples; bootstrap iterations/trim can be adjusted for performance vs. stability.
- **HealthKit dedupe**: Current proximity-based dedupe fits sparse data; harden for dense imports if needed.
- **Testing**: Add coverage for notification suppression/cleanup, badge math, adherence stats, and effectiveness verdicts (including CIs).

## Disclaimer

ChronicCare provides heuristic insights for self-management; it is not a medical device. Medication-effectiveness verdicts are non-clinical and should not replace professional medical advice.
