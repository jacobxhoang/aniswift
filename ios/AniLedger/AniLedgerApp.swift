import AuthenticationServices
import SwiftUI

@main
@MainActor
struct AniLedgerApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            TabView {
                stack { HomeScreen() }
                    .tabItem { Label("Home", systemImage: "house") }
                stack { ListsScreen() }
                    .tabItem { Label("My Lists", systemImage: "checklist") }
                stack { DiscoverScreen() }
                    .tabItem { Label("Discover", systemImage: "safari") }
                stack { FriendsScreen() }
                    .tabItem { Label("Friends", systemImage: "person.2") }
                stack { AccountScreen() }
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
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

    private func stack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: Title.self) { TitleScreen(title: $0) }
        }
    }
}

enum Palette {
    static let background = Color(red: 0.055, green: 0.085, blue: 0.13)
    static let surface = Color(red: 0.09, green: 0.14, blue: 0.21)
    static let accent = Color(red: 0.58, green: 0.83, blue: 0.99)
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
                                .padding(6).background(.black.opacity(0.75), in: .capsule).padding(5)
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
        .buttonStyle(.borderedProminent)
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
                    Button("Sign out", role: .destructive) { store.disconnect() }
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
                Link("AniLedger website", destination: API.backend)
                Link("Tenrai", destination: URL(string: "https://tenrai.org")!)
                Link("Jikan Edge", destination: URL(string: "https://jikan.lucashdo.com")!)
            }
        }.navigationTitle("Account")
    }
}
