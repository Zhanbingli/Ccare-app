# Ccare

A privacy-first iOS app for chronic medication management. Helps users build reliable daily medication routines through smart reminders, adherence tracking, and health measurement logging.

## Features

### Home — Daily Check-in
- Single-surface dashboard showing due, overdue, snoozed, and upcoming doses
- One-tap Take / Skip / Snooze on hero card and timeline
- As-needed (PRN) medication quick-log section
- Quick feeling check-in and symptom quick-log
- Weekly adherence reflection card opening straight into the calendar
- Profile drawer for Medications, Emergency Info, Caregivers, and Settings

### Medications
- Add medications with camera-based OCR label scanning
- Scheduled and as-needed (PRN) modes
- Flexible scheduling: once daily, twice daily, three times daily, or custom times
- Inventory tracking with refill reminders and course duration alerts
- Search and categorized list (Active / As Needed / Needs Setup)

### Doctor Visits & Follow-Up
- Capture upcoming and past visits with consultation snapshots
- Visit-day medication actions and post-visit follow-up checks
- Hypertension and diabetes follow-up report foundations
- Symptom logging and AI-assisted symptom clarification flow
- Persistent follow-up agent surfacing reminders, drafts, and follow-up suggestions

### Insights
- 7-day and 30-day adherence rates at a glance
- Latest health measurement with quick-log entry
- Reminder coverage diagnostics (gaps, permission issues)
- Detailed trends, adherence calendar, and health history

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
- PDF export for health reports and hypertension follow-up reports
- Full app backup and restore

### AI Assistance (optional)
- Pluggable provider configuration (OpenAI-compatible and DeepSeek)
- AI-drafted visit questions and follow-up reports (hypertension, diabetes)
- Drafts persist locally so reviews resume across launches
- API key stored in Keychain; all AI features are off by default

### Privacy
- All data stored locally on device
- No account required, no cloud sync
- OCR suggestions require user confirmation before applying
- Core functionality works fully without an AI API key

## Tech Stack

| Layer | Implementation |
| --- | --- |
| UI | SwiftUI, Swift Charts, editorial calm design system (`Card`, `InsetPanel`, `AppBadge`, Typography) |
| Shell | Single-surface Home (`RootViewV2` + `DashboardView`) with profile drawer and modal sheets |
| Data | `DataStore` (ObservableObject) with debounced JSON persistence via Combine |
| Notifications | `UNUserNotificationCenter` with adaptive scheduling, snooze chains, and lifecycle alerts |
| Agents | Persistent `FollowUpAgentTask` state for follow-up preparation, safety flags, and adaptive reminder confirmations |
| Health | HealthKit import/export |
| AI | Pluggable provider layer (OpenAI-compatible, DeepSeek), Keychain-stored credentials |
| Export | PDF generation (health + hypertension follow-up), JSON backup/restore |
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
