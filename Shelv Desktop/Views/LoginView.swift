import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.themeColor) private var themeColor

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
                    Text("Navidrome Desktop Client")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Form
                VStack(spacing: 14) {
                    LabeledContent("Server-URL") {
                        TextField("https://music.example.com", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Benutzername") {
                        TextField("Benutzername", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Passwort") {
                        SecureField("Passwort", text: $password)
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
                        Text("Verbinden")
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
            .frame(maxWidth: 440)

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
        let success = await appState.login(serverURL: url, username: username, password: password)
        if !success {
            errorMessage = appState.errorMessage ?? "Verbindung fehlgeschlagen."
        }
        isLoading = false
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState.shared)
        .frame(width: 700, height: 500)
}
