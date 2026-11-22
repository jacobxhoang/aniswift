import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var store: Store
    @State private var season: [Title] = []
    @State private var airing: [Title] = []
    @State private var upcoming: [Title] = []
    @State private var anime: [Title] = []
    @State private var manga: [Title] = []
    @State private var animeHint = "Loading suggestions…"

    private var suggestionsKey: String { "\(store.checking)-\(store.account?.id ?? 0)-\(store.lists[.manga, default: []].count)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent list updates").font(.headline)
                    if store.checking {
                        ProgressView("Checking session")
                    } else if store.account == nil {
                        SignInButton()
                    } else if store.recent.isEmpty {
                        Text("Your latest list updates will appear here.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.recent.prefix(4))) { item in
                            NavigationLink(value: item.title) {
                                TitleRow(title: item.title, note: "\(statusLabel(item.status)) · \(item.progress) \(item.title.kind.unit.lowercased())")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .ledgerPanel()
                .padding(.horizontal)
                Rail(name: "This season", titles: season)
                Rail(name: store.account == nil ? "Anime suggestions" : "My AnimeList suggestions", titles: anime, empty: animeHint)
                Rail(name: "AniLedger manga suggestions", titles: manga)
                ranking("Top airing anime", titles: airing)
                ranking("Top upcoming anime", titles: upcoming)
            }.padding(.vertical)
        }
        .background(Palette.canvas)
        .navigationTitle("AniLedger")
        .task { await loadCatalog() }
        .task(id: suggestionsKey) { if !store.checking { await loadSuggestions() } }
        .refreshable {
            await store.loadLists(force: true)
            await loadCatalog()
            await loadSuggestions()
        }
    }

    private func ranking(_ label: String, titles: [Title]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.headline)
            if titles.isEmpty { Text("No rankings available.").foregroundStyle(.secondary) }
            ForEach(Array(unique(titles).prefix(4).enumerated()), id: \.element.id) { rank, title in
                NavigationLink(value: title) {
                    HStack(spacing: 12) {
                        Text(String(rank + 1)).monospacedDigit().foregroundStyle(.secondary)
                        TitleRow(title: title, note: title.format ?? "Anime")
                    }
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal)
    }

    private func loadCatalog() async {
        async let seasonal = store.api.catalog("seasons/now")
        async let current = store.api.catalog("top/anime", [URLQueryItem(name: "filter", value: "airing")])
        async let later = store.api.catalog("top/anime", [URLQueryItem(name: "filter", value: "upcoming")])
        if let result = try? await seasonal { season = catalogPage(result, kind: .anime).items }
        if let result = try? await current { airing = catalogPage(result, kind: .anime).items }
        if let result = try? await later { upcoming = catalogPage(result, kind: .anime).items }
        else if let result = try? await store.api.catalog("seasons/upcoming") {
            upcoming = catalogPage(result, kind: .anime).items.sorted { ($0.members ?? 0) > ($1.members ?? 0) }
        }
    }

    private func loadSuggestions() async {
        let user = store.account
        anime = []
        animeHint = "Loading suggestions…"
        do {
            let items: [Title]
            if user != nil { items = try await store.api.suggestions() }
            else { items = recommendations(try await store.api.catalog("recommendations/anime"), kind: .anime) }
            guard !Task.isCancelled, store.account == user else { return }
            anime = items
            animeHint = "No anime suggestions available."
        } catch {
            guard !Task.isCancelled, store.account == user else { return }
            animeHint = "Could not load anime suggestions. Pull to retry."
        }
        var suggestions: [Title] = []
        let sources = store.lists[.manga, default: []].filter { $0.rating >= 7 || $0.status == "completed" }.prefix(2)
        for source in sources {
            if let result = try? await store.api.catalog("manga/\(source.title.malID)/recommendations") {
                suggestions += recommendations(result, kind: .manga)
            }
        }
        if let result = try? await store.api.catalog("recommendations/manga") {
            suggestions += recommendations(result, kind: .manga)
        }
        guard !Task.isCancelled, store.account == user else { return }
        let saved = Set(store.lists[.manga, default: []].map(\.id))
        manga = Array(unique(suggestions).filter { !saved.contains($0.id) }.prefix(20))
    }
}

struct ListsScreen: View {
    @EnvironmentObject private var store: Store
    @State private var kind: Kind = .anime
    @State private var status = "all"
    @State private var paging = false

    var body: some View {
        List {
            if store.checking { ProgressView("Checking session") }
            else if store.account == nil { SignInButton() }
            else {
                Section {
                    Picker("List", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Status", selection: $status) {
                        Text("All statuses").tag("all")
                        ForEach(kind.statuses, id: \.self) { Text(statusLabel($0)).tag($0) }
                    }
                }
                let entries = store.lists[kind, default: []].filter { status == "all" || $0.status == status }
                if entries.isEmpty { Text("No entries loaded for this filter.").foregroundStyle(.secondary) }
                ForEach(entries) { item in
                    NavigationLink(value: item.title) {
                        TitleRow(title: item.title, note: "\(statusLabel(item.status)) · \(item.progress)/\(item.title.total.map { String($0) } ?? "?")")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if item.title.total == nil || item.progress < item.title.total! {
                            Button {
                                Task {
                                    do {
                                        try await store.change(item.title, ListChange(status: item.status, progress: item.progress + 1, rating: item.rating))
                                    } catch { store.handle(error) }
                                }
                            } label: { Label("+1 progress", systemImage: "plus") }.tint(Palette.accent)
                        }
                    }
                }
                if let page = store.nextList[kind] {
                    Button(paging ? "Loading…" : "Load more") {
                        let selected = kind
                        Task {
                            paging = true
                            defer { paging = false }
                            do { try await store.loadList(selected, page: page) }
                            catch { store.handle(error) }
                        }
                    }.disabled(paging)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("My Lists")
        .onChange(of: kind) { _, _ in status = "all" }
        .refreshable { await store.loadLists(force: true) }
    }
}

private enum BrowseMode: String, CaseIterable, Identifiable {
    case popular = "Top rated", season = "Seasonal", airing = "Airing", upcoming = "Upcoming"
    var id: Self { self }
}

struct DiscoverScreen: View {
    @EnvironmentObject private var store: Store
    @State private var kind: Kind = .anime
    @State private var mode: BrowseMode = .popular
    @State private var search = ""
    @State private var season = ["winter", "spring", "summer", "fall"][(Calendar.current.component(.month, from: Date()) - 1) / 3]
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var titles: [Title] = []
    @State private var loading = true
    @State private var message: String?
    @State private var page = 1
    @State private var next = false
    @State private var activeQuery = UUID()
    @State private var reload = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Media type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                if search.isEmpty && kind == .anime {
                    Picker("Catalog", selection: $mode) {
                        ForEach(BrowseMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if mode == .season {
                        HStack {
                            Picker("Season", selection: $season) {
                                ForEach(["winter", "spring", "summer", "fall"], id: \.self) { Text($0.capitalized).tag($0) }
                            }
                            Picker("Year", selection: $year) {
                                ForEach((1917...(Calendar.current.component(.year, from: Date()) + 2)).reversed(), id: \.self) {
                                    Text(String($0)).tag($0)
                                }
                            }
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(.secondary); Button("Retry") { reload += 1 } }
                if titles.isEmpty && !loading && message == nil { Text("No matching titles.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 14) {
                    ForEach(titles) { CoverTile(title: $0) }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if next && !loading { Button("Load more") { Task { await load(reset: false) } } }
            }.padding()
        }
        .navigationTitle("Discover")
        .searchable(text: $search, prompt: "Search anime or manga")
        .background(Palette.canvas)
        .task(id: "\(kind)-\(mode)-\(search)-\(year)-\(season)-\(reload)") {
            await load(reset: true)
        }
    }

    private func load(reset: Bool) async {
        let request = UUID()
        activeQuery = request
        loading = true
        message = nil
        if reset { page = 1; titles = []; next = false }
        let selected = kind
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var params = [URLQueryItem(name: "page", value: String(page))]
        let path: String
        if !query.isEmpty {
            path = selected.rawValue
            params.append(URLQueryItem(name: "q", value: query))
        } else if selected == .anime && mode == .season {
            path = "seasons/\(year)/\(season)"
        } else {
            path = "top/\(selected.rawValue)"
            if selected == .anime && mode == .airing { params.append(URLQueryItem(name: "filter", value: "airing")) }
            if selected == .anime && mode == .upcoming { params.append(URLQueryItem(name: "filter", value: "upcoming")) }
        }
        defer { if activeQuery == request { loading = false } }
        do {
            if !query.isEmpty { try await Task.sleep(for: .milliseconds(350)) }
            let response: Fields
            do { response = try await store.api.catalog(path, params) }
            catch {
                try Task.checkCancellation()
                guard query.isEmpty, selected == .anime, mode == .upcoming else { throw error }
                response = try await store.api.catalog("seasons/upcoming", [params[0]])
            }
            guard !Task.isCancelled, activeQuery == request else { return }
            let result = catalogPage(response, kind: selected)
            titles = unique(titles + result.items)
            next = result.more
            page += 1
        } catch {
            if !Task.isCancelled && activeQuery == request { message = error.localizedDescription }
        }
    }
}

struct FriendsScreen: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            if store.checking { ProgressView("Checking session") }
            else if store.account == nil { SignInButton() }
            else {
                if let message = store.friendMessage {
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.loadFriends(reset: true) } }
                }
                ForEach(store.activity) { item in
                    NavigationLink(value: item.title) {
                        VStack(alignment: .leading, spacing: 7) {
                            FriendCaption(item: item)
                            TitleRow(title: item.title, note: statusLabel(item.status ?? ""))
                        }
                    }
                }
                if store.loadingFriends { ProgressView("Loading friend activity") }
                else if store.activity.isEmpty { Text("No public friend updates loaded.").foregroundStyle(.secondary) }
                if store.checkedFriends < store.friends.count {
                    Button("Check more friends") { Task { await store.loadFriends() } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Friends")
        .task(id: store.account?.id) { if store.checkedFriends == 0 { await store.loadFriends() } }
        .refreshable { await store.loadFriends(reset: true) }
    }
}

struct FriendCaption: View {
    let item: FriendUpdate

    var body: some View {
        HStack(spacing: 8) {
            Art(url: item.friend.avatar, symbol: "person.fill")
                .frame(width: 28, height: 28).clipShape(.circle)
            Text(item.friend.name).font(.caption.weight(.semibold))
            Spacer()
            Text(displayDate(item.date)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
