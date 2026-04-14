import SwiftUI
import Combine

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isLoggedIn: Bool = false
    @Published var selectedSidebar: SidebarItem? = .discover
    @Published var navigationPath = NavigationPath()
    @Published var errorMessage: String?

    let api = SubsonicAPIService.shared
    let player = AudioPlayerService.shared

    private init() {
        isLoggedIn = api.hasConfig
    }

    func login(serverURL: String, username: String, password: String) async -> Bool {
        let cfg = ServerConfig(serverURL: serverURL, username: username, password: password)
        api.setConfig(cfg)
        do {
            try await api.ping()
            isLoggedIn = true
            return true
        } catch {
            api.clearConfig()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() {
        api.clearConfig()
        player.stop()
        isLoggedIn = false
    }

    var serverDisplayName: String {
        api.currentConfig?.serverURL ?? ""
    }

    var username: String {
        api.currentConfig?.username ?? ""
    }
}
