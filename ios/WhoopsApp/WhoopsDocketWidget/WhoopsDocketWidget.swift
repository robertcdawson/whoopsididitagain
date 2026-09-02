import SwiftUI
import WidgetKit

@main
struct WhoopsDocketWidgetBundle: WidgetBundle {
    var body: some Widget {
        WhoopsDocketWidget()
    }
}

struct WhoopsDocketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WhoopsWidgetConstants.kind, provider: DocketTimelineProvider()) {
            entry in
            DocketWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.97, green: 0.95, blue: 0.89)
                }
        }
        .configurationDisplayName("Today's docket")
        .description("Complete PT and wind-down items without opening WHOOPs.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct DocketWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedDocketSnapshot?
}

struct DocketTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DocketWidgetEntry {
        DocketWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DocketWidgetEntry) -> Void) {
        completion(DocketWidgetEntry(date: .now, snapshot: loadSnapshot() ?? .placeholder))
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<DocketWidgetEntry>) -> Void
    ) {
        let entry = DocketWidgetEntry(date: .now, snapshot: loadSnapshot())
        let refresh =
            Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? .now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadSnapshot() -> SharedDocketSnapshot? {
        try? SharedDocketStore.live()?.effectiveSnapshot()
    }
}

private struct DocketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DocketWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 3 : 8) {
                header(snapshot)
                if visibleItems(snapshot).isEmpty {
                    Text(snapshot.items.isEmpty ? "nothing committed today." : "all done.")
                        .font(.system(.caption, design: .serif).italic())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleItems(snapshot)) { item in
                        itemRow(item, day: snapshot.day)
                    }
                }
                if family != .accessoryRectangular {
                    Spacer(minLength: 0)
                    Text(progress(snapshot))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .widgetURL(URL(string: "whoops://today"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHOOPS · TODAY")
                    .font(.caption2.weight(.bold))
                Text("Open WHOOPs once to publish today's docket.")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "whoops://today"))
        }
    }

    private func header(_ snapshot: SharedDocketSnapshot) -> some View {
        HStack(spacing: 4) {
            Text("WHOOPS · TODAY")
                .font(.caption2.weight(.bold))
                .tracking(0.4)
            Spacer(minLength: 0)
            if family != .accessoryRectangular {
                Text(shortDay(snapshot.day))
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func itemRow(_ item: SharedDocketItem, day: String) -> some View {
        Button(intent: CompleteDocketItemIntent(item: DocketItemEntity(item: item, day: day))) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: family == .accessoryRectangular ? 14 : 18, weight: .medium))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(
                            .system(
                                family == .accessoryRectangular ? .caption2 : .caption,
                                design: .serif
                            ).weight(.semibold)
                        )
                        .lineLimit(family == .systemMedium ? 2 : 1)
                    if family == .systemMedium, let tag = item.tag {
                        Text(tag)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete \(item.title)")
    }

    private func visibleItems(_ snapshot: SharedDocketSnapshot) -> [SharedDocketItem] {
        let incomplete = snapshot.items.filter {
            !$0.isCompleted && $0.supportsOneTapCompletion
        }
        switch family {
        case .systemMedium: return Array(incomplete.prefix(3))
        default: return Array(incomplete.prefix(1))
        }
    }

    private func progress(_ snapshot: SharedDocketSnapshot) -> String {
        let complete = snapshot.items.filter(\.isCompleted).count
        return "\(complete) of \(snapshot.items.count) done"
    }

    private func shortDay(_ day: String) -> String {
        guard let date = try? Date(day, strategy: .iso8601.year().month().day()) else { return day }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension SharedDocketSnapshot {
    fileprivate static let placeholder = SharedDocketSnapshot(
        day: "2026-09-01",
        items: [
            SharedDocketItem(
                id: "protocol_item:band-work",
                kind: "protocol_item",
                sourceID: "band-work",
                protocolID: "pt",
                title: "band extensions 3×15",
                tag: "PT",
                isCompleted: false,
                prescribedSets: 3,
                prescribedRepetitions: 15,
                prescribedDurationSeconds: nil
            )
        ]
    )
}
