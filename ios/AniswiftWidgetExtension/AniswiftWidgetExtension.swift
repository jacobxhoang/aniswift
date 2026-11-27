import AppIntents
import SwiftUI
import WidgetKit

// MARK: - The snapshot the app writes

/// One row a widget draws: what the reader sees and the progress its button
/// adds to. The app writes it into the App Group container both targets share,
/// so the widget carries no account of its own.
struct WidgetRow: Codable, Identifiable {
    let id: String
    let malID: Int
    let kind: String
    let name: String
    let image: URL?
    let progress: Int
    let total: Int?
}

/// The account's totals as the statistics widget draws them: the counts the
/// public profile publishes, with a figure left out where the provider has none.
struct WidgetStats: Codable {
    let animeCount: Int?
    let mangaCount: Int?
    let daysWatched: Double?
    let chaptersRead: Int?
}

struct WidgetSnapshot: Codable {
    var anime: [WidgetRow] = []
    var manga: [WidgetRow] = []
    /// The account's totals, once its public profile has been read.
    var stats: WidgetStats?

    static let group = "group.org.aniswift.ios.shared"
    private static let name = "Aniswift-widget-v1.json"

    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appending(path: name)
    }

    static func read() -> Self? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let file = Self.file, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: file, options: [.atomic])
    }

    func rows(for kind: String) -> [WidgetRow] {
        kind == "anime" ? anime : manga
    }
}

/// The token the app keeps for the widget's button, in the App Group container
/// the extension can read. The app writes it whenever the session changes.
struct WidgetCredentials: Codable {
    let accessToken: String
    let expiresAt: Date

    private static let name = "Aniswift-widget-token.json"

    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appending(path: name)
    }

    static func read() -> Self? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

// MARK: - Timeline

struct AniswiftWidgetEntry: TimelineEntry {
    let date: Date
    let kind: String
    let rows: [WidgetRow]
    /// The posters, fetched while the timeline is built: a widget's own view
    /// does not load a remote picture reliably, so the provider does it and the
    /// row draws the bytes it was handed.
    var posters: [String: Data] = [:]
}

struct AniswiftWidgetProvider: TimelineProvider {
    let kind: String

    func placeholder(in context: Context) -> AniswiftWidgetEntry {
        AniswiftWidgetEntry(date: Date(), kind: kind, rows: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (AniswiftWidgetEntry) -> Void) {
        Task { completion(await current()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AniswiftWidgetEntry>) -> Void) {
        Task {
            let entry = await current()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
        }
    }

    private func current() async -> AniswiftWidgetEntry {
        let rows = WidgetSnapshot.read()?.rows(for: kind) ?? []
        return AniswiftWidgetEntry(
            date: Date(), kind: kind, rows: rows, posters: await posters(for: rows))
    }

    /// Three posters at most, fetched together with a short timeout so a slow
    /// network leaves a row with its glyph rather than holding the timeline.
    private func posters(for rows: [WidgetRow]) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for row in rows.prefix(3) {
                guard let url = row.image else { continue }
                group.addTask {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 8
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                        let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
                    else { return (row.id, nil) }
                    return (row.id, data)
                }
            }
            var found: [String: Data] = [:]
            for await (id, data) in group {
                if let data { found[id] = data }
            }
            return found
        }
    }
}

// MARK: - The widget

struct AniswiftWidgetView: View {
    let entry: AniswiftWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A small widget, a large one and any accessibility text size draw one row,
    /// which is what the family's height holds; a medium widget draws three.
    private var visible: [WidgetRow] {
        family == .systemMedium && !typeSize.isAccessibilitySize
            ? Array(entry.rows.prefix(3)) : Array(entry.rows.prefix(1))
    }

    /// The widget's own name is the heading in the gallery and on the Home
    /// Screen, so the rows start at the top of the card instead of repeating
    /// "Last Updated Anime" inside it.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visible.isEmpty {
                Text("Open Aniswift to read your list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ForEach(visible) { row in
                    AniswiftWidgetRowView(row: row, poster: entry.posters[row.id])
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct AniswiftWidgetRowView: View {
    let row: WidgetRow
    let poster: Data?

    private var fraction: Double {
        guard let total = row.total, total > 0 else { return 0 }
        return min(Double(row.progress) / Double(total), 1)
    }

    private var progressLabel: String {
        if let total = row.total { return "\(row.progress)/\(total)" }
        return "\(row.progress)/?"
    }

    var body: some View {
        HStack(spacing: 10) {
            AniswiftWidgetPoster(data: poster, kind: row.kind)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                progressBar
                HStack(spacing: 6) {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(intent: IncrementProgressIntent(id: row.id)) {
                        Text("+1")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(minWidth: 44, minHeight: 24)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.35)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Add one \(row.kind == "anime" ? "episode" : "chapter") to \(row.name)")
                }
            }
        }
        .frame(height: 44)
    }

    /// The bar fills by the share of the total, and a title with no total keeps
    /// an empty track rather than claiming a length it does not have.
    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if fraction > 0 {
                    Capsule().fill(.tint).frame(width: proxy.size.width * fraction)
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct AniswiftWidgetPoster: View {
    let data: Data?
    let kind: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.18)
                    Image(systemName: kind == "anime" ? "film" : "book")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 30, height: 42)
        .clipShape(.rect(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

struct AniswiftAnimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "AniswiftAnimeWidget", provider: AniswiftWidgetProvider(kind: "anime")
        ) { entry in
            AniswiftWidgetView(entry: entry)
        }
        .configurationDisplayName("Last Updated Anime")
        .description("Your most recently updated anime, with a button to add an episode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AniswiftMangaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "AniswiftMangaWidget", provider: AniswiftWidgetProvider(kind: "manga")
        ) { entry in
            AniswiftWidgetView(entry: entry)
        }
        .configurationDisplayName("Last Updated Manga")
        .description("Your most recently updated manga, with a button to add a chapter.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Statistics

struct AniswiftStatsEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStats?
}

struct AniswiftStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AniswiftStatsEntry {
        AniswiftStatsEntry(date: Date(), stats: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AniswiftStatsEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AniswiftStatsEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(1800))))
    }

    private func current() -> AniswiftStatsEntry {
        AniswiftStatsEntry(date: Date(), stats: WidgetSnapshot.read()?.stats)
    }
}

/// One total: its figure, and what it counts.
private struct AniswiftStatistic: Identifiable {
    let id: String
    let symbol: String
    let value: String
    let label: String
}

struct AniswiftStatsView: View {
    let entry: AniswiftStatsEntry
    @Environment(\.widgetFamily) private var family

    /// The totals the profile answered with, in the order the card reads them. A
    /// figure the provider has none for is left out rather than drawn as a
    /// placeholder beside the ones it does have.
    private var statistics: [AniswiftStatistic] {
        guard let stats = entry.stats else { return [] }
        var items: [AniswiftStatistic] = []
        if let count = stats.animeCount {
            items.append(
                AniswiftStatistic(
                    id: "anime", symbol: "tv", value: count.formatted(), label: "anime watched"))
        }
        if let days = stats.daysWatched {
            items.append(
                AniswiftStatistic(
                    id: "days", symbol: "calendar",
                    value: days.formatted(.number.precision(.fractionLength(0...1))),
                    label: "days watched"))
        }
        if let count = stats.mangaCount {
            items.append(
                AniswiftStatistic(
                    id: "manga", symbol: "books.vertical", value: count.formatted(),
                    label: "manga read"))
        }
        if let count = stats.chaptersRead {
            items.append(
                AniswiftStatistic(
                    id: "chapters", symbol: "book", value: count.formatted(),
                    label: "chapters read"))
        }
        return items
    }

    var body: some View {
        Group {
            if statistics.isEmpty {
                Text("Open Aniswift to read your statistics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if family == .systemSmall {
                smallLayout
            } else {
                mediumLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Two totals, each with its glyph and a rule between them: what the small
    /// family holds.
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(statistics.prefix(2).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.value).font(.headline.monospacedDigit())
                        Text(item.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                if index == 0 { Divider() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Four totals in two columns, a rule between the rows and none between the
    /// columns: what the medium family holds.
    private var mediumLayout: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 8) {
            GridRow {
                cell(statistics[0])
                cell(statistics.count > 1 ? statistics[1] : nil)
            }
            if statistics.count > 2 {
                Divider().gridCellColumns(2)
                GridRow {
                    cell(statistics[2])
                    cell(statistics.count > 3 ? statistics[3] : nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cell(_ item: AniswiftStatistic?) -> some View {
        VStack(spacing: 2) {
            Text(item?.value ?? " ")
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(item?.label ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AniswiftStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AniswiftStatsWidget", provider: AniswiftStatsProvider()) { entry in
            AniswiftStatsView(entry: entry)
        }
        .configurationDisplayName("Profile Statistics")
        .description("Your anime and manga totals, and how many days you have watched.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct AniswiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        AniswiftAnimeWidget()
        AniswiftMangaWidget()
        AniswiftStatsWidget()
    }
}

// MARK: - Adding one from the widget

/// Adds one episode or chapter straight from the widget: the change goes to
/// MyAnimeList with the token the app keeps for it, and the snapshot the widget
/// draws moves with it, so the row reads the new progress at once.
struct IncrementProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Add one episode or chapter"

    @Parameter(title: "Row")
    var id: String

    init() {}

    init(id: String) {
        self.id = id
    }

    func perform() async throws -> some IntentResult {
        guard var snapshot = WidgetSnapshot.read(),
            let row = (snapshot.anime + snapshot.manga).first(where: { $0.id == id }),
            let credentials = WidgetCredentials.read(), credentials.expiresAt > .now,
            await WidgetList.addOne(row, token: credentials.accessToken)
        else { return .result() }
        let updated = WidgetRow(
            id: row.id, malID: row.malID, kind: row.kind, name: row.name, image: row.image,
            progress: row.progress + 1, total: row.total)
        if row.kind == "anime" {
            snapshot.anime = snapshot.anime.map { $0.id == id ? updated : $0 }
        } else {
            snapshot.manga = snapshot.manga.map { $0.id == id ? updated : $0 }
        }
        snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum WidgetList {
    /// One update to the entry, with the field each kind takes.
    static func addOne(_ row: WidgetRow, token: String) async -> Bool {
        guard
            let url = URL(
                string: "https://api.myanimelist.net/v2/\(row.kind)/\(row.malID)/my_list_status")
        else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let field = row.kind == "anime" ? "num_watched_episodes" : "num_chapters_read"
        request.httpBody = Data("\(field)=\(row.progress + 1)".utf8)
        guard let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return false }
        return true
    }
}
