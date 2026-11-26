import Kingfisher
import SwiftUI

struct TitleScreen: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var quickSheetExtra: CGFloat = 32
    let title: Title
    @State private var payload: Fields?
    @State private var related: [Title] = []
    @State private var suggested: [Title] = []
    @State private var relationNames: [String: String] = [:]
    @State private var characters: [CastMember] = []
    @State private var themes: Fields?
    @State private var reviews: Page<TitleReview>?
    @State private var reviewsUnavailable = false
    @State private var stacks: [InterestStack] = []
    @State private var stacksMore = false
    @State private var showingPoster = false
    @State private var summaryExpanded = false
    @State private var failure: String?
    @State private var savedAt: Date?
    @State private var editor: ListEditor.Mode?
    @State private var confirmRemoval = false
    @State private var changingList = false
    @State private var friendRows: [FriendUpdate] = []
    @State private var friendOffset = 0
    @State private var completedFriendBatches = 0
    @State private var checkingFriends = false
    /// A title page checks a bounded set of friends: the row is a bonus on the
    /// page, and every friend can cost a request or two.
    private static let friendScanLimit = 18

    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    @AppStorage(SettingKey.askForScore) private var asksForScore = true

    @AppStorage(SettingKey.detail(.anime, DetailSection.characters)) private var animeCharacters = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.trailer)) private var animeTrailer = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.related)) private var animeRelated = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.source)) private var animeSource = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.openings)) private var animeOpenings = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.endings)) private var animeEndings = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.recommendations)) private var animeRecommendations = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.characters)) private var mangaCharacters = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.related)) private var mangaRelated = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.source)) private var mangaSource = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.recommendations)) private var mangaRecommendations = true

    @AppStorage(SettingKey.detail(.anime, DetailSection.headerPoster)) private var animeHeaderPoster = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.headerScore)) private var animeHeaderScore = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.headerRank)) private var animeHeaderRank = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.headerPopularity)) private var animeHeaderPopularity = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.headerCreators)) private var animeHeaderCreators = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.headerPoster)) private var mangaHeaderPoster = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.headerScore)) private var mangaHeaderScore = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.headerRank)) private var mangaHeaderRank = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.headerPopularity)) private var mangaHeaderPopularity = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.headerCreators)) private var mangaHeaderCreators = true

    @AppStorage(SettingKey.detail(.anime, DetailSection.infoSeries)) private var animeInfoSeries = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.infoAlternatives)) private var animeInfoAlternatives = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.infoGenres)) private var animeInfoGenres = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.infoThemes)) private var animeInfoThemes = true
    @AppStorage(SettingKey.detail(.anime, DetailSection.infoCreators)) private var animeInfoCreators = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.infoSeries)) private var mangaInfoSeries = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.infoAlternatives)) private var mangaInfoAlternatives = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.infoGenres)) private var mangaInfoGenres = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.infoThemes)) private var mangaInfoThemes = true
    @AppStorage(SettingKey.detail(.manga, DetailSection.infoCreators)) private var mangaInfoCreators = true

    private var current: Title {
        let detail = record.flatMap { Title($0, kind: title.kind) } ?? store.api.cachedTitle(title) ?? title
        return detail.fillingTitleAndImage(from: title).fillingTitleAndImage(from: saved?.title)
    }

    private var displayName: String { current.displayName(for: titleLanguage) }

    private func chosen(_ anime: Bool, _ manga: Bool) -> Bool { title.kind == .anime ? anime : manga }

    private var showsCharacters: Bool { chosen(animeCharacters, mangaCharacters) }
    private var showsRelated: Bool { chosen(animeRelated, mangaRelated) }
    private var showsSource: Bool { chosen(animeSource, mangaSource) }
    private var showsRecommendations: Bool { chosen(animeRecommendations, mangaRecommendations) }
    private var showsTrailer: Bool { title.kind == .anime && animeTrailer }
    private var showsOpenings: Bool { title.kind == .anime && animeOpenings }
    private var showsEndings: Bool { title.kind == .anime && animeEndings }
    private var showsHeaderPoster: Bool { chosen(animeHeaderPoster, mangaHeaderPoster) }
    private var showsHeaderScore: Bool { chosen(animeHeaderScore, mangaHeaderScore) }
    private var showsHeaderRank: Bool { chosen(animeHeaderRank, mangaHeaderRank) }
    private var showsHeaderPopularity: Bool { chosen(animeHeaderPopularity, mangaHeaderPopularity) }
    private var showsHeaderCreators: Bool { chosen(animeHeaderCreators, mangaHeaderCreators) }
    private var showsSeriesInfo: Bool { chosen(animeInfoSeries, mangaInfoSeries) }
    private var showsAlternatives: Bool { chosen(animeInfoAlternatives, mangaInfoAlternatives) }
    private var showsGenres: Bool { chosen(animeInfoGenres, mangaInfoGenres) }
    private var showsThemes: Bool { chosen(animeInfoThemes, mangaInfoThemes) }
    private var showsCreators: Bool { chosen(animeInfoCreators, mangaInfoCreators) }
    private var showsMetadata: Bool {
        showsSeriesInfo || showsAlternatives || showsGenres || showsThemes || showsCreators
    }
    /// What the page can draw right now: the fetched payload, or the cached one.
    /// Reading the cache here means a title you already opened is complete on
    /// the first frame instead of flashing the skeleton until `.task` runs.
    private var record: Fields? { payload ?? store.api.cachedDetail(title) }

    /// The page stops scanning when it has checked its share of the friend list.
    private var friendScanComplete: Bool {
        friendOffset >= min(store.friends.count, Self.friendScanLimit)
    }

    private var saved: ListEntry? { store.lists[title.kind, default: []].first { $0.id == title.id } }

    var body: some View {
        ScrollView {
            if record == nil, failure == nil {
                TitleSkeleton(kind: title.kind)
            } else {
                header
                VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                    actions
                    if let savedAt {
                        SavedDataNote(savedAt: savedAt, retry: { await load() })
                    }
                    if let failure {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Reload details") { Task { await load() } }
                    }
                    if let description = record?.string("synopsis") {
                        block("Summary") { summary(description) }
                    }
                    if showsMetadata { metadata }
                    if let background = record?.string("background") { block("Background") { Text(background) } }
                    if showsRelated, !related.isEmpty { relations }
                    if showsCharacters, !characters.isEmpty { cast }
                    if showsRecommendations, !suggested.isEmpty { mediaRail("Recommended", titles: suggested) }
                    if !stacks.isEmpty { interestStacks }
                    if let trailer = trailerURL, showsTrailer { trailerCard(trailer) }
                    if title.kind == .anime { themeRows }
                    if !friendRows.isEmpty { friends }
                    if let reviews, !reviews.items.isEmpty || reviews.more {
                        reviewRows(reviews)
                    } else if reviewsUnavailable {
                        reviewRows(nil)
                    }
                }
                .padding(LedgerLayout.inset)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if store.account != nil {
                    Button { editor = .full } label: {
                        Image(systemName: saved == nil ? "plus" : "pencil")
                    }
                    .accessibilityLabel(saved == nil ? "Add to My List" : "Edit list entry")
                    .disabled(changingList)
                }
                Menu {
                    ShareLink(item: title.malURL)
                    Link(destination: title.malURL) { Label("View on MyAnimeList", systemImage: "arrow.up.right") }
                    if store.account != nil, let saved {
                        if saved.status != "completed" {
                            Button {
                                let progress = max(saved.progress, current.total ?? 0)
                                updateList(ListChange(status: "completed", progress: progress, rating: saved.rating))
                            } label: { Label("Mark completed", systemImage: "checkmark") }
                        }
                        Button(role: .destructive) { confirmRemoval = true } label: {
                            Label("Remove from My List", systemImage: "trash")
                        }
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More actions")
                .disabled(changingList)
            }
        }
        .task { await load() }
        .task(id: store.account?.id) {
            friendRows = []
            friendOffset = 0
            completedFriendBatches = 0
            checkingFriends = false
            await loadFriendBatch()
        }
        .sheet(item: $editor) { mode in
            ListEditor(title: current, original: saved, mode: mode)
                .presentationDetents(editorDetents(mode))
                .presentationBackground(Palette.sheet)
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Remove this title from your MyAnimeList list?", isPresented: $confirmRemoval) {
            Button("Remove", role: .destructive) { updateList(nil) }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingPoster) {
            PosterScreen(
                url: current.image ?? title.image,
                symbol: title.kind == .anime ? "film" : "book")
        }
    }

    private func editorDetents(_ mode: ListEditor.Mode) -> Set<PresentationDetent> {
        guard mode != .full, !typeSize.isAccessibilitySize else { return [.large] }
        let baseHeight: CGFloat = switch mode {
        case .status: 250
        case .progress: 196
        case .score, .full: 166
        }
        return [.height(baseHeight + quickSheetExtra), .large]
    }

    private func updateList(_ change: ListChange?) {
        guard !changingList else { return }
        changingList = true
        let item = current
        let completedWithoutScore =
            item.kind == .anime && change?.status == "completed" && (change?.rating ?? 0) == 0
            && (saved?.rating ?? 0) == 0
        Task {
            defer { changingList = false }
            do {
                try await store.change(item, change)
                Haptics.success()
                if completedWithoutScore, asksForScore { editor = .score }
            } catch { store.handle(error) }
        }
    }

    private var trailer: Fields? { record?.read("trailer") }

    private var trailerImage: URL? {
        let images: Fields? = trailer?.read("images")
        return publicURL(images?.string("maximum_image_url", "large_image_url", "image_url")
                         ?? trailer?.string("imageUrl", "thumbnailUrl"))
    }

    private var trailerURL: URL? {
        publicURL(trailer?.string("url", "embed_url", "embedUrl"))
    }

    private var header: some View {
        VStack(spacing: 12) {
            if showsHeaderPoster {
                Button { showingPoster = true } label: {
                    Art(url: current.image ?? title.image, symbol: title.kind == .anime ? "film" : "book")
                        .frame(width: 144, height: 208)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14))
                                .allowsHitTesting(false)
                        }
                        .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                .accessibilityLabel("Poster")
                .accessibilityHint("Shows the poster full screen")
            }
            Text(displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if showsHeaderCreators {
                let studios = catalogFacets("studios", category: .studio)
                if title.kind == .anime, !studios.isEmpty {
                    FlowLayout {
                        ForEach(studios) { studio in
                            NavigationLink(value: studio) {
                                Text(studio.name.uppercased()).font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityHint("Opens this studio's titles")
                        }
                    }
                } else if title.kind == .manga, !authorPeople.isEmpty {
                    FlowLayout {
                        ForEach(authorPeople) { author in
                            NavigationLink(value: author) {
                                Text(author.rawName.uppercased()).font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityHint("Opens this mangaka's page")
                        }
                    }
                } else if title.kind == .manga, !authorNames.isEmpty {
                    Text(authorNames.uppercased()).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if current.original != current.name {
                    Text(current.original).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if showsHeaderScore || showsHeaderRank || showsHeaderPopularity {
                HStack(alignment: .top, spacing: 6) {
                    let score = current.score.flatMap {
                        $0 > 0 ? $0.formatted(.number.precision(.fractionLength(2))) : nil
                    }
                    let rank: Int? = record?.read("rank")
                    let popularity: Int? = record?.read("popularity")
                    if showsHeaderScore { statistic("Average score", score) }
                    if showsHeaderRank { statistic("MAL rank", rank.flatMap { $0 > 0 ? "#\($0)" : nil }) }
                    if showsHeaderPopularity {
                        statistic("Popularity", popularity.flatMap { $0 > 0 ? "#\($0)" : nil })
                    }
                }
                .frame(maxWidth: 480)
                .padding(.top, 8)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, LedgerLayout.inset)
        .frame(maxWidth: .infinity)
    }

    private func statistic(_ label: String, _ value: String?) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Text(value ?? "—").font(.title3.bold().monospacedDigit())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        Group {
            if store.checking {
                ProgressView("Checking session")
            } else if store.account == nil {
                SignInButton()
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { listControls(saved) }
                    VStack(spacing: 8) { listControls(saved) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func listControls(_ item: ListEntry?) -> some View {
        let unit = title.kind == .anime ? "EP" : "CH"
        let total = (current.total ?? item?.title.total).flatMap { $0 > 0 ? String($0) : nil } ?? "?"
        editControl(
            "Status", item.map { statusLabel($0.status) } ?? "ADD TO LIST", mode: item == nil ? .full : .status)
        editControl("Progress", "\(item.map { String($0.progress) } ?? "—") / \(total) \(unit)", mode: .progress)
        let rating = item?.rating ?? 0
        editControl("My score", rating > 0 ? "\(rating) / 10" : "UNSCORED", mode: .score)
    }

    private func editControl(_ label: String, _ value: String, mode: ListEditor.Mode) -> some View {
        Button { editor = mode } label: {
            VStack(spacing: 3) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Palette.surface, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.14))
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .opacity(changingList ? 0.55 : 1)
        .accessibilityHint("Opens \(label.lowercased()) settings")
        .disabled(changingList)
    }

    private func fieldNames(_ key: String) -> [String] {
        let rows: [Fields] = record?.read(key) ?? []
        return (record?.read(key) as [String]?) ?? rows.compactMap { $0.string("name") }
    }

    /// The manga's authors, each carrying the person id that opens their page.
    /// Tenrai nests a `mal_id` in every author row, so the header can open one;
    /// a provider that flattens the list into names leaves them as plain text.
    private var authorPeople: [PersonReference] {
        let rows: [Fields] = record?.read("authors") ?? []
        return unique(rows.compactMap { PersonReference($0) })
    }

    private var authorNames: String {
        fieldNames("authors").joined(separator: " · ")
    }

    /// A synopsis longer than one paragraph starts collapsed. MAL puts its
    /// editor's note on a line of its own, so a long summary is the common case
    /// and should not push the rest of the page below the fold.
    private func summary(_ text: String) -> some View {
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let rest = Array(paragraphs.dropFirst())
        return VStack(alignment: .leading, spacing: 10) {
            Text(paragraphs.first ?? text).lineSpacing(4).textSelection(.enabled)
            if summaryExpanded {
                ForEach(Array(rest.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).lineSpacing(4).textSelection(.enabled)
                }
            }
            if !rest.isEmpty {
                ShowAllButton(title: summaryExpanded ? "Show less" : "Show more") {
                    summaryExpanded.toggle()
                }
                .accessibilityHint(
                    summaryExpanded ? "Collapses the summary" : "Shows the rest of the summary")
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let record {
                if showsSeriesInfo {
                    block("Series info") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 134), alignment: .topLeading)],
                                  alignment: .leading, spacing: 14) {
                            if let format = current.format { infoCell("Type", format) }
                            if let status = record.string("status") { infoCell("Status", status) }
                            if let total = current.total, total > 0 { infoCell(title.kind.unit, String(total)) }
                            if let volumes: Int = record.read("volumes"), volumes > 0 {
                                infoCell("Volumes", String(volumes))
                            }
                            if let aired = record.string("aired", "published")
                                ?? (record.read("aired", "published") as Fields?)?.string("string")
                            {
                                infoCell(title.kind == .anime ? "Aired" : "Published", aired)
                            }
                            if let duration = record.string("duration") { infoCell("Runtime", duration) }
                            if let season = record.string("season") {
                                let year: Int? = record.read("year")
                                infoCell(
                                    "Season",
                                    [season.capitalized, year.map { String($0) }].compactMap { $0 }
                                        .joined(separator: " "))
                            }
                            if showsSource, let source = record.string("source") {
                                infoCell("Source", source)
                            }
                            if let rating = record.string("rating") { infoCell("Rating", rating) }
                            if let members = current.members { infoCell("Members", members.formatted()) }
                            if let favorites: Int = record.read("favorites") {
                                infoCell("Favorites", favorites.formatted())
                            }
                        }
                    }
                }
                if showsAlternatives {
                    block("Alternative titles") {
                        if let english = current.englishName { infoCell("English", english) }
                        infoCell("Romaji", current.original)
                        if let japanese = record.string("title_japanese", "titleJapanese") {
                            infoCell("Japanese", japanese)
                        }
                        let aliases: [String] = record.read("title_synonyms", "titleSynonyms") ?? []
                        if !aliases.isEmpty { infoCell("Also known as", aliases.joined(separator: "\n")) }
                    }
                }
                if showsThemes { facetChips("Themes", catalogFacets("themes", category: .theme)) }
                if showsGenres { facetChips("Genres", catalogFacets("genres", category: .genre)) }
                if title.kind == .anime {
                    if showsCreators {
                        facetChips("Studios", catalogFacets("studios", category: .studio))
                        facetChips("Producers", catalogFacets("producers", category: .producer))
                    }
                } else if showsCreators {
                    chips("Serialization", fieldNames("serializations"))
                }
            }
        }
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func catalogFacets(_ key: String, category: CatalogFacet.Category) -> [CatalogFacet] {
        let rows: [Fields] = record?.read(key) ?? []
        let names: [String] = record?.read(key) ?? []
        let structured: [CatalogFacet] = rows.compactMap { row in
            guard let name = row.string("name") else { return nil }
            return CatalogFacet(name: name, malID: row.read("mal_id", "malId", "id"),
                                category: category, kind: title.kind)
        }
        return unique(structured + names.map { CatalogFacet(name: $0, malID: nil, category: category, kind: title.kind) })
    }

    @ViewBuilder
    private func facetChips(_ label: String, _ facets: [CatalogFacet]) -> some View {
        if !facets.isEmpty {
            block(label) {
                FlowLayout {
                    ForEach(facets) { facet in
                        NavigationLink(value: facet) { chipLabel(facet.name) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chipLabel(_ name: String) -> some View {
        Text(name).font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Palette.surface, in: .capsule)
    }

    @ViewBuilder
    private func chips(_ label: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            block(label) {
                FlowLayout {
                    ForEach(Array(Set(values)).sorted(), id: \.self) { value in
                        chipLabel(value)
                    }
                }
            }
        }
    }

    private var relations: some View { mediaRail("Relations", titles: related, notes: relationNames) }

    private var interestStacks: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                shelfHeading("Interest Stacks")
                Spacer(minLength: 8)
                NavigationLink(value: TitleStacksRoute(title: title, stacks: stacks, more: stacksMore)) {
                    viewAllLabel("stacks")
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(stacks.prefix(3))) { stack in
                    NavigationLink(value: StackRoute(stack: stack)) {
                        StackCard(stack: stack, showsDescription: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Divider() }
    }

    private func mediaRail(_ label: String, titles: [Title], notes: [String: String] = [:]) -> some View {
        let items = unique(titles)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                shelfHeading(label)
                Spacer(minLength: 8)
                NavigationLink(value: TitleCollectionRoute(label: label, titles: items, notes: notes)) {
                    viewAllLabel(label)
                }
                .buttonStyle(.plain)
            }
            LedgerShelf(spacing: 8, inset: LedgerLayout.inset) {
                ForEach(items.prefix(12)) { item in
                    shelfCover(item, note: notes[item.id]).frame(width: LedgerLayout.detailPosterWidth)
                }
            }
            .padding(.horizontal, -LedgerLayout.inset)
        }
    }

    private func shelfCover(_ title: Title, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            CoverTile(title: title, showsScore: false, loadMissingImage: note != nil,
                      reservesCaptionSpace: false, posterWidth: LedgerLayout.detailPosterWidth)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var cast: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                shelfHeading("Characters")
                Spacer(minLength: 8)
                NavigationLink(value: CharactersRoute(members: characters)) {
                    viewAllLabel("characters")
                }
                .buttonStyle(.plain)
            }
            LedgerShelf(spacing: 8, inset: LedgerLayout.inset) {
                ForEach(characters.prefix(12)) { member in
                    CastCard(member: member, showsRoleOnly: true).frame(width: LedgerLayout.detailPosterWidth)
                }
            }
            .padding(.horizontal, -LedgerLayout.inset)
        }
    }

    private func shelfHeading(_ label: String) -> some View {
        Text(label.uppercased()).font(.subheadline).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func viewAllLabel(_ section: String) -> some View {
        LedgerViewAll(section: section)
    }

    private func trailerCard(_ url: URL) -> some View {
        block("Trailer") {
            Link(destination: url) {
                Art(url: trailerImage ?? current.image)
                    .aspectRatio(16 / 9, contentMode: .fit)
                   .overlay {
                        Image(systemName: "play.fill").font(.title2)
                            .padding(16).ledgerGlassBadge()
                    }
                    .clipShape(.rect(cornerRadius: 12))
            }.accessibilityLabel("Play trailer")
        }
    }

    private var themeKeys: [String] {
        var keys: [String] = []
        if showsOpenings { keys.append("openings") }
        if showsEndings { keys.append("endings") }
        return keys
    }

    @ViewBuilder
    private var themeRows: some View {
        if !themeKeys.isEmpty {
            block("Theme songs") {
                if let themes {
                    ForEach(themeKeys, id: \.self) { key in
                        Text(key.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        let structured: [Fields] = themes.read(key) ?? []
                        let names: [String] = themes.read(key) ?? structured.compactMap { song in
                            guard let name = song.string("title") else { return nil }
                            if let artist = song.string("artist") { return "\(name) · \(artist)" }
                            return name
                        }
                        if names.isEmpty { Text("No themes listed.").foregroundStyle(.secondary) }
                        ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                            Text("\(index + 1). \(name)")
                        }
                    }
                } else {
                    Text("Theme information is unavailable.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var friends: some View {
        block("Friends’ list activity") {
            VStack(spacing: 0) {
                ForEach(friendRows) { row in
                    TitleFriendActivityRow(item: row)
                    if row.id != friendRows.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(Palette.surface.opacity(0.72), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.08))
                    .allowsHitTesting(false)
            }
            if !friendScanComplete {
                NextPageIndicator(label: "Checking friends", page: completedFriendBatches) {
                    await loadFriendBatch()
                }
            }
        }
    }

    private func reviewRows(_ firstPage: Page<TitleReview>?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                shelfHeading("Reviews")
                Spacer()
                NavigationLink(value: TitleReviewsRoute(
                    title: current, reviews: firstPage?.items, more: firstPage?.more ?? false)) {
                    viewAllLabel("reviews")
                }
                .buttonStyle(.plain)
            }
            if let firstPage, !firstPage.items.isEmpty {
                LedgerShelf {
                    ForEach(firstPage.items.prefix(3)) { review in
                        NavigationLink(value: TitleReviewRoute(title: current, review: review)) {
                            TitleReviewPreview(review: review, keepsShelfHeight: true)
                                .frame(width: 220, alignment: .leading)
                                .padding(12)
                                .ledgerPanel(radius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Divider() }
    }

    private func block<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LedgerSectionTitle(name)
            content()
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    private func load() async {
        failure = nil
        // Repaint the shelves from the last payload while the refresh runs. The
        // page body already reads that payload through `record`.
        if let cached = store.api.cachedDetail(title) {
            loadBundledSections(cached)
        }
        let path = "\(title.kind.rawValue)/\(title.malID)"
        // `/full` bundles the summary, relations and theme songs, so the page needs
        // one request instead of four. A section the reader hid from the Details
        // Page settings is never requested, not just hidden: the settings shape
        // the fan-out.
        async let detail = store.api.catalog(path + "/full", [], refresh: false)
        async let reviewData = store.api.titleReviews(title, page: 1)
        async let stackData = store.api.interestStacks(for: title, page: 1)
        async let castData = loadSection(showsCharacters, path + "/characters")
        async let recsData = loadSection(showsRecommendations, path + "/recommendations")
        do {
            let result = try await detail
            if let full: Fields = result.read("data") {
                payload = full
                savedAt = nil
                loadBundledSections(full)
            } else if record == nil {
                failure = "Title details are unavailable."
            }
        } catch {
            // A page opened without a connection falls back to the last payload
            // written to disk, labelled so an old synopsis is never passed off
            // as current.
            if !Task.isCancelled, record == nil {
                if let saved = store.api.savedDetail(title) {
                    payload = saved.fields
                    loadBundledSections(saved.fields)
                    savedAt = saved.savedAt
                } else {
                    failure = plainMessage(error, fallback: "Title details are unavailable.")
                }
            }
        }
        if let result = await castData {
            let items: [Fields] = result.read("data") ?? []
            let cast = unique(items.compactMap(CastMember.init))
            characters = cast.filter { $0.role?.lowercased() == "main" }
                + cast.filter { $0.role?.lowercased() != "main" }
        }
        do {
            let result = try await reviewData
            if !Task.isCancelled {
                reviews = result
                reviewsUnavailable = false
            }
        } catch {
            if !Task.isCancelled { reviewsUnavailable = true }
        }
        if let result = await recsData {
            suggested = unique(recommendations(result, kind: title.kind)).filter { $0.id != title.id }
        }
        if let page = try? await stackData {
            stacks = page.items
            stacksMore = page.more
        }
    }

    /// Reads the related titles and theme songs that `/full` returns with the details.
    private func loadBundledSections(_ detail: Fields) {
        let groups: [Fields] = detail.read("relations") ?? []
        var items: [Title] = []
        var names: [String: String] = [:]
        for group in groups {
            let entries: [Fields] = group.read("entry", "entries") ?? [group]
            for entry in entries {
                let type = entry.string("type") ?? "anime"
                let kind: Kind = ["manga", "novel", "light novel"].contains(type.lowercased()) ? .manga : .anime
                if let item = Title(entry, kind: kind) {
                    items.append(item)
                    names[item.id] = group.string("relation") ?? "Related"
                }
            }
        }
        relationNames = names
        related = unique(items)

        if let songs: Fields = detail.read("themeSongs", "theme") { themes = songs }
    }

    /// A catalog request for a section the reader may have hidden. The hidden
    /// case answers without touching the network.
    private func loadSection(_ wanted: Bool, _ path: String) async -> Fields? {
        guard wanted else { return nil }
        return try? await store.api.catalog(path, [], refresh: false)
    }

    private func loadFriendBatch() async {
        guard let user = store.account, !checkingFriends else { return }
        checkingFriends = true
        defer { if user == store.account { checkingFriends = false } }
        if store.friends.isEmpty {
            do { try await store.fetchFriends(user) }
            catch { return }
        }
        let ledger = store
        let item = current
        let limit = min(store.friends.count, Self.friendScanLimit)
        guard friendOffset < limit else { return }
        repeat {
            guard friendOffset < limit else { break }
            let batch = Array(store.friends[friendOffset..<min(friendOffset + 6, limit)])
            guard !batch.isEmpty else { break }
            // Look the whole batch up at once: each friend can cost two requests.
            let found = await withTaskGroup(of: FriendUpdate?.self) { group in
                for friend in batch {
                    group.addTask { try? await ledger.friendEntry(friend, item) }
                }
                var rows: [FriendUpdate] = []
                for await row in group {
                    if let row { rows.append(row) }
                }
                return rows
            }
            guard !Task.isCancelled, user == store.account else { return }
            friendOffset += batch.count
            guard !found.isEmpty else { continue }
            friendRows = unique(friendRows + found).sorted { activityDate($0.date) > activityDate($1.date) }
        } while friendRows.isEmpty && friendOffset < limit
        completedFriendBatches += 1
    }
}

/// The poster on its own, filling the screen. Tap to close; pinch to look closer.
private struct PosterScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let symbol: String
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1

    private var scale: CGFloat { min(max(zoom * pinch, 1), 4) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            KFImage.url(url)
                .placeholder { placeholder }
                .onFailureView { placeholder }
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: zoom)
                .gesture(
                    MagnifyGesture()
                        .onChanged { pinch = $0.magnification }
                        .onEnded { _ in
                            zoom = scale
                            pinch = 1
                        }
                )
                .accessibilityLabel("Poster")
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .padding(12)
                    .ledgerGlassBadge()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close poster")
            .padding(12)
        }
        .onTapGesture { dismiss() }
        .statusBarHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.black
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
        }
    }
}

/// The shape of a title page before its payload lands: poster, title, action
/// pills and a few section blocks. It replaces the partial page that used to
/// paint itself and then reflow as each request answered.
private struct TitleSkeleton: View {
    let kind: Kind

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
            VStack(spacing: 12) {
                SkeletonBlock(height: 208, width: 144, radius: 10)
                SkeletonBlock(height: 22, width: 240)
                SkeletonBlock(height: 14, width: 150)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 34) }
                }
                .frame(maxWidth: 480)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 46, radius: 9) }
            }
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(height: 16, width: 120)
                ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 12) }
                SkeletonBlock(height: 12, width: 220)
            }
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(height: 16, width: 90)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 150, radius: 8) }
                }
            }
        }
        .padding(LedgerLayout.inset)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(kind.rawValue) details")
    }
}

private struct StackCard: View {
    let stack: InterestStack
    var showsDescription = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stack.name)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsDescription, let summary = stack.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StackBadges(stack: stack).font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .ledgerPanel(radius: 12)
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct StackBadges: View {
    let stack: InterestStack

    var body: some View {
        FlowLayout {
            Text("\(stack.entryCount) \(stack.entryCount == 1 ? "title" : "titles")")
                .foregroundStyle(.secondary)
            if stack.isOfficial { pill("Official") }
            if stack.isChallenge { pill("Challenge") }
            if stack.isSpoiler { pill("Spoilers") }
            if stack.restacks > 0 {
                Label("\(stack.restacks)", systemImage: "arrow.2.squarepath")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(stack.restacks) restacks")
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.10), in: .capsule)
    }
}

/// A full screen of posters for a media rail's "View all" link.
struct TitleCollectionScreen: View {
    let route: TitleCollectionRoute

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                ForEach(route.titles) { title in
                    VStack(alignment: .leading, spacing: 3) {
                        CoverTile(
                            title: title, showsScore: route.showsScore,
                            loadMissingImage: route.notes[title.id] != nil,
                            reservesCaptionSpace: false, posterWidth: LedgerLayout.detailPosterWidth)
                        if let note = route.notes[title.id] {
                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
            .padding(LedgerLayout.inset)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(route.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One stack with its full description, author, badges and every entry it lists.
struct StackScreen: View {
    @EnvironmentObject private var store: Store
    let stack: InterestStack
    @State private var detail: StackDetail?
    @State private var failure: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let detail {
                    if detail.entries.isEmpty {
                        Text("No entries were returned for this stack.").foregroundStyle(.secondary)
                    } else {
                        let count = detail.entries.count
                        // The list row that pushed this page and the page's own
                        // response do not always carry the total, so take whichever knows it.
                        let total = max(shown.entryCount, stack.entryCount)
                        if count < total {
                            Text("Showing \(count) of \(total) titles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(detail.entries) { entry in
                                StackEntryRow(entry: entry, kind: shown.kind, hidesNote: shown.isSpoiler)
                            }
                        }
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 12)
                } else if let failure {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Retry") { Task { await load() } }.ledgerGlassButton()
                    }
                }
            }
            .padding(LedgerLayout.inset)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(shown.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// The stack the page was pushed with, replaced by the one its response
    /// describes. A page opened from a link carries an id alone, so the header it
    /// draws before loading is a placeholder.
    private var shown: InterestStack { detail?.stack ?? stack }

    /// Whether the page knows who wrote the stack and how long it is. A page
    /// opened from a link does not until its response lands, so it shows none of
    /// that rather than a placeholder author and a count of zero.
    private var showsFacts: Bool { detail != nil || shown.entryCount > 0 }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shown.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if showsFacts {
                HStack(spacing: 5) {
                    Text("by").foregroundStyle(.secondary)
                    if let authorURL = shown.authorURL {
                        Link(shown.author, destination: authorURL)
                    } else {
                        Text(shown.author)
                    }
                }
                .font(.subheadline)
                StackBadges(stack: shown).font(.caption)
            }
            if let summary = shown.summary {
                StackSummary(text: summary, kind: shown.kind)
            }
            if let created = shown.created {
                Text(created.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            detail = try await store.api.stackDetail(stack.id)
        } catch {
            if !Task.isCancelled { failure = plainMessage(error, fallback: "This stack is unavailable.") }
        }
    }
}

/// A stack description with the stack links in it made tappable, so a stack that
/// numbers the rest of its series opens those stacks here instead of the web.
private struct StackSummary: View {
    let text: String
    let kind: Kind

    private var paragraphs: [String] {
        text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                paragraphView(paragraph)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(_ paragraph: String) -> some View {
        let segments = StackLink.segments(in: paragraph)
        if segments.count == 1, case .text = segments[0] {
            Text(paragraph)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // A paragraph with a link is laid out as runs so the link can be its
            // own control while the surrounding text still wraps normally.
            FlowLayout {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let value):
                        Text(value).lineSpacing(4)
                    case .stack(let value, let id):
                        NavigationLink(value: StackRoute(stack: InterestStack(id: id, kind: kind))) {
                            Text(value)
                                .lineSpacing(4)
                                .foregroundStyle(.tint)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this stack in Aniswift")
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }
}

/// One title in a stack: poster on the left, the title and its facts on the
/// right, and the stack author's note underneath. A stack flagged as spoilers
/// keeps that note behind a tap, the same way the review reader hides spoilers.
private struct StackEntryRow: View {
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let entry: StackEntry
    let kind: Kind
    let hidesNote: Bool
    @State private var revealed = false

    private var note: String? {
        guard let note = entry.note, !note.isEmpty else { return nil }
        return note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: entry.title) { card }.buttonStyle(.plain)
            if let note {
                if hidesNote && !revealed {
                    Button("Reveal note") { revealed = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .buttonStyle(.borderless)
                        .accessibilityHint("Shows the stack author's note for this title")
                } else {
                    Text(note)
                        .font(.subheadline)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterArt(url: entry.title.image, symbol: kind == .anime ? "film" : "book", width: posterWidth)
                .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
                .overlay(alignment: .topLeading) {
                    if entry.position > 0 {
                        Text(String(entry.position))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6), in: .rect(cornerRadius: 4))
                            .padding(4)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title.displayName(for: titleLanguage))
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(facts)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: posterWidth / LedgerLayout.posterRatio, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var posterWidth: CGFloat { 96 }

    private var facts: String {
        var parts = [entry.title.kind.label]
        if let total = entry.title.total {
            parts.append("\(total) \(entry.title.kind == .anime ? "ep" : "ch")")
        }
        if let year = entry.title.releaseYear {
            parts.append(String(year))
        }
        if let score = entry.score {
            parts.append("\(score)/10")
        }
        return parts.joined(separator: ", ")
    }
}

/// Every stack that lists this title, with the first page handed over from the
/// title page so opening it does not repeat the request.
struct TitleStacksScreen: View {
    @EnvironmentObject private var store: Store
    let title: Title
    @State private var stacks: [InterestStack]
    @State private var nextPage: Int?
    @State private var loadingPage: Int?
    @State private var failed = false

    init(title: Title, firstPage: Page<InterestStack>? = nil) {
        self.title = title
        _stacks = State(initialValue: firstPage?.items ?? [])
        let more = firstPage?.more ?? false
        _nextPage = State(initialValue: firstPage == nil ? 1 : (more ? 2 : nil))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(stacks) { stack in
                    NavigationLink(value: StackRoute(stack: stack)) {
                        StackCard(stack: stack, showsDescription: true)
                    }
                    .buttonStyle(.plain)
                }
                if let nextPage {
                    if failed {
                        VStack(spacing: 8) {
                            Text("Could not load more stacks.").foregroundStyle(.secondary)
                            Button("Retry") { Task { await load(nextPage) } }.ledgerGlassButton()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        NextPageIndicator(label: "Loading more stacks", page: nextPage) {
                            await load(nextPage)
                        }
                    }
                }
            }
            .padding(LedgerLayout.inset)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Interest Stacks")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            loadingPage = nil
            failed = false
            stacks = []
            nextPage = 1
            await load(1)
        }
    }

    private func load(_ page: Int) async {
        guard loadingPage == nil else { return }
        loadingPage = page
        defer { loadingPage = nil }
        do {
            let result = try await store.api.interestStacks(for: title, page: page)
            guard !Task.isCancelled else { return }
            stacks = unique(stacks + result.items)
            nextPage = result.more ? page + 1 : nil
            failed = false
        } catch {
            // Keep the page indicator so the retry can ask for the same page again.
            if !Task.isCancelled { failed = true }
        }
    }
}

struct TitleReviewsScreen: View {
    @EnvironmentObject private var store: Store
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let title: Title
    @State private var reviews: [TitleReview]
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var failed = false

    init(title: Title, firstPage: Page<TitleReview>?) {
        self.title = title
        _reviews = State(initialValue: firstPage?.items ?? [])
        let nextPage: Int? = firstPage == nil ? 1 : (firstPage?.more == true ? 2 : nil)
        _nextPage = State(initialValue: nextPage)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(title.displayName(for: titleLanguage)).font(.title3.weight(.semibold))
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                ForEach(reviews) { review in
                    NavigationLink(value: TitleReviewRoute(title: title, review: review)) {
                        HStack(spacing: 12) {
                            TitleReviewPreview(review: review)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }

                if failed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not load reviews.").foregroundStyle(.secondary)
                        Button("Retry") { Task { await load() } }.ledgerGlassButton()
                    }
                    .padding(.top, 14)
                } else if let nextPage {
                    NextPageIndicator(label: "Loading reviews", page: nextPage) { await load() }
                } else if reviews.isEmpty {
                    ContentUnavailableView("No reviews yet", systemImage: "text.alignleft")
                }
            }
            .padding(LedgerLayout.inset)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            failed = false
            reviews = []
            nextPage = 1
            await load()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: title.malURL.appending(path: "_/reviews")) {
                    Label("Reviews on MyAnimeList", systemImage: "arrow.up.right")
                }
            }
        }
    }

    private func load() async {
        guard let page = nextPage, !loading else { return }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let result = try await store.api.titleReviews(title, page: page)
            guard !Task.isCancelled else { return }
            reviews = unique(reviews + result.items)
            nextPage = result.more ? page + 1 : nil
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

private struct TitleReviewPreview: View {
    let review: TitleReview
    /// Whether every card reserves the same verdict and date lines, so a row of
    /// shelf cards lines up; the reviews list leaves each row its own height.
    var keepsShelfHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Art(url: review.avatar, symbol: "person.fill")
                    .frame(width: 28, height: 28).clipShape(.circle)
                Text(review.author).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Text(review.spoiler ? "Contains spoilers" : review.text)
                .font(.subheadline).lineLimit(4, reservesSpace: keepsShelfHeight)
            // The date keeps a line of its own: with it on the verdict's line, a
            // long verdict pushed it onto a second line and broke the date in the
            // middle, and the two cards never matched. Both rows are reserved in
            // a shelf, so a card without a date still keeps the same height.
            let verdict = [review.tag, review.ratingLabel].compactMap { $0 }.joined(separator: " · ")
            VStack(alignment: .leading, spacing: 2) {
                if !verdict.isEmpty {
                    Text(verdict).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1, reservesSpace: keepsShelfHeight)
                } else if keepsShelfHeight {
                    Text(" ").font(.caption).lineLimit(1, reservesSpace: true).accessibilityHidden(true)
                }
                if let date = review.displayedDate {
                    Text(date).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1, reservesSpace: keepsShelfHeight)
                } else if keepsShelfHeight {
                    Text(" ").font(.caption).lineLimit(1, reservesSpace: true).accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TitleReviewReader: View {
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let title: Title
    let review: TitleReview
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    PosterArt(url: title.image, symbol: title.kind == .anime ? "film" : "book", width: 74)
                        .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title.displayName(for: titleLanguage)).font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Reviewed by \(Text(review.author).bold())")
                            .font(.subheadline).foregroundStyle(.secondary)
                        let metadata = [review.tag, review.ratingLabel, review.displayedDate].compactMap { $0 }
                        if !metadata.isEmpty {
                            Text(metadata.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                if review.spoiler && !revealed {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("This review contains spoilers.", systemImage: "eye.slash")
                            .foregroundStyle(.secondary)
                        Button("Show review") { revealed = true }.ledgerGlassButton()
                    }
                } else {
                    Text(review.text)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(LedgerLayout.inset)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = review.url {
                    Menu {
                        ShareLink(item: url)
                        Link(destination: url) { Label("View on MyAnimeList", systemImage: "arrow.up.right") }
                    } label: { Label("Review options", systemImage: "ellipsis") }
                }
            }
        }
    }
}

private struct TitleFriendActivityRow: View {
    let item: FriendUpdate

    private var progressLabel: String? {
        guard let progress = item.progress else { return nil }
        let total = item.total.flatMap { $0 > 0 ? $0 : nil }
        let singular = (total ?? progress) == 1
        let unit = item.title.kind == .anime ? (singular ? "episode" : "episodes") : (singular ? "chapter" : "chapters")
        let count = total.map { "\(progress.formatted()) / \($0.formatted())" } ?? progress.formatted()
        return "\(count) \(unit)"
    }

    var body: some View {
        NavigationLink(value: item.friend) {
            HStack(alignment: .top, spacing: 10) {
                Art(url: item.friend.avatar, symbol: "person.fill")
                    .frame(width: 40, height: 40)
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.friend.name)
                        .font(.subheadline.weight(.semibold))
                    let date = displayDate(item.date)
                    if !date.isEmpty {
                        Text(date).font(.caption).foregroundStyle(.secondary)
                    }
                    FlowLayout {
                        if let status = item.status {
                            Text(statusLabel(status))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.10), in: .capsule)
                        }
                        if let progressLabel {
                            Text(progressLabel).foregroundStyle(.secondary)
                        }
                        if let score = item.score, score > 0 {
                            Label("\(score) / 10", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Score \(score) out of 10")
                        }
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens their profile")
    }
}

struct FlowLayout: Layout {
    private let spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (view, item) in zip(subviews, rows.items) {
            view.place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                       anchor: .topLeading, proposal: ProposedViewSize(item.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, items: [CGRect]) {
        var items: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = ideal.width <= width ? ideal : view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), items)
    }
}

struct ListEditor: View {
    enum Mode: String, Identifiable {
        case full, status, progress, score
        var id: Self { self }
    }

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let title: Title
    let mode: Mode
    @State private var original: ListEntry?
    @State private var change: ListChange
    @State private var details: ListDetails
    @State private var ready: Bool
    @State private var loading = false
    @State private var selectedLists: Set<UUID> = []
    @State private var newLists: [CustomTitleList] = []
    @State private var hidden = false
    @State private var organizationLoaded = false
    @State private var creatingList = false
    @State private var newListName = ""
    @State private var busy = false
    @State private var confirmRemoval = false
    @State private var error: String?
    @AppStorage(SettingKey.askForScore) private var asksForScore = true
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    @State private var askingForScore = false

    init(title: Title, original: ListEntry?, mode: Mode = .full) {
        self.title = title
        self.mode = mode
        _original = State(initialValue: original)
        _change = State(initialValue: Self.listChange(title, original))
        _details = State(initialValue: original?.details ?? ListDetails())
        _ready = State(initialValue: original != nil && (mode != .full || original?.details != nil))
    }

    private var total: Int? {
        [title.total, original?.title.total].compactMap { $0 }.first { $0 > 0 }
    }

    private var maximumProgress: Int { max(total ?? 100_000, original?.progress ?? 0) }

    private var heading: String {
        switch mode {
        case .full: ready && original == nil ? "Add to My List" : "Edit"
        case .status: "Status"
        case .progress: title.kind.unit
        case .score: "My score"
        }
    }

    private var remoteChanged: Bool {
        guard let original else { return true }
        return original.status != change.status || original.progress != change.progress ||
            original.rating != change.rating || (mode == .full && details != (original.details ?? ListDetails()))
    }

    private var originalListIDs: Set<UUID> {
        Set(store.organization.lists.filter { list in list.titles.contains { $0.id == title.id } }.map(\.id))
    }

    private var organizationChanged: Bool {
        !newLists.isEmpty || selectedLists != originalListIDs || hidden != store.organization.hidden.contains(title.id)
    }

    private var saveDisabled: Bool {
        !ready || busy || !(0...maximumProgress).contains(change.progress) ||
            (mode == .full && details.notes.utf8.count > 4000) ||
            (!remoteChanged && (mode != .full || !organizationChanged))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !ready { preparation }
                else if askingForScore { scorePrompt }
                else if mode == .full { fullEditor }
                else { quickEditor }
            }
            .navigationTitle(askingForScore ? "My score" : heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                        .disabled(busy)
                }
                if mode == .full {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { submit(change) }.disabled(saveDisabled)
                    }
                }
            }
            .confirmationDialog("Remove this title from your MyAnimeList list?", isPresented: $confirmRemoval) {
                Button("Remove", role: .destructive) { submit(nil) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Create Custom List", isPresented: $creatingList) {
                TextField("List name", text: $newListName)
                Button("Create") { createList() }
                Button("Cancel", role: .cancel) {}
            }
            .interactiveDismissDisabled(busy)
            .task {
                if mode == .full, !organizationLoaded {
                    selectedLists = originalListIDs
                    hidden = store.organization.hidden.contains(title.id)
                    organizationLoaded = true
                }
                if !ready { await prepare() }
            }
        }
    }

    private var preparation: some View {
        VStack(spacing: 12) {
            if let error, !loading {
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { Task { await prepare() } }.ledgerGlassButton()
            } else {
                ProgressView("Loading list entry")
            }
        }
        .padding(LedgerLayout.inset)
    }

    private var fullEditor: some View {
        Form {
            Section {
                statusPicker
                numberRow("Score", value: $change.rating, range: 0...10)
                numberRow(title.kind.unit, value: $change.progress, range: 0...maximumProgress)
                numberRow(title.kind == .anime ? "Total rewatches" : "Total rereads",
                          value: $details.repeatCount, range: 0...100_000)
            }
            Section("Dates") {
                dateRow("Start Date", value: $details.startDate)
                dateRow("Finish Date", value: $details.finishDate)
            }
            Section("Notes") {
                TextField(
                    "Add notes for \(title.displayName(for: titleLanguage))",
                    text: $details.notes,
                    axis: .vertical
                )
                    .lineLimit(4...10)
                if details.notes.utf8.count > 4000 {
                    Text("Notes are too long.").foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Text("Custom Lists")
                    Spacer()
                    Button("Create") {
                        newListName = ""
                        creatingList = true
                    }.ledgerGlassButton()
                }
                ForEach(store.organization.lists + newLists) { list in
                    Toggle(list.name, isOn: Binding(
                        get: { selectedLists.contains(list.id) },
                        set: { if $0 { selectedLists.insert(list.id) } else { selectedLists.remove(list.id) } }
                    ))
                }
                Toggle("Hide from status lists", isOn: $hidden)
            } header: {
                Text("Organization")
            } footer: {
                Text("Custom lists and visibility are saved on this device. Hidden entries can still be found through search.")
            }
            if let error { Label(error, systemImage: "exclamationmark.circle") }
            if original != nil {
                Button("Remove from My List", role: .destructive) { confirmRemoval = true }
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(busy)
        .sensoryFeedback(.selection, trigger: selectedLists)
        .sensoryFeedback(.selection, trigger: hidden)
    }

    private func numberRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(label) {
                TextField(label, value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 50)
            }
        }
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }

    @ViewBuilder
    private func dateRow(_ label: String, value: Binding<String>) -> some View {
        if value.wrappedValue.isEmpty {
            LabeledContent(label) {
                Button("Set") { value.wrappedValue = dayFormatter.string(from: Date()) }
                    .ledgerGlassButton()
                    .accessibilityLabel("Set \(label.lowercased())")
            }
        } else {
            HStack {
                DatePicker(label, selection: Binding(
                    get: { dayFormatter.date(from: value.wrappedValue) ?? Date() },
                    set: { value.wrappedValue = dayFormatter.string(from: $0) }
                ), displayedComponents: .date)
                Button {
                    value.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear \(label.lowercased())")
            }
        }
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func listChange(_ title: Title, _ entry: ListEntry?) -> ListChange {
        ListChange(status: entry?.status ?? title.kind.statuses.last!,
                   progress: entry?.progress ?? 0, rating: entry?.rating ?? 0)
    }

    private func prepare() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let entry = try await store.api.listEntry(title)
            guard !Task.isCancelled else { return }
            original = entry
            details = entry?.details ?? ListDetails()
            change = Self.listChange(title, entry)
            ready = true
        } catch {
            if !Task.isCancelled { self.error = plainMessage(error, fallback: "Could not load this entry.") }
        }
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = (store.organization.lists + newLists).first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            selectedLists.insert(existing.id)
        } else {
            let list = CustomTitleList(name: name)
            newLists.append(list)
            selectedLists.insert(list.id)
        }
    }

    private var statusPicker: some View {
        Picker("Status", selection: $change.status) {
            ForEach(title.kind.statuses, id: \.self) { Text(statusLabel($0)).tag($0) }
        }
        .sensoryFeedback(.selection, trigger: change.status)
    }

    private var quickEditor: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch mode {
                case .status:
                    statusPicker.pickerStyle(.wheel).frame(height: 132)
                case .progress:
                    if let total { Text("Total \(title.kind.unit.lowercased()) · \(total)").foregroundStyle(.secondary) }
                    counter($change.progress, maximum: maximumProgress, label: title.kind.unit)
                case .score:
                    counter($change.rating, maximum: 10, label: "Score", zeroLabel: "—")
                case .full:
                    EmptyView()
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, LedgerLayout.inset)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                submit(change)
            } label: {
                Text(busy ? "Updating…" : "Update").frame(maxWidth: .infinity, minHeight: 32)
            }
            .ledgerProminentButton()
            .disabled(saveDisabled)
            .frame(maxWidth: 420)
            .padding(.horizontal, LedgerLayout.inset)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Palette.sheet)
        }
        .alert("Couldn’t update your list", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var scorePrompt: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("How was \(title.displayName(for: titleLanguage))?")
                    .font(.headline).multilineTextAlignment(.center)
                Text("Your entry is saved as completed. Add a score if you want.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                counter($change.rating, maximum: 10, label: "Score", zeroLabel: "—")
                HStack(spacing: 12) {
                    Button("Not now") { dismiss() }.ledgerGlassButton()
                    Button("Save score") { submit(change) }.ledgerProminentButton()
                        .disabled(busy || change.rating == 0)
                }
            }
            .padding(LedgerLayout.inset)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
    }

    private func counter(_ value: Binding<Int>, maximum: Int, label: String, zeroLabel: String = "0") -> some View {
        HStack(spacing: 14) {
            Button { value.wrappedValue -= 1 } label: {
                Image(systemName: "minus").frame(width: 36, height: 44)
            }
            .ledgerGlassButton()
            .accessibilityLabel("Decrease \(label.lowercased())")
            .disabled(value.wrappedValue <= 0 || busy)

            Text(value.wrappedValue == 0 ? zeroLabel : value.wrappedValue.formatted())
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 60)
                .ledgerPanel(radius: 14)
                .accessibilityLabel(label)
                .accessibilityValue(zeroLabel == "—" && value.wrappedValue == 0 ? "Unscored" : value.wrappedValue.formatted())

            Button { value.wrappedValue += 1 } label: {
                Image(systemName: "plus").frame(width: 36, height: 44)
            }
            .ledgerGlassButton()
            .accessibilityLabel("Increase \(label.lowercased())")
            .disabled(value.wrappedValue >= maximum || busy)
        }
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }

    private func submit(_ value: ListChange?) {
        guard let accountID = store.account?.id else { return }
        guard value == nil || !saveDisabled else { return }
        let shouldUpdateMAL = value == nil || remoteChanged
        let shouldOrganize = value != nil && mode == .full && organizationChanged
        var update = value
        if mode == .full { update?.details = details.changes(from: original?.details ?? ListDetails()) }
        let asksNow =
            !askingForScore && asksForScore && mode != .score && title.kind == .anime
            && original?.status != "completed" && update?.status == "completed" && update?.rating == 0
        busy = true
        Task {
            defer { busy = false }
            do {
                if shouldUpdateMAL { try await store.change(title, update) }
                if shouldOrganize {
                    store.organize(title, lists: selectedLists, adding: newLists, hidden: hidden, accountID: accountID)
                }
                Haptics.success()
                if asksNow {
                    askingForScore = true
                    return
                }
                dismiss()
            } catch {
                if (error as? APIError)?.status == 401 { store.handle(error) } else { Haptics.error() }
                self.error = plainMessage(error, fallback: "Could not save this entry.")
            }
        }
    }
}
