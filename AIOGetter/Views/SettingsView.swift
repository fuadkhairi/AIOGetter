import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VideoDownloaderService.self) private var service

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Dependencies") {
                dependencyRow(name: "yt-dlp", url: service.ytDlpURL, detail: service.ytDlpVersion.map { "v\($0)" })
                dependencyRow(name: "ffmpeg", url: service.ffmpegURL,
                              detail: service.hasFFmpeg ? nil : "Needed for MP3 and for merging 1080p+ streams")

                if !service.hasYtDlp || !service.hasFFmpeg { installHint }

                HStack {
                    TextField("Custom yt-dlp path (optional)", text: $settings.customYtDlpPath)
                    Button("Choose…", action: chooseBinary)
                }
                HStack {
                    Button("Re-check") { Task { await service.refreshDependencies() } }
                        .disabled(service.isCheckingDependencies)
                    if service.isCheckingDependencies { ProgressView().controlSize(.small) }
                    Spacer()
                    Text("Sites change often — keep yt-dlp current with `brew upgrade yt-dlp`.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Preferences") {
                Picker("Default format", selection: $settings.defaultQuality) {
                    ForEach(DownloadQuality.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Offer to download links copied to the clipboard", isOn: $settings.autoDetectClipboard)
                Toggle("Show menu bar item", isOn: $settings.showMenuBarExtra)
                LabeledContent("Save location", value: "~/Downloads")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
    }

    private func dependencyRow(name: String, url: URL?, detail: String?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: url != nil ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(url != nil ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(url?.path ?? "Not found").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var installHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Quick setup — run this in Terminal:", systemImage: "terminal")
            HStack {
                Text("brew install yt-dlp ffmpeg")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install yt-dlp ffmpeg", forType: .string)
                }
            }
            Text("Then press Re-check. Don't have Homebrew? See brew.sh.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            settings.customYtDlpPath = url.path
            Task { await service.refreshDependencies() }
        }
    }
}
