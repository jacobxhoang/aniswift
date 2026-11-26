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
        .buttonStyle(.plain)
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
    @EnvironmentObject private var store: Store
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Character details are unavailable.").foregroundStyle(.secondary)
                        Button("Retry") { Task { await load(refresh: true) } }.ledgerGlassButton()
                    }
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
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.hairline)
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
                Text(about).lineSpacing(3).textSelection(.enabled)
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
                        NavigationLink(value: person) { voiceCard(voice) }.buttonStyle(.plain)
                    } else {
                        voiceCard(voice)
                    }
                }
            }
        }
    }

    private func voiceCard(_ voice: CharacterVoice) -> some View {
        PortraitCard(
            image: voice.image, name: voice.name, detail: voice.language, posterWidth: LedgerLayout.posterWidth
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
    @EnvironmentObject private var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    let person: PersonReference

    @State private var profile: Fields?
    @State private var failed = false
    @State private var showingAllRoles = false
    @State private var expandedCredits: Set<Kind> = []
    /// English names for this person's credits, resolved in one batched request
    /// per kind instead of a detail request per row.
    @State private var creditNames: [String: String] = [:]
    /// Every credit the batch asked about, so a row whose name did not come back
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Person details are unavailable.").foregroundStyle(.secondary)
                        Button("Retry") { Task { await load(refresh: true) } }.ledgerGlassButton()
                    }
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
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.hairline)
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
            Text(about).lineSpacing(3).textSelection(.enabled)
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
        let row = personRow(
            image: role.image, symbol: "person.fill",
            title: role.characterName ?? role.displayTitle(for: titleLanguage),
            note: role.subtitle(for: titleLanguage),
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
                                plainCredit(credit, kind: kind)
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

    /// Every credit is a sparse title of its own, so the page names them all in
    /// one `ids` request per kind instead of a detail request per row.
    private func creditTitles(in fields: Fields) -> [Title] {
        var titles: [Title] = []
        for kind in Kind.allCases {
            let rows: [Fields] = fields.read(kind == .anime ? "anime" : "manga") ?? []
            let credits = rows.compactMap { PersonCredit($0, kind: kind) }
            titles += credits.compactMap(\.title)
        }
        return unique(titles).filter(\.needsTitleLookup)
    }

    private func resolveCreditNames(_ titles: [Title]) async -> [String: String] {
        var names: [String: String] = [:]
        for kind in Kind.allCases {
            let ids = titles.filter { $0.kind == kind }.map(\.malID)
            guard !ids.isEmpty else { continue }
            let resolved = await store.api.titleNames(ids, kind: kind)
            for (id, name) in resolved { names["\(kind.rawValue)-\(id)"] = name }
        }
        return names
    }

    /// A credit the provider flattens into ids and names carries no poster, so
    /// it still takes the shared row with a kind glyph standing in for one.
    private func plainCredit(_ credit: PersonCredit, kind: Kind) -> some View {
        personRow(
            image: nil, symbol: kind == .anime ? "film" : "book",
            title: credit.name ?? "", note: credit.note, linked: false
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
            // Mark every credit as asked before the rows are drawn, so they show
            // their original title for a moment instead of each firing a detail
            // request that renames it one at a time.
            let pending = creditTitles(in: updated)
            askedCreditNames = Set(pending.map(nameKey))
            profile = updated
            let names = await resolveCreditNames(pending)
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
        self.anime = nil
        characterName = fields.string("characterName").map(displayPersonName)
        self.animeName = animeName
        role = part
        image =
            publicURL(fields.string("characterImageUrl"))
            ?? publicURL(fields.string("animeImageUrl"))
        id = "\(animeID)-\(characterID ?? 0)-\(part ?? "")"
    }

    func displayTitle(for language: String) -> String {
        anime?.displayName(for: language) ?? animeName
    }

    func subtitle(for language: String) -> String {
        var parts: [String] = []
        if let role, !role.isEmpty { parts.append(role) }
        let title = displayTitle(for: language)
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

    init?(_ fields: Fields, kind: Kind) {
        if let node: Fields = fields.read(kind.rawValue),
            let title = Title(node, kind: kind)
        {
            let position = fields.string("position") ?? kind.label
            self.title = title
            name = nil
            note = position
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
