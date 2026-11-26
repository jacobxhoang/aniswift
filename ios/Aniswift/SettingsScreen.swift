import Kingfisher
import SafariServices
import SwiftUI
import UIKit

/// The accent applied to controls, links and highlights. Stored by raw value in
/// `SettingKey.accent` and read by the app root for `.tint`.
enum AccentChoice: String, CaseIterable, Identifiable {
    case white = "White"
    case blue = "Blue"
    case red = "Red"
    case green = "Green"
    case brown = "Brown"
    case cyan = "Cyan"
    case gray = "Gray"
    case purple = "Purple"
    case mint = "Mint"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white: .white
        case .blue: Color(red: 0.42, green: 0.70, blue: 0.98)
        case .red: Color(red: 0.94, green: 0.32, blue: 0.32)
        case .green: Color(red: 0.24, green: 0.78, blue: 0.42)
        case .brown: Color(red: 0.74, green: 0.56, blue: 0.38)
        case .cyan: Color(red: 0.32, green: 0.80, blue: 0.94)
        case .gray: Color(white: 0.62)
        case .purple: Color(red: 0.48, green: 0.44, blue: 0.98)
        case .mint: Color(red: 0.36, green: 0.86, blue: 0.72)
        }
    }

    /// A checkmark that stays legible on the swatch.
    var checkColor: Color {
        switch self {
        case .white, .cyan, .mint, .brown: .black
        default: .white
        }
    }
}

/// UserDefaults keys for every preference the settings screens write.
enum SettingKey {
    static let accent = "aniswift.settings.accent"
    static let titleLanguage = "aniswift.settings.titleLanguage"
    static let openLinksInApp = "aniswift.settings.openLinksInApp"
    static let askForScore = "aniswift.settings.askForScore"
    static let preferredLaunch = "aniswift.settings.preferredLaunch"
    static let launchTab = "aniswift.settings.launchTab"
    static let lastTab = "aniswift.settings.lastTab"
    static let tabBarBehavior = "aniswift.settings.tabBarBehavior"

    static func detail(_ kind: Kind, _ section: String) -> String {
        "aniswift.settings.details.\(kind.rawValue).\(section)"
    }

    static func profile(_ section: String) -> String {
        "aniswift.settings.profile.\(section)"
    }
}

/// Section names used inside `SettingKey.detail`.
enum DetailSection {
    static let sections = "sections"
    static let characters = "characters"
    static let trailer = "trailer"
    static let related = "related"
    static let source = "source"
    static let openings = "openings"
    static let endings = "endings"
    static let recommendations = "recommendations"
    static let headerPoster = "header.poster"
    static let headerScore = "header.score"
    static let headerRank = "header.rank"
    static let headerPopularity = "header.popularity"
    static let headerCreators = "header.creators"
    /// The next airing of an anime that is still on the air.
    static let headerAiringSchedule = "header.airing"
    static let infoSeries = "info.series"
    static let infoAlternatives = "info.alternatives"
    static let infoGenres = "info.genres"
    static let infoThemes = "info.themes"
    static let infoCreators = "info.creators"
}

extension DetailSection {
    /// Every section key, so a page reads them once instead of through
    /// thirty-four separate property wrappers.
    static let all = [
        sections, characters, trailer, related, source, openings, endings, recommendations,
        headerPoster, headerScore, headerRank, headerPopularity, headerCreators, headerAiringSchedule,
        infoSeries, infoAlternatives, infoGenres, infoThemes, infoCreators,
    ]
}

/// Every Details Page toggle for one kind, read once: an `@AppStorage` wrapper
/// reads `UserDefaults` on each access, and a title page asked for all
/// thirty-four of them on every body pass. Defaults are on, as before.
struct DetailPreferences: Equatable {
    private var values: [String: Bool] = [:]

    init(_ kind: Kind) {
        var values: [String: Bool] = [:]
        for section in DetailSection.all {
            values[section] = UserDefaults.standard.object(forKey: SettingKey.detail(kind, section)) as? Bool ?? true
        }
        self.values = values
    }

    func shows(_ section: String) -> Bool { values[section] ?? true }
}

/// Section names used inside `SettingKey.profile`, for the Profile page.
enum ProfileSection {
    static let friends = "friends"
    static let days = "days"
    static let animeStatistics = "anime.statistics"
    static let mangaStatistics = "manga.statistics"
    static let favoriteAnime = "favorite.anime"
    static let favoriteManga = "favorite.manga"
    static let favoriteCharacters = "favorite.characters"
    static let favoritePeople = "favorite.people"

    static let all = [
        friends, days, animeStatistics, mangaStatistics,
        favoriteAnime, favoriteManga, favoriteCharacters, favoritePeople,
    ]
}

/// Every Profile page toggle, read once: the page reads the eight values from
/// here on each body pass instead of through eight `@AppStorage` wrappers.
/// Defaults are on.
struct ProfilePreferences: Equatable {
    private var values: [String: Bool] = [:]

    init() {
        var values: [String: Bool] = [:]
        for section in ProfileSection.all {
            values[section] = UserDefaults.standard.object(forKey: SettingKey.profile(section)) as? Bool ?? true
        }
        self.values = values
    }

    func shows(_ section: String) -> Bool { values[section] ?? true }
}

struct SettingsScreen: View {
    @AppStorage(SettingKey.accent) private var accent = AccentChoice.white.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var confirmSignOut = false
    /// The AniList section keeps one client: it holds the session and the
    /// entries the read-only lists screen draws, and the store sends it the
    /// changes made on MyAnimeList.
    @StateObject private var aniList = AniListClient.shared

    var body: some View {
        List {
            Section("Accent Color") {
                accentRow
            }
            Section {
                NavigationLink {
                    BehaviorSettingsScreen()
                } label: {
                    SettingsRow(icon: "slider.horizontal.3", title: "Behavior")
                }
                .settingsRow()
            }
            Section {
                NavigationLink {
                    DetailsSettingsScreen()
                } label: {
                    SettingsRow(icon: "list.bullet.rectangle", title: "Details Page")
                }
                .settingsRow()
                NavigationLink {
                    ProfileSettingsScreen()
                } label: {
                    SettingsRow(icon: "person.crop.circle", title: "Profile")
                }
                .settingsRow()
            }
            Section {
                if aniList.isSignedIn, let session = aniList.session {
                    NavigationLink {
                        AniListListsScreen(client: aniList)
                    } label: {
                        SettingsRow(
                            icon: "list.bullet.rectangle",
                            title: session.name.isEmpty ? "AniList Lists" : session.name)
                    }
                    .settingsRow()
                    Button {
                        aniList.signOut()
                    } label: {
                        SettingsRow(
                            icon: "rectangle.portrait.and.arrow.right", title: "Sign Out of AniList")
                    }
                    .settingsRow()
                } else {
                    Button {
                        Task { await aniList.signIn() }
                    } label: {
                        // A settings action reads as a settings row, like every
                        // other action here, and names its busy state in the
                        // title rather than in a line under it.
                        SettingsRow(
                            icon: "person.crop.circle.badge.plus",
                            title: aniList.connecting ? "Connecting to AniList…" : "Connect AniList")
                    }
                    .settingsRow()
                    .disabled(aniList.connecting)
                    if let message = aniList.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                            .settingsRow()
                    }
                }
            } header: {
                Text("AniList")
            }
            // About sits under AniList: it explains the app rather than what the
            // app is connected to, so the version and the services come after.
            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    SettingsRow(icon: "info.circle", title: "About Aniswift")
                }
                .settingsRow()
            }
            if store.account != nil {
                Section {
                    Button {
                        confirmSignOut = true
                    } label: {
                        SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out")
                    }
                    .settingsRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of MyAnimeList?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) {
                store.disconnect()
                if store.account == nil { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var accentRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(AccentChoice.allCases) { choice in
                    let selected = accent == choice.rawValue
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                            accent = choice.rawValue
                        }
                    } label: {
                        ZStack {
                            Circle().fill(choice.color).frame(width: 38, height: 38)
                            if selected {
                                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                    .frame(width: 48, height: 48)
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(choice.checkColor)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
                    .accessibilityHint("Sets the accent color")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: accent)
        .listRowBackground(Palette.surface)
    }
}

struct BehaviorSettingsScreen: View {
    @AppStorage(SettingKey.titleLanguage) private var language = TitleLanguage.english.rawValue
    @AppStorage(SettingKey.openLinksInApp) private var openLinksInApp = true
    @AppStorage(SettingKey.askForScore) private var asksForScore = true
    @AppStorage(SettingKey.preferredLaunch) private var usesPreferredLaunch = false
    @AppStorage(SettingKey.launchTab) private var launchTab = "anime"
    @AppStorage(SettingKey.tabBarBehavior) private var tabBarBehavior = "never"

    private let launchTabs = [
        (id: "anime", label: "Anime"),
        (id: "manga", label: "Manga"),
        (id: "discover", label: "Discover"),
        (id: "feed", label: "Feed"),
        (id: "profile", label: "Profile"),
    ]

    var body: some View {
        List {
            Section {
                Picker("Preferred Title Language", selection: $language) {
                    ForEach(TitleLanguage.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                .sensoryFeedback(.selection, trigger: language)
                .settingsRow()
                Toggle("Open Links In-App", isOn: $openLinksInApp)
                    .sensoryFeedback(.selection, trigger: openLinksInApp)
                    .settingsRow()
            }
            Section {
                Toggle("Ask for Score After Watching an Anime", isOn: $asksForScore)
                    .sensoryFeedback(.selection, trigger: asksForScore)
                    .settingsRow()
            }
            Section {
                Toggle("Enable Preferred Launch Screen", isOn: $usesPreferredLaunch)
                    .sensoryFeedback(.selection, trigger: usesPreferredLaunch)
                    .settingsRow()
                if usesPreferredLaunch {
                    Picker("Preferred Screen", selection: $launchTab) {
                        ForEach(launchTabs, id: \.id) { tab in
                            Text(tab.label).tag(tab.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .sensoryFeedback(.selection, trigger: launchTab)
                    .settingsRow()
                }
            }
            if #available(iOS 26.0, *) {
                Section {
                    Picker("Tab Bar Behavior", selection: $tabBarBehavior) {
                        Text("Always Visible").tag("never")
                        Text("Hide on Scroll").tag("onScrollDown")
                    }
                    .pickerStyle(.menu)
                    .sensoryFeedback(.selection, trigger: tabBarBehavior)
                    .settingsRow()
                }
            }
            Section {
                CacheRow()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Behavior")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailsSettingsScreen: View {
    var body: some View {
        List {
            Section {
                PreferenceToggle(
                    "Show Sections Below Summary", key: SettingKey.detail(.anime, DetailSection.sections))
                NavigationLink {
                    HeaderSettingsScreen(kind: .anime)
                } label: {
                    SettingsRow(icon: "photo.on.rectangle", title: "Header")
                }
                .settingsRow()
                PreferenceToggle("Show Character List", key: SettingKey.detail(.anime, DetailSection.characters))
                PreferenceToggle("Show Trailer", key: SettingKey.detail(.anime, DetailSection.trailer))
                PreferenceToggle("Show Related Anime", key: SettingKey.detail(.anime, DetailSection.related))
                PreferenceToggle("Show Source", key: SettingKey.detail(.anime, DetailSection.source))
                PreferenceToggle("Show Openings", key: SettingKey.detail(.anime, DetailSection.openings))
                PreferenceToggle("Show Endings", key: SettingKey.detail(.anime, DetailSection.endings))
                PreferenceToggle(
                    "Show Recommendations", key: SettingKey.detail(.anime, DetailSection.recommendations))
                NavigationLink {
                    InfoSettingsScreen(kind: .anime)
                } label: {
                    SettingsRow(icon: "list.bullet", title: "Information")
                }
                .settingsRow()
            } header: {
                Text("Anime")
            }
            Section {
                PreferenceToggle(
                    "Show Sections Below Summary", key: SettingKey.detail(.manga, DetailSection.sections))
                NavigationLink {
                    HeaderSettingsScreen(kind: .manga)
                } label: {
                    SettingsRow(icon: "photo.on.rectangle", title: "Header")
                }
                .settingsRow()
                PreferenceToggle("Show Character List", key: SettingKey.detail(.manga, DetailSection.characters))
                PreferenceToggle("Show Related Manga", key: SettingKey.detail(.manga, DetailSection.related))
                PreferenceToggle("Show Source", key: SettingKey.detail(.manga, DetailSection.source))
                PreferenceToggle(
                    "Show Recommendations", key: SettingKey.detail(.manga, DetailSection.recommendations))
                NavigationLink {
                    InfoSettingsScreen(kind: .manga)
                } label: {
                    SettingsRow(icon: "list.bullet", title: "Information")
                }
                .settingsRow()
            } header: {
                Text("Manga")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Details Page")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileSettingsScreen: View {
    var body: some View {
        List {
            Section {
                PreferenceToggle("Friends", key: SettingKey.profile(ProfileSection.friends))
                PreferenceToggle("Days Watching", key: SettingKey.profile(ProfileSection.days))
                PreferenceToggle("Anime Statistics", key: SettingKey.profile(ProfileSection.animeStatistics))
                PreferenceToggle("Manga Statistics", key: SettingKey.profile(ProfileSection.mangaStatistics))
                PreferenceToggle("Favorite Anime", key: SettingKey.profile(ProfileSection.favoriteAnime))
                PreferenceToggle("Favorite Manga", key: SettingKey.profile(ProfileSection.favoriteManga))
                PreferenceToggle(
                    "Favorite Characters", key: SettingKey.profile(ProfileSection.favoriteCharacters))
                PreferenceToggle("Favorite People", key: SettingKey.profile(ProfileSection.favoritePeople))
            } header: {
                Text("Appearance")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HeaderSettingsScreen: View {
    let kind: Kind

    var body: some View {
        List {
            Section {
                PreferenceToggle("Show Poster", key: SettingKey.detail(kind, DetailSection.headerPoster))
                PreferenceToggle("Show Average Score", key: SettingKey.detail(kind, DetailSection.headerScore))
                PreferenceToggle("Show MAL Rank", key: SettingKey.detail(kind, DetailSection.headerRank))
                PreferenceToggle("Show Popularity", key: SettingKey.detail(kind, DetailSection.headerPopularity))
                PreferenceToggle(
                    kind == .anime ? "Show Studios" : "Show Authors",
                    key: SettingKey.detail(kind, DetailSection.headerCreators))
                // A manga never airs, so the countdown has nothing to say on
                // its page and the toggle is left out of its header settings.
                if kind == .anime {
                    PreferenceToggle(
                        "Show Airing Schedule",
                        key: SettingKey.detail(kind, DetailSection.headerAiringSchedule))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Header")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InfoSettingsScreen: View {
    let kind: Kind

    var body: some View {
        List {
            Section {
                PreferenceToggle("Series Information", key: SettingKey.detail(kind, DetailSection.infoSeries))
                PreferenceToggle("Alternative Titles", key: SettingKey.detail(kind, DetailSection.infoAlternatives))
                PreferenceToggle("Genres", key: SettingKey.detail(kind, DetailSection.infoGenres))
                PreferenceToggle("Themes", key: SettingKey.detail(kind, DetailSection.infoThemes))
                PreferenceToggle(
                    kind == .anime ? "Studios and Producers" : "Serialization",
                    key: SettingKey.detail(kind, DetailSection.infoCreators))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Information")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A switch bound to a boolean preference stored under an arbitrary key, so one
/// row type can serve both anime and manga settings.
private struct PreferenceToggle: View {
    let title: String
    @AppStorage private var isOn: Bool

    init(_ title: String, key: String) {
        self.title = title
        _isOn = AppStorage(wrappedValue: true, key)
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .sensoryFeedback(.selection, trigger: isOn)
            .settingsRow()
    }
}

private struct CacheRow: View {
    @EnvironmentObject private var store: Store
    @State private var bytes: UInt = 0
    @State private var confirming = false
    @State private var clearing = false

    private var sizeLabel: String {
        if bytes == 0 {
            return store.api.hasCachedCatalog ? "Catalog responses cached" : "Nothing cached"
        }
        let megabytes = Double(bytes) / 1_048_576
        return "Cache size: \(megabytes.formatted(.number.precision(.fractionLength(2)))) MB"
    }

    var body: some View {
        Button(role: .destructive) {
            confirming = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clear Cache").foregroundStyle(.red)
                    Text(clearing ? "Clearing…" : sizeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if clearing { ProgressView() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(clearing)
        .settingsRow()
        .confirmationDialog("Clear cached posters and catalog data?", isPresented: $confirming) {
            Button("Clear Cache", role: .destructive) { clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign-in, your lists and settings are kept.")
        }
        .task { refreshSize() }
    }

    private func refreshSize() {
        ImageCache.default.calculateDiskStorageSize { result in
            let images = (try? result.get()) ?? 0
            let responses = URLCache.shared.currentDiskUsage
            Task { @MainActor in
                bytes = images + UInt(max(responses, 0))
            }
        }
    }

    private func clear() {
        clearing = true
        ImageCache.default.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()
        store.api.clearCatalogCache()
        ImageCache.default.clearDiskCache {
            Task { @MainActor in
                refreshSize()
                clearing = false
                Haptics.success()
            }
        }
    }
}

/// A settings row: its badge and its title. A row names what it opens or sets
/// and nothing more, so the list scans as a set of titles instead of a wall of
/// lines that repeat the title under it.
private struct SettingsRow: View {
    var icon: String? = nil
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            if let icon { SettingsIcon(symbol: icon) }
            Text(title)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small rounded badge so the settings groups scan like the rest of the app.
private struct SettingsIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: 28, height: 28)
            .background(Palette.fill, in: .rect(cornerRadius: LedgerLayout.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LedgerLayout.rowRadius, style: .continuous)
                    .strokeBorder(Palette.hairline)
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }
}

private extension View {
    func settingsRow() -> some View {
        listRowBackground(Palette.surface)
    }
}

/// Opens external links in a Safari sheet instead of leaving the app. Chosen
/// from Behavior → Open Links In-App.
@MainActor
enum InAppBrowser {
    /// Returns false when there is no foreground scene to present from, so the
    /// caller can fall back to opening the link outside the app.
    @discardableResult
    static func present(_ url: URL) -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController
        else { return false }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        let browser = SFSafariViewController(url: url)
        browser.dismissButtonStyle = .close
        let accent = AccentChoice(rawValue: UserDefaults.standard.string(forKey: SettingKey.accent) ?? "")
            ?? .white
        browser.preferredControlTintColor = UIColor(accent.color)
        browser.preferredBarTintColor = UIColor(Palette.sheet)
        top.present(browser, animated: true)
        return true
    }
}


/// A signed-in account's AniList lists, read-only: the entries grouped by kind
/// and status the way AniList holds them, with a Sync to bring them over again.
struct AniListListsScreen: View {
    @ObservedObject var client: AniListClient
    @AppStorage(SettingKey.titleLanguage) private var titleLanguage = TitleLanguage.english.rawValue
    /// A row's thumbnail follows Dynamic Type with its labels.
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LedgerLayout.sectionGap) {
                if client.loading, client.entries.isEmpty {
                    ProgressView("Loading AniList lists").padding(.horizontal, LedgerLayout.inset)
                } else if client.entries.isEmpty, let message = client.message {
                    LedgerProblem(message: message, retryLabel: "Try again") {
                        await client.sync(refresh: true)
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                } else if client.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No AniList entries yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("The entries on your AniList lists appear here.")
                    } actions: {
                        Button("Sync AniList") { Task { await client.sync(refresh: true) } }
                    }
                    .padding(.horizontal, LedgerLayout.inset)
                } else {
                    ForEach(Kind.allCases) { kind in
                        shelf(kind)
                    }
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("AniList")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await client.sync(refresh: true) }
        .task { await client.sync() }
    }

    @ViewBuilder
    private func shelf(_ kind: Kind) -> some View {
        let entries = client.entries.filter { $0.kind == kind }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                LedgerSectionTitle(kind.label)
                ForEach(Self.statuses(for: kind), id: \.self) { status in
                    let rows = entries.filter { $0.status == status }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            // A group heading reads like the app's other list
                            // groups instead of a bare caption.
                            ListStatusHeader(
                                title: status, count: rows.count, expanded: true, partial: false,
                                isInteractive: false) {}
                            ForEach(rows) { entry in
                                row(entry)
                                if entry.id != rows.last?.id {
                                    Divider().overlay(Palette.hairline)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LedgerLayout.inset)
        }
    }

    private func row(_ entry: AniListEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Art(url: entry.image, symbol: entry.kind == .anime ? "film" : "book")
                .frame(width: thumbnailWidth, height: thumbnailWidth * 1.4)
                .clipShape(.rect(cornerRadius: LedgerLayout.rowRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName(for: titleLanguage))
                    .font(.subheadline)
                    .lineLimit(2)
                let details = [entry.progressLabel, entry.scoreLabel].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    /// AniList's own order of priorities, so a group keeps its place.
    private static func statuses(for kind: Kind) -> [String] {
        kind == .anime
            ? ["Watching", "Rewatching", "Plan to watch", "Completed", "On hold", "Dropped"]
            : ["Reading", "Rereading", "Plan to read", "Completed", "On hold", "Dropped"]
    }
}
