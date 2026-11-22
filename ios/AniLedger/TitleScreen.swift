import SwiftUI

struct TitleScreen: View {
    @EnvironmentObject private var store: Store
    let title: Title
    @State private var record: Fields?
    @State private var related: [Title] = []
    @State private var suggested: [Title] = []
    @State private var episodes: [Fields] = []
    @State private var relationNames: [String: String] = [:]
    @State private var characters: [Fields] = []
    @State private var themes: Fields?
    @State private var reviews: [TitleReview] = []
    @State private var reviewFailed = false
    @State private var openReview: TitleReview?
    @State private var external: [Fields] = []
    @State private var failure: String?
    @State private var editor = false
    @State private var friendRows: [FriendUpdate] = []
    @State private var friendOffset = 0
    @State private var checkingFriends = false
    @State private var friendsUnavailable = false

    private var current: Title { record.flatMap { Title($0, kind: title.kind) } ?? title }
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
                friends
                reviewRows
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
            ToolbarItem(placement: .topBarTrailing) {
                if store.account != nil {
                    Button { editor = true } label: {
                        Label(saved == nil ? "Add to My List" : "Edit list entry",
                              systemImage: saved == nil ? "plus" : "pencil")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: API.backend.appending(path: "\(title.kind.rawValue)/\(title.malID)"))
                    Link(destination: title.malURL) { Label("View on MyAnimeList", systemImage: "arrow.up.right") }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .task { await load() }
        .task(id: store.account?.id) {
            friendRows = []
            friendOffset = 0
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
        .sheet(isPresented: $editor) {
            ListEditor(title: current, original: saved)
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
            let credit = fieldNames(title.kind == .anime ? "studios" : "authors").joined(separator: " · ")
            if !credit.isEmpty {
                Text(credit.uppercased()).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        editControl("Status", item.map { statusLabel($0.status) } ?? "Add to list")
        editControl("Progress", "\(item.map { String($0.progress) } ?? "—") / \(total) \(unit)")
        let rating = item?.rating ?? 0
        editControl("My score", rating > 0 ? "\(rating) / 10" : "Unscored")
    }

    private func editControl(_ label: String, _ value: String) -> some View {
        Button { editor = true } label: {
            VStack(spacing: 3) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .ledgerGlassButton()
        .accessibilityHint("Opens your list entry")
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
                    if current.original != current.name { infoCell("English", current.name) }
                    infoCell("Romaji", current.original)
                    if let japanese = record.string("title_japanese", "titleJapanese") { infoCell("Japanese", japanese) }
                    let aliases: [String] = record.read("title_synonyms", "titleSynonyms") ?? []
                    if !aliases.isEmpty { infoCell("Also known as", aliases.joined(separator: "\n")) }
                }
                chips("Themes", fieldNames("themes"))
                chips("Genres", fieldNames("genres"))
                chips(title.kind == .anime ? "Producers" : "Serialization", fieldNames(title.kind == .anime ? "producers" : "serializations"))
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

    @ViewBuilder
    private func chips(_ label: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            block(label) {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(Array(Set(values)).sorted(), id: \.self) { value in
                            Text(value).font(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Palette.surface, in: .capsule)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var relations: some View { mediaRail("Related entries", titles: related, notes: relationNames) }

    private func mediaRail(_ label: String, titles: [Title], notes: [String: String] = [:]) -> some View {
        block(label) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(unique(titles)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            CoverTile(title: item, showsScore: false)
                            if let note = notes[item.id] {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: LedgerLayout.posterWidth)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private var cast: some View {
        block(title.kind == .anime ? "Characters & voice actors" : "Characters") {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { _, item in
                        let character: Fields = item.read("character") ?? item
                        let voices: [Fields] = item.read("voice_actors", "voiceActors") ?? []
                        let voice = voices.first { $0.string("language") == "Japanese" } ?? voices.first
                        let actor: Fields? = voice?.read("person")
                        VStack(alignment: .leading, spacing: 4) {
                            Art(url: character.image, symbol: "person.fill").frame(width: 104, height: 145)
                                .clipShape(.rect(cornerRadius: 8))
                            Text(character.string("name") ?? "Character").font(.subheadline.weight(.medium)).lineLimit(2)
                            if let role = item.string("role") { Text(role).font(.caption).foregroundStyle(.secondary) }
                            if let name = actor?.string("name") ?? voice?.string("name") {
                                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.frame(width: 104, alignment: .leading)
                    }
                }
            }.scrollIndicators(.hidden)
        }
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
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(episodes.enumerated()), id: \.offset) { index, item in
                        let number: Int = item.read("mal_id", "malId", "episode", "number") ?? index + 1
                        let name = item.string("title", "name") ?? "Episode \(number)"
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
            }.scrollIndicators(.hidden)
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
            if store.checking { ProgressView() }
            else if store.account == nil { Text("Sign in to see friends’ list activity.").foregroundStyle(.secondary) }
            else {
                ForEach(friendRows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        FriendCaption(item: row)
                        Text([row.status.map(statusLabel),
                              row.progress.map { "\($0)/\(row.total.map { String($0) } ?? "?")" },
                              row.score.flatMap { $0 > 0 ? "\($0)/10" : nil }].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if checkingFriends { ProgressView("Checking friends") }
                else {
                    if friendRows.isEmpty { Text("No matching public entries loaded.").foregroundStyle(.secondary) }
                    if friendsUnavailable { Text("Some friends’ activity is unavailable.").foregroundStyle(.secondary) }
                    if friendOffset < store.friends.count {
                        Button("Check more friends") { Task { await loadFriendBatch() } }
                    } else if friendsUnavailable && friendOffset == 0 {
                        Button("Retry") { Task { await loadFriendBatch() } }
                    }
                }
            }
        }
    }

    private var reviewRows: some View {
        block("Reviews") {
            Link("All reviews on MyAnimeList", destination: title.malURL.appending(path: "_/reviews"))
                .font(.subheadline)
            if reviews.isEmpty { Text(reviewFailed ? "Reviews are unavailable." : "No reviews loaded.").foregroundStyle(.secondary) }
            if !reviews.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
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
                }.scrollIndicators(.hidden)
            }
        }
    }

    private var externalLinks: some View {
        block("External links") {
            ForEach(Array(external.enumerated()), id: \.offset) { _, item in
                if let name = item.string("name"), let url = publicURL(item.string("url")) {
                    Link(name, destination: url)
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
        async let links = store.api.catalog(path + "/external")
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
            related = Array(unique(items).prefix(16))
        }
        if let result = try? await castData {
            let items: [Fields] = result.read("data") ?? []
            characters = Array(items.prefix(12))
        }
        if let result = try? await reviewData {
            let items: [Fields] = result.read("data") ?? []
            reviews = Array(items.compactMap(TitleReview.init).prefix(3))
            reviewFailed = false
        } else { reviewFailed = true }
        if let result = try? await links {
            let data: Fields? = result.read("data")
            external = result.read("data") ?? data?.read("externalLinks") ?? []
        }
        if let result = try? await recs {
            suggested = Array(unique(recommendations(result, kind: title.kind)).filter { $0.id != title.id }.prefix(12))
        }
        episodes = await episodeData
        themes = await songs
        await enrichRelated()
    }

    private func enrichRelated() async {
        for item in related where item.image == nil {
            if Task.isCancelled { return }
            let path = "\(item.kind.rawValue)/\(item.malID)"
            guard let response = try? await store.api.catalog(path),
                  let fields: Fields = response.read("data"),
                  let full = Title(fields, kind: item.kind),
                  let index = related.firstIndex(where: { $0.id == item.id }) else { continue }
            related[index] = full
        }
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
            let batch = Array(store.friends.dropFirst(friendOffset).prefix(6))
            for friend in batch {
                guard !Task.isCancelled, user == store.account else { return }
                do {
                    if let row = try await store.friendEntry(friend, current), user == store.account {
                        friendRows = unique(friendRows + [row]).sorted { activityDate($0.date) > activityDate($1.date) }
                    }
                } catch { if !Task.isCancelled { friendsUnavailable = true } }
                if user == store.account { friendOffset += 1 }
            }
        } catch { if !Task.isCancelled { friendsUnavailable = true } }
    }
}

struct ListEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let title: Title
    let original: ListEntry?
    @State private var change: ListChange
    @State private var busy = false
    @State private var confirmRemoval = false
    @State private var error: String?

    init(title: Title, original: ListEntry?) {
        self.title = title
        self.original = original
        _change = State(initialValue: ListChange(
            status: original?.status ?? title.kind.statuses.last!,
            progress: original?.progress ?? 0,
            rating: original?.rating ?? 0
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(title.name) {
                    Picker("Status", selection: $change.status) {
                        ForEach(title.kind.statuses, id: \.self) { Text(statusLabel($0)).tag($0) }
                    }
                    LabeledContent(title.kind.unit) {
                        TextField("Progress", value: $change.progress, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Rating", selection: $change.rating) {
                        Text("Unscored").tag(0)
                        ForEach(1...10, id: \.self) { Text("\($0)/10").tag($0) }
                    }
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.primary) }
                if original != nil { Button("Remove from My List") { confirmRemoval = true } }
            }
            .navigationTitle("List entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit(change) }.disabled(busy || change.progress < 0 || change.progress > max(title.total ?? 100_000, original?.progress ?? 0))
                }
            }
            .confirmationDialog("Remove this title from your MyAnimeList list?", isPresented: $confirmRemoval) {
                Button("Remove") { submit(nil) }
                Button("Cancel", role: .cancel) {}
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private func submit(_ value: ListChange?) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.change(title, value)
                dismiss()
            } catch {
                if (error as? APIError)?.status == 401 { store.handle(error) }
                self.error = error.localizedDescription
            }
        }
    }
}
