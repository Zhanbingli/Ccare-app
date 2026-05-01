# Ccare

A privacy-first iOS app for chronic medication management. Helps users build reliable daily medication routines through smart reminders, adherence tracking, and health measurement logging.

## Features

### Today — Daily Check-in
- Task-first surface showing due, overdue, snoozed, and upcoming doses
- One-tap Take / Skip / Snooze actions on both hero card and timeline
- As-needed (PRN) medication quick-log section
- Real-time progress tracking with completion summary

### Medications
- Add medications with camera-based OCR label scanning
- Scheduled and as-needed (PRN) modes
- Flexible scheduling: once daily, twice daily, three times daily, or custom times
- Inventory tracking with refill reminders and course duration alerts
- Drug interaction warnings and daily safety checks
- Search and categorized list (Active / As Needed / Needs Setup)

### Insights
- 7-day and 30-day adherence rates at a glance
- Latest health measurement with quick-log entry
- Reminder coverage diagnostics (gaps, permission issues)
- Navigation to detailed trends, adherence calendar, and health history

### Smart Notifications
- Adaptive reminder engine that adjusts strategy based on adherence patterns
- Deterministic notification scheduling with iOS 64-notification budget management
- Snooze with escalation (configurable limits per medication)
- Follow-up reminders for missed doses
- Refill and course-end lifecycle alerts
- Caregiver notifications after consecutive missed days
- Badge count reflecting pending actionable doses

### Health Tracking
- Blood pressure, blood glucose, weight, and heart rate logging
- Glucose unit preference (mg/dL or mmol/L)
- Goal ranges with out-of-range highlighting
- Medication-linked health trends in detail views
- Optional HealthKit import/export

### Safety & Support
- Emergency information card (conditions, allergies, emergency contacts)
- Caregiver contact management with missed-dose notification opt-in
- PDF health report export
- Full app backup and restore

### Privacy
- All data stored locally on device
- No account required, no cloud sync
- OCR suggestions require user confirmation before applying
- Optional AI features — core functionality works without API key

## Tech Stack

| Layer | Implementation |
| --- | --- |
| UI | SwiftUI, Swift Charts, custom design system (`Card`, `InsetPanel`, `AppBadge`) |
| Data | `DataStore` (ObservableObject) with debounced JSON persistence via Combine |
| Notifications | `UNUserNotificationCenter` with adaptive scheduling, snooze chains, and lifecycle alerts |
| Health | HealthKit import/export |
| Export | PDF generation, JSON backup/restore |
| Localization | English and Simplified Chinese (`zh-Hans`) |
| Testing | Swift Testing framework |

## Build

Open the project in Xcode and run the `ChronicCare` scheme.

```bash
xcodebuild -scheme ChronicCare -sdk iphonesimulator build
```

Requirements:

- Xcode 15+
- iOS 16+ deployment target
- HealthKit entitlement enabled

## Disclaimer

Ccare is a self-management support tool. It is not a medical device, does not diagnose conditions, and does not provide medical advice. Medication changes should always be discussed with a healthcare provider.
