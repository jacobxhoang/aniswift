import AuthenticationServices
import Kingfisher
import SwiftUI
import UIKit

@main
@MainActor
struct AniLedgerApp: App {
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
}

enum LedgerLayout {
    static let detailPosterWidth: CGFloat = 108
    static let posterRatio: CGFloat = 0.685
    static let inset: CGFloat = 20
    static let gap: CGFloat = 12
    static let sectionGap: CGFloat = 28
    static let posterWidth: CGFloat = 116
    static let posterRadius: CGFloat = 8
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

    private var text: String {
        var parts = ["Showing saved data"]
        if let message, !message.isEmpty { parts.append(message) }
        if let savedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Updated \(formatter.localizedString(for: savedAt, relativeTo: Date()))")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.surface.opacity(0.72), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08))
                .allowsHitTesting(false)
        }
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

    func ledgerPanel(radius: CGFloat = 16) -> some View {
        background(.thinMaterial, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(.white.opacity(0.08))
                    .allowsHitTesting(false)
            }
    }

    /// One search field for every searchable screen, so a search never sits in a
    /// different place just because it lives on another screen.
    func ledgerSearch(text: Binding<String>, prompt: String) -> some View {
        modifier(LedgerSearch(text: text, prompt: prompt))
    }
}

private struct LedgerSearch: ViewModifier {
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        // Always on screen, so a screenshot of any search screen looks the same
        // and a scope bar has somewhere to sit. The iOS 26 toolbar field hides
        // the search behind a button, which is why it is not used here yet.
        content
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
            .scrollDismissesKeyboard(.interactively)
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
                Capsule().strokeBorder(.white.opacity(0.16)).allowsHitTesting(false)
            }
    }
}

struct Art: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    var symbol = "film"

    var body: some View {
        GeometryReader { proxy in
            KFImage.url(url)
                .placeholder { placeholder }
                .onFailureView { placeholder }
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
    var onEnglishName: ((Title, String) -> Void)? = nil
    @ViewBuilder var content: (Title, String) -> Content
    @State private var resolved: Title?
    @State private var attemptedID: String?

    private var current: Title {
        let saved = store.lists[title.kind]?.first { $0.id == title.id }?.title
        return title.fillingTitleAndImage(from: saved)
            .fillingTitleAndImage(from: resolved ?? store.api.cachedTitle(title))
    }

    var body: some View {
        let item = current
        let waiting = item.needsTitleLookup && attemptedID != title.id && store.api.cachedTitle(title) == nil
        // A sparse row still carries its original title, so a reader that opts out
        // of the placeholder always has something real to show. Romaji reads the
        // original title instead of the English name.
        content(item, waiting && showsLoadingTitle ? "Loading title…" : item.displayName(for: titleLanguage))
            .onChange(of: item.englishName, initial: true) { _, english in
                if let english { onEnglishName?(item, english) }
            }
            .task(id: title) {
                guard attemptedID != title.id,
                    item.needsTitleLookup || (loadMissingImage && item.image == nil)
                else { return }
                let result = await store.api.resolveTitle(title)
                if !Task.isCancelled {
                    resolved = result
                    attemptedID = title.id
                }
            }
    }
}

struct PosterArt: View {
    let url: URL?
    let symbol: String
    var width: CGFloat?

    var body: some View {
        if let width {
            Art(url: url, symbol: symbol).frame(width: width, height: width / LedgerLayout.posterRatio)
        } else {
            Art(url: url, symbol: symbol).aspectRatio(LedgerLayout.posterRatio, contentMode: .fit)
        }
    }
}

struct CoverTile: View {
    let title: Title
    var showsScore = true
    var loadMissingImage = false
    var reservesCaptionSpace = true
    var posterWidth: CGFloat?

    var body: some View {
        PreferredTitle(title: title, loadMissingImage: loadMissingImage) { item, name in
            tile(item, name: name)
        }
    }

    private func tile(_ title: Title, name: String) -> some View {
        NavigationLink(value: title) {
            VStack(alignment: .leading, spacing: 6) {
                PosterArt(url: title.image, symbol: title.kind == .anime ? "film" : "book", width: posterWidth)
                    .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: LedgerLayout.posterRadius)
                            .strokeBorder(.white.opacity(0.10)).allowsHitTesting(false)
                    }
                    .overlay(alignment: .topTrailing) {
                        if showsScore, let score = title.score, score > 0 {
                            Text(score.formatted(.number.precision(.fractionLength(2))))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .ledgerGlassBadge().padding(6)
                        }
                    }
                Text(name)
                    .font(reservesCaptionSpace ? .subheadline.weight(.medium) : .subheadline)
                    .lineLimit(2, reservesSpace: reservesCaptionSpace)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct Rail: View {
    let name: String
    let titles: [Title]
    var empty = "No titles available."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle(name).padding(.horizontal, LedgerLayout.inset)
            if titles.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, LedgerLayout.inset)
            } else {
                LedgerShelf(inset: LedgerLayout.inset) {
                    ForEach(unique(titles)) { title in
                        CoverTile(title: title, showsScore: false, posterWidth: LedgerLayout.posterWidth)
                            .frame(width: LedgerLayout.posterWidth)
                    }
                }
            }
        }
    }
}

struct TitleRow: View {
    let title: Title
    let note: String

    var body: some View {
        PreferredTitle(title: title) { item, name in row(item, name: name) }
    }

    private func row(_ title: Title, name: String) -> some View {
        HStack(spacing: 12) {
            Art(url: title.image).frame(width: 40, height: 56).clipShape(.rect(cornerRadius: 5))
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
    @State private var configuring = false
    @State private var clientID = ""

    var body: some View {
        Button {
            if let saved = store.api.configuredClientID { signIn(saved) } else { configure() }
        } label: {
            if working { ProgressView() } else { Label("Sign in with MyAnimeList", systemImage: "person.crop.circle") }
        }
        .disabled(working)
        .ledgerProminentButton()
        .alert("MyAnimeList iOS Client ID", isPresented: $configuring) {
            TextField("Client ID", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Continue") { signIn(clientID) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Register an iOS app at myanimelist.net/apiconfig with redirect URL \(API.redirectURI). Enter its Client ID here."
            )
        }
    }

    private func configure() {
        clientID = store.api.configuredClientID ?? ""
        configuring = true
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                if let account = store.account {
                    let profile = store.profile(for: account.name)
                    let status = store.profileStatus(for: account.name)
                    let hasSavedProfile = profile.stats != nil || profile.favorites != nil
                    ProfileStatsHeader(
                        image: account.image, stats: profile.stats?.value,
                        loadedAnime: store.lists[.anime, default: []].count,
                        loadedManga: store.lists[.manga, default: []].count)
                    if let status, status.isShowingSavedData, hasSavedProfile {
                        SavedDataNote(savedAt: status.savedAt, message: status.failure, isBusy: loadingProfile) {
                            await loadProfile(refresh: true)
                        }
                        .padding(.horizontal, LedgerLayout.inset)
                    } else if loadingProfile && !hasSavedProfile {
                        ProgressView("Loading public profile").padding(.horizontal, LedgerLayout.inset)
                    } else if profileUnavailable && !loadingProfile {
                        Button("Retry loading profile") { Task { await loadProfile(refresh: true) } }
                            .padding(.horizontal, LedgerLayout.inset)
                    }
                    ProfileStatistics(stats: profile.stats?.value)
                    customListsLink
                    ForEach(Kind.allCases) { kind in favoriteShelf(kind) }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.checking {
                            ProgressView("Checking session")
                        } else {
                            Text("Connect MyAnimeList to show your stats and favorites.").foregroundStyle(.secondary)
                            SignInButton()
                        }
                    }.padding(.horizontal, LedgerLayout.inset)
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

    private func loadProfile(refresh: Bool = false) async {
        guard let user = store.account else {
            loadingProfile = false
            return
        }
        loadingProfile = true
        defer { if store.account?.id == user.id { loadingProfile = false } }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                let profile = store.profile(for: friend.name)
                let status = store.profileStatus(for: friend.name)
                let hasSavedProfile = profile.stats != nil || profile.favorites != nil
                ProfileStatsHeader(image: friend.avatar, stats: profile.stats?.value)
                if let status, status.isShowingSavedData, hasSavedProfile {
                    SavedDataNote(savedAt: status.savedAt, message: status.failure, isBusy: loading) {
                        await load(refresh: true)
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                } else if loading && !hasSavedProfile {
                    ProgressView("Loading profile").padding(.horizontal, LedgerLayout.inset)
                } else if unavailable && !loading {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Some public profile details are unavailable.").foregroundStyle(.secondary)
                        Button("Retry") { Task { await load(refresh: true) } }.ledgerGlassButton()
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
        .refreshable {
            async let profile: Void = load(refresh: true)
            async let activity: Void = loadUpdates(refresh: true)
            _ = await (profile, activity)
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
                                        .clipShape(.rect(cornerRadius: 5))
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
                Text("Recent updates are unavailable.").foregroundStyle(.secondary)
                Button("Retry recent updates") { Task { await loadUpdates(refresh: true) } }
                    .ledgerGlassButton()
                    .disabled(loadingUpdates)
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
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var isPrivate = false

    @State private var collapsed: Set<String>
    private let unknownStatus = "other"

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
                VStack(alignment: .leading, spacing: 12) {
                    Text(errorMessage).foregroundStyle(.secondary)
                    if !isPrivate {
                        Button("Retry") { Task { await load() } }.ledgerGlassButton()
                    }
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            } else if let nextPage {
                NextPageIndicator(label: "Loading \(kind.rawValue) list", page: nextPage) { await load() }
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
        .refreshable {
            entries = []
            nextPage = 1
            errorMessage = nil
            isPrivate = false
            await load()
        }
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
        let title = store.friendFeedTitle(entry.title)
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

    private func load() async {
        guard let page = nextPage, !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let result = try await store.publicListPage(friend, kind: kind, page: page)
            guard !Task.isCancelled else { return }
            entries = unique(entries + result.items)
            nextPage = result.more ? page + 1 : nil
        } catch {
            guard !Task.isCancelled else { return }
            let status = (error as? APIError)?.status
            isPrivate = status == 401 || status == 403
            errorMessage = isPrivate ? "This list is private." : "Could not load this list."
        }
    }
}

private struct ProfileStatsHeader: View {
    let image: URL?
    let stats: ProfileStats?
    var loadedAnime: Int? = nil
    var loadedManga: Int? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                avatar
                profileMetrics(stats?.animeCount, stats?.mangaCount, stats?.daysWatched, stats?.chaptersRead)
            }
            VStack(alignment: .leading, spacing: 16) {
                avatar
                profileMetrics(stats?.animeCount, stats?.mangaCount, stats?.daysWatched, stats?.chaptersRead)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerPanel()
        .padding(.horizontal, LedgerLayout.inset)
    }

    private var avatar: some View {
        Art(url: image, symbol: "person.fill").frame(width: 88, height: 88)
            .clipShape(.rect(cornerRadius: 12))
    }

    private func profileMetrics(_ anime: Int?, _ manga: Int?, _ days: Double?, _ chapters: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                metric(
                    anime == nil && loadedAnime != nil ? "Anime loaded" : "Total anime",
                    (anime ?? loadedAnime)?.formatted() ?? "—")
                metric(
                    manga == nil && loadedManga != nil ? "Manga loaded" : "Total manga",
                    (manga ?? loadedManga)?.formatted() ?? "—")
            }
            HStack(alignment: .top, spacing: 12) {
                metric("Days watched", days?.formatted(.number.precision(.fractionLength(0...1))) ?? "—")
                metric("Chapters read", chapters?.formatted() ?? "—")
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileStatistics: View {
    let stats: ProfileStats?

    var body: some View {
        ForEach(Kind.allCases) { kind in
            if let stats, !stats.isListEmpty(for: kind), let details = stats.details(for: kind) {
                ProfileStatisticsSection(kind: kind, stats: details)
                    .padding(.horizontal, LedgerLayout.inset)
            }
        }
    }

}

private struct ProfileStatisticsSection: View {
    let kind: Kind
    let stats: ProfileMediaStats
    @State private var expanded = true

    private var statuses: [Status] {
        zip(
            kind.statuses,
            [
                (kind == .anime ? "play.fill" : "book.fill", Color(uiColor: .systemBlue)),
                ("checkmark", Color(uiColor: .systemGreen)),
                ("pause.fill", Color(uiColor: .systemOrange)),
                ("xmark", Color(uiColor: .systemRed)),
                ("calendar", Color(uiColor: .systemGray)),
            ]
        ).map { key, style in
            Status(key: key, icon: style.0, color: style.1, count: stats.statusCounts[key])
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
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        if #available(iOS 26.0, *) {
            disclosure.glassEffect(.regular, in: shape)
        } else {
            disclosure.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }

    private var disclosure: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                if (stats.meanScore ?? 0) > 0 || stats.days != nil || total > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        summary
                        if total > 0 {
                            statusChart
                            if statuses.allSatisfy({ $0.count != nil }) {
                                Text(total == 1 ? "1 title" : "\(total.formatted()) titles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    Divider()
                }
                statusRows
                if !totalsLabel.isEmpty {
                    Divider()
                    Text(totalsLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 4)
        } label: {
            Text("\(kind.label) Statistics")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isHeader)
        }
        .tint(Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                meanScore
                Spacer(minLength: 0)
                days
            }
            VStack(alignment: .leading, spacing: 8) {
                meanScore
                days
            }
        }
    }

    @ViewBuilder
    private var meanScore: some View {
        if let score = stats.meanScore, score > 0 {
            metric("Mean score", score.formatted(.number.precision(.fractionLength(2))))
        }
    }

    @ViewBuilder
    private var days: some View {
        if let days = stats.days {
            metric(
                kind == .anime ? "Days watched" : "Days read",
                days.formatted(.number.precision(.fractionLength(0...1))))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var statusChart: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(statuses.filter { ($0.count ?? 0) > 0 }) { status in
                    status.color.opacity(0.65)
                        .frame(width: geometry.size.width * CGFloat(status.count ?? 0) / CGFloat(total))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var statusRows: some View {
        VStack(spacing: 0) {
            ForEach(statuses) { status in
                if status.id != statuses.first?.id {
                    Divider().padding(.leading, 40)
                }
                LabeledContent {
                    Text(status.count?.formatted() ?? "—")
                        .monospacedDigit()
                        .accessibilityLabel(status.count?.formatted() ?? "Count unavailable")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: status.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(status.color)
                            .frame(width: 30, height: 30)
                            .background(
                                status.color.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .accessibilityHidden(true)
                        Text(status.label)
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }

    private struct Status: Identifiable {
        let key: String
        let icon: String
        let color: Color
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
                Link(destination: URL(string: "https://github.com/jacobxhoang/aniledger")!) {
                    row("AniLedger on GitHub", detail: "Source code and iOS releases", symbol: "arrow.up.right")
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
        .navigationTitle("About AniLedger")
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
