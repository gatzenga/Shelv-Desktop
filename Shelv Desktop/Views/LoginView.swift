import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.themeColor) private var themeColor

    @State private var serverName: String = ""
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(themeColor)
                    Text("Shelv")
                        .font(.system(size: 32, weight: .bold))
                    Text(tr("Navidrome Desktop Client", "Navidrome Desktop-Client"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Form
                VStack(spacing: 14) {
                    LabeledContent(tr("Server Name", "Servername")) {
                        TextField(tr("My Navidrome", "Mein Navidrome"), text: $serverName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    LabeledContent(tr("Server URL", "Server-URL")) {
                        TextField("https://music.example.com", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    LabeledContent(tr("Username", "Benutzername")) {
                        TextField(tr("Username", "Benutzername"), text: $username)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    LabeledContent(tr("Password", "Passwort")) {
                        SecureField(tr("Password", "Passwort"), text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 360)

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                Button {
                    Task { await connect() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(tr("Connect", "Verbinden"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 360)
                .disabled(isLoading || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding(40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 460)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func connect() async {
        isLoading = true
        errorMessage = nil
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        let name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = await appState.addServer(name: name, serverURL: url, username: username, password: password)
        if !success {
            errorMessage = appState.errorMessage ?? tr("Connection failed.", "Verbindung fehlgeschlagen.")
        }
        isLoading = false
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState.shared)
        .frame(width: 700, height: 560)
}
