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
                    LedgerSectionTitle("Recent updates")
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
            LedgerSectionTitle(label)
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
    @State private var searchPresented = false
    @State private var sort = ListSort.recent
    @State private var paging = false
    @State private var pendingRemoval: ListEntry?
    @State private var saving: Set<String> = []
    private let rowInset: CGFloat = 10

    private enum ListSort: String, CaseIterable {
        case recent = "Recently updated"
        case title = "Title"
        case rating = "My rating"
    }

    init(kind: Kind) {
        self.kind = kind
        _collapsed = State(initialValue: Set(kind.statuses.dropFirst().dropLast()))
    }

    private var entries: [ListEntry] {
        let entries = store.lists[kind, default: []]
        return searchTerm.isEmpty ? entries.filter { !store.organization.hidden.contains($0.id) } : entries
    }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    var body: some View {
        if store.account == nil {
            list
        } else {
            list
                .searchable(text: $query, isPresented: $searchPresented,
                            placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
                .onChange(of: searchPresented) { _, presented in
                    if !presented { query = "" }
                }
        }
    }

    private var list: some View {
        List {
            if store.checking {
                ProgressView("Checking session").listRowBackground(Color.clear)
            } else if store.account == nil {
                SignInButton().listRowBackground(Color.clear)
            } else {
                ForEach(kind.statuses, id: \.self) { status in
                    let group = entries.filter { $0.status == status }
                    let matches = visibleEntries(group)
                    if searchTerm.isEmpty || !matches.isEmpty {
                        groupHeader(status, count: searchTerm.isEmpty ? group.count : matches.count)
                            .listRowInsets(EdgeInsets(top: 4, leading: rowInset, bottom: 4, trailing: rowInset))
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
                    }.disabled(paging || store.refreshingLists.contains(kind)).listRowBackground(Color.clear)
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
                if !searchPresented {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { searchPresented = true } label: {
                            Label("Search list", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
                Text(statusLabel(status)).foregroundStyle(.secondary)
                Spacer()
                Text("\(count)\(partial ? "+" : "")").monospacedDigit()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
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
        let link = NavigationLink(value: item.title) {
            HStack(alignment: .top, spacing: 8) {
                Art(url: item.title.image, symbol: kind == .anime ? "film" : "book")
                    .frame(width: 80, height: 116)
                    .clipShape(.rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    let total = item.title.total.flatMap { $0 > 0 ? String($0) : nil }
                    if item.status.hasPrefix("plan_to"), let total {
                        Text("\(total) \(kind.unit.lowercased()) total").foregroundStyle(.secondary)
                    } else if !item.status.hasPrefix("plan_to") {
                        Text("\(item.progress) / \(total ?? "?") \(kind.unit.lowercased())").foregroundStyle(.secondary)
                    }
                    if item.rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.caption)
                                .accessibilityHidden(true)
                            Text(item.rating.formatted()).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("My rating \(item.rating) out of ten")
                    }
                }
                .font(.subheadline)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        return Group {
            if #available(iOS 26.0, *) {
                link.navigationLinkIndicatorVisibility(.hidden)
            } else {
                link
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: rowInset, bottom: 4, trailing: rowInset))
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

private enum DiscoverShelf: String, CaseIterable, Identifiable {
    case airing = "Airing anime"
    case current = "Current season"
    case upcoming = "Upcoming season"
    case animeRank = "Top ranked anime"
    case movies = "Top ranked movies"
    case animePopular = "Popular anime"
    case mangaPublishing = "Popular publishing manga"
    case mangaRank = "Top ranked manga"
    case mangaPopular = "Popular manga"
    case manhwa = "Popular manhwa"

    var id: Self { self }
    var kind: Kind {
        switch self {
        case .mangaPublishing, .mangaRank, .mangaPopular, .manhwa: .manga
        default: .anime
        }
    }
    var path: String {
        switch self {
        case .current: "seasons/now"
        case .upcoming: "seasons/upcoming"
        default: "top/\(kind.rawValue)"
        }
    }
    var query: [URLQueryItem] {
        switch self {
        case .airing: [URLQueryItem(name: "filter", value: "airing")]
        case .movies: [URLQueryItem(name: "type", value: "movie")]
        case .animePopular, .mangaPopular: [URLQueryItem(name: "filter", value: "bypopularity")]
        case .mangaPublishing: [URLQueryItem(name: "filter", value: "publishing")]
        case .manhwa: [URLQueryItem(name: "type", value: "manhwa"), URLQueryItem(name: "filter", value: "bypopularity")]
        default: []
        }
    }

    @MainActor
    func page(_ page: Int, api: API, refresh: Bool = false) async throws -> Page<Title> {
        let pageQuery = [URLQueryItem(name: "page", value: String(page))]
        do {
            return catalogPage(try await api.catalog(path, query + pageQuery, refresh: refresh), kind: kind)
        } catch {
            try Task.checkCancellation()
            guard self == .manhwa else { throw error }
            let fallback = [URLQueryItem(name: "type", value: "manhwa"),
                            URLQueryItem(name: "order_by", value: "members"), URLQueryItem(name: "sort", value: "desc")]
            return catalogPage(try await api.catalog("manga", fallback + pageQuery, refresh: refresh), kind: kind)
        }
    }
}

struct PosterShelf<Trailing: View>: View {
    @EnvironmentObject private var store: Store
    let heading: String
    let titles: [Title]
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LedgerSectionTitle(heading)
                Spacer()
                trailing
            }.padding(.horizontal, LedgerLayout.inset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(unique(titles)) { title in
                        VStack(alignment: .leading, spacing: 3) {
                            CoverTile(title: title, showsScore: false)
                            if let entry = store.lists[title.kind]?.first(where: { $0.id == title.id }) {
                                Text(statusLabel(entry.status)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.frame(width: LedgerLayout.posterWidth)
                    }
                }.scrollTargetLayout()
            }
            .contentMargins(.horizontal, LedgerLayout.inset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

struct DiscoverScreen: View {
    @EnvironmentObject private var store: Store
    @State private var shelves: [DiscoverShelf: [Title]] = [:]
    @State private var search = ""
    @State private var loading = true
    @State private var searchKind: Kind = .anime

    var body: some View {
        Group {
            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PosterResults(name: "Search results", shelf: nil, query: search, kind: searchKind)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Picker("Search category", selection: $searchKind) {
                            ForEach(Kind.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).padding(.horizontal, LedgerLayout.inset).padding(.vertical, 6)
                            .background(.regularMaterial)
                    }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                        ForEach(DiscoverShelf.allCases) { shelf in
                            if let titles = shelves[shelf], !titles.isEmpty {
                                PosterShelf(heading: shelf.rawValue, titles: Array(titles.prefix(14))) {
                                    NavigationLink {
                                        PosterResults(name: shelf.rawValue, shelf: shelf, query: "", kind: shelf.kind)
                                            .navigationTitle(shelf.rawValue)
                                    } label: { Label("View all", systemImage: "chevron.right").font(.caption.weight(.semibold)).frame(minHeight: 44) }
                                }
                            }
                        }
                        if loading { ProgressView("Loading Discover").frame(maxWidth: .infinity) }
                        else if shelves.values.allSatisfy(\.isEmpty) {
                            VStack(spacing: 12) {
                                Label("Catalog unavailable", systemImage: "safari").foregroundStyle(.secondary)
                                Button("Retry") { Task { await loadShelves(refresh: true) } }.ledgerGlassButton()
                            }.frame(maxWidth: .infinity)
                        }
                    }.padding(.vertical, 18)
                }
                .refreshable { await loadShelves(refresh: true) }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .toolbar {
            if search.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CatalogBrowser() } label: { Label("Browse catalog", systemImage: "line.3.horizontal.decrease") }
                }
            }
        }
        .task { if shelves.isEmpty { await loadShelves() } }
    }

    private func loadShelves(refresh: Bool = false) async {
        loading = true
        defer { loading = false }
        for shelf in DiscoverShelf.allCases {
            if Task.isCancelled { return }
            if let page = try? await shelf.page(1, api: store.api, refresh: refresh), !Task.isCancelled {
                shelves[shelf] = page.items
            }
        }
    }
}

private struct PosterResults: View {
    @EnvironmentObject private var store: Store
    let name: String
    let shelf: DiscoverShelf?
    let query: String
    let kind: Kind
    @State private var titles: [Title] = []
    @State private var page = 1
    @State private var more = false
    @State private var loading = true
    @State private var failed = false
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                    ForEach(titles) { CoverTile(title: $0) }
                }
                if loading { ProgressView().accessibilityLabel("Loading \(name)") }
                else if failed {
                    Text("Could not load \(name.lowercased()).").foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                } else if titles.isEmpty { Text("No titles found.").foregroundStyle(.secondary) }
                if more && !loading && !failed { Button("Load more") { Task { await load() } } }
            }.padding(18).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .task(id: "\(kind.rawValue)-\(query)") {
            generation = UUID()
            titles = []
            page = 1
            more = false
            await load()
        }
    }

    private func load() async {
        let current = generation
        loading = true
        failed = false
        defer { if current == generation { loading = false } }
        do {
            let result: Page<Title>
            if let shelf { result = try await shelf.page(page, api: store.api) }
            else {
                if page == 1 { try await Task.sleep(for: .milliseconds(300)) }
                let filters = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "q", value: query)]
                result = catalogPage(try await store.api.catalog(kind.rawValue, filters), kind: kind)
            }
            guard !Task.isCancelled, current == generation else { return }
            titles = unique(titles + result.items)
            page += 1
            more = result.more
        } catch {
            if !Task.isCancelled && current == generation { failed = true }
        }
    }
}

private enum BrowseMode: String, CaseIterable, Identifiable {
    case popular = "Top rated", season = "Seasonal", airing = "Airing", upcoming = "Upcoming"
    var id: Self { self }
}

struct CatalogBrowser: View {
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
        .navigationTitle("Browse catalog")
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
    @State private var selectedFriend: Friend?
    @State private var selectedTitle: Title?

    var body: some View {
        List {
            if store.checking { ProgressView("Checking session").listRowBackground(Color.clear) }
            else if store.account == nil {
                VStack(alignment: .leading, spacing: LedgerLayout.gap) {
                    Text("See what your MyAnimeList friends are watching and reading.").foregroundStyle(.secondary)
                    SignInButton()
                }.listRowBackground(Color.clear)
            } else {
                if let message = store.friendMessage {
                    Text(message).foregroundStyle(.secondary).listRowBackground(Color.clear)
                    Button("Retry") { Task { await store.loadFriends(reset: true) } }.listRowBackground(Color.clear)
                }
                ForEach(store.activity) { item in
                    PreferredTitle(title: item.title) { title in
                        feedRow(item, title: title)
                    }
                        .listRowInsets(EdgeInsets(top: 9, leading: LedgerLayout.inset, bottom: 9, trailing: LedgerLayout.inset))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.white.opacity(0.20))
                }
                if store.loadingFriends { ProgressView("Loading friend activity").listRowBackground(Color.clear) }
                else if store.activity.isEmpty { Text("No public friend updates loaded.").foregroundStyle(.secondary).listRowBackground(Color.clear) }
                if store.checkedFriends < store.friends.count && !store.loadingFriends {
                    Button("Check more friends") { Task { await store.loadFriends() } }.listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationDestination(item: $selectedFriend) { FriendProfileScreen(friend: $0) }
        .navigationDestination(item: $selectedTitle) { TitleScreen(title: $0) }
        .navigationTitle("Friends Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.account != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.loadFriends(reset: true) } } label: {
                        Label("Refresh friends feed", systemImage: "arrow.clockwise")
                    }.disabled(store.loadingFriends)
                }
            }
        }
        .task(id: store.account?.id) { if store.checkedFriends == 0 { await store.loadFriends() } }
        .refreshable { await store.loadFriends(reset: true) }
    }

    private func feedRow(_ item: FriendUpdate, title: Title) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { selectedFriend = item.friend } label: {
                Art(url: item.friend.avatar, symbol: "person.fill")
                    .frame(width: 46, height: 46)
                    .clipShape(.rect(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.friend.name)’s profile")

            VStack(alignment: .leading, spacing: 5) {
                Button { selectedFriend = item.friend } label: {
                    Text(item.friend.name).font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens their profile")

                Button { selectedTitle = title } label: {
                    Text("\(activityPhrase(item)) \(Text(title.name).bold())")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let details = [item.score.flatMap { $0 > 0 ? "\($0)/10" : nil }, item.date.map { displayDate($0) }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !details.isEmpty { Text(details).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { selectedTitle = title } label: {
                Art(url: title.image).frame(width: 48, height: 68)
                    .clipShape(.rect(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title.name)")
        }
    }

    private func activityPhrase(_ item: FriendUpdate) -> String {
        let status = item.status?.lowercased().replacingOccurrences(of: "_", with: " ")
        if status == "completed" { return "completed" }
        if status?.hasPrefix("plan to") == true { return "plans to \(item.title.kind == .anime ? "watch" : "read")" }
        if status == "dropped" { return "dropped" }
        if status == "on hold" { return "put on hold" }
        if let progress = item.progress, progress > 0 {
            let unit = item.title.kind == .anime ? "episode" : "chapter"
            return "\(item.title.kind == .anime ? "watched" : "read") through \(unit) \(progress) of"
        }
        return "updated"
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
