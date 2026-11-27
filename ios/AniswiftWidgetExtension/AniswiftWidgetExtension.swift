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

/// The App Group both bundles read the snapshot from: the extension's own copy of
/// the app's list, and the two have to name the same groups. A group is an
/// entitlement, fixed when the bundle is signed and not chosen by the app, so the
/// container is looked up in the list and the first group that opens is the one
/// the certificate gave this build.
enum AppGroup {
    /// The app's own group, and any a certificate that signs a build carries,
    /// which is added here for that build. The first that opens is the one used,
    /// and this copy has to name what the app's copy names.
    static let known = ["group.org.aniswift.ios.shared"]

    /// The group this signature actually grants, when it grants any of them.
    static let identifier: String? = known.first {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    }
}

struct WidgetSnapshot: Codable {
    var anime: [WidgetRow] = []
    var manga: [WidgetRow] = []
    /// The account's totals, once its public profile has been read.
    var stats: WidgetStats?

    private static let name = "Aniswift-widget-v1.json"

    /// The container both bundles read, when the signature grants a group.
    static var container: URL? {
        guard let group = AppGroup.identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static var file: URL? {
        container?.appending(path: name)
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
        WidgetSnapshot.container?.appending(path: name)
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
    /// The next episode of each anime row, as AniList published it, when the
    /// provider could read it.
    var airing: [String: WidgetAiring] = [:]
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
        async let posterData = posters(for: rows)
        async let airingData = schedule(for: rows)
        return AniswiftWidgetEntry(
            date: Date(), kind: kind, rows: rows, posters: await posterData,
            airing: await airingData)
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

    /// The next episode of each anime row, asked of AniList while the timeline is
    /// built. AniList answers without a session, and a title that is not on the
    /// air, or one it does not list, is left out rather than guessed at.
    private func schedule(for rows: [WidgetRow]) async -> [String: WidgetAiring] {
        let anime = rows.filter { $0.kind == "anime" }
        guard !anime.isEmpty else { return [:] }
        var ids: [Int: String] = [:]
        for row in anime { ids[row.malID] = row.id }

        let body: [String: Any] = [
            "query": """
                query ($ids: [Int]) {
                  Page(perPage: 50) {
                    media(idMal_in: $ids, type: ANIME) {
                      idMal
                      nextAiringEpisode { episode airingAt }
                    }
                  }
                }
                """,
            "variables": ["ids": anime.map(\.malID)],
        ]
        var request = URLRequest(url: Self.graphql, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let answer = try? JSONDecoder().decode(ScheduleAnswer.self, from: data)
        else { return [:] }

        var learned: [String: WidgetAiring] = [:]
        for media in answer.data.Page.media {
            guard let malID = media.idMal, let id = ids[malID],
                let next = media.nextAiringEpisode, let episode = next.episode, episode > 0,
                let airingAt = next.airingAt
            else { continue }
            learned[id] = WidgetAiring(
                episode: episode, date: Date(timeIntervalSince1970: TimeInterval(airingAt)))
        }
        return learned
    }

    private static let graphql = URL(string: "https://graphql.anilist.co")!
}

/// The next episode of an anime that is still on the air, as a row draws it:
/// which episode it is and the sentence under the title.
struct WidgetAiring {
    let episode: Int
    let date: Date

    /// "Episode 7 airs in 3 days", the sentence a list row and a title page
    /// carry, so the widget says it the same way.
    func line(relativeTo now: Date = .now) -> String {
        let away = Self.relative.localizedString(for: date, relativeTo: now)
        return "Episode \(episode) airs \(away)"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()
}

/// AniList's GraphQL answer, read for the one field a row needs.
private struct ScheduleAnswer: Decodable {
    struct Payload: Decodable { let Page: Page }
    struct Page: Decodable { let media: [Media] }
    struct Media: Decodable {
        let idMal: Int?
        let nextAiringEpisode: NextAiring?
    }
    struct NextAiring: Decodable {
        let episode: Int?
        let airingAt: Int?
    }
    let data: Payload
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
                WidgetEmptyNote(text: "list")
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

private struct AniswiftAiringRowView: View {
    let row: WidgetRow
    let poster: Data?
    let airing: WidgetAiring?
    @Environment(\.widgetFamily) private var family

    /// A large widget draws three rows, so each takes a smaller picture than the
    /// single row a small or a medium widget can give its own.
    private var posterSize: CGSize {
        switch family {
        case .systemMedium: return CGSize(width: 72, height: 96)
        case .systemLarge: return CGSize(width: 40, height: 54)
        default: return CGSize(width: 44, height: 58)
        }
    }

    private var titleFont: Font {
        family == .systemMedium ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var fraction: Double {
        guard let total = row.total, total > 0 else { return 0 }
        return min(Double(row.progress) / Double(total), 1)
    }

    /// How many episodes have aired: the one before the next to air.
    private var aired: Int? {
        guard let airing else { return nil }
        return max(airing.episode - 1, 0)
    }

    private var caughtUp: Bool {
        guard let aired else { return false }
        return row.progress >= aired
    }

    /// The line under the countdown: "On the latest episode" once every aired
    /// episode is watched, and the count until then.
    private var progressLabel: String {
        if caughtUp { return "On the latest episode" }
        if let total = row.total { return "\(row.progress)/\(total)" }
        return "\(row.progress)/?"
    }

    var body: some View {
        HStack(spacing: 10) {
            AniswiftWidgetPoster(data: poster, kind: row.kind, size: posterSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(titleFont)
                    .lineLimit(2)
                if let airing {
                    Text(airing.line())
                        .font(.caption2)
                        .foregroundStyle(caughtUp ? Color.green : Color.orange)
                        .lineLimit(2)
                        .accessibilityLabel(
                            caughtUp ? "\(airing.line()). You are caught up."
                                : "\(airing.line()). You are behind.")
                }
                HStack(spacing: 6) {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if family != .systemSmall { WidgetProgressBar(fraction: fraction) }
                    Spacer(minLength: 2)
                    AddOneButton(row: row)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The card a **Next Episode** widget draws: one row in the small and medium
/// families, where it has the height to itself, and three in the large one.
struct AniswiftAiringView: View {
    let entry: AniswiftWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize

    /// An accessibility text size keeps the card to one row, which is all the
    /// height holds then.
    private var visible: [WidgetRow] {
        guard !typeSize.isAccessibilitySize else { return Array(entry.rows.prefix(1)) }
        return Array(entry.rows.prefix(family == .systemLarge ? 3 : 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visible.isEmpty {
                WidgetEmptyNote(text: "list")
                Spacer(minLength: 0)
            } else {
                ForEach(visible) { row in
                    AniswiftAiringRowView(
                        row: row, poster: entry.posters[row.id], airing: entry.airing[row.id]
                    )
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// The row a **Last Updated** widget draws: the poster, the name, the progress
/// bar and the **+1** its button adds to.
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
            AniswiftWidgetPoster(data: poster, kind: row.kind, size: CGSize(width: 30, height: 42))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                WidgetProgressBar(fraction: fraction)
                HStack(spacing: 6) {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    AddOneButton(row: row)
                }
            }
        }
        .frame(height: 44)
    }
}

/// The bar that fills by the share of the total. A title whose provider
/// publishes no length keeps an empty track rather than claiming one.
private struct WidgetProgressBar: View {
    let fraction: Double

    var body: some View {
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

/// The control a row's button adds one episode or chapter with.
private struct AddOneButton: View {
    let row: WidgetRow

    var body: some View {
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

/// What a widget with nothing to draw says. A build whose signature carries no
/// App Group can never read the snapshot — the container is missing, not empty —
/// so it says that instead of asking for the app to be opened again.
private struct WidgetEmptyNote: View {
    /// What the widget would draw: "list" or "statistics".
    let text: String

    private var message: String {
        WidgetSnapshot.file == nil
            ? "This build has no App Group, so the widget cannot read your \(text)."
            : "Open Aniswift to read your \(text)."
    }

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AniswiftWidgetPoster: View {
    let data: Data?
    let kind: String
    let size: CGSize

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
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 6))
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

/// The widget that puts when each anime is next on the Home Screen, in the three
/// sizes: one row small, that row with a bigger picture medium, and three large.
/// It draws the countdown AniList publishes, and no artwork behind the rows.
struct AniswiftAiringWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "AniswiftAiringWidget", provider: AniswiftWidgetProvider(kind: "anime")
        ) { entry in
            AniswiftAiringView(entry: entry)
        }
        .configurationDisplayName("Next Episode")
        .description("The anime you are watching, with when each next episode airs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
                    id: "anime", symbol: "tv",
                    value: count.formatted(.number.locale(Locale(identifier: "en_US"))),
                    label: "anime watched"))
        }
        if let days = stats.daysWatched {
            items.append(
                AniswiftStatistic(
                    id: "days", symbol: "calendar",
                    value: days.formatted(
                        .number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))),
                    label: "days watched"))
        }
        if let count = stats.mangaCount {
            items.append(
                AniswiftStatistic(
                    id: "manga", symbol: "books.vertical",
                    value: count.formatted(.number.locale(Locale(identifier: "en_US"))),
                    label: "manga read"))
        }
        if let count = stats.chaptersRead {
            items.append(
                AniswiftStatistic(
                    id: "chapters", symbol: "book",
                    value: count.formatted(.number.locale(Locale(identifier: "en_US"))),
                    label: "chapters read"))
        }
        return items
    }

    var body: some View {
        Group {
            if statistics.isEmpty {
                WidgetEmptyNote(text: "statistics")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        AniswiftAiringWidget()
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
