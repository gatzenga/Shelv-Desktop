import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appColorScheme") private var colorScheme: AppColorScheme = .system

    var body: some View {
        TabView {
            ServerTab()
                .tabItem { Label(tr("Server", "Server"), systemImage: "server.rack") }
            AppearanceTab(colorScheme: $colorScheme)
                .tabItem { Label(tr("Appearance", "Darstellung"), systemImage: "paintpalette") }
            CacheTab()
                .tabItem { Label(tr("Cache", "Cache"), systemImage: "internaldrive") }
            AboutTab()
                .tabItem { Label(tr("Info", "Info"), systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
        .environmentObject(appState)
    }
}

// MARK: - Server Tab

struct ServerTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddServer = false
    @State private var serverToEdit: SubsonicServer?
    @State private var serverToDelete: SubsonicServer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(appState.serverStore.servers) { server in
                    ServerRow(
                        server: server,
                        isActive: appState.serverStore.activeServerID == server.id,
                        onActivate: { appState.switchServer(server) },
                        onEdit: { serverToEdit = server },
                        onDelete: { serverToDelete = server }
                    )
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 140)

            Divider()

            HStack {
                Button {
                    showAddServer = true
                } label: {
                    Label(tr("Add Server…", "Server hinzufügen…"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Spacer()
            }
        }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet()
                .environmentObject(appState)
        }
        .sheet(item: $serverToEdit) { server in
            EditServerSheet(server: server)
                .environmentObject(appState)
        }
        .confirmationDialog(
            tr("Remove Server?", "Server entfernen?"),
            isPresented: Binding(get: { serverToDelete != nil }, set: { if !$0 { serverToDelete = nil } }),
            presenting: serverToDelete
        ) { server in
            Button(tr("Remove", "Entfernen"), role: .destructive) {
                appState.deleteServer(server)
                serverToDelete = nil
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) { serverToDelete = nil }
        } message: { server in
            Text(tr("\"\(server.displayName)\" will be removed and its credentials deleted.",
                    "\"\(server.displayName)\" wird entfernt und die Zugangsdaten gelöscht."))
        }
    }
}

struct ServerRow: View {
    let server: SubsonicServer
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? AnyShapeStyle(themeColor) : AnyShapeStyle(.tertiary))
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.body)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(server.username + " · " + server.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !isActive {
                Button(tr("Connect", "Verbinden")) { onActivate() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Button { onEdit() } label: {
                Image(systemName: "pencil").font(.caption)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Server Sheet

struct AddServerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColor) private var themeColor

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(tr("Add Server", "Server hinzufügen"))
                .font(.title2.bold())

            serverForm

            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button(tr("Cancel", "Abbrechen")) { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button {
                    Task { await connect() }
                } label: {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Text(tr("Connect", "Verbinden")) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || url.isEmpty || username.isEmpty || password.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private var serverForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            formFieldLabel(tr("Server Name", "Servername"))
            TextField(tr("My Navidrome", "Mein Navidrome"), text: $name)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            formFieldLabel("URL")
            TextField("https://music.example.com", text: $url)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            formFieldLabel(tr("Username", "Benutzername"))
            TextField(tr("Username", "Benutzername"), text: $username)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            formFieldLabel(tr("Password", "Passwort"))
            SecureField(tr("Password", "Passwort"), text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func connect() async {
        isLoading = true
        errorMessage = nil
        let success = await appState.addServer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username,
            password: password
        )
        if success { dismiss() }
        else { errorMessage = appState.errorMessage ?? tr("Connection failed.", "Verbindung fehlgeschlagen.") }
        isLoading = false
    }
}

// MARK: - Edit Server Sheet

struct EditServerSheet: View {
    let server: SubsonicServer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String = ""

    init(server: SubsonicServer) {
        self.server = server
        _name = State(initialValue: server.name)
        _url = State(initialValue: server.baseURL)
        _username = State(initialValue: server.username)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(tr("Edit Server", "Server bearbeiten"))
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                editFieldLabel(tr("Server Name", "Servername"))
                TextField(tr("My Navidrome", "Mein Navidrome"), text: $name)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()

                editFieldLabel("URL")
                TextField("https://music.example.com", text: $url)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()

                editFieldLabel(tr("Username", "Benutzername"))
                TextField(tr("Username", "Benutzername"), text: $username)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()

                editFieldLabel(tr("Password", "Passwort"))
                SecureField(tr("Leave blank to keep current", "Leer lassen zum Beibehalten"), text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(tr("Cancel", "Abbrechen")) { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(tr("Save", "Speichern")) {
                    var updated = server
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.serverStore.update(
                        server: updated,
                        password: password.isEmpty ? nil : password
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty || username.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func editFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Appearance Tab

enum AppColorScheme: String, CaseIterable {
    case system = "System"
    case light = "Hell"
    case dark = "Dunkel"

    var displayName: String {
        switch self {
        case .system: return tr("System", "System")
        case .light:  return tr("Light", "Hell")
        case .dark:   return tr("Dark", "Dunkel")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

struct AppearanceTab: View {
    @Binding var colorScheme: AppColorScheme

    var body: some View {
        Form {
            Section(tr("Appearance", "Erscheinungsbild")) {
                Picker(tr("Mode", "Modus"), selection: $colorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Cache Tab

struct CacheTab: View {
    @State private var cacheSize = "–"
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section(tr("Cover Images", "Cover-Bilder")) {
                LabeledContent(tr("Size", "Grösse")) {
                    Text(cacheSize).foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(tr("Clear Cache", "Cache leeren"), systemImage: "trash")
                }
                .confirmationDialog(tr("Clear Cache?", "Cache leeren?"), isPresented: $showClearConfirm) {
                    Button(tr("Clear", "Leeren"), role: .destructive) {
                        Task {
                            await ImageCacheService.shared.clearAll()
                            await recalculateCacheSize()
                        }
                    }
                    Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
                } message: {
                    Text(tr(
                        "All cached cover images will be deleted and reloaded next time they are displayed.",
                        "Alle zwischengespeicherten Cover-Bilder werden gelöscht und beim nächsten Anzeigen neu geladen."
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await recalculateCacheSize() }
    }

    private func recalculateCacheSize() async {
        let bytes = await ImageCacheService.shared.diskUsageBytes()
        cacheSize = bytes > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            : "0 KB"
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @Environment(\.themeColor) private var themeColor

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 48))
                .foregroundStyle(themeColor)
            Text("Shelv Desktop")
                .font(.title2.bold())
            Text(appVersion)
                .foregroundStyle(.secondary)
            Text(tr("Navidrome / Subsonic Client for macOS", "Navidrome / Subsonic Client für macOS"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/gatzenga/Shelv-Desktop")!)
                Text("·").foregroundStyle(.secondary)
                Link(tr("Privacy Policy", "Datenschutz"), destination: URL(string: "https://gatzenga.github.io/Shelv-Desktop/privacy.html")!)
                Text("·").foregroundStyle(.secondary)
                Link(tr("Contact", "Kontakt"), destination: URL(string: "mailto:kontakt@vkugler.ch")!)
            }
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
