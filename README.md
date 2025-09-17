# ChronicCare (Ccare)

ChronicCare is a SwiftUI reference application for chronic-condition self-management. It combines modern iOS UI patterns, offline-first storage, notification orchestration, HealthKit integration, and analytics to help users track measurements, medications, adherence, and heuristic effectiveness signals.

## Highlights

- **SwiftUI-first UI** with a tabbed shell (Dashboard, Measurements, Trends, Medications, More) and a custom design system (cards, chips, progress rings, typography helpers).
- **Local-first persistence** via a shared `DataStore` that saves JSON snapshots, debounces write operations, and guarantees one final intake status per med/time/day.
- **Robust notification handling**: time-sensitive categories, same-day suppression, snooze windows, badge updates, and scene-phase rehydration.
- **Analytics & charts** powered by Swift Charts, adaptive goal ranges, out-of-range highlighting, and contextual insight cards.
- **Medication effectiveness engine** that blends per-dose deltas, moving averages, adherence thresholds, and a smoothed confidence score.
- **HealthKit, PDF, and backup flows** for importing/exporting samples, generating summary reports, and round-tripping data safely.
- **Preference-driven UX** for haptics, overdue grace, glucose units, and effectiveness sensitivity modes (conservative/balanced/aggressive).

## Technology Stack

| Layer | Technology |
| --- | --- |
| UI | SwiftUI, SF Symbols, custom components in `DesignSystem.swift` |
| Data | `DataStore` (Combine + Codable JSON persistence) |
| Notifications | `UNUserNotificationCenter`, time-sensitive categories, suppression cache |
| Charts | Swift Charts (iOS 16+) for KPI grids and trend visuals |
| Integrations | HealthKit read/write, PDFKit report generation, Share sheet wrappers |
| Feedback | Haptics helpers (`UINotificationFeedbackGenerator`, `UIImpactFeedbackGenerator`) |
| Architecture | Environment-object store + domain helpers (MVVM-lite) |

## Project Layout

```
ChronicCare/
 ├── ChronicCareApp.swift        # App entry: injects DataStore, registers notification delegate
 ├── ContentView.swift           # Tab shell + scene-phase scheduling refresh
 ├── DataStore.swift             # Actor-like store: persistence, stats, intake upserts
 ├── Models.swift                # Measurement, Medication, IntakeLog definitions
 ├── Views/                      # SwiftUI screens (Dashboard, Measurements, Trends, Medications, Profile)
 ├── NotificationManager.swift   # Scheduling, snoozes, suppression, badge updates
 ├── NotificationHandler.swift   # Responds to notification actions (taken/snooze/skip)
 ├── EffectivenessEvaluator.swift# Heuristic medication-effectiveness evaluation
 ├── HealthKitManager.swift      # Authorization, import/export helpers
 ├── PDFGenerator.swift          # PDF report generation (measurements, meds, adherence)
 ├── DesignSystem.swift          # Reusable Card, TintedCard, Section headers, chips, action tiles
 ├── Typography.swift            # Rounded font definitions with dynamic type bounds
 └── AppBackground.swift         # Gradient background convenience view
```

## Core Feature Maps

### Data Flow & Persistence
- `DataStore` loads JSON snapshots on launch, publishes updates with `@Published`, and saves debounced snapshots using background tasks.
- `upsertIntake` removes any existing log for the same medication/day/schedule slot before writing, ensuring adherence charts and suppression caches remain coherent.

### Notifications
- Registers custom notification category (`MED_REMINDER`) with actionable buttons (Taken, Snooze 10/30/60, Skip).
- Uses deterministic IDs (`medID_yyyyMMdd_HH_MM`) and a suppression cache so repeat notifications are silenced after a user acts.
- Reschedules a rolling two-week horizon on app activation to keep reminders current without constant background execution.
- Snooze actions create a single timer-based notification per medication-time pair (`snooze_<UUID>_HH_MM`), avoiding stacking alerts and preserving schedule keys for analytics.

### Measurements & Trends
- Supports blood pressure, blood glucose (mg/dL ↔ mmol/L), weight, and heart rate.
- Dashboard shows grouped measurements with daily section headers; Trends provides KPI grid + chart + insight card.
- Charts adapt per type: BP median bands + thresholds, goal-range shading, out-of-range markers, and axis tick auto-scaling.

### Medications
- Horizontal filter chips (All / Active / Paused / Attention) with badge counts; “Attention” flags paused reminders or low-confidence meds.
- Each row includes status capsule, dose/times, latest intake state, and an effectiveness pill (verdict + confidence).
- Toggle prompts for notification authorization, schedules/cancels reminders instantly, and refreshes badge counts.

### Medication Effectiveness Algorithm
Implemented in `EffectivenessEvaluator`:

1. **Categorization**: currently supports antihypertensive (blood pressure) and antidiabetic (blood glucose); unspecified meds bypass evaluation.
2. **Per-dose window analysis**: compare pre-dose and post-dose measurements (BP: ≤2h prior & 1–6h after; glucose: ≤1h prior & 1–3h after) and store median deltas.
3. **Rolling averages**: compare 14-day moving means to the prior 14-day window.
4. **Adherence gating**: require recent adherence above configurable threshold (default 60%).
5. **Sensitivity modes** (`eff.mode`): conservative/balanced/aggressive adjust delta thresholds and minimum samples.
6. **Verdict rules**: if enough samples and either per-dose or moving deltas show improvement (negative) with good adherence → Likely Effective; otherwise degrade to Unclear or Likely Ineffective.
7. **Smoothed confidence**: blend normalized delta magnitudes with sample ratio and adherence penalty to produce a stable 0–100% confidence.
8. **Surfacing**: results power the medication list badges and the Trends “Medication Effectiveness” overview card (counts + top 3 meds).

### Profile (More) Hub
- Summary cards (counts, adherence, next medication) + status card (notification/HealthKit state).
- Quick Actions card with horizontally scrolling pill buttons (connect HealthKit, import/export, restore, clear).
- Preferences card (haptics, overdue grace, glucose units, effectiveness mode/sample).
- Goals card (glucose, heart rate, blood pressure steppers inside disclosure groups).
- Data & Backups card with export/restore/clear actions.
- Knowledge card (How It Works breakdown) and About card (privacy statement).

## Localization & Accessibility
- English default with `zh-Hans` localization for UI strings.
- Typography uses rounded system fonts with dynamic type bounds `.medium ... .accessibility5`.
- Visual components emphasize color contrast, capsule badges include text, and progress rings expose accessibility values.

## Build & Run

```bash
xcodebuild -scheme ChronicCare -sdk iphonesimulator build
```

Requirements:
- Xcode 15+, iOS 16+ deployment target.
- Enable HealthKit entitlement and provide `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in `Info.plist`.

## Maintenance Notes

- **Data schema changes**: update `DataStore` load/save paths and consider migrations when altering models.
- **Notification horizon**: `NotificationManager` schedules fourteen days ahead; adjust if user base expects longer planning windows.
- **Algorithm tuning**: tweak thresholds in `EffectivenessEvaluator.settings()`; expose additional knobs via preferences if needed.
- **HealthKit dedupe**: current proximity-based dedupe suits sparse samples. Strengthen if importing high-frequency data sets.
- **Testing**: add unit tests for adherence calculations, notification suppression, and effectiveness verdicts to avoid regressions.

## Engineering Update · September 2025

This milestone focused on closing the reliability gap between ChronicCare’s reminders and production-grade medication apps while polishing the daily workflows that sit on top of them.

### 1. Reminders That Stay in Sync with Reality
- **Two-week scheduling horizon**: `NotificationManager` now regenerates reminders 14 days out, ensuring patients who rarely foreground the app never age out of alerts.
- **Schedule-aware snoozes**: every notification carries its hour/minute payload, and snoozed alerts use deterministic IDs (`snooze_<medID>_HH_MM`). When a user snoozes from the lock screen we can still map the action back to the right dose, deduplicate follow-ups, and keep badge math exact.
- **Regression safety net**: lightweight unit tests cover schedule metadata extraction, snooze identifiers, and outstanding-count calculation, protecting these paths during future refactors.

### 2. Medication Cards Built for Scanning
- Cards adopt a clean hierarchy: name + reminder state up top, dosage and notes mid-card, and a right-aligned footer that pairs the latest intake badge with the effectiveness verdict and confidence.
- Time chips and reminder toggles are grouped for quick scanning, while Edit/Swipe affordances (and the noisy table separators) are removed to avoid accidental destructive actions during high-stress moments.

### 3. Clearer Guidance in More ▸ How It Works
- The knowledge card is now four DisclosureGroups (Reminders, Adherence Tracking, Trend Charts, Medication Effectiveness) with concise, localized bullets so new users understand how automation behaves before trusting it.

### 4. Less Friction When Capturing Data
- Add Medication and Add Measurement forms no longer pre-fill sample values—users start with blank fields, so there’s no risk of saving placeholder data when multitasking.
- Photo removal in the edit sheet updates instantly, preventing the “Remove” button from feeling broken.

### 5. What’s Next
Upcoming tasks include background refreshing via `BGAppRefreshTask`, Siri Shortcut exports to Calendar/Reminders for alarm-style redundancy, and deeper HealthKit reconciliation for high-frequency sources.

## Disclaimer

ChronicCare is an educational sample application, not a medical device. Medication-effectiveness verdicts are heuristic and should not replace professional medical advice.
