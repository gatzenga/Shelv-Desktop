import SwiftUI

@main
struct Shelv_DesktopApp: App {
    @StateObject private var appState = AppState.shared
    @AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
    @AppStorage("themeColor") private var themeColorName: String = "violet"

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
                Text(appState.username.isEmpty ? "Nicht angemeldet" : appState.username)
                    .foregroundStyle(.secondary)
                Divider()
                ServerManagementMenuItem()
                Divider()
                Button("Abmelden") {
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
