import SwiftUI

struct TranscodingPanel: View {
    @AppStorage("transcodingEnabled") private var transcodingEnabled = false
    @AppStorage("transcodingWifiCodec") private var wifiCodecRaw: String = "raw"
    @AppStorage("transcodingWifiBitrate") private var wifiBitrate: Int = 256
    @AppStorage("transcodingCellularCodec") private var cellularCodecRaw: String = "raw"
    @AppStorage("transcodingCellularBitrate") private var cellularBitrate: Int = 128
    @AppStorage("transcodingDownloadCodec") private var downloadCodecRaw: String = "raw"
    @AppStorage("transcodingDownloadBitrate") private var downloadBitrate: Int = 192
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $transcodingEnabled) {
                    Label(tr("Transcoding", "Transcoding"), systemImage: "waveform.badge.magnifyingglass")
                }
                .tint(themeColor)
                if transcodingEnabled {
                    Text(tr(
                        "Server transcodes to the format/bitrate below. \u{201C}Original\u{201D} requests unchanged source.",
                        "Server liefert im eingestellten Format/Bitrate. „Original\u{201C} lädt unverändert."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(tr(
                        "Transcoded songs play from a local copy, ensuring stable playback and seamless gapless transitions. The first song may take longer to load.\n\n• The current song is fully downloaded before playback\n• While it plays, the next song pre-fetches in the background\n• Every subsequent song starts instantly\n• Cached files are removed when the next song starts",
                        "Transcodierte Songs werden lokal abgespielt – stabile Wiedergabe und nahtlose Gapless-Übergänge. Beim ersten Song kann es zu einer längeren Ladezeit kommen.\n\n• Der aktuelle Song wird vollständig vor der Wiedergabe geladen\n• Währenddessen wird der nächste Song im Hintergrund geladen\n• Ab dem zweiten Song startet die Wiedergabe sofort\n• Gecachte Dateien werden beim Start des nächsten Songs gelöscht"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if transcodingEnabled {
                subsection(title: tr("WiFi", "WLAN"),
                           codecBinding: $wifiCodecRaw,
                           bitrateBinding: $wifiBitrate,
                           options: TranscodingCodec.streamingOptions)
                subsection(title: tr("Data Saver", "Datensparmodus"),
                           codecBinding: $cellularCodecRaw,
                           bitrateBinding: $cellularBitrate,
                           options: TranscodingCodec.streamingOptions)
                subsection(title: tr("Downloads", "Downloads"),
                           codecBinding: $downloadCodecRaw,
                           bitrateBinding: $downloadBitrate,
                           options: TranscodingCodec.downloadOptions)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func subsection(title: String,
                            codecBinding: Binding<String>,
                            bitrateBinding: Binding<Int>,
                            options: [TranscodingCodec]) -> some View {
        let codec = TranscodingCodec(rawValue: codecBinding.wrappedValue) ?? .raw
        Section(title) {
            Picker(tr("Format", "Format"), selection: codecBinding) {
                ForEach(options) { c in
                    Text(c.label).tag(c.rawValue)
                }
            }
            if codec != .raw {
                Picker(tr("Bitrate", "Bitrate"), selection: bitrateBinding) {
                    ForEach(TranscodingBitrate.allCases) { b in
                        Text(b.label).tag(b.rawValue)
                    }
                }
            }
        }
    }
}
