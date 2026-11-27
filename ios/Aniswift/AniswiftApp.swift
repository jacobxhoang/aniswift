import AuthenticationServices
import Kingfisher
import SwiftUI
import UIKit

@main
@MainActor
struct AniswiftApp: App {
    @StateObject private var store = Store()
    @AppStorage(SettingKey.accent) private var accent = AccentChoice.white.rawValue
    @AppStorage(SettingKey.openLinksInApp) private var openLinksInApp = true
    @AppStorage(SettingKey.lastTab) private var lastTab = "anime"
    @AppStorage(SettingKey.tabBarBehavior) private var tabBarBehavior = "never"
    @State private var tab: String

    /// The tabs this build has, and the only values a stored preference may
    /// select. An identifier written by an older build would otherwise restore a
    /// tab that no longer exists and leave the tab view with nothing selected.
    private static let tabIdentifiers: Set<String> = ["anime", "manga", "discover", "feed", "profile"]

    init() {
        let defaults = UserDefaults.standard
        let startsOnPreferred = defaults.object(forKey: SettingKey.preferredLaunch) as? Bool ?? false
        let stored =
            startsOnPreferred
            ? defaults.string(forKey: SettingKey.launchTab) ?? "anime"
            : defaults.string(forKey: SettingKey.lastTab) ?? "anime"
        _tab = State(initialValue: Self.tabIdentifiers.contains(stored) ? stored : "anime")
        // Posters and avatars are reused across scrolling and back navigation, so
        // keep them longer than Kingfisher's one-week disk default.
        let images = ImageCache.default
        images.memoryStorage.config.expiration = .seconds(3600)
        images.diskStorage.config.expiration = .days(30)
        images.diskStorage.config.sizeLimit = 500 * 1024 * 1024
    }

    private var accentColor: Color {
        (AccentChoice(rawValue: accent) ?? .white).color
    }

    var body: some Scene {
        WindowGroup {
            rootTabs
                .onChange(of: tab) { _, value in lastTab = value }
                .sensoryFeedback(.selection, trigger: tab)
                .tint(accentColor)
                .preferredColorScheme(.dark)
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        guard openLinksInApp, let scheme = url.scheme,
                            ["http", "https"].contains(scheme)
                        else { return .systemAction }
                        return InAppBrowser.present(url) ? .handled : .systemAction
                    }
                )
                .environmentObject(store)
                .task { await store.restore() }
                .alert(
                    "Something went wrong",
                    isPresented: Binding(
                        get: { store.message != nil }, set: { if !$0 { store.message = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(store.message ?? "")
                }
        }
    }

    @ViewBuilder
    private var rootTabs: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $tab) {
                Tab("Anime", systemImage: "tv", value: "anime") {
                    stack { ListsScreen(kind: .anime) }
                }
                Tab("Manga", systemImage: "books.vertical", value: "manga") {
                    stack { ListsScreen(kind: .manga) }
                }
                Tab("Discover", systemImage: "safari", value: "discover") {
                    stack { DiscoverScreen() }
                }
                Tab("Feed", systemImage: "person.2", value: "feed") {
                    stack { FriendsScreen() }
                }
                Tab("Profile", systemImage: "person.crop.circle", value: "profile") {
                    stack { AccountScreen() }
                }
            }
            .tabBarMinimizeBehavior(tabBarBehavior == "onScrollDown" ? .onScrollDown : .never)
            .modifier(LedgerSidebarTabs())
        } else {
            TabView(selection: $tab) {
                stack { ListsScreen(kind: .anime) }
                    .tabItem { Label("Anime", systemImage: "tv") }
                    .tag("anime")
                stack { ListsScreen(kind: .manga) }
                    .tabItem { Label("Manga", systemImage: "books.vertical") }
                    .tag("manga")
                stack { DiscoverScreen() }
                    .tabItem { Label("Discover", systemImage: "safari") }
                    .tag("discover")
                stack { FriendsScreen() }
                    .tabItem { Label("Feed", systemImage: "person.2") }
                    .tag("feed")
                stack { AccountScreen() }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    .tag("profile")
            }
            .modifier(LedgerSidebarTabs())
        }
    }

    private func stack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Title.self) { TitleScreen(title: $0) }
                .navigationDestination(for: Friend.self) { FriendProfileScreen(friend: $0) }
                .navigationDestination(for: CharacterReference.self) { CharacterScreen(character: $0) }
                .navigationDestination(for: PersonReference.self) { PersonScreen(person: $0) }
                .navigationDestination(for: CatalogFacet.self) { CatalogFacetScreen(facet: $0) }
                .navigationDestination(for: StackRoute.self) { StackScreen(stack: $0.stack) }
                .navigationDestination(for: TitleStacksRoute.self) { route in
                    TitleStacksScreen(
                        title: route.title, firstPage: Page(items: route.stacks, more: route.more))
                }
                .navigationDestination(for: TitleCollectionRoute.self) { TitleCollectionScreen(route: $0) }
                .navigationDestination(for: CharactersRoute.self) { CharactersScreen(members: $0.members) }
                .navigationDestination(for: TitleReviewsRoute.self) { route in
                    TitleReviewsScreen(
                        title: route.title,
                        firstPage: route.reviews.map { Page(items: $0, more: route.more) })
                }
                .navigationDestination(for: TitleReviewRoute.self) {
                    TitleReviewReader(title: $0.title, review: $0.review)
                }
                .navigationDestination(for: FriendMediaRoute.self) {
                    FriendMediaListScreen(friend: $0.friend, kind: $0.kind)
                }
                .navigationDestination(for: CatalogBrowserRoute.self) { _ in CatalogBrowser() }
                .navigationDestination(for: CatalogResultsRoute.self) { route in
                    PosterResults(name: route.name, shelf: route.shelf, query: route.query, kind: route.kind)
                        .navigationTitle(route.name)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationDestination(for: CustomListsRoute.self) { _ in
                    List(store.organization.lists) { collection in
                        NavigationLink(value: CustomListRoute(list: collection)) {
                            LabeledContent(collection.name, value: collection.titles.count.formatted())
                        }
                        .listRowBackground(Color.clear)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Palette.background)
                    .navigationTitle("Custom Lists")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .navigationDestination(for: CustomListRoute.self) { route in
                    List(route.list.titles) { title in
                        NavigationLink(value: title) { TitleRow(title: title, note: title.kind.label) }
                            .listRowBackground(Color.clear)
                    }
                    .overlay {
                        if route.list.titles.isEmpty {
                            ContentUnavailableView("No titles in this list", systemImage: "list.bullet")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Palette.background)
                    .navigationTitle(route.list.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
    }
}

/// Tactile feedback for the moments a screen finishes something: a save that
/// reached MyAnimeList, a request that failed. State-driven feedback (pickers,
/// toggles, steppers) uses `.sensoryFeedback` at the control instead.
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// A quiet placeholder block for content that has not arrived yet, so a screen
/// can be drawn once instead of assembling itself in front of the reader.
struct SkeletonBlock: View {
    var height: CGFloat = 14
    var width: CGFloat?
    var radius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(pulse ? 0.13 : 0.06))
            .frame(width: width, height: height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

enum Palette {
    static let background: Color = .black
    static let surface = Color(white: 0.12)
    static let sheet = Color(white: 0.08)
    /// The hairline around posters, panels and capsules: one step up from the
    /// 8–14% white used before, which measured about 1.3:1 against the canvas,
    /// so an edge that separates two surfaces could not be seen at all.
    static let hairline = Color.white.opacity(0.22)
    /// The edge of an active or selected control, one step above `hairline`.
    static let border = Color.white.opacity(0.32)
    /// The fill behind a chip or a status pill. A fill carries no boundary, so
    /// it stays softer than a hairline.
    static let fill = Color.white.opacity(0.12)
    /// The two states of an airing row: amber while an episode that already
    /// aired is unwatched, green once the reader has caught up with the run.
    static let airingBehind = Color(red: 0.97, green: 0.82, blue: 0.42)
    static let airingCaughtUp = Color(red: 0.45, green: 0.85, blue: 0.55)
}

enum LedgerLayout {
    static let detailPosterWidth: CGFloat = 108
    static let posterRatio: CGFloat = 0.685
    static let inset: CGFloat = 20
    static let gap: CGFloat = 12
    static let sectionGap: CGFloat = 28
    static let posterWidth: CGFloat = 116
    static let posterRadius: CGFloat = 8
    /// The corners a row's thumbnail and a chip share.
    static let rowRadius: CGFloat = 7
    /// The corners a panel, a shelf card and a preview share.
    static let panelRadius: CGFloat = 12
}

extension Double {
    /// A decimal the way the app writes it: a period before the decimals and a
    /// comma between thousands, whatever the device's locale. The app's copy is
    /// English throughout, and on a keyboard that writes "8,40" a score reads as
    /// two numbers rather than one.
    func ledgerDecimal(_ fractionDigits: ClosedRange<Int>) -> String {
        formatted(.number.precision(.fractionLength(fractionDigits)).locale(Locale(identifier: "en_US")))
    }
}

/// One horizontal shelf for every carousel, so card width, gutters and snapping
/// stay consistent instead of each screen rolling its own scroll view.
struct LedgerShelf<Content: View>: View {
    var spacing: CGFloat = LedgerLayout.gap
    var inset: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: spacing) {
                content
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, inset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}

struct LedgerSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one control for "see everything in this section". A shelf link on a title
/// page, on Discover and on Profile read the same instead of a grey pill in one
/// place, a bare chevron in another and a caption in a third.
struct LedgerViewAll: View {
    let section: String

    var body: some View {
        HStack(spacing: 3) {
            Text("View All").font(.subheadline)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("View all \(section.lowercased())")
    }
}

/// Shown while a screen keeps a saved snapshot on screen because the public
/// data provider failed or served a stale copy.
struct SavedDataNote: View {
    let savedAt: Date?
    var message: String? = nil
    var isBusy = false
    var retry: (() async -> Void)? = nil

    /// One formatter for every note: building one per body pass is the cost this
    /// row pays for a relative date.
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var text: String {
        var parts = ["Showing saved data"]
        if let message, !message.isEmpty { parts.append(message) }
        if let savedAt {
            parts.append("Updated \(Self.relative.localizedString(for: savedAt, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let retry {
                Button("Retry") { Task { await retry() } }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .disabled(isBusy)
            }
        }
        .ledgerNoticePanel()
    }
}

/// A failure a screen can recover from: what could not be loaded, and the one
/// control that asks again. It wears the same notice panel as `SavedDataNote`,
/// so the two conditions a screen reports — a copy kept while the provider is
/// down, and a request that failed — read as one family instead of a grey
/// sentence floating above a pill.
struct LedgerProblem: View {
    let message: String
    var retryLabel = "Retry"
    var isBusy = false
    var retry: (() async -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(message)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let retry {
                Button(retryLabel) { Task { await retry() } }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .disabled(isBusy)
            }
        }
        .ledgerNoticePanel()
    }
}

extension View {
    func ledgerProminentButton() -> some View {
        buttonStyle(LedgerPrimaryButtonStyle())
    }

    @ViewBuilder
    func ledgerGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func ledgerGlassBadge() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.ultraThinMaterial, in: .capsule)
        }
    }

    /// A round glass control the size of a navigation bar button, for one that
    /// floats over a picture rather than sitting in a bar. It is drawn like the
    /// system's back button, so a glyph on it stays white instead of taking the
    /// accent the bar's other buttons wear.
    @ViewBuilder
    func ledgerGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: .circle)
                .overlay {
                    Circle().strokeBorder(Palette.border).allowsHitTesting(false)
                }
        }
    }

    func ledgerPanel(radius: CGFloat = 16) -> some View {
        background(.thinMaterial, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Palette.hairline)
                    .allowsHitTesting(false)
            }
    }

    /// The panel behind a notice: the copy a screen keeps while the provider is
    /// down, or a section that could not be loaded. One surface, so the two
    /// conditions every screen reports read as one family.
    func ledgerNoticePanel() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.surface.opacity(0.72), in: .rect(cornerRadius: LedgerLayout.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LedgerLayout.panelRadius)
                    .strokeBorder(Palette.hairline)
                    .allowsHitTesting(false)
            }
    }
}

private struct LedgerPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = isEnabled ? (configuration.isPressed ? 0.32 : 0.22) : 0.15
        return configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.56))
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Color(white: fill), in: .capsule)
            .overlay {
                Capsule().strokeBorder(Palette.border).allowsHitTesting(false)
            }
    }
}

/// A shelf tile that answers a touch: a small scale and a dim, without moving
/// anything around it, and no motion at all under Reduce Motion. A tile in a
/// scroll view used to give no sign that it had been pressed.
struct LedgerTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Art: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    var symbol = "film"
    /// Called once the picture cannot be loaded, so the row that owns it can ask
    /// for the title's current copy: a poster a bundled payload carried can be
    /// a URL that no longer answers while the title itself is fine.
    var onFailure: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            KFImage.url(url)
                .placeholder { placeholder }
                .onFailureView { failurePlaceholder }
                .cancelOnDisappear(true)
                .setProcessor(processor(proxy.size))
                .fade(duration: reduceMotion ? 0 : 0.18)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }

    /// The state a picture that could not be loaded leaves behind. It says so to
    /// the row on the one frame it appears, and the row resolves the title once.
    private var failurePlaceholder: some View {
        placeholder.task { onFailure?() }
    }

    /// Decode to the size the image is drawn at: a full poster is several times
    /// larger than a tile and costs memory on every row. Before the first layout
    /// pass reports a real size, fall back to the unprocessed image.
    private func processor(_ size: CGSize) -> ImageProcessor {
        let scale = max(displayScale, 1)
        let pixels = CGSize(
            width: (size.width * scale).rounded(.up),
            height: (size.height * scale).rounded(.up))
        guard pixels.width >= 16, pixels.height >= 16 else { return DefaultImageProcessor.default }
        return DownsamplingImageProcessor(size: pixels)
    }

    private var placeholder: some View {
        ZStack {
            Palette.surface
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Warms the posters a scrolling list is about to show. Keyed on the ids of the
    /// first rows, so a refresh that swaps rows without changing the count still
    /// prefetches the new art.
    func prefetchingPosters<T: Identifiable>(
        _ items: [T], limit: Int = 30,
        url: (T) -> URL?
    ) -> some View {
        let upcoming = Array(items.prefix(limit))
        let ids = upcoming.map { "\($0.id)" }
        let urls = upcoming.compactMap(url)
        return task(id: ids) {
            guard !urls.isEmpty else { return }
            ImagePrefetcher(urls: urls).start()
        }
    }
}

struct PreferredTitle<Content: View>: View {
    @EnvironmentObject private var store: Store
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let title: Title
    var loadMissingImage = false
    /// Read titles always render a real name. A view that has nothing to show
    /// until the lookup resolves (a poster tile) can keep the placeholder.
    var showsLoadingTitle = true
    /// A name the page resolved in a batch, so a row in a long list costs no
    /// detail request of its own.
    var knownName: String? = nil
    /// Whether that batch asked for this title too, so a name it did not return
    /// means there is no English title rather than one worth another request.
    var nameSettled = false
    /// A poster that failed to load is repaired once, by asking the API for the
    /// title's current copy: a bundled relation can carry a URL that no longer
    /// answers while the title it names is fine.
    var repairsMissingPoster = false
    @ViewBuilder var content: (Title, String) -> Content
    @State private var resolved: Title?
    @State private var attemptedID: String?
    @State private var repairedPoster = false

    private var current: Title {
        let saved = store.entries[title.kind]?[title.id]?.title
        return title.fillingTitleAndImage(from: saved)
            .fillingTitleAndImage(from: resolved ?? store.api.cachedTitle(title))
    }

    var body: some View {
        let item = current
        let waiting =
            !nameSettled && item.needsTitleLookup && attemptedID != title.id
            && !store.api.isNameResolved(title)
        // A sparse row still carries its original title, so a reader that opts out
        // of the placeholder always has something real to show. Romaji reads the
        // original title instead of the English name.
        let name =
            knownName
            ?? (waiting && showsLoadingTitle ? "Loading title…" : item.displayName(for: titleLanguage))
        let request = PreferredLookup(id: title.id, poster: repairsMissingPoster)
        content(item, name)
            .task(id: request) {
                // A settled name still leaves the poster to fetch, so either one
                // can justify the lookup, and a poster that failed to download
                // is worth one ask of its own. A title that answered with no
                // poster at all is not asked twice.
                let needsName =
                    item.needsTitleLookup && !nameSettled && !store.api.isNameResolved(title)
                    && attemptedID != title.id
                let needsPoster =
                    loadMissingImage
                    && (item.image == nil
                        ? attemptedID != title.id
                        : repairsMissingPoster && !repairedPoster)
                guard needsName || needsPoster else { return }
                if needsPoster, item.image != nil { repairedPoster = true }
                let result = await store.api.resolveTitle(title)
                if !Task.isCancelled {
                    resolved = result
                    attemptedID = title.id
                }
            }
    }
}

/// What a row is still waiting on: its name, and whether its poster failed to
/// load. The row re-asks only when one of those changes, and never because its
/// own repair moved, which would cancel the repair it just started.
private struct PreferredLookup: Hashable {
    let id: String
    let poster: Bool
}

struct PosterArt: View {
    let url: URL?
    let symbol: String
    var width: CGFloat?
    var onFailure: (() -> Void)? = nil

    var body: some View {
        if let width {
            Art(url: url, symbol: symbol, onFailure: onFailure)
                .frame(width: width, height: width / LedgerLayout.posterRatio)
        } else {
            Art(url: url, symbol: symbol, onFailure: onFailure)
                .aspectRatio(LedgerLayout.posterRatio, contentMode: .fit)
        }
    }
}

struct CoverTile: View {
    @EnvironmentObject private var store: Store
    let title: Title
    var showsScore = true
    var loadMissingImage = false
    var reservesCaptionSpace = true
    var posterWidth: CGFloat?
    /// Whether a poster that failed to download is asked for again, so a stale
    /// URL from a bundled payload does not leave the tile blank for good.
    @State private var posterFailed = false

    var body: some View {
        PreferredTitle(
            title: title, loadMissingImage: loadMissingImage, repairsMissingPoster: posterFailed
        ) { item, name in
            tile(item, name: name)
        }
    }

    private func tile(_ title: Title, name: String) -> some View {
        NavigationLink(value: title) {
            VStack(alignment: .leading, spacing: 6) {
                PosterArt(
                    url: title.image, symbol: title.kind == .anime ? "film" : "book", width: posterWidth,
                    onFailure: { posterFailed = true }
                )
                .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LedgerLayout.posterRadius)
                        .strokeBorder(Palette.hairline).allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if showsScore, let score = title.score, score > 0 {
                        Text(score.ledgerDecimal(2...2))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .ledgerGlassBadge().padding(6)
                            .accessibilityLabel("Score \(score.ledgerDecimal(2...2)) out of 10")
                    }
                }
                Text(name)
                    .font(reservesCaptionSpace ? .subheadline.weight(.medium) : .subheadline)
                    .lineLimit(2, reservesSpace: reservesCaptionSpace)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // One tile reads as one row: the poster, its name and its score
            // used to be three stops for VoiceOver.
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(LedgerTileButtonStyle())
        // A long press opens the tile's quick actions, the way a poster in a
        // shelf answers on iOS: progress, MyAnimeList and Share, over the poster.
        .contextMenu {
            if let saved = store.entries[title.kind]?[title.id] {
                if (title.total ?? 0) <= 0 || saved.progress < (title.total ?? 0) {
                    Button {
                        Task {
                            try? await store.change(
                                title,
                                ListChange(
                                    status: saved.status, progress: saved.progress + 1, rating: saved.rating))
                        }
                    } label: {
                        Label(title.kind == .anime ? "Add one episode" : "Add one chapter", systemImage: "plus")
                    }
                }
            } else if store.account != nil {
                Button {
                    Task {
                        try? await store.change(
                            title,
                            ListChange(
                                status: title.kind.statuses.first ?? "watching", progress: 0, rating: 0))
                    }
                } label: {
                    Label(title.kind == .anime ? "Start watching" : "Start reading", systemImage: "plus")
                }
            }
            Link(destination: title.malURL) {
                Label("Open on MyAnimeList", systemImage: "arrow.up.right")
            }
            ShareLink(item: title.malURL) { Label("Share", systemImage: "square.and.arrow.up") }
        } preview: {
            PosterArt(url: title.image, symbol: title.kind == .anime ? "film" : "book")
                .frame(width: 220)
                .clipShape(.rect(cornerRadius: LedgerLayout.panelRadius))
        }
    }
}

struct Rail: View {
    let name: String
    let titles: [Title]
    var empty = "No titles available."
    /// The dupes are dropped once per page instead of on every body pass, so a
    /// scroll does not rebuild the set for each shelf it redraws.
    @State private var items: [Title]
    /// The poster follows Dynamic Type the way the names beside it do, and stops
    /// growing at the accessibility sizes so a shelf keeps its shape.
    @ScaledMetric(relativeTo: .subheadline) private var scaledPosterWidth: CGFloat = LedgerLayout.posterWidth

    private var posterWidth: CGFloat { min(scaledPosterWidth, LedgerLayout.posterWidth * 1.4) }

    init(name: String, titles: [Title], empty: String = "No titles available.") {
        self.name = name
        self.titles = titles
        self.empty = empty
        _items = State(initialValue: unique(titles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle(name).padding(.horizontal, LedgerLayout.inset)
            if items.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, LedgerLayout.inset)
            } else {
                LedgerShelf(inset: LedgerLayout.inset) {
                    ForEach(items) { title in
                        CoverTile(title: title, showsScore: false, posterWidth: posterWidth)
                            .frame(width: posterWidth)
                    }
                }
            }
        }
        .onChange(of: titles) { _, new in items = unique(new) }
    }
}

struct TitleRow: View {
    let title: Title
    let note: String
    /// A row's thumbnail follows Dynamic Type with its labels.
    @ScaledMetric(relativeTo: .subheadline) private var posterWidth: CGFloat = 40

    private var posterHeight: CGFloat { posterWidth * 1.4 }

    var body: some View {
        PreferredTitle(title: title) { item, name in row(item, name: name) }
    }

    private func row(_ title: Title, name: String) -> some View {
        HStack(spacing: 12) {
            Art(url: title.image).frame(width: posterWidth, height: posterHeight)
                .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.subheadline.weight(.semibold))
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct SignInButton: View {
    @EnvironmentObject private var store: Store
    @State private var working = false

    var body: some View {
        Button {
            // The client ID is the one the build ships: the app has no field for
            // it, so a build without one says so instead of asking for it.
            guard let clientID = store.api.configuredClientID else {
                store.message = "This build has no MyAnimeList client ID. Add one to Info.plist to sign in."
                return
            }
            signIn(clientID)
        } label: {
            if working { ProgressView() } else { Label("Sign in with MyAnimeList", systemImage: "person.crop.circle") }
        }
        .disabled(working)
        .ledgerProminentButton()
    }

    private func signIn(_ clientID: String) {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let account = try await store.api.signIn(clientID: clientID)
                await store.connected(account)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            } catch { store.handle(error) }
        }
    }
}

struct AccountScreen: View {
    @EnvironmentObject private var store: Store
    @State private var loadingProfile = false
    @State private var profileUnavailable = false
    /// Every Profile toggle, read once and refreshed when Settings writes one.
    @State private var preferences = ProfilePreferences()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                if let account = store.account {
                    let profile = store.profile(for: account.name)
                    let status = store.profileStatus(for: account.name)
                    let hasSavedProfile = profile.stats != nil || profile.favorites != nil
                    ProfileStatsHeader(
                        image: account.image, stats: profile.stats?.value, name: account.name,
                        loadedAnime: store.lists[.anime, default: []].count,
                        loadedManga: store.lists[.manga, default: []].count,
                        showsDays: preferences.shows(ProfileSection.days))
                    if let status, status.isShowingSavedData, hasSavedProfile {
                        SavedDataNote(savedAt: status.savedAt, message: status.failure, isBusy: loadingProfile) {
                            await loadProfile(refresh: true)
                        }
                        .padding(.horizontal, LedgerLayout.inset)
                    } else if loadingProfile && !hasSavedProfile {
                        ProgressView("Loading public profile").padding(.horizontal, LedgerLayout.inset)
                    } else if profileUnavailable && !loadingProfile {
                        LedgerProblem(message: "Your public profile could not be loaded.", retryLabel: "Try again") {
                            await loadProfile(refresh: true)
                        }
                        .padding(.horizontal, LedgerLayout.inset)
                    }
                    // The numbers come before the social shelf: what the account
                    // has watched is the page's subject, and the friends rail is
                    // a door to somewhere else.
                    ProfileStatistics(
                        stats: profile.stats?.value,
                        showsAnime: preferences.shows(ProfileSection.animeStatistics),
                        showsManga: preferences.shows(ProfileSection.mangaStatistics))
                    if preferences.shows(ProfileSection.friends) { friendsShelf }
                    customListsLink
                    ForEach(Kind.allCases) { kind in
                        let section = kind == .anime ? ProfileSection.favoriteAnime : ProfileSection.favoriteManga
                        if preferences.shows(section) { favoriteShelf(kind) }
                    }
                    if preferences.shows(ProfileSection.favoriteCharacters) { favoriteCharactersShelf }
                    if preferences.shows(ProfileSection.favoritePeople) { favoritePeopleShelf }
                } else {
                    // Signed out, the page still has a subject: one panel that
                    // says what will appear here and the way in.
                    VStack(alignment: .leading, spacing: 14) {
                        if store.checking {
                            ProgressView("Checking session")
                        } else {
                            Text("Your statistics, favorites and friends appear here once MyAnimeList is connected.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            SignInButton()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .ledgerPanel()
                    .padding(.horizontal, LedgerLayout.inset)
                }
            }.padding(.vertical, 18).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(store.account?.name ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let name = store.account?.name,
                    let profile = publicURL("https://myanimelist.net/profile/\(name)")
                {
                    ShareLink(item: profile) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share MyAnimeList profile")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsScreen()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .task(id: store.account?.id) {
            profileUnavailable = false
            await loadProfile()
        }
        .refreshable { await loadProfile(refresh: true) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            preferences = ProfilePreferences()
        }
    }

    @ViewBuilder
    private var customListsLink: some View {
        if !store.organization.lists.isEmpty {
            NavigationLink(value: CustomListsRoute()) {
                Label("Custom Lists", systemImage: "list.bullet.rectangle")
            }
            .ledgerGlassButton()
            .padding(.horizontal, LedgerLayout.inset)
        }
    }

    @ViewBuilder
    private func favoriteShelf(_ kind: Kind) -> some View {
        if let titles = store.malFavorites[kind], !titles.isEmpty {
            PosterShelf(heading: "Favorite \(kind.rawValue)", titles: titles) {
                NavigationLink(
                    value: TitleCollectionRoute(
                        label: "Favorite \(kind.rawValue)", titles: unique(titles), showsScore: true)
                ) {
                    LedgerViewAll(section: "favorite \(kind.rawValue.lowercased())")
                }
            }
        }
    }

    /// A friend's portrait follows Dynamic Type with the name under it, and
    /// stops growing at the accessibility sizes so the row keeps its shape.
    @ScaledMetric(relativeTo: .footnote) private var scaledFriendAvatar: CGFloat = 72

    private var friendAvatarSize: CGFloat { min(scaledFriendAvatar, 72 * 1.4) }
    /// The portrait, plus the room a two-line handle needs beside it.
    private var friendTileWidth: CGFloat { friendAvatarSize + 28 }

    @ViewBuilder
    private var friendsShelf: some View {
        if !store.friends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LedgerSectionTitle("Friends").padding(.horizontal, LedgerLayout.inset)
                LedgerShelf(spacing: 14, inset: LedgerLayout.inset) {
                    ForEach(store.friends) { friend in
                        friendTile(friend)
                    }
                }
            }
        }
    }

    /// A friend reads as a person, not as a poster: a round portrait with the
    /// hairline the app gives artwork, and the handle under it at reading size,
    /// centred, so a long one wraps in the middle of its own tile instead of
    /// running off the end of the row.
    private func friendTile(_ friend: Friend) -> some View {
        NavigationLink(value: friend) {
            VStack(spacing: 8) {
                Art(url: friend.avatar, symbol: "person.fill")
                    .frame(width: friendAvatarSize, height: friendAvatarSize)
                    .clipShape(.circle)
                    .overlay {
                        Circle().strokeBorder(Palette.hairline).allowsHitTesting(false)
                    }
                Text(friend.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .frame(width: friendTileWidth)
            }
            .frame(width: friendTileWidth)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open \(friend.name)’s profile")
        }
        .buttonStyle(LedgerTileButtonStyle())
    }

    @ViewBuilder
    private var favoriteCharactersShelf: some View {
        let characters = store.malFavoriteCharacters
        if !characters.isEmpty {
            portraitShelf(
                "Favorite characters", items: characters, value: { $0 }, image: { $0.image }, name: { $0.name })
        }
    }

    @ViewBuilder
    private var favoritePeopleShelf: some View {
        let people = store.malFavoritePeople
        if !people.isEmpty {
            portraitShelf(
                "Favorite people", items: people, value: { $0 }, image: { $0.image }, name: { $0.name })
        }
    }

    /// A shelf of people — friends, favorite characters or favorite people —
    /// each opening its own page.
    private func portraitShelf<Item: Identifiable, Value: Hashable>(
        _ heading: String, items: [Item], value: @escaping (Item) -> Value,
        image: @escaping (Item) -> URL?, name: @escaping (Item) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle(heading).padding(.horizontal, LedgerLayout.inset)
            LedgerShelf(spacing: LedgerLayout.gap, inset: LedgerLayout.inset) {
                ForEach(items) { item in
                    NavigationLink(value: value(item)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Art(url: image(item), symbol: "person.fill")
                                .frame(width: 88, height: 88)
                                .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
                            Text(name(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2, reservesSpace: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 88)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadProfile(refresh: Bool = false) async {
        guard let user = store.account else {
            loadingProfile = false
            return
        }
        loadingProfile = true
        defer { if store.account?.id == user.id { loadingProfile = false } }
        // The friends rail reads the same list the feed uses, so it is asked for
        // only while that rail shows.
        if preferences.shows(ProfileSection.friends), store.friends.isEmpty {
            try? await store.fetchFriends(user)
        }
        let loaded = await store.loadProfile(user.name, refresh: refresh)
        guard !Task.isCancelled, store.account?.id == user.id else { return }
        profileUnavailable = !loaded
    }
}

struct FriendProfileScreen: View {
    @EnvironmentObject private var store: Store
    let friend: Friend

    @State private var loading = true
    @State private var unavailable = false
    @State private var updates: [FriendUpdate]?
    @State private var updatesUnavailable = false
    @State private var updatesAreSaved = false
    @State private var loadingUpdates = false
    @State private var friendFriends: [Friend]?
    @State private var loadingFriends = false
    @State private var friendsUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                let profile = store.profile(for: friend.name)
                let status = store.profileStatus(for: friend.name)
                let hasSavedProfile = profile.stats != nil || profile.favorites != nil
                ProfileStatsHeader(image: friend.avatar, stats: profile.stats?.value, name: friend.name)
                if let status, status.isShowingSavedData, hasSavedProfile {
                    SavedDataNote(savedAt: status.savedAt, message: status.failure, isBusy: loading) {
                        await load(refresh: true)
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                } else if loading && !hasSavedProfile {
                    ProgressView("Loading profile").padding(.horizontal, LedgerLayout.inset)
                } else if unavailable && !loading {
                    LedgerProblem(message: "Some public profile details are unavailable.") {
                        await load(refresh: true)
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                }
                let listKinds = Kind.allCases.filter { profile.stats?.value.isListEmpty(for: $0) != true }
                if !listKinds.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(listKinds) { kind in
                            NavigationLink(value: FriendMediaRoute(friend: friend, kind: kind)) {
                                Label("\(kind.label) List", systemImage: kind == .anime ? "film" : "books.vertical")
                                    .frame(maxWidth: .infinity)
                            }
                            .ledgerGlassButton()
                        }
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                }
                ProfileStatistics(stats: profile.stats?.value)
                friendsSection
                recentUpdates
                ForEach(Kind.allCases) { kind in
                    if let titles = profile.favorites?.value[kind], !titles.isEmpty {
                        Rail(name: "Favorite \(kind.rawValue)", titles: titles)
                    }
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(friend.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await loadUpdates() }
        .task { await loadFriendsList() }
        .refreshable {
            async let profile: Void = load(refresh: true)
            async let activity: Void = loadUpdates(refresh: true)
            async let people: Void = loadFriendsList(refresh: true)
            _ = await (profile, activity, people)
        }
    }

    /// The friend's own friends, each opening their profile. Only a public
    /// friends list is read, so this needs nothing of the other account.
    @ViewBuilder
    private var friendsSection: some View {
        if let friendFriends, !friendFriends.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LedgerSectionTitle("Friends")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(friendFriends) { person in
                            NavigationLink(value: person) {
                                VStack(spacing: 8) {
                                    Art(url: person.avatar, symbol: "person.fill")
                                        .frame(width: 64, height: 64)
                                        .clipShape(.circle)
                                        .overlay {
                                            Circle().strokeBorder(Palette.hairline)
                                                .allowsHitTesting(false)
                                        }
                                    Text(person.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 76)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                }
            }
            .padding(.horizontal, LedgerLayout.inset)
        } else if friendsUnavailable, !loadingFriends {
            LedgerProblem(message: "This friend's friends are unavailable.") {
                await loadFriendsList(refresh: true)
            }
            .padding(.horizontal, LedgerLayout.inset)
        }
    }

    private func loadFriendsList(refresh: Bool = false) async {
        guard !loadingFriends, refresh || friendFriends == nil else { return }
        loadingFriends = true
        defer { loadingFriends = false }
        do {
            let people = try await store.friends(of: friend)
            guard !Task.isCancelled else { return }
            friendFriends = people
            friendsUnavailable = false
        } catch {
            guard !Task.isCancelled else { return }
            friendsUnavailable = friendFriends == nil
        }
    }

    private var recentUpdates: some View {
        VStack(alignment: .leading, spacing: 12) {
            LedgerSectionTitle("Recent list updates")
            if let updates, !updates.isEmpty {
                if updatesAreSaved {
                    SavedDataNote(savedAt: nil, isBusy: loadingUpdates) {
                        await loadUpdates(refresh: true)
                    }
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(updates) { update in
                        PreferredTitle(title: update.title) { title, name in
                            NavigationLink(value: title) {
                                HStack(spacing: 12) {
                                    Art(url: title.image, symbol: title.kind == .anime ? "film" : "book")
                                        .frame(width: 40, height: 56)
                                        .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(name).font(.subheadline.weight(.semibold))
                                        Text(update.activityDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !update.activityDetails.isEmpty {
                                            Text(update.activityDetails).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if !updatesUnavailable {
                if updates == nil {
                    ProgressView("Loading recent updates")
                } else {
                    Text("No public list updates.").foregroundStyle(.secondary)
                }
            }

            if updatesUnavailable {
                LedgerProblem(message: "Recent updates are unavailable.", isBusy: loadingUpdates) {
                    await loadUpdates(refresh: true)
                }
            }
        }
        .padding(.horizontal, LedgerLayout.inset)
    }

    private func loadUpdates(refresh: Bool = false) async {
        guard !loadingUpdates, refresh || updates == nil else { return }
        loadingUpdates = true
        defer { loadingUpdates = false }
        do {
            let items = try await store.publicUpdates(friend, refresh: refresh)
            guard !Task.isCancelled else { return }
            let sorted = items.map { (item: $0, date: activityDate($0.date)) }
                .sorted { $0.date > $1.date }
            // The rows are Edge rows, so their names are resolved in a batch
            // before the recent updates are drawn.
            await store.resolveNames(in: items.map(\.title))
            guard !Task.isCancelled else { return }
            updates = unique(sorted.map(\.item))
            updatesAreSaved = false
            updatesUnavailable = false
        } catch {
            guard !Task.isCancelled else { return }
            if updates == nil {
                let saved = store.savedUpdates(for: friend)
                updates = saved.isEmpty ? nil : saved
            }
            updatesAreSaved = updates != nil
            updatesUnavailable = updates == nil
        }
    }

    private func load(refresh: Bool = false) async {
        loading = true
        defer { loading = false }
        let loaded = await store.loadProfile(friend.name, refresh: refresh)
        if !Task.isCancelled { unavailable = !loaded }
    }
}

private struct FriendMediaListScreen: View {
    @EnvironmentObject private var store: Store
    let friend: Friend
    let kind: Kind

    @State private var entries: [FriendUpdate] = []
    @State private var nextPage: Int? = 1
    @State private var listTotal: Int?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var isPrivate = false

    @State private var collapsed: Set<String>
    private let unknownStatus = "other"
    /// Pages asked for in one batch, so a long list arrives in a few requests
    /// instead of one per scroll to its last row.
    private static let pagesPerBatch = 4

    init(friend: Friend, kind: Kind) {
        self.friend = friend
        self.kind = kind
        _collapsed = State(initialValue: Set(kind.statuses.dropFirst().dropLast()))
    }

    var body: some View {
        List {
            if !entries.isEmpty {
                statusGroups
            }

            if let errorMessage {
                // A private list cannot be asked again, so its notice names the
                // failure without offering a control that would fail too.
                let retry: (() async -> Void)? = isPrivate ? nil : { await load() }
                LedgerProblem(message: errorMessage, retry: retry)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
            } else if nextPage != nil {
                VStack(spacing: 6) {
                    ProgressView()
                        .accessibilityLabel("Loading \(kind.rawValue) list")
                    if let listTotal, entries.count < listTotal {
                        Text("\(entries.count) of \(listTotal) titles")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if entries.isEmpty {
                VStack(spacing: 6) {
                    Label("No \(kind.rawValue) in this list", systemImage: kind == .anime ? "film" : "books.vertical")
                        .font(.headline)
                    Text("This list is empty on MyAnimeList.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("\(friend.name)’s \(kind.label) List")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(refresh: true) }
    }

    private var statusGroups: some View {
        let groups = Dictionary(grouping: entries, by: groupKey)
        let statuses = groups[unknownStatus] == nil ? kind.statuses : kind.statuses + [unknownStatus]
        return ForEach(statuses, id: \.self) { status in
            let group = groups[status, default: []]
            let expanded = !collapsed.contains(status)
            ListStatusHeader(
                title: statusLabel(status), count: group.count,
                expanded: expanded, partial: nextPage != nil
            ) {
                if expanded { collapsed.insert(status) } else { collapsed.remove(status) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if expanded {
                ForEach(group) { entry in entryRow(entry) }
            }
        }
    }

    private func entryRow(_ entry: FriendUpdate) -> some View {
        let title = store.named(entry.title)
        return NavigationLink(value: title) {
            TitleRow(title: title, note: detail(for: entry))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .listRowBackground(Color.clear)
    }

    private func groupKey(_ entry: FriendUpdate) -> String {
        guard let status = entry.status else { return unknownStatus }
        let key = status.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .joined(separator: "_")
        return kind.statuses.contains(key) ? key : unknownStatus
    }

    private func detail(for entry: FriendUpdate) -> String {
        var details: [String] = []
        if let status = entry.status { details.append(statusLabel(status)) }
        if let progress = entry.progress, progress > 0 {
            let count = entry.total.flatMap { $0 > 0 ? "\(progress) / \($0)" : nil } ?? progress.formatted()
            details.append("\(count) \(kind.unit.lowercased())")
        }
        if let score = entry.score, score > 0 { details.append("★ \(score)/10") }
        return details.joined(separator: " · ")
    }

    /// A friend's list is read to its end here rather than one page per scroll:
    /// the rows a page adds push the screen's loading row out of view, so a load
    /// driven by that row appearing left a long list half read, and a list that
    /// never finishes reading never says so.
    private func load(refresh: Bool = false) async {
        // A refresh that lands while a batch is still being read would clear the
        // rows the running batch is about to merge into, so it waits its turn.
        guard !loading else { return }
        if refresh {
            entries = []
            nextPage = 1
            listTotal = nil
            errorMessage = nil
            isPrivate = false
        }
        guard let start = nextPage else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        var page = start
        while true {
            let batch = await store.publicListBatch(
                friend, kind: kind, from: page, pages: Self.pagesPerBatch, refresh: refresh)
            // The pages a batch did read are kept even when it stopped short,
            // so a failed page never throws away the rows before it.
            entries = unique(entries + batch.items)
            if let total = batch.total { listTotal = total }
            if let failure = batch.failure {
                nextPage = batch.nextPage
                let status = (failure as? APIError)?.status
                isPrivate = status == 401 || status == 403
                errorMessage =
                    isPrivate
                    ? "This list is private."
                    : entries.isEmpty ? "Could not load this list." : "Could not load the rest of this list."
                return
            }
            guard let next = batch.nextPage else {
                nextPage = nil
                return
            }
            nextPage = next
            page = next
            guard !Task.isCancelled else { return }
        }
    }
}

private struct ProfileStatsHeader: View {
    let image: URL?
    let stats: ProfileStats?
    /// The handle this card belongs to. Your own profile and a friend's draw the
    /// same card, so the two read alike.
    var name: String? = nil
    var loadedAnime: Int? = nil
    var loadedManga: Int? = nil
    /// Whether the days-watched metric shows: Profile settings can hide it.
    var showsDays = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                avatar
                details
            }
            VStack(alignment: .leading, spacing: 16) {
                avatar
                details
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerPanel()
        .padding(.horizontal, LedgerLayout.inset)
    }

    /// A person is a round portrait with the hairline every picture carries —
    /// the shape the friends shelf gives everyone, this page's owner included.
    private var avatar: some View {
        Art(url: image, symbol: "person.fill")
            .frame(width: 76, height: 76)
            .clipShape(.circle)
            .overlay {
                Circle().strokeBorder(Palette.hairline).allowsHitTesting(false)
            }
    }

    /// Who, then how much, then how long. The two counts are a caption's worth
    /// of fact; the two durations are the numbers worth their own line.
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(counts)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(alignment: .top, spacing: 24) {
                if showsDays { metric("Days watched", daysValue) }
                metric("Chapters read", chaptersValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var counts: String {
        let parts = [
            count(stats?.animeCount, loaded: loadedAnime, "anime"),
            count(stats?.mangaCount, loaded: loadedManga, "manga"),
        ].compactMap { $0 }
        return parts.isEmpty ? "No list totals yet" : parts.joined(separator: " · ")
    }

    private func count(_ value: Int?, loaded: Int?, _ unit: String) -> String? {
        if let value { return "\(value.formatted()) \(unit)" }
        // The totals come from the public statistics. Until they arrive, what
        // this device has read off the list is the honest number to name.
        guard let loaded else { return nil }
        return "\(loaded.formatted()) \(unit) loaded"
    }

    private var daysValue: String {
        stats?.daysWatched?.ledgerDecimal(0...1) ?? "—"
    }

    private var chaptersValue: String {
        stats?.chaptersRead?.formatted() ?? "—"
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The account's numbers, one kind at a time in one panel: the totals, the
/// share each status takes, and the counts themselves. One panel with a picker
/// replaces a card per kind, so the page holds one statistics block instead of
/// two five-row tables, and the shut panel still carries the headline numbers.
private struct ProfileStatistics: View {
    let stats: ProfileStats?
    var showsAnime = true
    var showsManga = true

    @State private var chosen: Kind = .anime
    @State private var expanded = true

    init(stats: ProfileStats?, showsAnime: Bool = true, showsManga: Bool = true) {
        self.stats = stats
        self.showsAnime = showsAnime
        self.showsManga = showsManga
        _chosen = State(initialValue: showsAnime ? .anime : .manga)
    }

    private func shows(_ kind: Kind) -> Bool {
        kind == .anime ? showsAnime : showsManga
    }

    /// The kinds the panel can show: the ones Settings allows that the account
    /// actually keeps a list for.
    private var available: [Kind] {
        guard let stats else { return [] }
        return Kind.allCases.filter {
            shows($0) && !stats.isListEmpty(for: $0) && stats.details(for: $0) != nil
        }
    }

    private var active: Kind? { available.contains(chosen) ? chosen : available.first }

    /// The picker's selection, clamped to a kind the panel can actually draw, so
    /// hiding one kind in Settings while this page is open lands on the other.
    private var picked: Binding<Kind> {
        Binding(get: { active ?? .anime }, set: { chosen = $0 })
    }

    var body: some View {
        if let kind = active, let details = stats?.details(for: kind) {
            panel(kind: kind, details: details)
                .padding(.horizontal, LedgerLayout.inset)
        }
    }

    private func panel(kind: Kind, details: ProfileMediaStats) -> some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 16) {
                if available.count > 1 {
                    Picker("Statistics", selection: picked) {
                        ForEach(available) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                ProfileStatisticsSection(kind: kind, stats: details)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)
        } label: {
            HStack(spacing: 8) {
                Text("Statistics")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(headline(kind: kind, details: details))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .tint(Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .ledgerPanel()
    }

    private func headline(kind: Kind, details: ProfileMediaStats) -> String {
        var parts: [String] = []
        let total = kind.statuses.compactMap { details.statusCounts[$0] }.reduce(0, +)
        if total > 0 { parts.append("\(total.formatted()) \(total == 1 ? "title" : "titles")") }
        if let score = details.meanScore, score > 0 {
            parts.append(score.ledgerDecimal(2...2))
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProfileStatisticsSection: View {
    let kind: Kind
    let stats: ProfileMediaStats

    /// The statuses in the order a list groups them, each with the strength the
    /// proportion bar and its dot read at: one tint at five strengths, rather
    /// than five system hues the rest of the app never uses.
    private var statuses: [Status] {
        zip(kind.statuses, [1.0, 0.72, 0.5, 0.32, 0.16]).map { key, strength in
            Status(key: key, strength: strength, count: stats.statusCounts[key])
        }
    }

    private var total: Int { statuses.compactMap(\.count).reduce(0, +) }

    private var totalsLabel: String {
        var parts: [String] = []
        if let progress = stats.progress {
            let unit =
                kind == .anime ? (progress == 1 ? "episode" : "episodes") : (progress == 1 ? "chapter" : "chapters")
            parts.append("\(kind == .anime ? "Watched" : "Read") \(progress.formatted()) \(unit)")
        }
        if kind == .manga, let volumes = stats.volumes {
            parts.append("\(volumes.formatted()) \(volumes == 1 ? "volume" : "volumes")")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            totals
            if total > 0 {
                proportion
                statusRows
            }
            if !totalsLabel.isEmpty {
                Text(totalsLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A number is drawn only where it has one — the rule the title page's
    /// header follows — so the row never shows a column of dashes.
    private var totals: some View {
        let metrics: [Metric] = [
            total > 0 ? Metric(label: total == 1 ? "Title" : "Titles", value: total.formatted()) : nil,
            (stats.meanScore ?? 0) > 0
                ? Metric(label: "Mean score", value: (stats.meanScore ?? 0).ledgerDecimal(2...2))
                : nil,
            stats.days.map {
                Metric(
                    label: kind == .anime ? "Days watched" : "Days read",
                    value: $0.ledgerDecimal(0...1))
            },
        ].compactMap { $0 }
        return HStack(alignment: .top, spacing: 20) {
            ForEach(metrics) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private struct Metric: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// How the statuses divide the list: one tint at five strengths, with the
    /// hairline gaps the app puts between touching surfaces, so the bar reads as
    /// one material instead of five hues the rest of the app never uses.
    private var proportion: some View {
        let shown = statuses.filter { ($0.count ?? 0) > 0 }
        return GeometryReader { geometry in
            let gaps = CGFloat(max(shown.count - 1, 0)) * 2
            let width = max(geometry.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(shown) { status in
                    Rectangle()
                        .fill(.tint)
                        .frame(width: max(width * CGFloat(status.count ?? 0) / CGFloat(max(total, 1)), 2))
                        .opacity(status.strength)
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    /// The counts, each with the dot its slice of the bar carries, so the row
    /// and the bar name the same thing twice in two ways a reader can use.
    private var statusRows: some View {
        VStack(spacing: 0) {
            ForEach(statuses) { status in
                HStack(spacing: 10) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .opacity(status.strength)
                        .accessibilityHidden(true)
                    Text(status.label)
                    Spacer(minLength: 8)
                    Text(status.count?.formatted() ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(status.count == nil ? Color.secondary : Color.primary)
                }
                .font(.subheadline)
                .padding(.vertical, 7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    status.count.map { "\(status.label), \($0)" } ?? "\(status.label), count unavailable")
            }
        }
    }

    private struct Status: Identifiable {
        let key: String
        /// How strong the tint reads for this status, from the list's first
        /// status to its last. The bar's slice and the row's dot share it.
        let strength: Double
        let count: Int?
        var id: String { key }

        var label: String {
            switch key {
            case "plan_to_watch": "Plan to Watch"
            case "plan_to_read": "Plan to Read"
            default: statusLabel(key)
            }
        }
    }
}

struct AboutScreen: View {
    private let credits = [
        Credit("MyAnimeList", "Account sign-in, lists, and personal anime suggestions", "https://myanimelist.net"),
        Credit("Tenrai", "Anime and manga catalog", "https://tenrai.org"),
        Credit("Jikan Edge", "Catalog fallback and public friend activity", "https://jikan.lucashdo.com"),
    ]

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, let build { return "\(short) (\(build))" }
        return short ?? build ?? "Unavailable"
    }

    var body: some View {
        List {
            Section("App") {
                LabeledContent("Version", value: version).listRowBackground(Color.clear)
                Link(destination: URL(string: "https://github.com/jacobxhoang/aniswift")!) {
                    row("Aniswift on GitHub", detail: "Source code and iOS releases", symbol: "arrow.up.right")
                }
                .listRowBackground(Color.clear)
            }
            Section("Data and services") {
                ForEach(credits) { credit in
                    Link(destination: credit.url) {
                        row(credit.name, detail: credit.detail, symbol: "arrow.up.right")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            Section("Open-source libraries") {
                Link(destination: URL(string: "https://github.com/onevcat/Kingfisher")!) {
                    row("Kingfisher", detail: "Image loading and caching · MIT License", symbol: "arrow.up.right")
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("About Aniswift")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private struct Credit: Identifiable {
        let name: String
        let detail: String
        let url: URL
        var id: String { name }

        init(_ name: String, _ detail: String, _ url: String) {
            self.name = name
            self.detail = detail
            self.url = URL(string: url)!
        }
    }
}

/// A tab bar on iPhone and the sidebar iPadOS 18 puts beside it, so the five
/// destinations keep their place on a large screen and can be reordered the way
/// the system offers.
private struct LedgerSidebarTabs: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

/// The searches kept on this device, so a search field offers them instead of
/// opening blank, and the last one is a single tap away.
enum SearchRecents {
    private static let key = "aniswift.settings.recentSearches"
    private static let limit = 6

    static func values() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func remember(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return }
        var values = values().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        values.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(values.prefix(limit)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension View {
    /// The searches kept on this device, offered under a search field, so a
    /// query starts from a recent one rather than from nothing.
    func searchRecents(_ text: Binding<String>) -> some View {
        self
            .searchSuggestions {
                ForEach(SearchRecents.values(), id: \.self) { term in
                    Text(term).searchCompletion(term)
                }
            }
            .onSubmit(of: .search) { SearchRecents.remember(text.wrappedValue) }
    }
}
