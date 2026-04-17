import SwiftUI

let appLang: String = Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en"
func tr(_ en: String, _ de: String, _ lang: String = appLang) -> String { lang == "de" ? de : en }

extension Notification.Name {
    static let addSongsToPlaylist = Notification.Name("shelv.addSongsToPlaylist")
    static let showToast = Notification.Name("shelv.showToast")
}

@main
struct Shelv_DesktopApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var lyricsStore = LyricsStore()
    @AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
    @AppStorage("themeColor") private var themeColorName: String = "violet"
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(lyricsStore)
                .frame(minWidth: 900, minHeight: 600)
                .task { await lyricsStore.setup() }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 760)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button(tr("About Shelv", "Über Shelv")) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandMenu(tr("Profile", "Profil")) {
                if appState.isLoggedIn, let active = appState.serverStore.activeServer {
                    Text(active.displayName)
                    Text(appState.username)
                        .foregroundStyle(.secondary)
                } else {
                    Text(tr("Not logged in", "Nicht angemeldet"))
                        .foregroundStyle(.secondary)
                }
                Divider()
                ServerManagementMenuItem()
                Divider()
                Button(tr("Log Out", "Abmelden")) {
                    appState.logout()
                }
                .disabled(!appState.isLoggedIn)
            }

            CommandGroup(replacing: .help) {
                Link(tr("Shelv on GitHub", "Shelv auf GitHub"), destination: URL(string: "https://github.com/gatzenga/Shelv-Desktop")!)
                Link(tr("Navidrome Documentation", "Navidrome Dokumentation"), destination: URL(string: "https://www.navidrome.org/docs/")!)
                Divider()
                Link(tr("Privacy Policy", "Datenschutz"), destination: URL(string: "https://gatzenga.github.io/Shelv-Desktop/privacy.html")!)
                Link(tr("Contact", "Kontakt"), destination: URL(string: "mailto:kontakt@vkugler.ch")!)
            }

            CommandMenu(tr("Playback", "Wiedergabe")) {
                Button(tr("Play / Pause", "Abspielen / Pause")) {
                    AppState.shared.player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button(tr("Next Track", "Nächster Titel")) {
                    AppState.shared.player.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(tr("Previous Track", "Vorheriger Titel")) {
                    AppState.shared.player.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                CrossfadeMenuItem()
                LyricsSettingsMenuItem()
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Toggle(isOn: Binding(get: { enableFavorites }, set: { enableFavorites = $0 })) {
                    Text(tr("Show Favorites", "Favoriten anzeigen"))
                }
                Toggle(isOn: Binding(get: { enablePlaylists }, set: { enablePlaylists = $0 })) {
                    Text(tr("Show Playlists", "Wiedergabelisten anzeigen"))
                }
            }
        }

        Window(tr("Lyrics", "Lyrics"), id: "lyrics-settings") {
            LyricsSettingsPanel()
                .environmentObject(appState)
                .environmentObject(lyricsStore)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
        .windowResizability(.contentSize)

        Window(tr("Crossfade", "Crossfade"), id: "crossfade") {
            CrossfadePanel()
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
        .windowResizability(.contentSize)

        Window(tr("Insights", "Insights"), id: "insights") {
            InsightsView()
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
        .windowResizability(.contentSize)

        Window(tr("Manage Servers", "Server verwalten"), id: "server-management") {
            ServerManagementView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 660, height: 420)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
    }
}

struct LyricsSettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Lyrics…", "Lyrics…")) {
            openWindow(id: "lyrics-settings")
        }
    }
}

struct CrossfadeMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Crossfade…", "Crossfade…")) {
            openWindow(id: "crossfade")
        }
    }
}

struct ServerManagementMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Manage Servers…", "Server verwalten…")) {
            openWindow(id: "server-management")
        }
    }
}

struct InsightsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Insights…", "Insights…")) {
            openWindow(id: "insights")
        }
    }
}
