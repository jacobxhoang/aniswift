import SwiftUI

struct TitleScreen: View {
    @EnvironmentObject private var store: Store
    let title: Title
    @State private var record: Fields?
    @State private var related: [Title] = []
    @State private var relationNames: [String: String] = [:]
    @State private var characters: [Fields] = []
    @State private var themes: Fields?
    @State private var reviews: [TitleReview] = []
    @State private var reviewFailed = false
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
            VStack(alignment: .leading, spacing: 22) {
                header
                actions
                if let failure {
                    Text(failure).foregroundStyle(.secondary)
                    Button("Reload details") { Task { await load() } }
                }
                if let description = record?.string("synopsis") { block("Synopsis") { Text(description) } }
                if let background = record?.string("background") { block("Background") { Text(background) } }
                if !related.isEmpty { relations }
                metadata
                if !characters.isEmpty { cast }
                if title.kind == .anime { themeRows }
                friends
                reviewRows
                if !external.isEmpty { externalLinks }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: store.account?.id) {
            friendRows = []
            friendOffset = 0
            friendsUnavailable = false
            checkingFriends = false
            await loadFriendBatch()
        }
        .sheet(isPresented: $editor) {
            ListEditor(title: current, original: saved)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Art(url: current.image ?? title.image).frame(width: 106, height: 150)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 8) {
                Text(current.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                if current.original != current.name { Text(current.original).font(.subheadline).foregroundStyle(.secondary) }
                if let format = current.format { Text(format.uppercased()).font(.caption.weight(.semibold)) }
                if let score = current.score, score > 0 {
                    Label(score.formatted(.number.precision(.fractionLength(2))), systemImage: "star.fill")
                        .foregroundStyle(Palette.accent).font(.headline)
                }
                HStack {
                    if let rank: Int = record?.read("rank"), rank > 0 { Text("Rank #\(rank)") }
                    if let members = current.members, members > 0 { Text("\(members.formatted()) members") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.checking { ProgressView("Checking session") }
            else if store.account != nil {
                Button { editor = true } label: {
                    Label(saved == nil ? "Add to My List" : "Edit My List Entry", systemImage: saved == nil ? "plus" : "pencil")
                }.buttonStyle(.borderedProminent)
                if let saved {
                    Text("\(statusLabel(saved.status)) · \(saved.progress) \(title.kind.unit.lowercased())")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else { SignInButton() }
            Link("View on MyAnimeList", destination: title.malURL).font(.subheadline)
        }
    }

    private var metadata: some View {
        let labels = title.kind == .anime
            ? [("Status", "status"), ("Season", "season"), ("Source", "source"), ("Duration", "duration"), ("Rating", "rating")]
            : [("Status", "status"), ("Published", "published"), ("Serialization", "serialization")]
        return VStack(alignment: .leading, spacing: 8) {
            if let record {
                block("Information") {
                    ForEach(labels, id: \.0) { label, key in
                        if let value = record.string(key) ?? (record.read(key) as Fields?)?.string("string") {
                            LabeledContent(label, value: value)
                        }
                    }
                    if let total = current.total, total > 0 { LabeledContent(title.kind.unit, value: String(total)) }
                    if let volumes: Int = record.read("volumes"), volumes > 0 { LabeledContent("Volumes", value: String(volumes)) }
                    let genres: [Fields]? = record.read("genres")
                    let names = genres?.compactMap { $0.string("name") } ?? (record.read("genres") as [String]?) ?? []
                    if !names.isEmpty { LabeledContent("Genres", value: names.joined(separator: ", ")) }
                    if let popularity: Int = record.read("popularity") { LabeledContent("Popularity", value: "#\(popularity)") }
                    if let favorites: Int = record.read("favorites") { LabeledContent("Favorites", value: favorites.formatted()) }
                }
                let aliases: [String] = record.read("title_synonyms", "titleSynonyms") ?? []
                if current.original != current.name || record.string("title_japanese", "titleJapanese") != nil || !aliases.isEmpty {
                    block("Alternative titles") {
                        if current.original != current.name { LabeledContent("Romaji", value: current.original) }
                        if let japanese = record.string("title_japanese", "titleJapanese") { LabeledContent("Japanese", value: japanese) }
                        if !aliases.isEmpty { LabeledContent("Synonyms", value: aliases.joined(separator: ", ")) }
                    }
                }
            }
        }
    }

    private var relations: some View {
        block("Related entries") {
            ForEach(related) { item in
                NavigationLink(value: item) {
                    TitleRow(title: item, note: [relationNames[item.id], item.format ?? item.kind.label].compactMap { $0 }.joined(separator: " · "))
                }.buttonStyle(.plain)
            }
        }
    }

    private var cast: some View {
        block(title.kind == .anime ? "Characters & voice actors" : "Characters") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading) {
                ForEach(Array(characters.enumerated()), id: \.offset) { _, item in
                    let character: Fields = item.read("character") ?? item
                    let voices: [Fields] = item.read("voice_actors", "voiceActors") ?? []
                    let voice = voices.first { $0.string("language") == "Japanese" } ?? voices.first
                    let actor: Fields? = voice?.read("person")
                    HStack(spacing: 8) {
                        Art(url: character.image, symbol: "person.fill").frame(width: 34, height: 44).clipShape(.rect(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(character.string("name") ?? "Character").font(.caption.weight(.semibold))
                            if let name = actor?.string("name") ?? voice?.string("name") {
                                Text(name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
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
            ForEach(reviews) { review in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Art(url: review.avatar, symbol: "person.fill").frame(width: 32, height: 32).clipShape(.circle)
                        Text(review.author).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(displayDate(review.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        if let tag = review.tag { Text(tag) }
                        if let rating = review.rating, (1...10).contains(rating) { Text("Reviewer rating: \(rating)/10") }
                    }.font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    if review.spoiler || review.text.count > 420 {
                        if !review.spoiler { Text(String(review.text.prefix(420)) + "…").font(.subheadline) }
                        DisclosureGroup(review.spoiler ? "Show review with spoilers" : "Read full review") {
                            Text(review.text).font(.subheadline).textSelection(.enabled)
                        }
                    } else { Text(review.text).font(.subheadline) }
                }
                .padding(.vertical, 6)
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
            Text(name).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 12))
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
                if let error { Text(error).foregroundStyle(.red) }
                if original != nil { Button("Remove from My List", role: .destructive) { confirmRemoval = true } }
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
                Button("Remove", role: .destructive) { submit(nil) }
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
