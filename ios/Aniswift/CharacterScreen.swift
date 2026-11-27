import SwiftUI

struct CharacterReference: Hashable, Identifiable, Codable {
    let id: Int
    let name: String
    let image: URL?

    init?(_ fields: Fields) {
        guard let id: Int = fields.read("mal_id", "malId", "id"), id > 0,
            let name = fields.string("name")
        else { return nil }
        self.id = id
        self.name = displayPersonName(name)
        image = fields.image
    }
}

/// A voice actor, mangaka or staff member, addressable as its own page.
struct PersonReference: Hashable, Identifiable, Codable {
    let id: Int
    let name: String
    /// The name as the provider writes it (`Takanaga, Hinako`), for the title
    /// header that lists authors family name first the way MyAnimeList does.
    let rawName: String
    let image: URL?

    init?(_ fields: Fields) {
        guard let id: Int = fields.read("mal_id", "malId", "id"), id > 0,
            let name = fields.string("name")
        else { return nil }
        self.id = id
        self.name = displayPersonName(name)
        rawName = name
        image = fields.image
    }
}

struct CastMember: Identifiable, Hashable {
    let character: CharacterReference
    let role: String?
    let actor: String?
    var id: Int { character.id }

    init?(_ fields: Fields) {
        let info: Fields = fields.read("character") ?? fields
        guard let character = CharacterReference(info) else { return nil }
        let voices: [Fields] = fields.read("voice_actors", "voiceActors") ?? []
        let voice = voices.first { $0.string("language") == "Japanese" } ?? voices.first
        let person: Fields? = voice?.read("person")
        self.character = character
        role = fields.string("role")
        actor = (person?.string("name") ?? voice?.string("name")).map(displayPersonName)
    }
}

struct CastCard: View {
    let member: CastMember
    var inDirectory = false
    var showsRoleOnly = false

    var body: some View {
        NavigationLink(value: member.character) {
            let detail =
                inDirectory || showsRoleOnly
                ? (member.role ?? "") : [member.role, member.actor].compactMap { $0 }.joined(separator: " · ")
            PortraitCard(
                image: member.character.image, name: member.character.name,
                detail: detail, inDirectory: inDirectory, compactCaption: showsRoleOnly,
                posterWidth: showsRoleOnly ? LedgerLayout.detailPosterWidth : nil)
        }
        .buttonStyle(LedgerTileButtonStyle())
    }
}

struct CharactersScreen: View {
    let members: [CastMember]

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingList = false

    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: 150), spacing: 20, alignment: .top)]
        }
        if sizeClass == .compact {
            return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 22, alignment: .top), count: 3)
        }
        return [GridItem(.adaptive(minimum: 135), spacing: 22, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            if showingList {
                LazyVStack(spacing: 0) {
                    ForEach(members) { member in listRow(member) }
                }
                .padding(.horizontal, LedgerLayout.inset)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(members) { CastCard(member: $0, inDirectory: true) }
                }
                .padding(.horizontal, LedgerLayout.inset)
                .padding(.top, 16)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Characters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingList.toggle()
                } label: {
                    Label(
                        showingList ? "Show grid" : "Show list",
                        systemImage: showingList ? "square.grid.3x3" : "list.bullet")
                }
            }
        }
    }

    private func listRow(_ member: CastMember) -> some View {
        NavigationLink(value: member.character) {
            HStack(spacing: 12) {
                Art(url: member.character.image, symbol: "person.fill")
                    .frame(width: 48, height: 68)
                    .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.character.name).foregroundStyle(.primary)
                    if let role = member.role {
                        Text(role).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 60) }
    }
}

struct CharacterScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    let character: CharacterReference

    @State private var profile: Fields?
    @State private var failed = false

    private var name: String { profile.flatMap { $0.string("name") }.map(displayPersonName) ?? character.name }
    private var voices: [CharacterVoice] {
        let rows: [Fields] = profile?.read("voices", "voice_actors", "voiceActors") ?? []
        return unique(rows.compactMap(CharacterVoice.init))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                header.padding(.horizontal, LedgerLayout.inset)
                if let profile {
                    summary(profile)
                    if !voices.isEmpty { voiceShelf }
                    ForEach(Kind.allCases) { kind in
                        appearanceShelf(kind)
                    }
                } else if failed {
                    LedgerProblem(message: "Character details are unavailable.") { await load(refresh: true) }
                        .padding(.horizontal, LedgerLayout.inset)
                } else {
                    ProgressView("Loading character").padding(.horizontal, LedgerLayout.inset)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(refresh: true) }
    }

    private var header: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    portrait
                    identity
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    portrait
                    identity.frame(minHeight: 196)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var portrait: some View {
        Art(url: profile?.image ?? character.image, symbol: "person.fill")
            .frame(width: 134, height: 196)
            .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LedgerLayout.posterRadius).strokeBorder(Palette.hairline)
                    .allowsHitTesting(false)
            }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let native = profile?.string("name_kanji", "nameKanji") {
                Text(native).font(.headline).foregroundStyle(.secondary)
            }
            let aliases: [String] = profile?.read("nicknames") ?? []
            if !aliases.isEmpty {
                Text(aliases.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            if let count: Int = profile?.read("favorites") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Member favorites").font(.caption).foregroundStyle(.secondary)
                    Text(count.formatted()).font(.title3.weight(.semibold).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func summary(_ profile: Fields) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle("Summary")
            if let about = profile.string("about", "biography") {
                BiographyText(text: about)
            } else {
                Text("No biography is available.").foregroundStyle(.secondary)
            }
            Divider().padding(.top, 6)
        }
        .padding(.horizontal, LedgerLayout.inset)
    }

    private var voiceShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle("Voice actors").padding(.horizontal, LedgerLayout.inset)
            LedgerShelf(inset: LedgerLayout.inset) {
                ForEach(voices) { voice in
                    if let person = voice.person {
                        NavigationLink(value: person) { voiceCard(voice) }
                            .buttonStyle(LedgerTileButtonStyle())
                    } else {
                        voiceCard(voice)
                    }
                }
            }
        }
    }

    private func voiceCard(_ voice: CharacterVoice) -> some View {
        // The language sits under the name rather than in a reserved slot, so a
        // name that wraps takes its language with it instead of leaving a gap.
        PortraitCard(
            image: voice.image, name: voice.name, detail: voice.language, compactCaption: true,
            posterWidth: LedgerLayout.posterWidth
        )
        .frame(width: LedgerLayout.posterWidth)
    }

    @ViewBuilder
    private func appearanceShelf(_ kind: Kind) -> some View {
        let rows: [Fields] = profile?.read(kind.rawValue) ?? []
        let titles = unique(
            rows.compactMap { row -> Title? in
                let entry: Fields = row.read(kind.rawValue) ?? row
                return Title(entry, kind: kind)
            })
        if !titles.isEmpty {
            PosterShelf(heading: "\(kind.label) appearances", titles: titles) { EmptyView() }
        }
    }

    private func load(refresh: Bool = false) async {
        failed = false
        do {
            let result = try await store.api.catalog("characters/\(character.id)/full", [], refresh: refresh)
            guard !Task.isCancelled else { return }
            if let updated: Fields = result.read("data") { profile = updated } else { failed = true }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// A voice actor, mangaka or staff member: their roles, their credits and what
/// MyAnimeList knows about them. Opened from a character's voice actors, and from
/// the authors a manga's header lists.
struct PersonScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let person: PersonReference

    @State private var profile: Fields?
    @State private var failed = false
    @State private var showingAllRoles = false
    @State private var expandedCredits: Set<Kind> = []
    /// English names for this person's credits and voiced roles, resolved in one
    /// batched request per kind instead of a detail request per row.
    @State private var creditNames: [String: String] = [:]
    /// Every row the batch asked about, so a row whose name did not come back
    /// shows its original title instead of asking again.
    @State private var askedCreditNames: Set<String> = []

    private var name: String {
        profile.flatMap { $0.string("name") }.map(displayPersonName) ?? person.name
    }

    private var roles: [PersonRole] {
        let rows: [Fields] = profile?.read("voices") ?? []
        let items = unique(rows.compactMap(PersonRole.init))
        return items.sorted { ($0.role == "Main" ? 0 : 1) < ($1.role == "Main" ? 0 : 1) }
    }

    private func credits(_ kind: Kind) -> [PersonCredit] {
        let rows: [Fields] = profile?.read(kind == .anime ? "anime" : "manga") ?? []
        return unique(rows.compactMap { PersonCredit($0, kind: kind) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                header.padding(.horizontal, LedgerLayout.inset)
                if let profile {
                    if let about = profile.string("about", "biography") { summary(about) }
                    if !roles.isEmpty { roleList }
                    ForEach(Kind.allCases) { kind in creditList(kind) }
                } else if failed {
                    LedgerProblem(message: "Person details are unavailable.") { await load(refresh: true) }
                        .padding(.horizontal, LedgerLayout.inset)
                } else {
                    ProgressView("Loading person").padding(.horizontal, LedgerLayout.inset)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(refresh: true) }
    }

    private var header: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    portrait
                    facts
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    portrait
                    facts.frame(minHeight: 196, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var portrait: some View {
        Art(url: profile?.image ?? person.image, symbol: "person.fill")
            .frame(width: 134, height: 196)
            .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LedgerLayout.posterRadius).strokeBorder(Palette.hairline)
                    .allowsHitTesting(false)
            }
    }

    /// The name already sits in the navigation bar, so this column carries the
    /// facts instead of repeating it.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            let aliases: [String] = profile?.read("alternate_names", "alternateNames") ?? []
            ForEach(aliases.prefix(3), id: \.self) { alias in
                Text(alias).font(.subheadline).foregroundStyle(.secondary)
            }
            if let birthday = profile?.string("birthday") {
                fact("Birthday", birthdayText(birthday))
            }
            if let favorites: Int = profile?.read("favorites") {
                fact("Member favorites", favorites.formatted())
            }
        }
    }

    /// Tenrai sends an ISO timestamp and Jikan Edge a display string, so both
    /// go through the shared date heuristic before they are shown.
    private func birthdayText(_ raw: String) -> String {
        let date = activityDate(raw)
        guard date != .distantPast else { return raw }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private func summary(_ about: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle("Summary")
            BiographyText(text: about)
            Divider().padding(.top, 6)
        }
        .padding(.horizontal, LedgerLayout.inset)
    }

    private var roleList: some View {
        let shown = showingAllRoles ? roles : Array(roles.prefix(12))
        return VStack(alignment: .leading, spacing: 10) {
            LedgerSectionTitle("Voiced roles").padding(.horizontal, LedgerLayout.inset)
            LazyVStack(spacing: 0) {
                ForEach(shown) { role in roleRow(role) }
            }
            .padding(.horizontal, LedgerLayout.inset)
            if roles.count > 12 {
                ShowAllButton(title: showingAllRoles ? "Show fewer" : "Show all \(roles.count) roles") {
                    showingAllRoles.toggle()
                }
                .padding(.horizontal, LedgerLayout.inset)
            }
        }
    }

    /// One row of the person page: a poster, two clamped lines of text and a
    /// chevron. Voiced roles and staff credits share it, so both lists line up
    /// as a single column.
    private func personRow(image: URL?, symbol: String, title: String, note: String, linked: Bool) -> some View {
        HStack(spacing: 12) {
            Art(url: image, symbol: symbol)
                .frame(width: 44, height: 62)
                .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if linked {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func roleRow(_ role: PersonRole) -> some View {
        let known = creditNames[nameKey(.anime, role.animeID)]
        let row = personRow(
            image: role.image, symbol: "person.fill",
            title: role.characterName ?? role.displayTitle(for: titleLanguage, known: known),
            note: role.subtitle(for: titleLanguage, known: known),
            linked: role.character != nil || role.anime != nil)
        return Group {
            if let character = role.character {
                NavigationLink(value: character) { row }
            } else if let anime = role.anime {
                NavigationLink(value: anime) { row }
            } else {
                row
            }
        }
        .buttonStyle(.plain)
        .personRowDivider()
    }

    private func creditList(_ kind: Kind) -> some View {
        let rows = credits(kind)
        let expanded = expandedCredits.contains(kind)
        let shown = expanded ? rows : Array(rows.prefix(8))
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LedgerSectionTitle(kind == .anime ? "Anime staff roles" : "Manga staff roles")
                        .padding(.horizontal, LedgerLayout.inset)
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { credit in
                            if let title = credit.title {
                                // The batch already asked about every credit, so
                                // a row shows the name it returned and never
                                // fires a detail request of its own.
                                PreferredTitle(
                                    title: title, knownName: creditNames[nameKey(title)],
                                    nameSettled: askedCreditNames.contains(nameKey(title))
                                ) { item, name in
                                    NavigationLink(value: item) {
                                        personRow(
                                            image: item.image, symbol: item.kind == .anime ? "film" : "book",
                                            title: name, note: credit.note, linked: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .personRowDivider()
                            } else {
                                plainCredit(credit)
                            }
                        }
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                    if rows.count > 8 {
                        ShowAllButton(title: expanded ? "Show fewer" : "Show all \(rows.count) credits") {
                            if expanded { expandedCredits.remove(kind) } else { expandedCredits.insert(kind) }
                        }
                        .padding(.horizontal, LedgerLayout.inset)
                    }
                }
            }
        }
    }

    private func nameKey(_ title: Title) -> String { "\(title.kind.rawValue)-\(title.malID)" }
    private func nameKey(_ kind: Kind, _ malID: Int) -> String { "\(kind.rawValue)-\(malID)" }

    /// Every anime and manga id this page names in a row that still needs its
    /// English title: a nested node that came back sparse, and every row the
    /// provider flattened into ids and a romaji name. One `ids` request per kind
    /// names them all, instead of a detail request per row.
    private func idsToResolve(in fields: Fields) -> [Kind: [Int]] {
        var wanted: [Kind: [Int]] = [:]
        for kind in Kind.allCases {
            let rows: [Fields] = fields.read(kind == .anime ? "anime" : "manga") ?? []
            for credit in rows.compactMap({ PersonCredit($0, kind: kind) }) {
                if credit.title?.needsTitleLookup ?? true {
                    wanted[kind, default: []].append(credit.malID)
                }
            }
        }
        // A voiced role names an anime too, so it is asked for in the same
        // batch: a role row used to read the payload's romaji title.
        let voices: [Fields] = fields.read("voices") ?? []
        for role in voices.compactMap(PersonRole.init) {
            wanted[.anime, default: []].append(role.animeID)
        }
        return wanted
    }

    private func resolveNames(_ wanted: [Kind: [Int]]) async -> [String: String] {
        var names: [String: String] = [:]
        for kind in Kind.allCases {
            let ids = wanted[kind] ?? []
            guard !ids.isEmpty else { continue }
            let resolved = await store.api.titleNames(ids, kind: kind)
            for (id, name) in resolved { names[nameKey(kind, id)] = name }
        }
        return names
    }

    /// A credit the provider flattens into ids and names carries no poster, so
    /// it still takes the shared row with a kind glyph standing in for one.
    private func plainCredit(_ credit: PersonCredit) -> some View {
        personRow(
            image: nil, symbol: credit.kind == .anime ? "film" : "book",
            title: creditNames[nameKey(credit.kind, credit.malID)] ?? credit.name ?? "",
            note: credit.note, linked: false
        )
        .personRowDivider()
    }

    private func load(refresh: Bool = false) async {
        failed = false
        do {
            let result = try await store.api.catalog("people/\(person.id)/full", [], refresh: refresh)
            guard !Task.isCancelled else { return }
            guard let updated: Fields = result.read("data") else {
                failed = true
                return
            }
            // Mark every row as asked before it is drawn, so a row shows its
            // original title for a moment instead of each firing a detail request
            // that renames it one at a time.
            let wanted = idsToResolve(in: updated)
            askedCreditNames = Set(wanted.flatMap { kind, ids in ids.map { nameKey(kind, $0) } })
            profile = updated
            let names = await resolveNames(wanted)
            guard !Task.isCancelled else { return }
            creditNames = names
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// One voiced role. Tenrai nests the anime and character nodes; Jikan Edge
/// flattens the same role into one row, so both are optional here.
private struct PersonRole: Identifiable {
    let id: String
    let characterName: String?
    let animeName: String
    /// The anime's MyAnimeList id, kept even when the provider flattened the
    /// row, so the page can ask for its English name in one batch.
    let animeID: Int
    let role: String?
    let image: URL?
    let character: CharacterReference?
    let anime: Title?

    init?(_ fields: Fields) {
        if let animeFields: Fields = fields.read("anime"),
            let anime = Title(animeFields, kind: .anime)
        {
            let characterFields: Fields? = fields.read("character")
            let character = characterFields.flatMap { CharacterReference($0) }
            let part = fields.string("role")
            self.character = character
            self.anime = anime
            characterName = character?.name
            animeName = ""
            animeID = anime.malID
            role = part
            image = character?.image ?? anime.image
            id = "\(anime.id)-\(character?.id ?? 0)-\(part ?? "")"
            return
        }
        guard let animeID: Int = fields.read("animeId"), animeID > 0,
            let animeName = fields.string("animeTitle")
        else { return nil }
        let characterID: Int? = fields.read("characterId")
        let part = fields.string("characterRole", "role")
        character = nil
        anime = nil
        characterName = fields.string("characterName").map(displayPersonName)
        self.animeName = animeName
        self.animeID = animeID
        role = part
        image =
            publicURL(fields.string("characterImageUrl"))
            ?? publicURL(fields.string("animeImageUrl"))
        id = "\(animeID)-\(characterID ?? 0)-\(part ?? "")"
    }

    /// The anime's name in the reader's preferred language. `known` is the
    /// English name the page resolved in its batch: a sparse node, and every row
    /// the provider flattened, carries only the romaji title, which is what this
    /// row used to show.
    func displayTitle(for language: String, known: String? = nil) -> String {
        if language == TitleLanguage.japanese.rawValue {
            return anime?.japaneseName ?? animeName
        }
        if language == TitleLanguage.romaji.rawValue { return anime?.original ?? animeName }
        return known ?? anime?.displayName(for: language) ?? animeName
    }

    func subtitle(for language: String, known: String? = nil) -> String {
        var parts: [String] = []
        if let role, !role.isEmpty { parts.append(role) }
        let title = displayTitle(for: language, known: known)
        if !title.isEmpty { parts.append(title) }
        return parts.joined(separator: " · ")
    }
}

/// One production credit: the title and the job this person did on it. Tenrai
/// nests the title node; Jikan Edge flattens it into ids, names and positions.
private struct PersonCredit: Identifiable {
    let id: String
    let name: String?
    let note: String
    let title: Title?
    /// The title's MyAnimeList id and kind, kept even when the provider
    /// flattened the row, so the page can name it in English from its batch.
    let malID: Int
    let kind: Kind

    init?(_ fields: Fields, kind: Kind) {
        if let node: Fields = fields.read(kind.rawValue),
            let title = Title(node, kind: kind)
        {
            let position = fields.string("position") ?? kind.label
            self.title = title
            name = nil
            note = position
            malID = title.malID
            self.kind = kind
            id = "\(title.id)-\(position)"
            return
        }
        guard let malID: Int = fields.read(kind == .anime ? "animeId" : "mangaId"), malID > 0,
            let name = fields.string(kind == .anime ? "animeTitle" : "mangaTitle")
        else { return nil }
        let positions: [String] = fields.read("positions") ?? []
        let position = positions.isEmpty ? (fields.string("position") ?? kind.label) : positions.joined(separator: ", ")
        title = nil
        self.name = name
        note = position
        self.malID = malID
        self.kind = kind
        id = "\(kind.rawValue)-\(malID)-\(position)"
    }
}

private struct CharacterVoice: Identifiable {
    let id: String
    let name: String
    let language: String
    let image: URL?
    let person: PersonReference?

    init?(_ fields: Fields) {
        let personFields: Fields = fields.read("person") ?? fields
        guard let name = personFields.string("name") else { return nil }
        let malID: Int? = personFields.read("mal_id", "malId", "id")
        self.name = displayPersonName(name)
        language = fields.string("language") ?? ""
        id = (malID.map { String($0) } ?? name) + "|" + language
        image = personFields.image
        person = PersonReference(personFields)
    }
}

/// The shared “show all / fewer” control for a capped section.
struct ShowAllButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
    }
}

private struct PortraitCard: View {
    let image: URL?
    let name: String
    let detail: String
    var inDirectory = false
    var compactCaption = false
    var posterWidth: CGFloat?

    private var reservesCaptionSpace: Bool { !inDirectory && !compactCaption }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterArt(url: image, symbol: "person.fill", width: posterWidth)
                .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
            Text(name)
                .font(inDirectory ? .body : .subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: reservesCaptionSpace)
            if reservesCaptionSpace || !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: reservesCaptionSpace)
                    .accessibilityHidden(detail.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A biography as MyAnimeList writes it: prose, and any part the provider marked
/// as a spoiler waiting behind a tap. The markers — `[Spoiler] … [/Spoiler]`,
/// sometimes with the closing bracket on a line of its own — are never drawn.
private struct BiographyText: View {
    let text: String
    @State private var revealed: Set<Int> = []
    private let parts: [CharacterBiography.Part]

    init(text: String) {
        self.text = text
        parts = CharacterBiography.parts(of: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parts) { part in
                if part.isSpoiler, !revealed.contains(part.id) {
                    // The button is the whole of the hidden state: a line above
                    // it said the same thing twice for every spoiler in a bio.
                    Button("Show spoiler") { revealed.insert(part.id) }
                        .ledgerGlassButton()
                        .accessibilityHint("Shows the hidden part of the biography")
                } else {
                    Text(BiographyLinks.attributed(part.text))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                    if part.isSpoiler {
                        Button("Hide spoiler") { revealed.remove(part.id) }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                            .accessibilityHint("Hides the part of the biography again")
                    }
                }
            }
        }
        // A biography read again marks its parts afresh, so a revealed spoiler
        // from the previous copy is not left open in the new one.
        .onChange(of: text) { _, _ in revealed = [] }
    }
}

/// The split itself: one part per run of prose or of spoiler text, numbered in
/// the order the biography reads, so a part keeps its identity across passes.
private enum CharacterBiography {
    struct Part: Identifiable {
        let id: Int
        let text: String
        let isSpoiler: Bool
    }

    static func parts(of text: String) -> [Part] {
        var parts: [Part] = []
        var remainder = Substring(text)
        while let open = remainder.range(of: "[spoiler]", options: .caseInsensitive) {
            append(&parts, remainder[..<open.lowerBound], spoiler: false)
            let rest = remainder[open.upperBound...]
            guard let close = rest.range(of: "[/spoiler]", options: .caseInsensitive) else {
                // An unclosed marker hides the rest instead of showing it.
                append(&parts, rest, spoiler: true)
                remainder = Substring("")
                break
            }
            append(&parts, rest[..<close.lowerBound], spoiler: true)
            remainder = rest[close.upperBound...]
        }
        append(&parts, remainder, spoiler: false)
        return parts
    }

    private static func append(_ parts: inout [Part], _ raw: Substring, spoiler: Bool) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Two spoiler markers in a row are one hidden region, so they take one
        // button instead of two facing each other.
        if spoiler, let last = parts.last, last.isSpoiler {
            parts[parts.count - 1] = Part(
                id: last.id, text: last.text + "\n\n" + text, isSpoiler: true)
            return
        }
        parts.append(Part(id: parts.count, text: text, isSpoiler: spoiler))
    }
}

/// A biography's prose with the links MyAnimeList writes as plain text turned
/// into tappable ones: any URL, and a handle on a line that names Twitter or X.
/// A handle anywhere else stays part of the sentence.
private enum BiographyLinks {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for (range, url) in found(in: text).sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) {
            guard range.lowerBound >= cursor else { continue }
            if cursor < range.lowerBound { result += AttributedString(text[cursor..<range.lowerBound]) }
            var piece = AttributedString(text[range])
            piece.link = url
            result += piece
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result += AttributedString(text[cursor...]) }
        return result
    }

    private static func found(in text: String) -> [(Range<String.Index>, URL)] {
        var links: [(Range<String.Index>, URL)] = []
        for match in text.matches(of: /https?:\/\/[^\s<>()]+/) {
            let raw = String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
            guard !raw.isEmpty, let url = URL(string: raw) else { continue }
            let start = match.output.startIndex
            links.append((start..<text.index(start, offsetBy: raw.count), url))
        }
        // "Twitter: @name", "X: @name", "Instagram: @name" and "Facebook:
        // name" are how a biography names an account: the label before a token is
        // what makes it a handle, and only the handle itself is linked.
        for match in text.matches(of: /(?i)(?:twitter|x|instagram|facebook)[^@\n]{0,12}@[A-Za-z0-9_.]{1,30}/) {
            appendHandle(&links, in: text, matched: match.output)
        }
        // Instagram's handle is often written without its @, so the label alone
        // makes the word after it the handle.
        for match in text.matches(of: /(?i)instagram\s*:?\s*[a-z0-9_][a-z0-9_.]{1,29}/) {
            appendHandle(&links, in: text, matched: match.output)
        }
        return links
    }

    /// The service a matched line names, and the host its profile link goes to.
    private static func service(in matched: String) -> (name: String, host: String)? {
        let value = matched.lowercased()
        if value.hasPrefix("twitter") || value.hasPrefix("x") { return ("twitter", "x.com") }
        if value.hasPrefix("instagram") { return ("instagram", "instagram.com") }
        if value.hasPrefix("facebook") { return ("facebook", "facebook.com") }
        return nil
    }

    private static func appendHandle(
        _ links: inout [(Range<String.Index>, URL)], in text: String, matched: Substring
    ) {
        let value = String(matched)
        guard let service = service(in: value), let start = handleStart(in: value, service: service.name),
            let url = URL(string: "https://\(service.host)/\(value[start...])")
        else { return }
        let index = text.index(matched.startIndex, offsetBy: value.distance(from: value.startIndex, to: start))
        links.append((index..<matched.endIndex, url))
    }

    /// Where the handle begins: the service's name, then the punctuation between
    /// it and the handle, which is never part of the link.
    private static func handleStart(in value: String, service: String) -> String.Index? {
        var index = value.index(value.startIndex, offsetBy: service.count)
        while index < value.endIndex {
            let character = value[index]
            if character == ":" || character == " " || character == "@" {
                index = value.index(after: index)
                continue
            }
            guard character.isLetter || character.isNumber || character == "_" else { return nil }
            return index
        }
        return nil
    }
}

private func displayPersonName(_ raw: String) -> String {
    let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return raw }
    return "\(parts[1]) \(parts[0])"
}

extension View {
    /// Roles and credits rule the same line: one divider inset for the page.
    fileprivate func personRowDivider() -> some View {
        overlay(alignment: .bottom) { Divider().padding(.leading, 44 + 12) }
    }
}
