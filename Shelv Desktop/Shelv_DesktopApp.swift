import SwiftUI

// MARK: - Localization helper (identical to iOS)
let appLang: String = Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en"
func tr(_ en: String, _ de: String, _ lang: String = appLang) -> String { lang == "de" ? de : en }

// MARK: - Notification Names

extension Notification.Name {
    static let addSongsToPlaylist = Notification.Name("shelv.addSongsToPlaylist")
    static let showToast = Notification.Name("shelv.showToast")
}

@main
struct Shelv_DesktopApp: App {
    @StateObject private var appState = AppState.shared
    @AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
    @AppStorage("themeColor") private var themeColorName: String = "violet"
    @AppStorage("enableFavorites") private var enableFavorites = false
    @AppStorage("enablePlaylists") private var enablePlaylists = false

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 760)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button("Über Shelv") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandMenu("Profil") {
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
                Link("Shelv auf GitHub", destination: URL(string: "https://github.com/gatzenga/Shelv-Desktop")!)
                Link("Navidrome Dokumentation", destination: URL(string: "https://www.navidrome.org/docs/")!)
                Divider()
                Link("Privacy Policy", destination: URL(string: "https://gatzenga.github.io/Shelv-Desktop/privacy.html")!)
                Link("Kontakt", destination: URL(string: "mailto:kontakt@vkugler.ch")!)
            }

            CommandMenu("Wiedergabe") {
                Button("Abspielen / Pause") {
                    AppState.shared.player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button("Nächster Titel") {
                    AppState.shared.player.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Vorheriger Titel") {
                    AppState.shared.player.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Toggle(isOn: Binding(get: { enableFavorites }, set: { enableFavorites = $0 })) {
                    Text("Favoriten anzeigen")
                }
                Toggle(isOn: Binding(get: { enablePlaylists }, set: { enablePlaylists = $0 })) {
                    Text("Wiedergabelisten anzeigen")
                }
            }
        }

        // Server management window (via Profil menu)
        Window("Server verwalten", id: "server-management") {
            ServerManagementView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 660, height: 420)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environmentObject(appState)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
    }
}

// MARK: - Menu item helper (needs @Environment for openWindow)

struct ServerManagementMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Server verwalten…") {
            openWindow(id: "server-management")
        }
    }
}
