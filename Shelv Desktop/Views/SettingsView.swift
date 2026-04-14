import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appColorScheme") private var colorScheme: AppColorScheme = .system

    var body: some View {
        TabView {
            ServerTab()
                .tabItem { Label("Server", systemImage: "server.rack") }
            AppearanceTab(colorScheme: $colorScheme)
                .tabItem { Label("Darstellung", systemImage: "paintpalette") }
            AboutTab()
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
        .environmentObject(appState)
    }
}

// MARK: - Server Tab

struct ServerTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        Form {
            Section("Verbundener Server") {
                LabeledContent("URL") {
                    Text(appState.serverDisplayName)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Benutzer") {
                    Text(appState.username)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .confirmationDialog("Wirklich abmelden?", isPresented: $showLogoutConfirm) {
                    Button("Abmelden", role: .destructive) { appState.logout() }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text("Die Server-Verbindung wird getrennt und alle gespeicherten Zugangsdaten werden gelöscht.")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Tab

enum AppColorScheme: String, CaseIterable {
    case system = "System"
    case light = "Hell"
    case dark = "Dunkel"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceTab: View {
    @Binding var colorScheme: AppColorScheme

    var body: some View {
        Form {
            Section("Erscheinungsbild") {
                Picker("Modus", selection: $colorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 48))
                .foregroundStyle(themeColor)
            Text("Shelv Desktop")
                .font(.title2.bold())
            Text("Version 1.0")
                .foregroundStyle(.secondary)
            Text("Navidrome / Subsonic Client für macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Link("Navidrome Dokumentation", destination: URL(string: "https://www.navidrome.org/docs/developers/subsonic-api/")!)
                .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
