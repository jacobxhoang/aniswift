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

    var body: some View {
        List {
            Section("MyAnimeList") {
                if let account = store.account {
                    HStack {
                        Art(url: account.image, symbol: "person.fill").frame(width: 46, height: 46).clipShape(.circle)
                        Text(account.name).font(.headline)
                    }
                    if let profile = publicURL("https://myanimelist.net/profile/\(account.name)") {
                        Link("View MyAnimeList profile", destination: profile)
                    }
                    Button("Sign out") { store.disconnect() }
                } else if store.checking {
                    ProgressView("Checking session")
                } else {
                    SignInButton()
                }
            }
            if store.account != nil {
                Section("Lists") {
                    LabeledContent("Anime entries loaded", value: String(store.lists[.anime, default: []].count))
                    LabeledContent("Manga entries loaded", value: String(store.lists[.manga, default: []].count))
                    LabeledContent("Completed entries loaded", value: String(store.recent.filter { $0.status == "completed" }.count))
                }
            }
            Section("AniLedger") {
                NavigationLink { HomeScreen() } label: { Label("Dashboard", systemImage: "house") }
                Link("AniLedger website", destination: API.backend)
                Link("Tenrai", destination: URL(string: "https://tenrai.org")!)
                Link("Jikan Edge", destination: URL(string: "https://jikan.lucashdo.com")!)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Profile")
    }
}
