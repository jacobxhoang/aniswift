import SwiftUI

struct CharacterReference: Hashable, Identifiable {
    let id: Int
    let name: String
    let image: URL?

    var malURL: URL { URL(string: "https://myanimelist.net/character/\(id)")! }

    init?(_ fields: Fields) {
        guard let id: Int = fields.read("mal_id", "malId", "id"), id > 0,
              let name = fields.string("name") else { return nil }
        self.id = id
        self.name = displayPersonName(name)
        image = fields.image
    }
}

struct CastMember: Identifiable {
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

    var body: some View {
        NavigationLink(value: member.character) {
            PortraitCard(image: member.character.image, name: member.character.name,
                         detail: [member.role, member.actor].compactMap { $0 }.joined(separator: " · "))
        }
        .buttonStyle(.plain)
    }
}

struct CharacterScreen: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let character: CharacterReference

    @State private var profile: Fields?
    @State private var failed = false
    @State private var managingFavorite = false

    private var name: String { profile.flatMap { $0.string("name") }.map(displayPersonName) ?? character.name }
    private var isFavorite: Bool { store.malCharacterFavorites.contains(character.id) }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    managingFavorite = true
                    openURL(character.malURL)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel("Manage favorite on MyAnimeList")
                .accessibilityValue(isFavorite ? "Favorited" : "")
            }
        }
        .task { await load() }
        .task(id: store.account?.id) { await store.loadFavorites() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, managingFavorite else { return }
            managingFavorite = false
            Task { await store.loadFavorites(refresh: true) }
        }
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
                RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12))
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
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: LedgerLayout.gap) {
                    ForEach(voices) { voice in
                        if let url = voice.url {
                            Link(destination: url) { voiceCard(voice) }.buttonStyle(.plain)
                        } else {
                            voiceCard(voice)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, LedgerLayout.inset, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private func voiceCard(_ voice: CharacterVoice) -> some View {
        PortraitCard(image: voice.image, name: voice.name, detail: voice.language)
            .frame(width: LedgerLayout.posterWidth)
    }

    @ViewBuilder
    private func appearanceShelf(_ kind: Kind) -> some View {
        let rows: [Fields] = profile?.read(kind.rawValue) ?? []
        let titles = unique(rows.compactMap { row -> Title? in
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
            let result = try await store.api.catalog("characters/\(character.id)/full", refresh: refresh)
            guard !Task.isCancelled else { return }
            if let updated: Fields = result.read("data") { profile = updated }
            else { failed = true }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

private struct CharacterVoice: Identifiable {
    let id: String
    let name: String
    let language: String
    let image: URL?
    let url: URL?

    init?(_ fields: Fields) {
        let person: Fields = fields.read("person") ?? fields
        guard let name = person.string("name") else { return nil }
        let malID: Int? = person.read("mal_id", "malId", "id")
        self.name = displayPersonName(name)
        language = fields.string("language") ?? ""
        id = (malID.map { String($0) } ?? name) + "|" + language
        image = person.image
        url = malID.flatMap { $0 > 0 ? publicURL("https://myanimelist.net/people/\($0)") : nil }
    }
}

private struct PortraitCard: View {
    let image: URL?
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Art(url: image, symbol: "person.fill")
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: LedgerLayout.posterRadius))
            Text(name).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
