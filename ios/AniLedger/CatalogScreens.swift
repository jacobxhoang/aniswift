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
    let kind: Kind
    @State private var collapsed: Set<String> = []
    @State private var query = ""
    @State private var searching = false
    @State private var sort = ListSort.recent
    @State private var paging = false
    @State private var pendingRemoval: ListEntry?
    @State private var saving: Set<String> = []
    @FocusState private var searchFocused: Bool

    private enum ListSort: String, CaseIterable {
        case recent = "Recently updated"
        case title = "Title"
        case rating = "My rating"
    }

    init(kind: Kind) {
        self.kind = kind
        _collapsed = State(initialValue: Set(kind.statuses.dropFirst().dropLast()))
    }

    private var entries: [ListEntry] { store.lists[kind, default: []] }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    var body: some View {
        List {
            if store.checking {
                ProgressView("Checking session").listRowBackground(Color.clear)
            } else if store.account == nil {
                SignInButton().listRowBackground(Color.clear)
            } else {
                if searching {
                    TextField("Search \(kind.label) list", text: $query)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(Palette.surface)
                }
                ForEach(kind.statuses, id: \.self) { status in
                    let group = entries.filter { $0.status == status }
                    let matches = visibleEntries(group)
                    if searchTerm.isEmpty || !matches.isEmpty {
                        groupHeader(status, count: searchTerm.isEmpty ? group.count : matches.count)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        if !collapsed.contains(status) || !searchTerm.isEmpty {
                            ForEach(matches) { item in entryRow(item) }
                        }
                    }
                }
                if !searchTerm.isEmpty && visibleEntries(entries).isEmpty {
                    Text("No matches in your loaded list.").foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                if let page = store.nextList[kind] {
                    Button(paging ? "Loading…" : "Load more entries") {
                        Task {
                            guard !paging else { return }
                            paging = true
                            defer { paging = false }
                            do { try await store.loadList(kind, page: page) }
                            catch { store.handle(error) }
                        }
                    }.disabled(paging).listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.account != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(ListSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Label("Sort list", systemImage: "line.3.horizontal.decrease") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        searching.toggle()
                        if !searching { query = "" }
                    } label: { Label(searching ? "Close search" : "Search list", systemImage: searching ? "xmark" : "magnifyingglass") }
                }
            }
        }
        .onChange(of: searching) { _, showing in searchFocused = showing }
        .refreshable { await store.loadLists(force: true) }
        .confirmationDialog("Remove from your MyAnimeList list?", isPresented: removalPresented, presenting: pendingRemoval) { item in
            Button("Remove", role: .destructive) { update(item, change: nil) }
            Button("Cancel", role: .cancel) {}
        } message: { item in Text(item.title.name) }
    }

    private func groupHeader(_ status: String, count: Int) -> some View {
        let expanded = !collapsed.contains(status) || !searchTerm.isEmpty
        let partial = store.nextList[kind] != nil && searchTerm.isEmpty
        return Button {
            if collapsed.contains(status) { collapsed.remove(status) }
            else { collapsed.insert(status) }
        } label: {
            HStack(spacing: 12) {
                Text(statusLabel(status)).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(count)\(partial ? "+" : "")").monospacedDigit()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .ledgerGlassBadge()
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .disabled(!searchTerm.isEmpty)
    }

    private func visibleEntries(_ group: [ListEntry]) -> [ListEntry] {
        let matches = group.filter { entry in
            searchTerm.isEmpty || entry.title.name.localizedCaseInsensitiveContains(searchTerm)
                || entry.title.original.localizedCaseInsensitiveContains(searchTerm)
        }
        switch sort {
        case .recent: return matches.sorted { $0.updated > $1.updated }
        case .title: return matches.sorted { $0.title.name.localizedStandardCompare($1.title.name) == .orderedAscending }
        case .rating: return matches.sorted { $0.rating == $1.rating ? $0.updated > $1.updated : $0.rating > $1.rating }
        }
    }

    private func entryRow(_ item: ListEntry) -> some View {
        NavigationLink(value: item.title) {
            HStack(alignment: .top, spacing: 12) {
                Art(url: item.title.image, symbol: kind == .anime ? "film" : "book")
                    .frame(width: 80, height: 116)
                    .clipShape(.rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    let total = item.title.total.flatMap { $0 > 0 ? String($0) : nil }
                    if item.status.hasPrefix("plan_to"), let total {
                        Text("\(total) \(kind.unit.lowercased()) total").foregroundStyle(.secondary)
                    } else if !item.status.hasPrefix("plan_to") {
                        Text("\(item.progress) / \(total ?? "?") \(kind.unit.lowercased())").foregroundStyle(.secondary)
                    }
                    if item.rating > 0 {
                        Label("\(item.rating)", systemImage: "star.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("My rating \(item.rating) out of ten")
                    }
                }.font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingRemoval = item } label: { Label("Remove", systemImage: "trash") }
                .disabled(saving.contains(item.id))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if (item.title.total ?? 0) <= 0 || item.progress < (item.title.total ?? 0) {
                Button {
                    update(item, change: ListChange(status: item.status, progress: item.progress + 1, rating: item.rating))
                } label: { Label("+1 progress", systemImage: "plus") }
                .tint(.gray)
                .disabled(saving.contains(item.id))
            }
        }
    }

    private func update(_ item: ListEntry, change: ListChange?) {
        guard saving.insert(item.id).inserted else { return }
        Task {
            defer { saving.remove(item.id) }
            do { try await store.change(item.title, change) }
            catch { store.handle(error) }
        }
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
