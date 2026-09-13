import HomelabCore
import SwiftUI
import WidgetKit

/// What is up and what is not. Prometheus is tailnet-only, so this widget is
/// usually drawing the reading the app last took — it says so when it is, and
/// that is still the fastest answer to "is anything down" on a home screen.
struct HomelabHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomelabHealth", provider: HealthProvider()) { entry in
            WidgetSurface { HealthWidgetView(entry: entry) }
        }
        .configurationDisplayName("Service health")
        .description("How many monitored endpoints are up, and which are not.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct HealthEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthSnapshot
    let isStale: Bool
}

struct HealthProvider: TimelineProvider {
    private static let sample = HealthSnapshot(
        services: [
            ServiceHealth(name: "plex", host: "Media", isUp: true),
            ServiceHealth(name: "grafana", host: "Monitoring", isUp: true),
        ],
        lastRefreshedAt: Date()
    )

    func placeholder(in context: Context) -> HealthEntry {
        HealthEntry(date: Date(), snapshot: Self.sample, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        completion(HealthEntry(
            date: Date(),
            snapshot: WidgetData.healthCache.load() ?? Self.sample,
            isStale: false
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let handler = UncheckedSendable(completion)

        Task {
            let entry = await Self.makeEntry()
            handler.value(Timeline(
                entries: [entry],
                policy: .after(WidgetData.nextRefresh(active: entry.snapshot.downCount > 0))
            ))
        }
    }

    private static func makeEntry() async -> HealthEntry {
        let cached = WidgetData.healthCache.load()
        let fetched = await WidgetData.fetchHealth()

        if let fetched { WidgetData.healthCache.save(fetched) }

        return HealthEntry(
            date: Date(),
            snapshot: fetched ?? cached ?? HealthSnapshot(),
            isStale: fetched == nil
        )
    }
}

struct HealthWidgetView: View {
    let entry: HealthEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.palette) private var palette

    private var isHealthy: Bool { entry.snapshot.downCount == 0 }
    private var tint: Color { isHealthy ? palette.positive : palette.negative }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Services", tint: tint, isStale: entry.isStale)

            if entry.snapshot.services.isEmpty {
                Text("No reading")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                Text("Open the app on the tailnet")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            } else {
                Text("\(entry.snapshot.upCount)/\(entry.snapshot.services.count)")
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(isHealthy ? "all up" : "\(entry.snapshot.downCount) down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHealthy ? palette.textSecondary : palette.negative)
            }

            Spacer(minLength: 0)

            if let first = entry.snapshot.downServices.first {
                Text(first.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.negative)
                    .lineLimit(1)
            } else if let refreshed = entry.snapshot.lastRefreshedAt {
                Text(RelativeTime.ago(refreshed, now: entry.date))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Service health", tint: tint, isStale: entry.isStale)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.snapshot.upCount)/\(entry.snapshot.services.count)")
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(isHealthy ? "all up" : "\(entry.snapshot.downCount) down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHealthy ? palette.textSecondary : palette.negative)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if entry.snapshot.downServices.isEmpty {
                        ForEach(entry.snapshot.servicesByHost.prefix(4), id: \.host) { group in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(palette.positive)
                                    .frame(width: 5, height: 5)
                                Text(group.host)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textSecondary)
                                Spacer(minLength: 0)
                                Text("\(group.services.count)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    } else {
                        ForEach(entry.snapshot.downServices.prefix(4)) { service in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(palette.negative)
                                    .frame(width: 5, height: 5)
                                Text(service.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 0)
                                Text(service.host)
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            if let refreshed = entry.snapshot.lastRefreshedAt {
                Text("Read \(RelativeTime.ago(refreshed, now: entry.date))")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: isHealthy ? "checkmark.circle" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                Text("Services")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(inlineText)
                .font(.system(size: 12))
            if let first = entry.snapshot.downServices.first {
                Text("\(first.name) · \(first.host)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var inlineText: String {
        guard !entry.snapshot.services.isEmpty else { return "Services · no reading" }
        return isHealthy
            ? "\(entry.snapshot.services.count) services up"
            : "\(entry.snapshot.downCount) of \(entry.snapshot.services.count) down"
    }
}
