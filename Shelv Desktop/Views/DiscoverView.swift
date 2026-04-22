import SwiftUI

struct DiscoverView: View {
    @StateObject private var vm = DiscoverViewModel()
    @EnvironmentObject var appState: AppState
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    @State private var mixLoading: String?

    @ViewBuilder
    var body: some View {
        if offlineMode.isOffline {
            offlineEmptyState
                .navigationTitle(tr("Discover", "Entdecken"))
        } else {
            onlineBody
        }
    }

    private var offlineEmptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(tr("You are offline", "Du bist offline"))
                .font(.title2.bold())
            Text(tr(
                "Switch to your downloads in the sidebar, or use search to find downloaded tracks.",
                "Wechsle in der Seitenleiste zu deinen Downloads, oder nutze die Suche um Titel zu finden."
            ))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            Button {
                offlineMode.exitOfflineMode()
            } label: {
                Label(tr("Go Online", "Online gehen"), systemImage: "wifi")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var onlineBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Smart Mixes", "Smart Mixes"))
                        .font(.title2).bold()
                    VStack(spacing: 10) {
                        MixButton(
                            title: tr("Mix: Newest Tracks", "Mix: Neueste Titel"),
                            icon: "sparkles",
                            color: .blue,
                            isLoading: mixLoading == "newest"
                        ) {
                            mixLoading = "newest"
                            await vm.playMixNewest()
                            mixLoading = nil
                        }
                        MixButton(
                            title: tr("Mix: Most Played", "Mix: Häufig gespielt"),
                            icon: "chart.bar.fill",
                            color: .orange,
                            isLoading: mixLoading == "frequent"
                        ) {
                            mixLoading = "frequent"
                            await vm.playMixFrequent()
                            mixLoading = nil
                        }
                        MixButton(
                            title: tr("Mix: Recently Played", "Mix: Kürzlich gespielt"),
                            icon: "clock.fill",
                            color: .green,
                            isLoading: mixLoading == "recent"
                        ) {
                            mixLoading = "recent"
                            await vm.playMixRecent()
                            mixLoading = nil
                        }
                    }
                }

                if vm.isLoading {
                    ProgressView(tr("Loading…", "Laden…"))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    if !vm.recentlyAdded.isEmpty {
                        AlbumShelfSection(title: tr("Recently Added", "Kürzlich hinzugefügt"), albums: vm.recentlyAdded)
                    }
                    if !vm.recentlyPlayed.isEmpty {
                        AlbumShelfSection(title: tr("Recently Played", "Kürzlich gespielt"), albums: vm.recentlyPlayed)
                    }
                    if !vm.frequentlyPlayed.isEmpty {
                        AlbumShelfSection(title: tr("Frequently Played", "Häufig gespielt"), albums: vm.frequentlyPlayed)
                    }
                    if !vm.randomAlbums.isEmpty {
                        AlbumShelfSection(
                            title: tr("Random Albums", "Zufällige Alben"),
                            albums: vm.randomAlbums,
                            refreshAction: { await vm.refreshRandom() }
                        )
                    }
                }

                if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(24)
        }
        .navigationTitle(tr("Discover", "Entdecken"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ThemePickerButton()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        async let discover:  Void = vm.load()
                        async let playlists: Void = libraryStore.loadPlaylists()
                        async let sync:      Void = CloudKitSyncService.shared.syncNow()
                        _ = await (discover, playlists, sync)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
                .help(tr("Reload", "Neu laden"))
            }
            ToolbarItem(placement: .automatic) {
                Divider()
            }
            ToolbarItem(placement: .automatic) {
                RecapToolbarButton()
            }
            ToolbarItem(placement: .automatic) {
                InsightsToolbarButton()
            }
        }
        .task { await vm.load() }
        .onChange(of: appState.serverStore.activeServerID) { _, _ in
            vm.reset()
            Task { await vm.load() }
        }
    }
}

struct MixButton: View {
    let title: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.bold())
                    .frame(width: 24)
                Text(title)
                    .font(.body.bold())
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(color)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25), lineWidth: 1))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct AlbumShelfSection: View {
    let title: String
    let albums: [Album]
    var refreshAction: (() async -> Void)? = nil

    private let cardWidth: CGFloat   = 150
    private let cardSpacing: CGFloat  = 16
    private let shelfHeight: CGFloat  = 196
    private let cardsPerStep: Int     = 3

    @State private var firstVisible: Int = 0
    @State private var isRefreshing = false

    private var atStart: Bool { firstVisible == 0 }
    private var atEnd: Bool   { firstVisible + cardsPerStep >= albums.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.title2).bold()
                Spacer()
                HStack(spacing: 6) {
                    if let refreshAction {
                        ShelfNavButton(icon: isRefreshing ? "arrow.clockwise" : "dice", disabled: isRefreshing) {
                            isRefreshing = true
                            firstVisible = 0
                            await refreshAction()
                            isRefreshing = false
                        }
                    }
                    ShelfNavButton(icon: "chevron.left", disabled: atStart) {
                        firstVisible = max(0, firstVisible - cardsPerStep)
                    }
                    ShelfNavButton(icon: "chevron.right", disabled: atEnd) {
                        firstVisible = min(albums.count - cardsPerStep, firstVisible + cardsPerStep)
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: cardSpacing) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .albumContextMenu(album)
                            .id(index)
                        }
                    }
                    .padding(.leading, 2)
                    .padding(.top, 8)
                }
                .frame(height: shelfHeight + 8)
                .clipped()
                .onChange(of: firstVisible) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(newValue, anchor: .leading)
                    }
                }
            }
        }
    }
}

struct ShelfNavButton: View {
    let icon: String
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: icon)
                .font(.callout.bold())
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct AlbumCard: View {
    let album: Album
    @State private var isHovered = false

    private var coverURL: URL? {
        guard let id = album.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 200)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArtView(url: coverURL, size: 150, cornerRadius: 8)
                .overlay(alignment: .bottomTrailing) {
                    AlbumDownloadBadge(albumId: album.id)
                        .padding(4)
                }
                .shadow(color: .black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 8 : 4)
            Text(album.name)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            if let artist = album.artist {
                Text(artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .scaleEffect(isHovered ? 1.03 : 1.0, anchor: .bottom)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct InsightsToolbarButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Button {
            openWindow(id: "insights")
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(themeColor)
        }
        .help(tr("Insights", "Insights"))
    }
}

struct RecapToolbarButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Button {
            openWindow(id: "recap")
        } label: {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(themeColor)
        }
        .help(tr("Recap", "Recap"))
    }
}

struct ThemePickerButton: View {
    @AppStorage("themeColor") private var themeColorName: String = "violet"
    @State private var showPicker = false

    var body: some View {
        Button { showPicker.toggle() } label: {
            Image(systemName: "paintpalette.fill")
                .foregroundStyle(AppTheme.color(for: themeColorName))
        }
        .help(tr("Choose color", "Farbe wählen"))
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            ThemePickerPopover(themeColorName: $themeColorName)
        }
    }
}

struct ThemePickerPopover: View {
    @Binding var themeColorName: String

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Color", "Farbe"))
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppTheme.options, id: \.name) { option in
                    Button {
                        themeColorName = option.name
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if themeColorName == option.name {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(
                                            option.useDarkCheckmark ? Color.black : Color.white
                                        )
                                }
                            }
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help(tr(option.nameEN, option.nameDE))
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

#Preview {
    DiscoverView()
        .frame(width: 900, height: 700)
        .environmentObject(AppState.shared)
}
