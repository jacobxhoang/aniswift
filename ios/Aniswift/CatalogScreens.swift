import SwiftUI

private struct ListStatusGlass: ViewModifier {
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(isInteractive), in: .capsule)
        } else {
            content
                .background(.thinMaterial, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.16)).allowsHitTesting(false)
                }
        }
    }
}

struct ListStatusHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let count: Int
    let expanded: Bool
    let partial: Bool
    var isInteractive = true
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(count)\(partial ? "+" : "")").monospacedDigit()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: expanded)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(ListStatusGlass(isInteractive: isInteractive))
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .disabled(!isInteractive)
    }
}

struct ListsScreen: View {
    @EnvironmentObject private var store: Store
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let kind: Kind
    @State private var collapsed: Set<String> = []
    @State private var query = ""
    @State private var sort = ListSort.recent
    @State private var paging = false
    @State private var listPageError: String?
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

    private func displayName(_ title: Title) -> String { title.displayName(for: titleLanguage) }
    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    var body: some View {
        if store.account != nil {
            list.ledgerSearch(text: $query, prompt: "Search")
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if store.checking {
                ProgressView("Checking session").listRowBackground(Color.clear)
            } else if store.account == nil {
                SignInButton().listRowBackground(Color.clear)
            } else if store.lists[kind] == nil, store.pendingListLoads.contains(kind) {
                ListSkeleton(kind: kind)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if store.lists[kind] == nil, let failure = store.listFailures[kind] {
                VStack(alignment: .leading, spacing: 10) {
                    Text(failure).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.loadLists(force: true) } }
                        .ledgerGlassButton()
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if store.lists[kind]?.isEmpty == true, searchTerm.isEmpty, store.nextList[kind] == nil,
                !store.refreshingLists.contains(kind)
            {
                // An empty state belongs in the page, not in a row: inside a List
                // it centres against the row's insets instead of the screen.
                VStack(spacing: 6) {
                    Label("No \(kind.label.lowercased()) yet", systemImage: kind == .anime ? "tv" : "books.vertical")
                        .font(.headline)
                    Text("Titles you add from Discover or a title page appear here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                if !searchTerm.isEmpty && visibleEntries(entries).isEmpty && store.nextList[kind] == nil {
                    Text("No matches in your list.").foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                if let page = store.nextList[kind] {
                    if let listPageError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(listPageError).foregroundStyle(.secondary)
                            Button("Retry") { Task { await loadListPage(page) } }
                        }
                        .listRowBackground(Color.clear)
                    } else if !store.refreshingLists.contains(kind) {
                        NextPageIndicator(label: "Loading entries", page: page) { await loadListPage(page) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
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
                        .sensoryFeedback(.selection, trigger: sort)
                    } label: { Label("Sort list", systemImage: "line.3.horizontal.decrease") }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .prefetchingPosters(entries) { $0.title.image }
        .onChange(of: store.account?.id) { _, _ in
            query = ""
            listPageError = nil
        }
        .refreshable {
            await store.loadLists(force: true)
            listPageError = nil
        }
        .confirmationDialog("Remove from your MyAnimeList list?", isPresented: removalPresented, presenting: pendingRemoval) { item in
            Button("Remove", role: .destructive) { update(item, change: nil) }
            Button("Cancel", role: .cancel) {}
        } message: { item in Text(displayName(item.title)) }
    }

    private func groupHeader(_ status: String, count: Int) -> some View {
        let expanded = !collapsed.contains(status) || !searchTerm.isEmpty
        let partial = store.nextList[kind] != nil && searchTerm.isEmpty
        return ListStatusHeader(title: statusLabel(status), count: count, expanded: expanded,
                                partial: partial, isInteractive: searchTerm.isEmpty) {
            if expanded { collapsed.insert(status) }
            else { collapsed.remove(status) }
        }
    }

    private func visibleEntries(_ group: [ListEntry]) -> [ListEntry] {
        let matches = group.filter { entry in
            searchTerm.isEmpty || entry.title.name.localizedCaseInsensitiveContains(searchTerm)
                || entry.title.original.localizedCaseInsensitiveContains(searchTerm)
        }
        switch sort {
        case .recent: return matches.sorted { $0.updated > $1.updated }
        case .title:
            return matches.sorted {
                displayName($0.title).localizedStandardCompare(displayName($1.title)) == .orderedAscending
            }
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
                    Text(displayName(item.title))
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
                .tint(.red)
                .disabled(saving.contains(item.id))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if (item.title.total ?? 0) <= 0 || item.progress < (item.title.total ?? 0) {
                Button {
                    update(item, change: ListChange(status: item.status, progress: item.progress + 1, rating: item.rating))
                } label: { Label(kind == .anime ? "Episode" : "Chapter", systemImage: "plus") }
                .tint(Color(red: 0.03, green: 0.57, blue: 0.08))
                .accessibilityLabel(kind == .anime ? "Add one episode" : "Add one chapter")
                .disabled(saving.contains(item.id))
            }
        }
    }

    private func loadListPage(_ page: Int) async {
        guard !paging, !store.refreshingLists.contains(kind), store.nextList[kind] == page else { return }
        paging = true
        defer { paging = false }
        do {
            try await store.loadList(kind, page: page)
            listPageError = nil
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.status == 401 { store.handle(error) }
            else { listPageError = "Could not load more entries." }
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

enum DiscoverShelf: String, CaseIterable, Identifiable {
    case airing = "Currently airing anime"
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
    var heading: String {
        guard self == .current || self == .upcoming else { return rawValue }
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let date = self == .upcoming ? (calendar.date(byAdding: .month, value: 3, to: today) ?? today) : today
        let names = ["Winter", "Spring", "Summer", "Fall"]
        let name = names[(calendar.component(.month, from: date) - 1) / 3]
        let year = calendar.component(.year, from: date)
        return "\(rawValue) – \(name) \(year)"
    }

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
    func page(_ page: Int, api: any APIClient, refresh: Bool = false) async throws -> Page<Title> {
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
    var isDiscoverShelf = false
    @ViewBuilder var trailing: Trailing

    private var posterWidth: CGFloat { isDiscoverShelf ? LedgerLayout.detailPosterWidth : LedgerLayout.posterWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: isDiscoverShelf ? 6 : 12) {
            HStack {
                if isDiscoverShelf {
                    Text(heading.uppercased()).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    LedgerSectionTitle(heading)
                }
                Spacer()
                trailing
            }.padding(.horizontal, LedgerLayout.inset)
            LedgerShelf(spacing: isDiscoverShelf ? 8 : LedgerLayout.gap, inset: LedgerLayout.inset) {
                ForEach(unique(titles)) { title in
                    VStack(alignment: .leading, spacing: 3) {
                        CoverTile(title: title, showsScore: false, reservesCaptionSpace: false, posterWidth: posterWidth)
                        if let entry = store.lists[title.kind]?.first(where: { $0.id == title.id }) {
                            Text(statusLabel(entry.status)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(width: posterWidth)
                }
            }
        }
    }
}

struct DiscoverScreen: View {
    @EnvironmentObject private var store: Store
    @State private var shelves: [DiscoverShelf: [Title]] = [:]
    @State private var search = ""
    @State private var loading = true
    @State private var finishedLoadingShelves = false
    @State private var failedShelves: Set<DiscoverShelf> = []
    @State private var searchKind: Kind = .anime

    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if searchTerm.isEmpty {
                browse
            } else {
                PosterResults(name: "Search results", shelf: nil, query: searchTerm, kind: searchKind)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .ledgerSearch(text: $search, prompt: "Search")
        // The media type is a search scope, not a second bar above the results.
        .searchScopes($searchKind) {
            ForEach(Kind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .sensoryFeedback(.selection, trigger: searchKind)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: CatalogBrowserRoute()) {
                    Label("Browse catalog", systemImage: "square.grid.2x2")
                }
            }
        }
        .task { if !finishedLoadingShelves { await loadShelves() } }
    }

    private var browse: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if loading && shelves.isEmpty {
                    DiscoverSkeleton()
                } else {
                    ForEach(DiscoverShelf.allCases) { shelf in
                        if let titles = shelves[shelf], !titles.isEmpty {
                            PosterShelf(
                                heading: shelf.heading, titles: Array(titles.prefix(14)), isDiscoverShelf: true
                            ) {
                                NavigationLink(value: CatalogResultsRoute(
                                    name: shelf.heading, shelf: shelf, query: "", kind: shelf.kind)) {
                                    LedgerViewAll(section: shelf.rawValue.lowercased())
                                }
                            }
                        }
                    }
                    if loading {
                        ProgressView("Loading Discover").frame(maxWidth: .infinity)
                    } else {
                        if shelves.values.allSatisfy(\.isEmpty) {
                            VStack(spacing: 12) {
                                Label("Catalog unavailable", systemImage: "safari").foregroundStyle(.secondary)
                                Button("Retry") { Task { await loadShelves(refresh: true) } }.ledgerGlassButton()
                            }
                            .frame(maxWidth: .infinity)
                        } else if !failedShelves.isEmpty {
                            Button("Retry unavailable sections") { Task { await loadShelves() } }
                                .ledgerGlassButton()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .refreshable { await loadShelves(refresh: true) }
    }

    private func loadShelves(refresh: Bool = false) async {
        loading = true
        defer { loading = false }
        let pending = DiscoverShelf.allCases.filter { refresh || shelves[$0] == nil || failedShelves.contains($0) }
        let api = store.api
        let batchSize = 3
        for start in stride(from: 0, to: pending.count, by: batchSize) {
            guard !Task.isCancelled else { return }
            let batch = pending[start..<min(start + batchSize, pending.count)]
            await withTaskGroup(of: (DiscoverShelf, [Title]?).self) { group in
                for shelf in batch {
                    group.addTask {
                        let page = try? await shelf.page(1, api: api, refresh: refresh)
                        return (shelf, page?.items)
                    }
                }
                for await (shelf, titles) in group {
                    guard !Task.isCancelled else { break }
                    if let titles {
                        shelves[shelf] = titles
                        failedShelves.remove(shelf)
                    } else {
                        failedShelves.insert(shelf)
                    }
                }
            }
        }
        if !Task.isCancelled { finishedLoadingShelves = true }
    }
}

enum CatalogFacetSort: String, CaseIterable, Identifiable {
    case catalog = "Default"
    case highestRated = "Highest rated"
    case mostPopular = "Most popular"
    case newest = "Newest first"
    case oldest = "Oldest first"

    var id: Self { self }

    var queryItems: [URLQueryItem] {
        let field: String
        let direction: String
        switch self {
        case .catalog: return []
        case .highestRated: (field, direction) = ("score", "desc")
        case .mostPopular: (field, direction) = ("popularity", "asc")
        case .newest: (field, direction) = ("start_date", "desc")
        case .oldest: (field, direction) = ("start_date", "asc")
        }
        var items = [
            URLQueryItem(name: "order_by", value: field),
            URLQueryItem(name: "sort", value: direction)
        ]
        if self == .oldest { items.append(URLQueryItem(name: "nulls", value: "last")) }
        return items
    }
}

struct CatalogFacet: Hashable, Identifiable {
    enum Category: String {
        case genre, theme, studio, producer

        var usesGenreIndex: Bool { self == .genre || self == .theme }
        var filter: String { usesGenreIndex ? "genres" : "producers" }
    }

    let name: String
    let malID: Int?
    let category: Category
    let kind: Kind
    var id: String { name.lowercased() }

    @MainActor
    func page(_ page: Int, query: String, sort: CatalogFacetSort, api: any APIClient,
              refresh: Bool = false) async throws -> Page<Title> {
        let id: Int
        if let malID, malID > 0 {
            id = malID
        } else {
            id = try await resolveID(api: api)
        }
        var filters = [
            URLQueryItem(name: category.filter, value: String(id)),
            URLQueryItem(name: "page", value: String(page))
        ] + sort.queryItems
        if !category.usesGenreIndex && sort == .newest {
            filters.append(URLQueryItem(name: "nulls", value: "first"))
        }
        if !query.isEmpty { filters.append(URLQueryItem(name: "q", value: query)) }
        return catalogPage(try await api.catalog(kind.rawValue, filters, refresh: refresh), kind: kind)
    }

    @MainActor
    private func resolveID(api: any APIClient) async throws -> Int {
        let usesGenreIndex = category.usesGenreIndex
        let path = usesGenreIndex ? "genres/\(kind.rawValue)" : "producers"
        let query = usesGenreIndex
            ? URLQueryItem(name: "filter", value: category == .theme ? "themes" : "genres")
            : URLQueryItem(name: "q", value: name)
        let response = try await api.catalog(path, [query], refresh: false)
        let entries: [Fields] = response.read("data") ?? []
        for entry in entries {
            let aliases: [Fields] = entry.read("titles") ?? []
            let names = [entry.string("name")].compactMap { $0 } + aliases.compactMap { $0.string("title", "name") }
            if names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
               let id: Int = entry.read("mal_id", "malId", "id"), id > 0 {
                return id
            }
        }
        throw APIError(status: 404, message: "Could not find \(name) in the catalog.")
    }
}

struct CatalogFacetScreen: View {
    let facet: CatalogFacet
    @State private var sort = CatalogFacetSort.catalog
    @State private var search = ""

    var body: some View {
        Group {
            if facet.category.usesGenreIndex {
                results
            } else {
                results.ledgerSearch(text: $search, prompt: "Search titles")
            }
        }
        .navigationTitle(facet.category.usesGenreIndex ? facet.name : "More from \(facet.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if facet.category.usesGenreIndex {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort titles", selection: $sort) {
                            ForEach(CatalogFacetSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .sensoryFeedback(.selection, trigger: sort)
                    } label: {
                        Label("Sort titles", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityValue(sort.rawValue)
                }
            }
        }
    }

    private var results: some View {
        PosterResults(name: facet.name, shelf: nil,
                      query: search.trimmingCharacters(in: .whitespacesAndNewlines),
                      kind: facet.kind, facet: facet, sort: facet.category.usesGenreIndex ? sort : .newest)
    }
}

struct NextPageIndicator: View {
    let label: String
    let page: Int
    let load: () async -> Void
    /// A page request that answers without advancing its counter would otherwise
    /// leave this row spinning for as long as the screen is open.
    @State private var finished = false

    var body: some View {
        Group {
            if finished {
                EmptyView()
            } else {
                ProgressView().accessibilityLabel(label)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .task(id: page) {
            finished = false
            await load()
            finished = true
        }
    }
}

private struct SearchResultCard: View {
    let title: Title
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var posterWidth: CGFloat = 96

    private var summary: String {
        var values = [title.format ?? title.kind.label]
        if let total = title.total {
            let unit = title.kind == .anime ? "episode" : "chapter"
            values.append("\(total) \(total == 1 ? unit : unit + "s")")
        }
        if let score = title.score, score > 0 {
            values.append(score.formatted(.number.precision(.fractionLength(2))))
        }
        return values.joined(separator: " · ")
    }

    var body: some View {
        PreferredTitle(title: title) { item, name in
            NavigationLink(value: item) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    poster(item)
                    details(item, name: name)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        Palette.surface
                        if let image = item.image {
                            Art(url: image)
                                .overlay {
                                    LinearGradient(colors: [.black.opacity(0.67), .black.opacity(0.95)],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.18)).allowsHitTesting(false)
                }
                .contentShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func poster(_ item: Title) -> some View {
        PosterArt(url: item.image, symbol: item.kind == .anime ? "film" : "book", width: posterWidth)
            .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
    }

    private func details(_ item: Title, name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline).foregroundStyle(.white).lineLimit(2)
            Text(summary).font(.footnote).foregroundStyle(.white.opacity(0.78))
            if let synopsis = item.synopsis {
                Text(synopsis).font(.subheadline).foregroundStyle(.white.opacity(0.82)).lineLimit(6)
            }
            if let genres = item.genres, !genres.isEmpty {
                FlowLayout {
                    ForEach(Array(genres.prefix(3)), id: \.self) { genre in
                        Text(genre).font(.caption).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.10), in: .capsule)
                            .overlay { Capsule().strokeBorder(.white.opacity(0.38)) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ProducerPeriod: Hashable {
    case announced
    case year(Int)
    case unknown

    init(_ title: Title) {
        if let year = title.releaseYear {
            self = .year(year)
        } else {
            let status = title.catalogStatus?.lowercased().replacingOccurrences(of: "_", with: " ")
            switch status {
            case "not yet aired", "not yet published", "announced", "upcoming":
                self = .announced
            default:
                self = .unknown
            }
        }
    }

    var heading: String {
        switch self {
        case .announced: "Announced"
        case .year(let year): String(year)
        case .unknown: "Year unknown"
        }
    }

    var sortOrder: Int {
        switch self {
        case .announced: Int.max
        case .year(let year): year
        case .unknown: Int.min
        }
    }
}

private struct ProducerTitleRow: View {
    let title: Title

    var body: some View {
        PreferredTitle(title: title) { item, name in
            NavigationLink(value: item) {
                HStack(alignment: .top, spacing: 8) {
                    PosterArt(url: item.image, symbol: item.kind == .anime ? "film" : "book", width: 78)
                        .clipShape(.rect(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.body)
                        if let total = item.total {
                            let unit = item.kind == .anime ? "episode" : "chapter"
                            Text("\(total) \(total == 1 ? unit : unit + "s") total")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct PosterResults: View {
    @EnvironmentObject private var store: Store
    let name: String
    let shelf: DiscoverShelf?
    let query: String
    let kind: Kind
    var facet: CatalogFacet? = nil
    var sort = CatalogFacetSort.catalog
    @State private var titles: [Title] = []
    @State private var page = 1
    @State private var more = false
    @State private var loading = true
    @State private var failed = false
    @State private var generation = UUID()
    @State private var activeRequest: String?
    @State private var visibleResult: String?

    private var requestKey: String { "\(kind.rawValue)-\(sort.rawValue)-\(query)" }
    private var showsProducerRows: Bool { facet?.category.usesGenreIndex == false }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: showsProducerRows ? 8 : 16, pinnedViews: showsProducerRows ? .sectionHeaders : []) {
                if showsProducerRows {
                    producerSections
                } else if query.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                        ForEach(titles) { CoverTile(title: $0) }
                    }
                } else {
                    ForEach(titles) { SearchResultCard(title: $0) }
                }
                if failed {
                    Text("Could not load \(name.lowercased()).").foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                } else if more {
                    NextPageIndicator(label: "Loading more titles", page: page) {
                        if !loading { await load() }
                    }
                } else if loading {
                    ProgressView().accessibilityLabel("Loading \(name)")
                } else if titles.isEmpty {
                    ContentUnavailableView(
                        "No titles found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search or section."))
                }
            }
            .scrollTargetLayout(isEnabled: !query.isEmpty && !showsProducerRows)
            .padding(.horizontal, showsProducerRows ? 8 : 18)
            .padding(.vertical, showsProducerRows ? 4 : 18)
            .frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleResult)
        .background(Palette.background.ignoresSafeArea())
        .refreshable {
            generation = UUID()
            titles = []
            visibleResult = nil
            page = 1
            more = false
            failed = false
            await load(refresh: true)
        }
        .task(id: requestKey) {
            if activeRequest != requestKey {
                generation = UUID()
                activeRequest = requestKey
                titles = []
                visibleResult = nil
                page = 1
                more = false
                failed = false
            }
            if page == 1 && !failed { await load() }
        }
    }

    private var producerSections: some View {
        let groups = Dictionary(grouping: titles, by: ProducerPeriod.init)
        let openPeriod = more ? titles.last.map(ProducerPeriod.init) : nil
        return ForEach(groups.keys.sorted { $0.sortOrder > $1.sortOrder }, id: \.self) { period in
            let items = groups[period, default: []]
            Section {
                ForEach(items) { ProducerTitleRow(title: $0) }
            } header: {
                HStack {
                    Text(period.heading).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(items.count.formatted())\(period == openPeriod ? "+" : "")")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .modifier(ListStatusGlass(isInteractive: false))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .padding(.vertical, 3)
            }
        }
    }

    private func load(refresh: Bool = false) async {
        let current = generation
        loading = true
        failed = false
        defer { if current == generation { loading = false } }
        do {
            let result: Page<Title>
            if page == 1, !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
            if let shelf { result = try await shelf.page(page, api: store.api, refresh: refresh) }
            else if let facet {
                result = try await facet.page(page, query: query, sort: sort, api: store.api, refresh: refresh)
            } else {
                let filters = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "q", value: query)]
                result = catalogPage(
                    try await store.api.catalog(kind.rawValue, filters, refresh: refresh), kind: kind)
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

struct CatalogBrowserRoute: Hashable {}

struct CatalogResultsRoute: Hashable {
    let name: String
    let shelf: DiscoverShelf
    let query: String
    let kind: Kind
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
    @State private var loadedRequest: String?

    private var requestKey: String { "\(kind)-\(mode)-\(search)-\(year)-\(season)-\(reload)" }
    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("Media type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: kind)
                if searchTerm.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 14) {
                        ForEach(titles) { CoverTile(title: $0) }
                    }
                } else {
                    ForEach(titles) { SearchResultCard(title: $0) }
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry") {
                        if page == 1 { reload += 1 }
                        else { Task { await load(reset: false) } }
                    }
                } else if next {
                    NextPageIndicator(label: "Loading more titles", page: page) {
                        if !loading { await load(reset: false) }
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if titles.isEmpty {
                    ContentUnavailableView(
                        "No matching titles",
                        systemImage: "magnifyingglass",
                        description: Text("Adjust the filters or search for another title."))
                }
            }.padding()
        }
        .navigationTitle("Browse catalog")
        .ledgerSearch(text: $search, prompt: "Search anime or manga")
        // Mode, season and year live in one toolbar menu: three rows of pickers
        // above the grid used a third of the first screen for controls.
        .toolbar {
            if searchTerm.isEmpty && kind == .anime {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Catalog", selection: $mode) {
                            ForEach(BrowseMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if mode == .season {
                            Picker("Season", selection: $season) {
                                ForEach(["winter", "spring", "summer", "fall"], id: \.self) { season in
                                    Text(season.capitalized).tag(season)
                                }
                            }
                            Picker("Year", selection: $year) {
                                ForEach(
                                    (1917...(Calendar.current.component(.year, from: Date()) + 2)).reversed(),
                                    id: \.self
                                ) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                        }
                    } label: {
                        Label("Catalog filters", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityValue(mode.rawValue)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: season)
        .sensoryFeedback(.selection, trigger: year)
        .background(Palette.background.ignoresSafeArea())
        .refreshable { await load(reset: true, refresh: true) }
        .task(id: requestKey) {
            guard loadedRequest != requestKey else { return }
            await load(reset: true)
        }
    }

    private func load(reset: Bool, refresh: Bool = false) async {
        let request = UUID()
        let key = requestKey
        activeQuery = request
        loading = true
        message = nil
        if reset { page = 1; titles = []; next = false }
        let selected = kind
        let query = searchTerm
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
            do { response = try await store.api.catalog(path, params, refresh: refresh) }
            catch {
                try Task.checkCancellation()
                guard query.isEmpty, selected == .anime, mode == .upcoming else { throw error }
                response = try await store.api.catalog("seasons/upcoming", [params[0]], refresh: refresh)
            }
            guard !Task.isCancelled, activeQuery == request else { return }
            let result = catalogPage(response, kind: selected)
            titles = unique(titles + result.items)
            loadedRequest = key
            next = result.more
            page += 1
        } catch {
            if !Task.isCancelled && activeQuery == request {
                message = plainMessage(error, fallback: "Could not load the catalog.")
            }
        }
    }
}

struct FriendsScreen: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        // A ScrollView, not a List: List resolves a row that contains links as a
        // single tap target, so tapping the poster could open the friend profile
        // instead of the title. Plain links own their hit areas here.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.checking {
                    ProgressView("Checking session").padding(rowInsets)
                } else if store.account == nil {
                    VStack(alignment: .leading, spacing: LedgerLayout.gap) {
                        Text("See what your MyAnimeList friends are watching and reading.").foregroundStyle(.secondary)
                        SignInButton()
                    }.padding(rowInsets)
                } else {
                    if store.feedStatus.isShowingSavedData, !store.activity.isEmpty {
                        SavedDataNote(savedAt: store.feedStatus.savedAt, message: store.feedStatus.failure,
                                      isBusy: store.loadingFriends) {
                            await store.loadFriends(reset: true)
                        }
                        .padding(rowInsets)
                    } else if let message = store.friendMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message).foregroundStyle(.secondary)
                            Button("Retry") { Task { await store.loadFriends(reset: true) } }
                        }.padding(rowInsets)
                    }
                    ForEach(store.activity) { item in
                        PreferredTitle(title: store.friendFeedTitle(item.title),
                                       showsLoadingTitle: false,
                                       onEnglishName: { store.rememberFriendFeedEnglishName($1, for: $0) }) { title, name in
                            feedRow(item, title: title, name: name)
                        }
                        .padding(rowInsets)
                        Divider().overlay(Color.white.opacity(0.20))
                            .padding(.horizontal, LedgerLayout.inset)
                    }
                    if store.hasMoreFriendActivity {
                        NextPageIndicator(label: "Loading friend activity", page: store.friendFeedPage) {
                            await store.loadFriends()
                        }.padding(rowInsets)
                    } else if store.activity.isEmpty,
                        store.loadingFriends
                            || (store.friendFeedPage == 0 && store.friendMessage == nil)
                    {
                        FeedSkeleton().padding(rowInsets)
                    } else if store.activity.isEmpty, store.friendMessage == nil {
                        ContentUnavailableView(
                            "No friend activity yet",
                            systemImage: "person.2",
                            description: Text("Recent updates from your MyAnimeList friends appear here."))
                        .padding(rowInsets)
                    }
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Feed")
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
        .task(id: store.account?.id) { if store.friendFeedPage == 0 { await store.loadFriends() } }
        .prefetchingPosters(store.activity) { $0.title.image }
        .refreshable { await store.loadFriends(reset: true) }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 9, leading: LedgerLayout.inset, bottom: 9, trailing: LedgerLayout.inset)
    }

    private func feedRow(_ item: FriendUpdate, title: Title, name: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: item.friend) {
                Art(url: item.friend.avatar, symbol: "person.fill")
                    .frame(width: 46, height: 46)
                    .clipShape(.rect(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.friend.name)’s profile")

            VStack(alignment: .leading, spacing: 5) {
                NavigationLink(value: item.friend) {
                    Text(item.friend.name).font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens their profile")

                NavigationLink(value: title) {
                    Text("\(item.activityPhrase) \(Text(name).bold())")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !item.activityDetails.isEmpty {
                    Text(item.activityDetails).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NavigationLink(value: title) {
                Art(url: title.image).frame(width: 48, height: 68)
                    .clipShape(.rect(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(name)")
        }
    }

}

/// First-load placeholders so a list paints its shape instead of a spinner.
private struct ListSkeleton: View {
    let kind: Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SkeletonBlock(height: 14, width: 120)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            ForEach(0..<7, id: \.self) { index in
                if index > 0 { Divider().padding(.leading, 96) }
                HStack(alignment: .top, spacing: 10) {
                    SkeletonBlock(height: 116, width: 80, radius: 7)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 14, width: 200)
                        SkeletonBlock(height: 12, width: 110)
                        SkeletonBlock(height: 12, width: 64)
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(kind.label.lowercased())")
    }
}

/// The Discover page before its first shelf batch answers.
private struct DiscoverSkeleton: View {
    private var posterWidth: CGFloat { LedgerLayout.detailPosterWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SkeletonBlock(height: 16, width: 170)
                        Spacer(minLength: 0)
                        SkeletonBlock(height: 16, width: 16, radius: 4)
                    }
                    .frame(height: 36)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(
                                    height: posterWidth / LedgerLayout.posterRatio, width: posterWidth,
                                    radius: LedgerLayout.posterRadius)
                                SkeletonBlock(height: 12, width: posterWidth - 18)
                                SkeletonBlock(height: 12, width: posterWidth - 52)
                            }
                            .frame(width: posterWidth)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, LedgerLayout.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Discover")
    }
}

/// Feed rows before the first batch of friend activity answers.
private struct FeedSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 { Divider().overlay(Color.white.opacity(0.12)) }
                HStack(alignment: .top, spacing: 10) {
                    SkeletonBlock(height: 46, width: 46, radius: 7)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(height: 12, width: 110)
                        SkeletonBlock(height: 14, width: 190)
                        SkeletonBlock(height: 12, width: 90)
                    }
                    .padding(.top, 3)
                    Spacer(minLength: 0)
                    SkeletonBlock(height: 68, width: 48, radius: 5)
                }
                .padding(.vertical, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading friend activity")
    }
}
