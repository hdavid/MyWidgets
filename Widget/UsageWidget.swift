import WidgetKit
import SwiftUI

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: UsageStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // Weather-widget pattern: WidgetKit wakes us, we fetch our own data.
        // If the shared snapshot is fresh (the app just wrote it), reuse it;
        // otherwise self-fetch and persist for the app/menu panel to reuse.
        DispatchQueue.global(qos: .userInitiated).async {
            let previous = UsageStore.load()
            var snapshot = previous
            let age = previous?.generatedDate.map { Date().timeIntervalSince($0) } ?? .infinity
            if age > 180 {
                if let fresh = SelfFetch.refresh(previous: previous) {
                    UsageStore.save(fresh)
                    snapshot = fresh
                }
            }
            let entry = UsageEntry(date: Date(), snapshot: snapshot)
            let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Family layouts

struct UsageMediumView: View {
    let snapshot: Snapshot?
    var body: some View {
        if let snap = snapshot {
            let bestID = Ranking.bestAccountID(snap.accounts)
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader(compact: true, tight: true)
                ForEach(snap.accounts) { acc in
                    Spacer(minLength: 6)
                    AccountRow(account: acc, isBest: acc.id == bestID, compact: true, tight: true)
                }
                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            EmptyStateView()
        }
    }
}

struct UsageLargeView: View {
    let snapshot: Snapshot?
    var body: some View {
        if let snap = snapshot {
            let bestID = Ranking.bestAccountID(snap.accounts)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Claude usage").font(.system(size: 14, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(UsageStore.ageText(from: snap.generatedDate))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                ColumnHeader(tight: true)
                ForEach(snap.accounts) { acc in
                    Spacer(minLength: 4)
                    AccountRow(account: acc, isBest: acc.id == bestID, tight: true)
                }
                Spacer(minLength: 4)
            }
        } else {
            EmptyStateView()
        }
    }
}

struct UsageSmallView: View {
    let snapshot: Snapshot?
    var body: some View {
        if let snap = snapshot, let best = Ranking.best(snap.accounts) {
            VStack(alignment: .leading, spacing: 6) {
                Text("use").font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(best.cli).font(.system(size: 15, weight: .bold, design: .monospaced))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11)).foregroundStyle(.green)
                }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 8) {
                    RingGauge(title: "5h", gauge: best.fiveHour, size: 40)
                    RingGauge(title: "Week", gauge: best.week, size: 40)
                    RingGauge(title: "Fable", gauge: best.fable, size: 40)
                }
                Spacer(minLength: 0)
                Text(UsageStore.ageText(from: snap.generatedDate))
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        } else {
            EmptyStateView()
        }
    }
}

// MARK: - Widget

struct ClaudeUsageWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: UsageEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: UsageSmallView(snapshot: entry.snapshot)
            case .systemLarge: UsageLargeView(snapshot: entry.snapshot)
            default: UsageMediumView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsageWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("5h / weekly / Fable quota for each Claude account.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
