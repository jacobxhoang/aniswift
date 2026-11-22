import SwiftUI

struct TitleScreen: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var quickSheetExtra: CGFloat = 32
    let title: Title
    @State private var record: Fields?
    @State private var related: [Title] = []
    @State private var suggested: [Title] = []
    @State private var episodes: [Fields] = []
    @State private var relationNames: [String: String] = [:]
    @State private var characters: [CastMember] = []
    @State private var themes: Fields?
    @State private var reviews: [TitleReview] = []
    @State private var openReview: TitleReview?
    @State private var external: [TitleExternalLink] = []
    @State private var failure: String?
    @State private var editor: ListEditor.Mode?
    @State private var confirmRemoval = false
    @State private var changingList = false
    @State private var friendRows: [FriendUpdate] = []
    @State private var friendOffset = 0
    @State private var completedFriendBatches = 0
    @State private var checkingFriends = false
    @State private var friendsUnavailable = false

    private var current: Title {
        let detail = record.flatMap { Title($0, kind: title.kind) } ?? title
        return detail.fillingTitleAndImage(from: title).fillingTitleAndImage(from: saved?.title)
    }
    private var saved: ListEntry? { store.lists[title.kind, default: []].first { $0.id == title.id } }

    var body: some View {
        ScrollView {
            header
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                actions
                if let failure {
                    Text(failure).foregroundStyle(.secondary)
                    Button("Reload details") { Task { await load() } }
                }
                if let description = record?.string("synopsis") {
                    block("Summary") { Text(description).lineSpacing(4).textSelection(.enabled) }
                }
                metadata
                if let background = record?.string("background") { block("Background") { Text(background) } }
                if !related.isEmpty { relations }
                if !characters.isEmpty { cast }
                if !suggested.isEmpty { mediaRail("Recommended", titles: suggested) }
                if let trailer = trailerURL { trailerCard(trailer) }
                if !episodes.isEmpty { episodeRail }
                if title.kind == .anime { themeRows }
                if !friendRows.isEmpty { friends }
                if !reviews.isEmpty { reviewRows }
                if !external.isEmpty { externalLinks }
            }
            .padding(LedgerLayout.inset)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(current.name)
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
                    ShareLink(item: API.website.appending(path: "\(title.kind.rawValue)/\(title.malID)"))
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
            friendsUnavailable = false
            checkingFriends = false
            await loadFriendBatch()
        }
        .sheet(item: $openReview) { review in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(review.author).font(.headline)
                        if let rating = review.rating, (1...10).contains(rating) { Text("Reviewer rating: \(rating)/10").foregroundStyle(.secondary) }
                        Text(review.text).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(LedgerLayout.inset)
                }
                .background(Palette.background)
                .navigationTitle("Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { openReview = nil } } }
            }
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
        Task {
            defer { changingList = false }
            do { try await store.change(item, change) }
            catch { store.handle(error) }
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
            Art(url: current.image ?? title.image, symbol: title.kind == .anime ? "film" : "book")
                .frame(width: 144, height: 208)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14))
                        .allowsHitTesting(false)
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
            Text(current.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            let studios = catalogFacets("studios", category: .studio)
            let authors = fieldNames("authors").joined(separator: " · ")
            if title.kind == .anime, !studios.isEmpty {
                FlowLayout {
                    ForEach(studios) { studio in
                        NavigationLink(value: studio) {
                            Text(studio.name.uppercased()).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if title.kind == .manga, !authors.isEmpty {
                Text(authors.uppercased()).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if current.original != current.name {
                Text(current.original).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 6) {
                let score = current.score.flatMap { $0 > 0 ? ($0 / 10).formatted(.percent.precision(.fractionLength(0))) : nil }
                let rank: Int? = record?.read("rank")
                let popularity: Int? = record?.read("popularity")
                statistic("Average score", score)
                statistic("MAL rank", rank.flatMap { $0 > 0 ? "#\($0)" : nil })
                statistic("Popularity", popularity.flatMap { $0 > 0 ? "#\($0)" : nil })
            }
            .frame(maxWidth: 480)
            .padding(.top, 8)
        }
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
        let unit = title.kind == .anime ? "ep" : "ch"
        let total = (current.total ?? item?.title.total).flatMap { $0 > 0 ? String($0) : nil } ?? "?"
        editControl("Status", item.map { statusLabel($0.status) } ?? "Add to list", mode: item == nil ? .full : .status)
        editControl("Progress", "\(item.map { String($0.progress) } ?? "—") / \(total) \(unit)", mode: .progress)
        let rating = item?.rating ?? 0
        editControl("My score", rating > 0 ? "\(rating) / 10" : "Unscored", mode: .score)
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

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let record {
                block("Series info") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 134), alignment: .topLeading)],
                              alignment: .leading, spacing: 14) {
                        if let format = current.format { infoCell("Type", format) }
                        if let status = record.string("status") { infoCell("Status", status) }
                        if let total = current.total, total > 0 { infoCell(title.kind.unit, String(total)) }
                        if let volumes: Int = record.read("volumes"), volumes > 0 { infoCell("Volumes", String(volumes)) }
                        if let aired = record.string("aired", "published") ?? (record.read("aired", "published") as Fields?)?.string("string") {
                            infoCell(title.kind == .anime ? "Aired" : "Published", aired)
                        }
                        if let duration = record.string("duration") { infoCell("Runtime", duration) }
                        if let season = record.string("season") {
                            let year: Int? = record.read("year")
                            infoCell("Season", [season.capitalized, year.map { String($0) }].compactMap { $0 }.joined(separator: " "))
                        }
                        if let source = record.string("source") { infoCell("Source", source) }
                        if let rating = record.string("rating") { infoCell("Rating", rating) }
                        if let members = current.members { infoCell("Members", members.formatted()) }
                        if let favorites: Int = record.read("favorites") { infoCell("Favorites", favorites.formatted()) }
                    }
                }
                block("Alternative titles") {
                    if let english = current.englishName { infoCell("English", english) }
                    infoCell("Romaji", current.original)
                    if let japanese = record.string("title_japanese", "titleJapanese") { infoCell("Japanese", japanese) }
                    let aliases: [String] = record.read("title_synonyms", "titleSynonyms") ?? []
                    if !aliases.isEmpty { infoCell("Also known as", aliases.joined(separator: "\n")) }
                }
                facetChips("Themes", catalogFacets("themes", category: .theme))
                facetChips("Genres", catalogFacets("genres", category: .genre))
                if title.kind == .anime {
                    facetChips("Studios", catalogFacets("studios", category: .studio))
                    facetChips("Producers", catalogFacets("producers", category: .producer))
                } else {
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

    private func mediaRail(_ label: String, titles: [Title], notes: [String: String] = [:]) -> some View {
        let items = unique(titles)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                shelfHeading(label)
                Spacer(minLength: 8)
                NavigationLink {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                            ForEach(items) { item in shelfCover(item, note: notes[item.id]) }
                        }
                        .padding(LedgerLayout.inset)
                    }
                    .background(Palette.background.ignoresSafeArea())
                    .navigationTitle(label)
                    .navigationBarTitleDisplayMode(.inline)
                } label: { viewAllLabel(label) }
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
                NavigationLink {
                    CharactersScreen(members: characters)
                } label: { viewAllLabel("characters") }
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
        Text("View All")
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.surface, in: .rect(cornerRadius: 7))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("View all \(section.lowercased())")
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

    private var episodeRail: some View {
        block("Episodes") {
            LedgerShelf {
                ForEach(Array(episodes.enumerated()), id: \.offset) { index, item in
                    let number: Int = item.read("mal_id", "malId", "episode", "number") ?? index + 1
                    let name = item.englishTitle ?? item.string("title") ?? item.romajiTitle ?? "Episode \(number)"
                    let url = publicURL(item.string("url")) ?? title.malURL.appending(path: "episode/\(number)")
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 7) {
                            if let image = item.image {
                                Art(url: image).frame(width: 150, height: 84)
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                            Text("Episode \(number)").font(.caption).foregroundStyle(.secondary)
                            Text(name).font(.subheadline.weight(.medium)).lineLimit(2)
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(10)
                        .background(Palette.surface, in: .rect(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var themeRows: some View {
        block("Theme songs") {
            if let themes {
                ForEach(["openings", "endings"], id: \.self) { key in
                    Text(key.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    let structured: [Fields] = themes.read(key) ?? []
                    let names: [String] = themes.read(key) ?? structured.compactMap { song in
                        guard let name = song.string("title") else { return nil }
                        if let artist = song.string("artist") { return "\(name) · \(artist)" }
                        return name
                    }
                    if names.isEmpty { Text("No themes listed.").foregroundStyle(.secondary) }
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in Text("\(index + 1). \(name)") }
                }
            } else { Text("Theme information is unavailable.").foregroundStyle(.secondary) }
        }
    }

    private var friends: some View {
        block("Friends’ list activity") {
            ForEach(friendRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    FriendCaption(item: row)
                    Text([row.status.map(statusLabel),
                          row.progress.map { "\($0)/\(row.total.map { String($0) } ?? "?")" },
                          row.score.flatMap { $0 > 0 ? "\($0)/10" : nil }].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if friendsUnavailable && !checkingFriends {
                Text("Some friends’ activity is unavailable.").foregroundStyle(.secondary)
            }
            if friendOffset < store.friends.count || checkingFriends {
                NextPageIndicator(label: "Checking friends", page: completedFriendBatches) {
                    await loadFriendBatch()
                }
            }
        }
    }

    private var reviewRows: some View {
        block("Reviews") {
            Link("All reviews on MyAnimeList", destination: title.malURL.appending(path: "_/reviews"))
                .font(.subheadline)
            LedgerShelf {
                ForEach(reviews) { review in
                    Button { openReview = review } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Art(url: review.avatar, symbol: "person.fill")
                                    .frame(width: 28, height: 28).clipShape(.circle)
                                Text(review.author).font(.subheadline.weight(.semibold)).lineLimit(1)
                            }
                            Text(review.spoiler ? "Show review with spoilers" : review.text)
                                .font(.subheadline).lineLimit(4)
                            if let tag = review.tag { Text(tag).font(.caption).foregroundStyle(.secondary) }
                            if let rating = review.rating, (1...10).contains(rating) {
                                Text("Reviewer rating: \(rating)/10").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 220, alignment: .leading)
                        .padding(12)
                        .ledgerPanel(radius: 14)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var externalLinks: some View {
        block("External links") {
            FlowLayout {
                ForEach(external) { item in
                    Link(destination: item.url) {
                        HStack(spacing: 7) {
                            switch item.style {
                            case .social:
                                Text("𝕏").font(.body)
                                    .accessibilityHidden(true)
                            case .crunchyroll:
                                Image(systemName: "play.circle.fill").accessibilityHidden(true)
                            case .netflix:
                                Text("N").font(.subheadline.weight(.black)).accessibilityHidden(true)
                            case .standard:
                                EmptyView()
                            }
                            Text(item.name).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(item.style.fill, in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
        let path = "\(title.kind.rawValue)/\(title.malID)"
        async let detail = store.api.catalog(path)
        async let relatedData = store.api.catalog(path + "/relations")
        async let castData = store.api.catalog(path + "/characters")
        async let reviewData = store.api.catalog(path + "/reviews")
        async let links = loadExternalLinks(path)
        async let songs = loadThemes(path)
        async let recs = store.api.catalog(path + "/recommendations")
        async let episodeData = loadEpisodes(path)
        do {
            let result = try await detail
            record = result.read("data")
            if record == nil { failure = "Title details are unavailable." }
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        if let result = try? await relatedData {
            let groups: [Fields] = result.read("data") ?? []
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
        }
        if let result = try? await castData {
            let items: [Fields] = result.read("data") ?? []
            let cast = unique(items.compactMap(CastMember.init))
            characters = cast.filter { $0.role?.lowercased() == "main" }
                + cast.filter { $0.role?.lowercased() != "main" }
        }
        if let result = try? await reviewData {
            let items: [Fields] = result.read("data") ?? []
            reviews = Array(items.compactMap(TitleReview.init).prefix(3))
        }
        external = await links
        if let result = try? await recs {
            suggested = unique(recommendations(result, kind: title.kind)).filter { $0.id != title.id }
        }
        episodes = await episodeData
        themes = await songs
    }

    private func loadExternalLinks(_ path: String) async -> [TitleExternalLink] {
        async let websites = loadLinkRows(path + "/external", key: "externalLinks")
        async let services = title.kind == .anime
            ? loadLinkRows(path + "/streaming", key: "streaming") : []
        let rows = await (websites, services)
        let allRows = rows.0 + rows.1
        let links = unique(allRows.compactMap(TitleExternalLink.init))
        return links.sorted { $0.priority < $1.priority }
    }

    private func loadLinkRows(_ path: String, key: String) async -> [Fields] {
        guard let response = try? await store.api.catalog(path) else { return [] }
        let data: Fields? = response.read("data")
        return response.read("data") ?? data?.read(key) ?? []
    }

    private func loadEpisodes(_ path: String) async -> [Fields] {
        guard title.kind == .anime,
              let response = try? await store.api.catalog(path + "/episodes") else { return [] }
        let rows: [Fields] = response.read("data") ?? []
        return Array(rows.prefix(12))
    }

    private func loadThemes(_ path: String) async -> Fields? {
        guard title.kind == .anime else { return nil }
        for suffix in ["/themes", "/full"] {
            if let response = try? await store.api.catalog(path + suffix),
               let data: Fields = response.read("data") {
                if let themes: Fields = data.read("themeSongs", "theme") { return themes }
                if suffix == "/themes" { return data }
            }
        }
        return nil
    }

    private func loadFriendBatch() async {
        guard let user = store.account, !checkingFriends else { return }
        checkingFriends = true
        defer { if user == store.account { checkingFriends = false } }
        do {
            if store.friends.isEmpty { try await store.fetchFriends(user) }
            repeat {
                let batch = Array(store.friends.dropFirst(friendOffset).prefix(6))
                for friend in batch {
                    guard !Task.isCancelled, user == store.account else { return }
                    do {
                        if let row = try await store.friendEntry(friend, current), !Task.isCancelled, user == store.account {
                            friendRows = unique(friendRows + [row]).sorted { activityDate($0.date) > activityDate($1.date) }
                        }
                    } catch { if !Task.isCancelled { friendsUnavailable = true } }
                    guard !Task.isCancelled, user == store.account else { return }
                    friendOffset += 1
                }
            } while friendRows.isEmpty && friendOffset < store.friends.count
            completedFriendBatches += 1
        } catch { if !Task.isCancelled { friendsUnavailable = true } }
    }
}

private struct TitleExternalLink: Identifiable {
    enum Style {
        case standard, social, crunchyroll, netflix

        var fill: Color {
            switch self {
            case .standard: Palette.surface
            case .social: .clear
            case .crunchyroll: Color(red: 0.53, green: 0.27, blue: 0.07)
            case .netflix: Color(red: 0.55, green: 0.04, blue: 0.07)
            }
        }
    }

    let name: String
    let url: URL
    let style: Style
    var id: URL { url }

    var priority: Int {
        if name.localizedCaseInsensitiveContains("official") { return 0 }
        switch style {
        case .social: return 1
        case .crunchyroll, .netflix: return 2
        case .standard: return 3
        }
    }

    init?(_ fields: Fields) {
        guard let name = fields.string("name"), let url = publicURL(fields.string("url")),
              let host = url.host()?.lowercased() else { return nil }
        self.name = name
        self.url = url
        func isDomain(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if isDomain("x.com") || isDomain("twitter.com") { style = .social }
        else if isDomain("crunchyroll.com") { style = .crunchyroll }
        else if isDomain("netflix.com") { style = .netflix }
        else { style = .standard }
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
                else if mode == .full { fullEditor }
                else { quickEditor }
            }
            .navigationTitle(heading)
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
                TextField("Add notes for \(title.name)", text: $details.notes, axis: .vertical)
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
            if !Task.isCancelled { self.error = error.localizedDescription }
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
    }

    private func submit(_ value: ListChange?) {
        guard let accountID = store.account?.id else { return }
        guard value == nil || !saveDisabled else { return }
        let shouldUpdateMAL = value == nil || remoteChanged
        let shouldOrganize = value != nil && mode == .full && organizationChanged
        var update = value
        if mode == .full { update?.details = details.changes(from: original?.details ?? ListDetails()) }
        busy = true
        Task {
            defer { busy = false }
            do {
                if shouldUpdateMAL { try await store.change(title, update) }
                if shouldOrganize {
                    store.organize(title, lists: selectedLists, adding: newLists, hidden: hidden, accountID: accountID)
                }
                dismiss()
            } catch {
                if (error as? APIError)?.status == 401 { store.handle(error) }
                self.error = error.localizedDescription
            }
        }
    }
}
