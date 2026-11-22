import AuthenticationServices
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
            .tabBarMinimizeBehavior(.onScrollDown)
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
                .navigationDestination(for: Title.self) { TitleScreen(title: $0) }
        }
    }
}

enum Palette {
    static let background: Color = .black
    static let surface = Color(white: 0.12)
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

extension View {
    @ViewBuilder
    func ledgerProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
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

struct Art: View {
    let url: URL?
    var symbol = "film"

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Palette.surface
                        Image(systemName: symbol).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

struct CoverTile: View {
    let title: Title

    var body: some View {
        NavigationLink(value: title) {
            VStack(alignment: .leading, spacing: 6) {
                Art(url: title.image, symbol: title.kind == .anime ? "film" : "book")
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if let score = title.score, score > 0 {
                            Text(score.formatted(.number.precision(.fractionLength(2))))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .ledgerGlassBadge().padding(6)
                        }
                    }
                Text(title.name).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
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
            Text(name).font(.headline).padding(.horizontal)
            if titles.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(unique(titles)) { title in CoverTile(title: title).frame(width: 114) }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct TitleRow: View {
    let title: Title
    let note: String

    var body: some View {
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

    var body: some View {
        Button {
            working = true
            Task {
                defer { working = false }
                do {
                    let account = try await store.api.signIn()
                    await store.connected(account)
                } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                } catch { store.handle(error) }
            }
        } label: {
            if working { ProgressView() } else { Label("Sign in with MyAnimeList", systemImage: "person.crop.circle") }
        }
        .disabled(working)
        .ledgerProminentButton()
    }
}

struct AccountScreen: View {
    @EnvironmentObject private var store: Store
    @State private var stats: Fields?
    @State private var favorites: [Kind: [Title]] = [:]
    @State private var loadingProfile = false
    @State private var favoritesUnavailable = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let account = store.account {
                    profileHeader(account)
                    if loadingProfile { ProgressView("Loading public profile").padding(.horizontal, 18) }
                    else if favoritesUnavailable {
                        Button("Retry loading favorites") { Task { await loadProfile(refresh: true) } }
                            .padding(.horizontal, 18)
                    }
                    ForEach(Kind.allCases) { kind in favoriteShelf(kind) }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.checking { ProgressView("Checking session") }
                        else {
                            Text("Connect MyAnimeList to show your stats and favorites.").foregroundStyle(.secondary)
                            SignInButton()
                        }
                    }.padding(.horizontal, 18)
                }
                NavigationLink { HomeScreen() } label: {
                    Label("Dashboard", systemImage: "rectangle.grid.2x2")
                }
                .ledgerGlassButton()
                .padding(.horizontal, 18)
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
                    Link("AniLedger website", destination: API.backend)
                    Link("Tenrai", destination: URL(string: "https://tenrai.org")!)
                    Link("Jikan Edge", destination: URL(string: "https://jikan.lucashdo.com")!)
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
            favorites = [:]
            favoritesUnavailable = false
            await loadProfile()
        }
        .refreshable { await loadProfile(refresh: true) }
    }

    private func profileHeader(_ user: Account) -> some View {
        let anime: Fields? = stats?.read("anime")
        let manga: Fields? = stats?.read("manga")
        let animeCount: Int? = anime?.read("totalEntries", "total_entries")
        let mangaCount: Int? = manga?.read("totalEntries", "total_entries")
        let days: Double? = anime?.read("daysWatched", "days_watched")
        let chapters: Int? = manga?.read("chaptersRead", "chapters_read", "chapters")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                avatar(user)
                profileMetrics(animeCount, mangaCount, days, chapters)
            }
            VStack(alignment: .leading, spacing: 16) {
                avatar(user)
                profileMetrics(animeCount, mangaCount, days, chapters)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerPanel()
        .padding(.horizontal, 18)
    }

    private func avatar(_ user: Account) -> some View {
        Art(url: user.image, symbol: "person.fill").frame(width: 88, height: 88)
            .clipShape(.rect(cornerRadius: 12))
    }

    private func profileMetrics(_ anime: Int?, _ manga: Int?, _ days: Double?, _ chapters: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                metric(anime == nil ? "Anime loaded" : "Total anime",
                       (anime ?? store.lists[.anime, default: []].count).formatted())
                metric(manga == nil ? "Manga loaded" : "Total manga",
                       (manga ?? store.lists[.manga, default: []].count).formatted())
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
            Text(value).font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func favoriteShelf(_ kind: Kind) -> some View {
        if let titles = favorites[kind] {
            if titles.isEmpty {
                Text("No public favorite \(kind.rawValue).").font(.subheadline)
                    .foregroundStyle(.secondary).padding(.horizontal, 18)
            } else {
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
    }

    private func loadProfile(refresh: Bool = false) async {
        guard let user = store.account else { loadingProfile = false; return }
        loadingProfile = true
        favoritesUnavailable = false
        let path = "users/\(user.name)"
        async let statsResponse = store.api.catalog(path + "/statistics", refresh: refresh)
        async let favoritesResponse = store.api.catalog(path + "/favorites", refresh: refresh)
        let result = try? await statsResponse
        let favoriteResult = try? await favoritesResponse
        guard !Task.isCancelled, store.account == user else { return }
        stats = result?.read("data")
        if let data: Fields = favoriteResult?.read("data") {
            for kind in Kind.allCases {
                let rows: [Fields] = data.read(kind.rawValue) ?? []
                favorites[kind] = rows.compactMap { Title($0, kind: kind) }
            }
        } else { favoritesUnavailable = true }
        loadingProfile = false
    }
}
