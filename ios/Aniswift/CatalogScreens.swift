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
                    Capsule().strokeBorder(Palette.border).allowsHitTesting(false)
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

/// The orders a list can be read in. Every order is written ascending here and
/// read the other way when the sheet asks for it, so one comparator serves both
/// directions.
enum ListSort: String, CaseIterable, Identifiable, Codable {
    case title = "Title"
    case recent = "Recently updated"
    case rating = "My rating"
    case progress = "My progress"
    case score = "Average score"

    var id: Self { self }

    /// The direction a reader wants first: names read A to Z, everything else
    /// reads newest or highest first.
    var readsDescending: Bool { self != .title }
}

/// What a list asks of an entry. Every chip that is on has to hold, so Has
/// Score with Has Notes keeps only the entries that have both.
enum ListDetailFilter: String, CaseIterable, Identifiable, Codable {
    case score = "Has Score"
    case progress = "Has Progress"
    case notes = "Has Notes"
    case rewatched = "Rewatched / Reread"
    case customLists = "Custom Lists"

    var id: Self { self }
}

/// How a list is ordered and narrowed. It is remembered per kind, so a reader
/// who sorts by score and hides finished titles finds the same list next time.
struct ListFilter: Codable, Equatable {
    var sort = ListSort.title
    var descending = false
    var statuses: Set<String>
    var formats: Set<String>
    var details: Set<ListDetailFilter> = []
    var year = ""

    /// Everything kept: every status, every format, no requirement and no year.
    /// This is what Reset returns to and what a first visit starts on.
    static func defaults(for kind: Kind) -> ListFilter {
        ListFilter(statuses: Set(kind.statuses), formats: Set(kind.formats))
    }

    /// The formats a list offers, taken from the kind itself: an anime list has
    /// TV and movies, a manga list manga and novels, and they share none.
    static func formats(for kind: Kind) -> [String] { kind.formats }

    /// Whether anything narrows the list, so the screen can say so and offer to
    /// clear it. The order the list is read in is not a filter.
    func isFiltering(for kind: Kind) -> Bool {
        statuses != Set(kind.statuses) || formats != Set(kind.formats) || !details.isEmpty
            || !year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Everything a tap in the sheet can change, without the year a reader
    /// types, so the sheet's haptic fires on a chip and not on every digit.
    var selectionKey: String {
        let statuses = statuses.sorted().joined(separator: ",")
        let formats = formats.sorted().joined(separator: ",")
        let details = details.map(\.rawValue).sorted().joined(separator: ",")
        return "\(sort.rawValue)-\(descending)-\(statuses)-\(formats)-\(details)"
    }

    /// The year a reader typed, as a number, when it is one.
    var yearNumber: Int? {
        let digits = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 4 else { return nil }
        return Int(digits)
    }

    /// MyAnimeList names a format its own way ("tv", "tv_special", "lightnovel"),
    /// so a chip and a title compare with every mark that is not a letter or a
    /// digit taken out: Light Novel reads as lightnovel either way.
    static func formatName(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Remembering

    /// The filter a list opens with: the one it was last left on, or everything
    /// kept. A saved set naming a status or a format this kind does not have is
    /// dropped rather than leaving the list empty with no chip to blame — which
    /// is also how a manga list left with anime formats starts over.
    static func remembered(_ kind: Kind) -> ListFilter {
        guard let data = UserDefaults.standard.data(forKey: key(kind)),
            let saved = try? JSONDecoder().decode(ListFilter.self, from: data),
            saved.statuses.isSubset(of: Set(kind.statuses)),
            saved.formats.isSubset(of: Set(kind.formats))
        else { return .defaults(for: kind) }
        return saved
    }

    static func remember(_ filter: ListFilter, kind: Kind) {
        guard let data = try? JSONEncoder().encode(filter) else { return }
        UserDefaults.standard.set(data, forKey: key(kind))
    }

    private static func key(_ kind: Kind) -> String { "aniswift.list.filter.\(kind.rawValue)" }
}

/// A change a list row has just made, kept for a few seconds so the bar can take
/// it back. A removal and a step both answer Undo; only the removal did.
private struct ListUndo {
    /// The row the change touched, so a second change replaces the first.
    let id: String
    /// What the bar reads.
    let message: String
    /// The row as it was, which the Undo sends back.
    let entry: ListEntry
    /// The change that puts the row back the way it was.
    let restore: ListChange
}

struct ListsScreen: View {
    @Environment(Store.self) private var store
    /// The next-episode schedules AniList has published for the airing rows.
    /// Observation tracks the reads, so the singleton is held, not wrapped.
    private let schedules = AiringScheduleCache.shared
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let kind: Kind
    @State private var collapsed: Set<String> = []
    @State private var query = ""
    @State private var filter: ListFilter
    @State private var showingFilter = false
    @State private var paging = false
    @State private var listPageError: String?
    /// The change the list has just made, held for a few seconds so the bar can
    /// take it back: a removal and a step both answer Undo now.
    @State private var undo: ListUndo?
    @State private var saving: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let rowInset: CGFloat = 10

    init(kind: Kind) {
        self.kind = kind
        _collapsed = State(initialValue: Set(kind.statuses.dropFirst().dropLast()))
        _filter = State(initialValue: ListFilter.remembered(kind))
    }

    private var entries: [ListEntry] {
        let entries = store.lists[kind, default: []]
        let visible = searchTerm.isEmpty ? entries.filter { !store.organization.hidden.contains($0.id) } : entries
        return visible.filter(matchesFilters)
    }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFiltering: Bool { filter.isFiltering(for: kind) }
    /// Whether the list is narrowed at all, by a filter or by a search, so a
    /// group with no match is not drawn and a collapsed one opens itself.
    private var isNarrowed: Bool { isFiltering || !searchTerm.isEmpty }

    /// The airing anime in the list, whose schedules are read in one request so
    /// each row can name the episode that is really next.
    private var airingIDs: [Int] {
        kind == .anime ? entries.filter { $0.title.isAiring }.map(\.title.malID).sorted() : []
    }

    /// Whether an entry survives the sheet's chips. A status chip reads the
    /// entry's own status; the rest read what its title or its row carries.
    private func matchesFilters(_ entry: ListEntry) -> Bool {
        guard filter.statuses.contains(entry.status) else { return false }
        if filter.formats != Set(kind.formats) {
            let format = ListFilter.formatName(entry.title.format ?? "")
            guard filter.formats.contains(where: { ListFilter.formatName($0) == format }) else { return false }
        }
        if let year = filter.yearNumber, entry.title.releaseYear != year { return false }
        for detail in filter.details {
            switch detail {
            case .score:
                if entry.rating <= 0 { return false }
            case .progress:
                if entry.progress <= 0 { return false }
            case .notes:
                if (entry.details?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            case .rewatched:
                if (entry.details?.repeatCount ?? 0) <= 0 { return false }
            case .customLists:
                let listed = store.organization.lists.contains { list in
                    list.titles.contains { $0.id == entry.id }
                }
                if !listed { return false }
            }
        }
        return true
    }

    private func displayName(_ title: Title) -> String { title.displayName(for: titleLanguage) }

    var body: some View {
        if store.account != nil {
            list.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
                .searchRecents($query)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if store.checking {
                ProgressView("Checking session").listRowBackground(Color.clear)
            } else if store.account == nil {
                // Signed out, the tab is still a page with a subject: one panel
                // that says what will appear here and the two ways in, the way
                // the Profile tab explains itself, instead of a bare sign-in
                // button floating in an otherwise empty list.
                signedOut
                    .listRowInsets(
                        EdgeInsets(top: 12, leading: LedgerLayout.inset, bottom: 12, trailing: LedgerLayout.inset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if store.lists[kind] == nil, store.pendingListLoads.contains(kind) {
                ListSkeleton(kind: kind)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if store.lists[kind] == nil, let failure = store.listFailures[kind] {
                LedgerProblem(message: failure) { await store.loadLists(force: true) }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if store.lists[kind]?.isEmpty == true, searchTerm.isEmpty, store.nextList[kind] == nil,
                !store.refreshingLists.contains(kind)
            {
                // An empty state belongs in the page, not in a row: inside a List
                // it centres against the row's insets instead of the screen. The
                // step out of it is the catalog, where a title is added.
                LedgerEmpty(
                    title: "No \(kind.label.lowercased()) yet",
                    symbol: kind == .anime ? "tv" : "books.vertical",
                    message: "Titles you add from Discover or a title page appear here."
                ) {
                    NavigationLink(value: CatalogBrowserRoute()) {
                        Label("Browse catalog", systemImage: "square.grid.2x2")
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(kind.statuses, id: \.self) { status in
                    let group = entries.filter { $0.status == status }
                    let matches = visibleEntries(group)
                    if !isNarrowed || !matches.isEmpty {
                        groupHeader(status, count: isNarrowed ? matches.count : group.count)
                            .listRowInsets(EdgeInsets(top: 4, leading: rowInset, bottom: 4, trailing: rowInset))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        if !collapsed.contains(status) || isNarrowed {
                            ForEach(matches) { item in entryRow(item) }
                        }
                    }
                }
                if isNarrowed && !hasSearchMatch(entries) && store.nextList[kind] == nil {
                    noMatches
                }
                if let page = store.nextList[kind] {
                    if let listPageError {
                        LedgerProblem(message: listPageError) { await loadListPage(page) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                    Button { showingFilter = true } label: {
                        // A dot on the icon says a filter is hiding something,
                        // so the sheet is not the only way to find out.
                        Label("Sort and filter", systemImage: "line.3.horizontal.decrease")
                            .overlay(alignment: .topTrailing) {
                                if isFiltering {
                                    Circle().fill(.tint)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 3, y: -2)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    // A hardware keyboard opens the sheet as well: the sort and
                    // the filters used to be reachable by pointer alone.
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await store.loadLists(force: true)
                            listPageError = nil
                        }
                    } label: {
                        if store.refreshingLists.contains(kind) {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh")
                    .accessibilityHint("Reads your list from MyAnimeList again")
                    .disabled(store.refreshingLists.contains(kind))
                    // The pull to refresh in one press, so a reader who is not
                    // at the top of the list, and a hardware keyboard, have a
                    // way to ask again.
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .sheet(isPresented: $showingFilter) {
            ListFilterSheet(kind: kind, filter: $filter)
        }
        .onChange(of: filter) { _, value in ListFilter.remember(value, kind: kind) }
        .scrollDismissesKeyboard(.interactively)
        .prefetchingPosters(entries) { $0.title.image }
        // The airing rows name the episode that is really next once AniList's
        // schedule for them is in, so it is read in one request whenever the set
        // of airing titles changes.
        .task(id: airingIDs) { await schedules.learn(airingIDs) }
        .onChange(of: store.account?.id) { _, _ in
            query = ""
            listPageError = nil
        }
        .refreshable {
            await store.loadLists(force: true)
            listPageError = nil
        }
        // A removal or a step is a swipe and an Undo, not a question: the row
        // waits in the bar for a few seconds, then the change stands.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let undo {
                HStack(spacing: 12) {
                    Text(undo.message)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Undo") { undoChange() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(minHeight: 44)
                        .accessibilityHint("Puts the row back the way it was")
                }
                .padding(.horizontal, LedgerLayout.inset)
                .padding(.vertical, 4)
                .background(.regularMaterial)
                .overlay(alignment: .top) { Divider().overlay(Palette.hairline) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: undo?.id)
    }

    /// What the tab says before MyAnimeList is connected: what will appear
    /// here, the way in, and the catalog for a reader who would rather look
    /// first. The Profile tab has always explained itself; this one offered a
    /// sign-in button and nothing else.
    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your \(kind.label.lowercased()) list appears here once MyAnimeList is connected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SignInButton()
            NavigationLink(value: CatalogBrowserRoute()) {
                Label("Browse the catalog", systemImage: "square.grid.2x2")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityHint("Finds a title to add once you are signed in")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ledgerPanel()
    }

    private func groupHeader(_ status: String, count: Int) -> some View {
        let expanded = !collapsed.contains(status) || isNarrowed
        let partial = store.nextList[kind] != nil && !isNarrowed
        return ListStatusHeader(title: statusLabel(status), count: count, expanded: expanded,
                                partial: partial, isInteractive: !isNarrowed) {
            if expanded { collapsed.insert(status) }
            else { collapsed.remove(status) }
        }
    }

    /// A list a filter or a search has emptied: it says which one emptied it
    /// and offers the way back out of the filter.
    private var noMatches: some View {
        LedgerEmpty(
            title: "No matches in your list",
            symbol: "line.3.horizontal.decrease.circle",
            message: searchTerm.isEmpty
                ? "These filters hide every title in it."
                : "Nothing here matches the search."
        ) {
            if isFiltering {
                Button("Clear Filters") { filter = .defaults(for: kind) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityHint("Shows every title in your list again")
            }
        }
        .padding(.vertical, 20)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Whether a narrowed list has anything to show by its search, without
    /// sorting every entry just to ask whether one is left.
    private func hasSearchMatch(_ group: [ListEntry]) -> Bool {
        group.contains { entry in
            searchTerm.isEmpty || entry.title.name.localizedCaseInsensitiveContains(searchTerm)
                || entry.title.original.localizedCaseInsensitiveContains(searchTerm)
        }
    }

    private func visibleEntries(_ group: [ListEntry]) -> [ListEntry] {
        let matches = group.filter { entry in
            searchTerm.isEmpty || entry.title.name.localizedCaseInsensitiveContains(searchTerm)
                || entry.title.original.localizedCaseInsensitiveContains(searchTerm)
        }
        // Each order is written ascending, and the sheet's direction reads it
        // the other way, so one comparator serves both.
        let sorted: [ListEntry]
        switch filter.sort {
        case .title:
            sorted = matches.sorted {
                displayName($0.title).localizedStandardCompare(displayName($1.title)) == .orderedAscending
            }
        case .recent:
            sorted = matches.sorted { $0.updated < $1.updated }
        case .rating:
            sorted = matches.sorted { $0.rating == $1.rating ? $0.updated < $1.updated : $0.rating < $1.rating }
        case .progress:
            sorted = matches.sorted { $0.progress == $1.progress ? $0.updated < $1.updated : $0.progress < $1.progress }
        case .score:
            sorted = matches.sorted { left, right in
                let one = left.title.score ?? 0
                let other = right.title.score ?? 0
                guard one == other else { return one < other }
                return displayName(left.title).localizedStandardCompare(displayName(right.title)) == .orderedAscending
            }
        }
        return filter.descending ? Array(sorted.reversed()) : sorted
    }

    /// When a title that is still on the air next airs, under the row's facts:
    /// amber while an episode that already aired is unwatched, green once the
    /// reader is caught up with every one of them, and the same in words for
    /// VoiceOver, which cannot see the colour.
    private func airingLine(_ airing: AiringProgress, progress: Int) -> some View {
        let behind = (airing.aired ?? 0) > progress
        let colour = airing.aired == nil
            ? Color.secondary : (behind ? Palette.airingBehind : Palette.airingCaughtUp)
        let state = airing.aired == nil ? nil : (behind ? "You are behind." : "You are caught up.")
        let label = [airing.line(), state].compactMap { $0 }.joined(separator: " ")
        return HStack(spacing: 5) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .accessibilityHidden(true)
            Text(airing.line()).font(.subheadline)
        }
        .foregroundStyle(colour)
        .padding(.top, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func entryRow(_ item: ListEntry) -> some View {
        let link = NavigationLink(value: item.title) {
            HStack(alignment: .top, spacing: 8) {
                Art(url: item.title.image, symbol: kind == .anime ? "film" : "book")
                    .frame(width: 80, height: 116)
                    .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
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
                    if let airing = item.title.nextAiring(
                        schedule: schedules.schedule(for: item.title.malID)
                    ) {
                        airingLine(airing, progress: item.progress)
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
            Button(role: .destructive) {
                remove(item)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .tint(.red)
            .disabled(saving.contains(item.id))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if (item.title.total ?? 0) <= 0 || item.progress < (item.title.total ?? 0) {
                Button { step(item) } label: {
                    Label(kind == .anime ? "Episode" : "Chapter", systemImage: "plus")
                }
                .tint(Palette.progress)
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

    /// A removal keeps the entry so the Undo can put it back exactly as it was.
    private func remove(_ item: ListEntry) {
        hold(
            ListUndo(
                id: item.id, message: "Removed \(displayName(item.title))", entry: item,
                restore: ListChange(status: item.status, progress: item.progress, rating: item.rating)))
        update(item, change: nil)
    }

    /// A step keeps the progress it started from, so a stray swipe is one tap
    /// away from where it was instead of a number the reader has to remember.
    private func step(_ item: ListEntry) {
        hold(
            ListUndo(
                id: item.id,
                message: "\(displayName(item.title)) · \(item.progress + 1) \(kind.unit.lowercased())",
                entry: item,
                restore: ListChange(status: item.status, progress: item.progress, rating: item.rating)))
        update(
            item,
            change: ListChange(status: item.status, progress: item.progress + 1, rating: item.rating))
    }

    /// Keeps one change in the bar for six seconds. A second change to the same
    /// row replaces the first, so the bar always describes what Undo takes back.
    private func hold(_ change: ListUndo) {
        undo = change
        Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, undo?.id == change.id else { return }
            undo = nil
        }
    }

    private func undoChange() {
        guard let undo else { return }
        self.undo = nil
        Haptics.success()
        update(undo.entry, change: undo.restore)
    }
}

/// A filter chip: one tap toggles it, and a chip that is on says so with a
/// checkmark as well as a fill, so the sheet reads in whatever accent the app is
/// set to instead of only in a shade of grey.
private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Text(title)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline)
            .foregroundStyle(isOn ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(isOn ? Palette.fill : Color.clear, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? Palette.border : Palette.hairline)
                    .allowsHitTesting(false)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The lists screen's order and filters in one sheet: the sort a list is read
/// in and which direction, then the status, format, entry and year chips that
/// narrow it. Every choice is written back to the list as it is made, so the
/// sheet needs no Done, and Reset returns to everything kept.
struct ListFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    @Binding var filter: ListFilter

    private var isReset: Bool { filter == ListFilter.defaults(for: kind) }
    private var directionLabel: String { filter.descending ? "Descending order" : "Ascending order" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    sortPanel
                    group("Status") {
                        ForEach(kind.statuses, id: \.self) { status in
                            FilterChip(title: statusLabel(status), isOn: filter.statuses.contains(status)) {
                                toggleStatus(status)
                            }
                        }
                    }
                    group("Format") {
                        ForEach(ListFilter.formats(for: kind), id: \.self) { format in
                            FilterChip(title: format, isOn: filter.formats.contains(format)) {
                                toggleFormat(format)
                            }
                        }
                    }
                    group("Entry Details") {
                        ForEach(ListDetailFilter.allCases) { detail in
                            FilterChip(title: detail.rawValue, isOn: filter.details.contains(detail)) {
                                toggleDetail(detail)
                            }
                        }
                    }
                    yearField
                }
                .padding(LedgerLayout.inset)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Sort and Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { filter = .defaults(for: kind) }
                        .disabled(isReset)
                }
            }
            .sensoryFeedback(.selection, trigger: filter.selectionKey)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // The sheet's cards are the app's own surface on its own canvas, so the
        // sheet sits on the black the lists are drawn on rather than on the
        // lighter sheet colour the editor uses for a system Form.
        .presentationBackground(Palette.background)
    }

    /// The order a list reads in: its sort in a menu, a round control that
    /// turns it around, and the direction spelled out under it.
    private var sortPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Sort").font(.body)
                Spacer(minLength: 8)
                Button { filter.descending.toggle() } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        // The round control takes the 44 points of every other
                        // touch target; at 38 it was the one short one.
                        .frame(width: 44, height: 44)
                        .ledgerGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(directionLabel)
                .accessibilityHint("Turns the order around")
                Menu {
                    Picker("Sort", selection: $filter.sort) {
                        ForEach(ListSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.sort.rawValue).font(.body)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Sort by \(filter.sort.rawValue)")
            }
            HStack {
                Spacer(minLength: 8)
                Text(directionLabel).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.surface, in: .rect(cornerRadius: LedgerLayout.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LedgerLayout.panelRadius)
                .strokeBorder(Palette.hairline)
                .allowsHitTesting(false)
        }
        // A sort that reads newest or highest first starts the other way, so
        // choosing it does not land the reader on the quietest rows.
        .onChange(of: filter.sort) { _, sort in filter.descending = sort.readsDescending }
    }

    private func group<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            FlowLayout { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: .rect(cornerRadius: LedgerLayout.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LedgerLayout.panelRadius)
                        .strokeBorder(Palette.hairline)
                        .allowsHitTesting(false)
                }
        }
    }

    private var yearField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Year".uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Text("Released in").font(.body)
                Spacer(minLength: 12)
                TextField("Any year", text: $filter.year)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: 110)
                    .accessibilityLabel("Released in")
                if !filter.year.isEmpty {
                    Button { filter.year = "" } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear the year")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .background(Palette.surface, in: .rect(cornerRadius: LedgerLayout.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LedgerLayout.panelRadius)
                    .strokeBorder(Palette.hairline)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: filter.year) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(4))
            if digits != value { filter.year = digits }
        }
    }

    private func toggleStatus(_ status: String) {
        if filter.statuses.contains(status) { filter.statuses.remove(status) }
        else { filter.statuses.insert(status) }
    }

    private func toggleFormat(_ format: String) {
        if filter.formats.contains(format) { filter.formats.remove(format) }
        else { filter.formats.insert(format) }
    }

    private func toggleDetail(_ detail: ListDetailFilter) {
        if filter.details.contains(detail) { filter.details.remove(detail) }
        else { filter.details.insert(detail) }
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
    @Environment(Store.self) private var store
    let heading: String
    let titles: [Title]
    var isDiscoverShelf = false
    let trailing: Trailing
    /// The dupes are dropped once per page instead of on every body pass.
    @State private var items: [Title]

    init(heading: String, titles: [Title], isDiscoverShelf: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.heading = heading
        self.titles = titles
        self.isDiscoverShelf = isDiscoverShelf
        self.trailing = trailing()
        _items = State(initialValue: unique(titles))
    }

    /// The poster follows Dynamic Type the way the names beside it do, and stops
    /// growing at the accessibility sizes so a shelf keeps its shape.
    @ScaledMetric(relativeTo: .subheadline) private var scaledPosterWidth: CGFloat = LedgerLayout.posterWidth
    @ScaledMetric(relativeTo: .subheadline) private var scaledDetailWidth: CGFloat = LedgerLayout.detailPosterWidth

    private var posterWidth: CGFloat {
        if isDiscoverShelf { return min(scaledDetailWidth, LedgerLayout.detailPosterWidth * 1.4) }
        return min(scaledPosterWidth, LedgerLayout.posterWidth * 1.4)
    }

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
                ForEach(items) { title in
                    VStack(alignment: .leading, spacing: 3) {
                        CoverTile(
                            title: title, showsScore: false, reservesCaptionSpace: false,
                            posterWidth: posterWidth)
                        if let entry = store.entries[title.kind]?[title.id] {
                            Text(statusLabel(entry.status)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(width: posterWidth)
                    // One tile reads as one row, name and status together.
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .onChange(of: titles) { _, new in items = unique(new) }
    }
}

struct DiscoverScreen: View {
    @Environment(Store.self) private var store
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !searchTerm.isEmpty {
                Picker("Search category", selection: $searchKind) {
                    ForEach(Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: searchKind)
                .padding(.horizontal, LedgerLayout.inset)
                .padding(.vertical, 6)
                .background(Palette.background)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .searchRecents($search)
        .toolbar {
            // The shelves are read again from here as well as by a pull, so a
            // reader who is not at the top of the page has the same way in.
            if searchTerm.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadShelves(refresh: true) }
                    } label: {
                        if loading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh")
                    .accessibilityHint("Reads the shelves from the catalog again")
                    .disabled(loading)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
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
                    } else if shelves.values.allSatisfy(\.isEmpty) {
                        ContentUnavailableView {
                            Label("Catalog unavailable", systemImage: "safari")
                        } description: {
                            Text("Discover could not reach the catalog. Check your connection and try again.")
                        } actions: {
                            Button("Retry") { Task { await loadShelves(refresh: true) } }
                        }
                    } else if !failedShelves.isEmpty {
                        let count = failedShelves.count
                        LedgerProblem(
                            message: count == 1 ? "One shelf did not load." : "\(count) shelves did not load."
                        ) {
                            await loadShelves()
                        }
                        .padding(.horizontal, LedgerLayout.inset)
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
            } else if #available(iOS 26.0, *) {
                results
                    .searchable(text: $search, placement: .toolbar, prompt: "Search titles")
                    .toolbar { DefaultToolbarItem(kind: .search, placement: .topBarTrailing) }
                    .scrollDismissesKeyboard(.interactively)
            } else {
                results
                    .searchable(
                        text: $search, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search titles")
                    .scrollDismissesKeyboard(.interactively)
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

    /// The card is as tall as its poster, so the text beside it stops there
    /// instead of stretching the row past the artwork.
    private var posterHeight: CGFloat { posterWidth / LedgerLayout.posterRatio }

    private var summary: String {
        var values = [title.format ?? title.kind.label]
        if let total = title.total {
            let unit = title.kind == .anime ? "episode" : "chapter"
            values.append("\(total) \(total == 1 ? unit : unit + "s")")
        }
        if let score = title.score, score > 0 {
            values.append(score.ledgerDecimal(2...2))
        }
        return values.joined(separator: " · ")
    }

    var body: some View {
        PreferredTitle(title: title) { item, name in
            NavigationLink(value: item) {
                let stacked = typeSize.isAccessibilitySize
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    poster(item)
                    details(item, name: name)
                        .frame(height: stacked ? nil : posterHeight, alignment: .top)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface)
                .clipShape(.rect(cornerRadius: LedgerLayout.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LedgerLayout.panelRadius)
                        .strokeBorder(Palette.border).allowsHitTesting(false)
                }
                .contentShape(.rect(cornerRadius: LedgerLayout.panelRadius))
            }
            .buttonStyle(.plain)
        }
    }

    private func poster(_ item: Title) -> some View {
        PosterArt(url: item.image, symbol: item.kind == .anime ? "film" : "book", width: posterWidth)
            .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
    }

    /// The name, its facts and its genres around a summary that takes the room
    /// left between them: a long one is cut at the poster's edge rather than
    /// growing the card.
    private func details(_ item: Title, name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline).lineLimit(2)
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            if let synopsis = item.synopsis {
                Text(synopsis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
            if let genres = item.genres, !genres.isEmpty {
                FlowLayout {
                    ForEach(Array(genres.prefix(3)), id: \.self) { genre in
                        Text(genre).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Palette.fill, in: .capsule)
                            .overlay { Capsule().strokeBorder(Palette.border) }
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
                        .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
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
    @Environment(Store.self) private var store
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
                    LedgerProblem(message: "Could not load \(name.lowercased()).") { await load() }
                } else if more {
                    NextPageIndicator(label: "Loading more titles", page: page) {
                        if !loading { await load() }
                    }
                } else if loading {
                    ProgressView().accessibilityLabel("Loading \(name)")
                } else if titles.isEmpty {
                    ContentUnavailableView {
                        Label("No titles found", systemImage: "magnifyingglass")
                    } description: {
                        Text(query.isEmpty
                            ? "Nothing here yet. Pull down to refresh."
                            : "Try another search or section.")
                    } actions: {
                        if let search = Self.searchURL(query, kind: kind) {
                            Link("Search MyAnimeList", destination: search)
                        }
                    }
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

    /// A MyAnimeList search for the query, so an empty result still leads
    /// somewhere useful instead of a dead end.
    private static func searchURL(_ query: String, kind: Kind) -> URL? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://myanimelist.net/\(kind.rawValue).php")
        components?.queryItems = [URLQueryItem(name: "q", value: term)]
        return components?.url
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
    @Environment(Store.self) private var store
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
                    LedgerProblem(message: message) {
                        if page == 1 { reload += 1 } else { await load(reset: false) }
                    }
                } else if next {
                    NextPageIndicator(label: "Loading more titles", page: page) {
                        if !loading { await load(reset: false) }
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if titles.isEmpty {
                    ContentUnavailableView {
                        Label("No matching titles", systemImage: "magnifyingglass")
                    } description: {
                        Text("Adjust the filters or search for another title.")
                    } actions: {
                        // The step out of an empty result: the query first,
                        // then the filters back to the top rated shelf.
                        if !search.isEmpty {
                            Button("Clear Search") { search = "" }
                        } else {
                            Button("Show Top Rated") { mode = .popular }
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("Browse catalog")
        .searchable(text: $search, prompt: "Search anime or manga")
        .searchRecents($search)
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
    @Environment(Store.self) private var store

    var body: some View {
        // A ScrollView, not a List: List resolves a row that contains links as a
        // single tap target, so tapping the poster could open the friend profile
        // instead of the title. Plain links own their hit areas here.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.checking {
                    ProgressView("Checking session").padding(rowInsets)
                } else if store.account == nil {
                    // Signed out, the Feed explains itself in the same panel as
                    // the lists and the Profile, with the way in: it was the one
                    // tab that said it in bare text.
                    VStack(alignment: .leading, spacing: 14) {
                        Text("See what your MyAnimeList friends are watching and reading.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SignInButton()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .ledgerPanel()
                    .padding(rowInsets)
                } else {
                    if store.feedStatus.isShowingSavedData, !store.activity.isEmpty {
                        SavedDataNote(savedAt: store.feedStatus.savedAt, message: store.feedStatus.failure,
                                      isBusy: store.loadingFriends) {
                            await store.loadFriends(reset: true)
                        }
                        .padding(rowInsets)
                    } else if let message = store.friendMessage {
                        LedgerProblem(message: message) { await store.loadFriends(reset: true) }
                            .padding(rowInsets)
                    }
                    ForEach(store.activity) { item in
                        PreferredTitle(title: store.named(item.title), showsLoadingTitle: false) { title, name in
                            feedRow(item, title: title, name: name)
                        }
                        .padding(rowInsets)
                        Divider().overlay(Palette.hairline)
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
                        ContentUnavailableView {
                            Label("No friend activity yet", systemImage: "person.2")
                        } description: {
                            Text("Recent updates from your MyAnimeList friends appear here.")
                        } actions: {
                            Button("Refresh") { Task { await store.loadFriends(reset: true) } }
                        }
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
                        if store.loadingFriends {
                            ProgressView()
                        } else {
                            Label("Refresh friends feed", systemImage: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh friends feed")
                    .disabled(store.loadingFriends)
                    // The same press and the same shortcut as the list and
                    // Discover, so the three tabs answer a keyboard alike.
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .task(id: store.account?.id) { await store.openFeed() }
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
                    .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
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
                    .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
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
                if index > 0 { Divider().overlay(Palette.hairline) }
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
