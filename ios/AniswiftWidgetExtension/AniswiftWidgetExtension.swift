import AppIntents
import Darwin
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

    /// Where a tap on the row goes: the app's own scheme, so the title opens in
    /// the app rather than MyAnimeList in a browser.
    var link: URL { URL(string: "org.aniswift.ios://title/\(kind)/\(malID)")! }
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
/// the app's, and the two have to resolve the same group. A group is an
/// entitlement, fixed when the bundle is signed rather than chosen by the app, so
/// it is read back from the signature and none of a certificate is written into
/// the project. The list below is only the fallback for a signature that cannot
/// be read.
enum AppGroup {
    /// The app's own group, and any a certificate that signs a build carries,
    /// added here for a signature that cannot be read back.
    static let known = ["group.org.aniswift.ios.shared"]

    /// The group in use: the first of the signature's groups that opens, and the
    /// known list only when the signature gave none.
    static let identifier: String? = {
        let granted = signatureGroups()
        let candidates = granted.isEmpty ? known : granted + known
        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    /// The App Groups the code signature carries, whether or not any of them
    /// opens.
    static var signature: [String] { signatureGroups() }

    /// The App Groups the code signature carries, read through Security's own
    /// task API. The symbols are looked up at runtime rather than linked, so a
    /// system without them falls back to `known` instead of failing to launch.
    private static func signatureGroups() -> [String] {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)
        else { return [] }
        defer { dlclose(handle) }
        guard let create = dlsym(handle, "SecTaskCreateFromSelf"),
            let copy = dlsym(handle, "SecTaskCopyValueForEntitlement")
        else { return [] }

        // The two CF values are handed to Swift, which releases them: CFRelease
        // is unavailable here because Core Foundation is memory managed.
        typealias CreateTask = @convention(c) (UnsafeRawPointer?) -> AnyObject?
        typealias CopyEntitlement =
            @convention(c) (AnyObject?, CFString, UnsafeMutableRawPointer?) -> AnyObject?

        guard let task = unsafeBitCast(create, to: CreateTask.self)(nil) else { return [] }
        let lookUp = unsafeBitCast(copy, to: CopyEntitlement.self)
        guard let value = lookUp(task, "com.apple.security.application-groups" as CFString, nil)
        else { return [] }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

/// A step the widget could not take, written into the shared snapshot because a
/// widget cannot raise an alert: a tap that was refused must not look like a tap
/// that missed. The app reports it and clears it the next time it opens.
struct WidgetFailedWrite: Codable {
    let name: String
    let date: Date
}

struct WidgetSnapshot: Codable {
    var anime: [WidgetRow] = []
    var manga: [WidgetRow] = []
    /// The anime the reader is watching now, which is all the Next Episode card
    /// draws: a title marked completed or on hold is not on the air for them.
    var watching: [WidgetRow] = []
    /// The account's totals, once its public profile has been read.
    var stats: WidgetStats?
    /// The last step a widget's button could not take, until the app says so.
    var failedWrite: WidgetFailedWrite?

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
    /// Which rows the card draws: the most recently updated of a kind, or the
    /// anime the reader is watching now.
    enum Rows {
        case recent
        case watching
    }

    let kind: String
    var rows: Rows = .recent

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
        let snapshot = WidgetSnapshot.read()
        let drawn: [WidgetRow] = switch rows {
        case .recent: snapshot?.rows(for: kind) ?? []
        case .watching: snapshot?.watching ?? []
        }
        async let posterData = posters(for: drawn)
        async let airingData = schedule(for: drawn)
        return AniswiftWidgetEntry(
            date: Date(), kind: kind, rows: drawn, posters: await posterData,
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

/// The card a **Last Updated** widget draws: the medium size alone, with the
/// single most recently updated entry, which is the one a card that wide and
/// that short holds at a size worth reading.
struct AniswiftWidgetView: View {
    let entry: AniswiftWidgetEntry
    @Environment(\.widgetFamily) private var family

    /// A medium card draws the newest entry, a large one the three the snapshot
    /// keeps — the tall card is what a list is for.
    private var visible: [WidgetRow] {
        family == .systemLarge ? Array(entry.rows.prefix(3)) : Array(entry.rows.prefix(1))
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
                    Link(destination: row.link) {
                        AniswiftWidgetRowView(row: row, poster: entry.posters[row.id])
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// The two states of an airing row, carried at the values the app measures them
/// at: amber while an episode that already aired is unwatched, green once the
/// reader is caught up. The extension shares no module with the app, so the pair
/// is written here as the app writes it, each with a light and a dark shade so
/// the text clears 4.5:1 on either card.
private enum AiringInk {
    static let behind = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.97, green: 0.82, blue: 0.42, alpha: 1)
                : UIColor(red: 0.62, green: 0.40, blue: 0, alpha: 1)
        })
    static let caughtUp = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1)
                : UIColor(red: 0.09, green: 0.45, blue: 0.20, alpha: 1)
        })
}

private struct AniswiftAiringRowView: View {
    let row: WidgetRow
    let poster: Data?
    let airing: WidgetAiring?
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isSmall: Bool { family == .systemSmall }

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

    /// The episodes that have aired and are still unwatched, when there are any:
    /// what each card names in amber under its countdown.
    private var behind: Int? {
        guard let aired, row.progress < aired else { return nil }
        return aired - row.progress
    }

    /// A name is worth three lines in the small family, which has no bar beside
    /// it, and two where the picture takes the greater share of the card.
    private var name: some View {
        Text(row.name)
            .font(titleFont)
            .lineLimit(isSmall ? 3 : 2)
    }

    /// The countdown AniList publishes, in the app's green whatever the reader's
    /// place in the run — what they are behind by is the line under it, in amber
    /// — at the size the card holding it was given: a small card gives it a line
    /// of its own, a row shares its height with a picture.
    @ViewBuilder private var countdown: some View {
        if let airing {
            Text(airing.line())
                .font(textFont)
                .foregroundStyle(AiringInk.caughtUp)
                .lineLimit(2)
                .accessibilityLabel(
                    caughtUp ? "\(airing.line()). You are caught up."
                        : "\(airing.line()). You are behind.")
        }
    }

    /// The size a line of the countdown, or of what the reader is behind by, is
    /// written at.
    private var textFont: Font { isSmall ? .subheadline : .caption }

    var body: some View {
        if isSmall || typeSize.isAccessibilitySize {
            small
        } else {
            wide
        }
    }

    /// The words-only card: the small family, and every size once the text is at
    /// an accessibility size, because a picture beside three growing lines would
    /// clip them instead of making room.
    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.name)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            countdown
            state
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private var state: some View {
        if let behind {
            Text("\(behind) episode\(behind == 1 ? "" : "s") behind")
                .font(textFont)
                .foregroundStyle(AiringInk.behind)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else if caughtUp {
            Text("On the latest episode")
                .font(textFont)
                .foregroundStyle(AiringInk.caughtUp)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else if let total = row.total {
            Text("\(row.progress)/\(total)")
                .font(textFont)
                .foregroundStyle(.secondary)
        }
    }

    /// The medium and large families: one column beside the picture, carrying the
    /// same two lines the small card does — the countdown and what the reader is
    /// behind by — with the bar and the **+1** under them.
    private var wide: some View {
        HStack(spacing: 12) {
            AniswiftWidgetPoster(data: poster, kind: row.kind, size: posterSize)
            VStack(alignment: .leading, spacing: 4) {
                name
                countdown
                state
                HStack(spacing: 6) {
                    WidgetProgressBar(fraction: fraction)
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
                    Link(destination: row.link) {
                        AniswiftAiringRowView(
                            row: row, poster: entry.posters[row.id], airing: entry.airing[row.id]
                        )
                    }
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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var fraction: Double {
        guard let total = row.total, total > 0 else { return 0 }
        return min(Double(row.progress) / Double(total), 1)
    }

    private var progressLabel: String {
        if let total = row.total { return "\(row.progress)/\(total)" }
        return "\(row.progress)/?"
    }

    var body: some View {
        HStack(spacing: 12) {
            // At an accessibility text size the title needs the whole card, so
            // the picture steps out rather than squeezing it.
            if !typeSize.isAccessibilitySize {
                AniswiftWidgetPoster(data: poster, kind: row.kind, size: CGSize(width: 64, height: 88))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(progressLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    WidgetProgressBar(fraction: fraction)
                }
            }
            Spacer(minLength: 8)
            AddOneButton(row: row)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The bar that fills by the share of the total, in the app's own ink rather than
/// the system tint a widget falls back to. A title whose provider publishes no
/// length keeps an empty track rather than claiming one.
private struct WidgetProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if fraction > 0 {
                    Capsule().fill(.primary.opacity(0.85)).frame(width: proxy.size.width * fraction)
                }
            }
        }
        .frame(height: 3)
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
                .frame(minWidth: 40, minHeight: 24)
                .background(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        // The drawing stays a slim capsule; the target a thumb aims at is the 44
        // points the app holds itself to everywhere else.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
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
        .supportedFamilies([.systemMedium, .systemLarge])
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
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// The widget that puts when each anime is next on the Home Screen, in the three
/// sizes: one row small, that row with a bigger picture medium, and three large.
/// It draws the countdown AniList publishes, and no artwork behind the rows.
struct AniswiftAiringWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "AniswiftAiringWidget", provider: AniswiftWidgetProvider(kind: "anime", rows: .watching)
        ) { entry in
            AniswiftAiringView(entry: entry)
        }
        .configurationDisplayName("Next Episode")
        .description("The anime you are watching, with when each next episode airs. The +1 that adds one is on the medium and large sizes.")
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
            let row = (snapshot.anime + snapshot.manga).first(where: { $0.id == id })
        else { return .result() }

        let credentials = WidgetCredentials.read()
        var sent = false
        if let credentials, credentials.expiresAt > .now {
            sent = await WidgetList.addOne(row, token: credentials.accessToken)
        }
        guard sent else {
            // The card cannot say it failed, so the failure is written down for
            // the app: a refused tap must not look like a missed one.
            snapshot.failedWrite = WidgetFailedWrite(name: row.name, date: .now)
            snapshot.write()
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }

        let updated = WidgetRow(
            id: row.id, malID: row.malID, kind: row.kind, name: row.name, image: row.image,
            progress: row.progress + 1, total: row.total)
        if row.kind == "anime" {
            snapshot.anime = snapshot.anime.map { $0.id == id ? updated : $0 }
        } else {
            snapshot.manga = snapshot.manga.map { $0.id == id ? updated : $0 }
        }
        snapshot.failedWrite = nil
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
