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
}

/// Section names used inside `SettingKey.detail`.
enum DetailSection {
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
    static let infoSeries = "info.series"
    static let infoAlternatives = "info.alternatives"
    static let infoGenres = "info.genres"
    static let infoThemes = "info.themes"
    static let infoCreators = "info.creators"
}

extension DetailSection {
    /// Every section key, so a page reads them once instead of through
    /// thirty-one separate property wrappers.
    static let all = [
        characters, trailer, related, source, openings, endings, recommendations,
        headerPoster, headerScore, headerRank, headerPopularity, headerCreators,
        infoSeries, infoAlternatives, infoGenres, infoThemes, infoCreators,
    ]
}

/// Every Details Page toggle for one kind, read once: an `@AppStorage` wrapper
/// reads `UserDefaults` on each access, and a title page asked for all thirty-one
/// of them on every body pass. Defaults are on, as before.
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

struct SettingsScreen: View {
    @AppStorage(SettingKey.accent) private var accent = AccentChoice.white.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                accentRow
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Used for controls, links and highlights across Aniswift.")
            }
            Section {
                NavigationLink {
                    BehaviorSettingsScreen()
                } label: {
                    SettingsRow(
                        icon: "slider.horizontal.3", title: "Behavior",
                        detail: "Title language, links, launch screen and cache")
                }
                .settingsRow()
            }
            Section {
                NavigationLink {
                    DetailsSettingsScreen()
                } label: {
                    SettingsRow(
                        icon: "list.bullet.rectangle", title: "Details Page",
                        detail: "Choose what appears on anime and manga pages")
                }
                .settingsRow()
            }
            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    SettingsRow(
                        icon: "info.circle", title: "About Aniswift",
                        detail: "Version, services and open-source libraries")
                }
                .settingsRow()
            }
            if store.account != nil {
                Section {
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        SettingsRow(
                            icon: "rectangle.portrait.and.arrow.right", title: "Sign Out",
                            detail: "End this device's MyAnimeList session")
                    }
                    .settingsRow()
                } footer: {
                    Text("Your lists stay on MyAnimeList.")
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
    @EnvironmentObject private var store: Store
    @AppStorage(SettingKey.titleLanguage) private var language = TitleLanguage.english.rawValue
    @AppStorage(SettingKey.openLinksInApp) private var openLinksInApp = true
    @AppStorage(SettingKey.askForScore) private var asksForScore = true
    @AppStorage(SettingKey.preferredLaunch) private var usesPreferredLaunch = false
    @AppStorage(SettingKey.launchTab) private var launchTab = "anime"
    @AppStorage(SettingKey.tabBarBehavior) private var tabBarBehavior = "never"
    @State private var editingClientID = false
    @State private var clientIDDraft = ""

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
            } footer: {
                Text(
                    "Titles are shown in Romaji or in English when a translation exists. "
                        + "Links open in a browser sheet inside Aniswift; turn this off to use your default browser."
                )
            }
            Section {
                Toggle("Ask for Score After Watching an Anime", isOn: $asksForScore)
                    .sensoryFeedback(.selection, trigger: asksForScore)
                    .settingsRow()
            } footer: {
                Text("When an anime is marked completed without a score, Aniswift asks for one.")
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
            } footer: {
                Text(
                    "When on, Aniswift always opens your preferred screen. "
                        + "When off, it opens the last tab you used."
                )
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
                } footer: {
                    Text("Choose whether the tab bar stays visible or minimizes as you scroll down.")
                }
            }
            Section {
                Button {
                    clientIDDraft = store.api.configuredClientID ?? ""
                    editingClientID = true
                } label: {
                    SettingsRow(
                        icon: "key", title: "MyAnimeList Client ID",
                        detail: store.api.configuredClientID.map { "Ending in \($0.suffix(4))" } ?? "Not set")
                }
                .settingsRow()
            } footer: {
                Text("The iOS app ID from myanimelist.net/apiconfig, registered with \(API.redirectURI).")
            }
            Section {
                CacheRow()
            } footer: {
                Text("Removes downloaded posters and catalog responses. Sign-in, your lists and settings are kept.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Behavior")
        .navigationBarTitleDisplayMode(.inline)
        .alert("MyAnimeList Client ID", isPresented: $editingClientID) {
            TextField("Client ID", text: $clientIDDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { store.api.configuredClientID = clientIDDraft }
                .disabled(!clientIDDraft.isEmpty && !Self.isClientID(clientIDDraft))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Register an iOS app at myanimelist.net/apiconfig with redirect URL \(API.redirectURI).")
        }
    }

    /// MyAnimeList iOS client IDs are 32 letters and digits. An empty field
    /// clears the saved ID, so the app falls back to the one its build ships with.
    private static func isClientID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

struct DetailsSettingsScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    HeaderSettingsScreen(kind: .anime)
                } label: {
                    SettingsRow(icon: "photo.on.rectangle", title: "Header", detail: "Poster, score, rank and studios")
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
                    SettingsRow(icon: "list.bullet", title: "Information", detail: "Genres, themes and studios")
                }
                .settingsRow()
            } header: {
                Text("Anime")
            }
            Section {
                NavigationLink {
                    HeaderSettingsScreen(kind: .manga)
                } label: {
                    SettingsRow(icon: "photo.on.rectangle", title: "Header", detail: "Poster, score, rank and authors")
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
                    SettingsRow(icon: "list.bullet", title: "Information", detail: "Genres, themes and serialization")
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
            } footer: {
                Text("Choose which parts of the \(kind.rawValue) header stay visible.")
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
            } footer: {
                Text("Choose which information groups appear under the title.")
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

private struct SettingsRow: View {
    var icon: String? = nil
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            if let icon { SettingsIcon(symbol: icon) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
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
            .background(Color.white.opacity(0.10), in: .rect(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
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
