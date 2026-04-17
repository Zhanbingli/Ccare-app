import WidgetKit

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let nextDose: WidgetDoseEntry?
    let upcomingDoses: [WidgetDoseEntry]
    let todayTaken: Int
    let todayTotal: Int
}

struct NextDoseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDoseEntry {
        NextDoseEntry(
            date: Date(),
            nextDose: WidgetDoseEntry(
                medicationName: "Metformin",
                dose: "500mg",
                scheduledTime: Date(),
                medicationID: UUID()
            ),
            upcomingDoses: [],
            todayTaken: 2,
            todayTotal: 5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDoseEntry) -> Void) {
        completion(entryFromSharedData(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDoseEntry>) -> Void) {
        guard let data = WidgetDataProvider.read() else {
            let entry = NextDoseEntry(date: Date(), nextDose: nil, upcomingDoses: [], todayTaken: 0, todayTotal: 0)
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
            completion(timeline)
            return
        }

        let now = Date()
        var entries: [NextDoseEntry] = []

        // Generate an entry for now
        entries.append(makeEntry(from: data, at: now))

        // Generate entries at each upcoming dose time so the widget auto-updates
        for dose in data.upcomingDoses where dose.scheduledTime > now {
            entries.append(makeEntry(from: data, at: dose.scheduledTime))
        }

        // Refresh after the last dose, or in 15 minutes if no doses
        let nextRefresh: Date
        if let lastDose = data.upcomingDoses.last, lastDose.scheduledTime > now {
            nextRefresh = lastDose.scheduledTime.addingTimeInterval(60)
        } else {
            nextRefresh = now.addingTimeInterval(15 * 60)
        }

        let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
        completion(timeline)
    }

    private func entryFromSharedData(at date: Date) -> NextDoseEntry {
        if let data = WidgetDataProvider.read() {
            return makeEntry(from: data, at: date)
        }
        return NextDoseEntry(date: date, nextDose: nil, upcomingDoses: [], todayTaken: 0, todayTotal: 0)
    }

    private func makeEntry(from data: WidgetData, at date: Date) -> NextDoseEntry {
        // Find the next dose that hasn't passed relative to `date`
        let remaining = data.upcomingDoses.filter { $0.scheduledTime >= date }
        return NextDoseEntry(
            date: date,
            nextDose: remaining.first ?? data.upcomingDoses.first,
            upcomingDoses: data.upcomingDoses,
            todayTaken: data.todayTaken,
            todayTotal: data.todayTotal
        )
    }
}
