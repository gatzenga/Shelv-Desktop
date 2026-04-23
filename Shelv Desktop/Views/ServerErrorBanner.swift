import SwiftUI

struct ServerErrorBanner: View {
    @ObservedObject var offlineMode = OfflineModeService.shared

    var body: some View {
        if offlineMode.serverErrorBannerVisible {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Server unreachable", "Server nicht erreichbar"))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(tr(
                        "Switch to offline mode to use your downloads.",
                        "In Offline-Modus wechseln um Downloads zu verwenden."
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button(tr("Offline", "Offline")) {
                    offlineMode.enterOfflineMode()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                Button {
                    offlineMode.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
