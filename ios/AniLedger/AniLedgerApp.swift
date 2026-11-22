import AuthenticationServices
import Kingfisher
import SwiftUI

@main
@MainActor
struct AniLedgerApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            rootTabs
            .tint(Palette.accent)
            .preferredColorScheme(.dark)
            .environmentObject(store)
            .task { await store.restore() }
            .alert("AniLedger", isPresented: Binding(
                get: { store.message != nil }, set: { if !$0 { store.message = nil } }
            )) { Button("OK", role: .cancel) {} }
            message: { Text(store.message ?? "") }
        }
    }

    @ViewBuilder
    private var rootTabs: some View {
        if #available(iOS 26.0, *) {
            TabView {
                Tab("Anime", systemImage: "tv") { stack { ListsScreen(kind: .anime) } }
                Tab("Manga", systemImage: "books.vertical") { stack { ListsScreen(kind: .manga) } }
                Tab("Discover", systemImage: "safari") { stack { DiscoverScreen() } }
                Tab("Feed", systemImage: "person.2") { stack { FriendsScreen() } }
                Tab("Profile", systemImage: "person.crop.circle") { stack { AccountScreen() } }
            }
            .tabBarMinimizeBehavior(.never)
        } else {
            TabView {
                stack { ListsScreen(kind: .anime) }
                    .tabItem { Label("Anime", systemImage: "tv") }
                stack { ListsScreen(kind: .manga) }
                    .tabItem { Label("Manga", systemImage: "books.vertical") }
                stack { DiscoverScreen() }
                    .tabItem { Label("Discover", systemImage: "safari") }
                stack { FriendsScreen() }
                    .tabItem { Label("Feed", systemImage: "person.2") }
                stack { AccountScreen() }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }
        }
    }

    private func stack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Title.self) { TitleScreen(title: $0).toolbar(.visible, for: .navigationBar) }
                .navigationDestination(for: Friend.self) { FriendProfileScreen(friend: $0) }
                .navigationDestination(for: CharacterReference.self) { CharacterScreen(character: $0) }
                .navigationDestination(for: CatalogFacet.self) { CatalogFacetScreen(facet: $0) }
        }
    }
}

enum Palette {
    static let background: Color = .black
    static let surface = Color(white: 0.12)
    static let sheet = Color(white: 0.08)
    static let accent: Color = .white
    static let glow = Color(white: 0.16)

    static var canvas: some View {
        ZStack {
            background
            RadialGradient(colors: [glow.opacity(0.8), background], center: .topTrailing,
                           startRadius: 0, endRadius: 570)
        }
        .ignoresSafeArea()
    }
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
    let url: URL?
    var symbol = "film"

    var body: some View {
        GeometryReader { proxy in
            KFImage.url(url)
                .placeholder { placeholder }
                .onFailureView { placeholder }
                .cancelOnDisappear(true)
                .fade(duration: reduceMotion ? 0 : 0.18)
                .resizable()
                .scaledToFill()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Palette.surface
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}

struct PreferredTitle<Content: View>: View {
    @EnvironmentObject private var store: Store
    let title: Title
    var loadMissingImage = false
    @ViewBuilder var content: (Title) -> Content
    @State private var resolved: Title?

    private var current: Title {
        let saved = store.lists[title.kind]?.first { $0.id == title.id }?.title
        return title.fillingTitleAndImage(from: saved).fillingTitleAndImage(from: resolved)
    }

    var body: some View {
        content(current)
            .task(id: title) {
                guard current.needsTitleLookup || (loadMissingImage && current.image == nil) else { return }
                let result = await store.api.resolveTitle(title)
                if !Task.isCancelled { resolved = result }
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
        PreferredTitle(title: title, loadMissingImage: loadMissingImage) { item in
            tile(item)
        }
    }

    private func tile(_ title: Title) -> some View {
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
                Text(title.name)
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
        PreferredTitle(title: title) { item in row(item) }
    }

    private func row(_ title: Title) -> some View {
        HStack(spacing: 12) {
            Art(url: title.image).frame(width: 40, height: 56).clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.name).font(.subheadline.weight(.semibold))
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
            if let saved = store.api.configuredClientID { signIn(saved) }
            else { configure() }
        } label: {
            if working { ProgressView() } else { Label("Sign in with MyAnimeList", systemImage: "person.crop.circle") }
        }
        .disabled(working)
        .ledgerProminentButton()
        .contextMenu {
            Button("Change MyAnimeList Client ID") { configure() }
        }
        .alert("MyAnimeList iOS Client ID", isPresented: $configuring) {
            TextField("Client ID", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Continue") { signIn(clientID) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Register an iOS app at myanimelist.net/apiconfig with redirect URL \(API.redirectURI). Enter its Client ID here.")
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
    @State private var stats: Fields?
    @State private var loadingProfile = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                if let account = store.account {
                    ProfileStatsHeader(image: account.image, stats: stats,
                                       loadedAnime: store.lists[.anime, default: []].count,
                                       loadedManga: store.lists[.manga, default: []].count)
                    if loadingProfile { ProgressView("Loading public profile").padding(.horizontal, LedgerLayout.inset) }
                    else if store.favoritesUnavailable {
                        Button("Retry loading favorites") { Task { await loadProfile(refresh: true) } }
                            .padding(.horizontal, LedgerLayout.inset)
                    }
                    customListsLink
                    ForEach(Kind.allCases) { kind in favoriteShelf(kind) }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.checking { ProgressView("Checking session") }
                        else {
                            Text("Connect MyAnimeList to show your stats and favorites.").foregroundStyle(.secondary)
                            SignInButton()
                        }
                    }.padding(.horizontal, LedgerLayout.inset)
                }
                ForEach(Kind.allCases) { kind in
                    let titles = store.previousLocalFavorites.filter { $0.kind == kind && !store.isMALFavorite($0) }
                    if !titles.isEmpty {
                        PosterShelf(heading: "Previously saved \(kind.rawValue)", titles: titles) {
                            EmptyView()
                        }
                    }
                }
            }.padding(.vertical, 18).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(store.account?.name ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let name = store.account?.name, let profile = publicURL("https://myanimelist.net/profile/\(name)") {
                        Link("View MyAnimeList profile", destination: profile)
                    }
                    NavigationLink { AboutScreen() } label: {
                        Label("About AniLedger", systemImage: "info.circle")
                    }
                    if store.account != nil {
                        Button("Sign out") { confirmSignOut = true }
                    }
                } label: { Label("Profile options", systemImage: "gearshape") }
            }
        }
        .confirmationDialog("Sign out of MyAnimeList?", isPresented: $confirmSignOut) {
            Button("Sign out") { store.disconnect() }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: store.account?.id) {
            stats = nil
            await loadProfile()
        }
        .refreshable { await loadProfile(refresh: true) }
    }

    @ViewBuilder
    private var customListsLink: some View {
        if !store.organization.lists.isEmpty {
            NavigationLink {
                List(store.organization.lists) { collection in
                    NavigationLink {
                        List(collection.titles) { title in
                            NavigationLink(value: title) { TitleRow(title: title, note: title.kind.label) }
                                .listRowBackground(Color.clear)
                        }
                        .overlay {
                            if collection.titles.isEmpty {
                                ContentUnavailableView("No titles in this list", systemImage: "list.bullet")
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Palette.background)
                        .navigationTitle(collection.name)
                    } label: {
                        LabeledContent(collection.name, value: collection.titles.count.formatted())
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(Palette.background)
                .navigationTitle("Custom Lists")
            } label: { Label("Custom Lists", systemImage: "list.bullet.rectangle") }
            .ledgerGlassButton()
            .padding(.horizontal, LedgerLayout.inset)
        }
    }

    @ViewBuilder
    private func favoriteShelf(_ kind: Kind) -> some View {
        if let titles = store.malFavorites[kind], !titles.isEmpty {
            PosterShelf(heading: "Favorite \(kind.rawValue)", titles: titles) {
                NavigationLink {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                            ForEach(unique(titles)) { CoverTile(title: $0) }
                        }.padding(18)
                    }
                    .background(Palette.background)
                    .navigationTitle("Favorite \(kind.rawValue)")
                } label: { Text("View all").font(.caption.weight(.semibold)) }
            }
        }
    }

    private func loadProfile(refresh: Bool = false) async {
        guard let user = store.account else { loadingProfile = false; return }
        loadingProfile = true
        async let favorites: Void = store.loadFavorites(refresh: refresh)
        let path = "users/\(user.name)/statistics"
        let result = try? await store.api.catalog(path, refresh: refresh)
        await favorites
        guard !Task.isCancelled, store.account == user else { return }
        stats = result?.read("data")
        loadingProfile = false
    }
}

struct FriendProfileScreen: View {
    @EnvironmentObject private var store: Store
    let friend: Friend

    @State private var stats: Fields?
    @State private var favorites: [Kind: [Title]] = [:]
    @State private var loading = true
    @State private var unavailable = false
    @State private var updates: [FriendUpdate]?
    @State private var updatesUnavailable = false
    @State private var loadingUpdates = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                ProfileStatsHeader(image: friend.avatar, stats: stats)
                if loading {
                    ProgressView("Loading profile").padding(.horizontal, LedgerLayout.inset)
                } else if unavailable {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Some public profile details are unavailable.").foregroundStyle(.secondary)
                        Button("Retry") { Task { await load(refresh: true) } }.ledgerGlassButton()
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                }
                recentUpdates
                ForEach(Kind.allCases) { kind in
                    if let titles = favorites[kind], !titles.isEmpty {
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
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(updates) { update in
                        PreferredTitle(title: update.title) { title in
                            NavigationLink(value: title) {
                                HStack(spacing: 12) {
                                    Art(url: title.image, symbol: title.kind == .anime ? "film" : "book")
                                        .frame(width: 40, height: 56)
                                        .clipShape(.rect(cornerRadius: 5))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(title.name).font(.subheadline.weight(.semibold))
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
                if updates == nil { ProgressView("Loading recent updates") }
                else { Text("No public list updates.").foregroundStyle(.secondary) }
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
            updatesUnavailable = false
        } catch {
            if !Task.isCancelled { updatesUnavailable = true }
        }
    }

    private func load(refresh: Bool = false) async {
        loading = true
        defer { loading = false }
        let path = "users/\(friend.name)"
        async let statsRequest = try? store.api.catalog(path + "/statistics", refresh: refresh)
        async let favoritesRequest = try? store.api.catalog(path + "/favorites", refresh: refresh)
        let (statsResult, favoritesResult) = await (statsRequest, favoritesRequest)
        guard !Task.isCancelled else { return }
        let statsData: Fields? = statsResult?.read("data")
        let favoritesData: Fields? = favoritesResult?.read("data")
        if let statsData { stats = statsData }
        if let favoritesData {
            favorites = Dictionary(uniqueKeysWithValues: Kind.allCases.map { kind in
                let rows: [Fields] = favoritesData.read(kind.rawValue) ?? []
                return (kind, rows.compactMap { Title($0, kind: kind) })
            })
        }
        unavailable = statsData == nil || favoritesData == nil
    }
}

private struct ProfileStatsHeader: View {
    let image: URL?
    let stats: Fields?
    var loadedAnime: Int? = nil
    var loadedManga: Int? = nil

    var body: some View {
        let anime: Fields? = stats?.read("anime")
        let manga: Fields? = stats?.read("manga")
        let animeCount: Int? = anime?.read("totalEntries", "total_entries")
        let mangaCount: Int? = manga?.read("totalEntries", "total_entries")
        let days: Double? = anime?.read("daysWatched", "days_watched")
        let chapters: Int? = manga?.read("chaptersRead", "chapters_read", "chapters")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                avatar
                profileMetrics(animeCount, mangaCount, days, chapters)
            }
            VStack(alignment: .leading, spacing: 16) {
                avatar
                profileMetrics(animeCount, mangaCount, days, chapters)
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
                metric(anime == nil && loadedAnime != nil ? "Anime loaded" : "Total anime",
                       (anime ?? loadedAnime)?.formatted() ?? "—")
                metric(manga == nil && loadedManga != nil ? "Manga loaded" : "Total manga",
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

private struct AboutScreen: View {
    private let credits = [
        Credit("MyAnimeList", "Account sign-in, lists, and personal anime suggestions", "https://myanimelist.net"),
        Credit("Tenrai", "Anime and manga catalog", "https://tenrai.org"),
        Credit("Jikan Edge", "Catalog fallback and public friend activity", "https://jikan.lucashdo.com")
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
                Link(destination: API.website) {
                    row("AniLedger website", detail: API.website.host() ?? "", symbol: "arrow.up.right")
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
