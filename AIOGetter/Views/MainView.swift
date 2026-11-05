import SwiftUI
import AppKit

struct MainView: View {
    @Environment(VideoDownloaderService.self) private var service
    @Environment(AppSettings.self) private var settings

    @State private var urlText = ""
    @State private var quality: DownloadQuality = .best
    @State private var errorMessage: String?
    @State private var clipboardURL: URL?
    @State private var lastClipboardChange = -1

    var body: some View {
        VStack(spacing: 14) {
            if !service.isCheckingDependencies && !service.hasYtDlp { missingToolBanner }
            if let url = clipboardURL { clipboardBanner(url) }

            inputSection

            if !service.tasks.isEmpty {
                VStack(spacing: 8) {
                    ForEach(service.tasks) { DownloadProgressView(task: $0) }
                }
            }

            HistoryListView()
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 520)
        .toolbar {
            ToolbarItem { SettingsLink { Label("Settings", systemImage: "gearshape") } }
        }
        .alert("Couldn't start download", isPresented: Binding(get: { errorMessage != nil },
                                                                set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .onAppear {
            quality = settings.defaultQuality
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboard()
        }
    }

    // MARK: Sections

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Paste a TikTok, Instagram, YouTube, X, Reddit… link", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("Download", action: submit)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    pasteAndDownload()
                } label: {
                    Label("Paste & Download", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                Picker("Format", selection: $quality) {
                    ForEach(DownloadQuality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Saves to ~/Downloads")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var missingToolBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text("yt-dlp not found").font(.headline)
                Text("Install it with `brew install yt-dlp ffmpeg`, then re-check in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink { Text("Open Settings") }
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func clipboardBanner(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.plus").foregroundStyle(.tint)
            Text("Link on clipboard: \(url.absoluteString)")
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Download") { enqueue(url.absoluteString); clipboardURL = nil }
            Button { clipboardURL = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Actions

    private func submit() {
        if enqueue(urlText) { urlText = "" }
    }

    private func pasteAndDownload() {
        guard let text = PasteboardHelper.string(), PasteboardHelper.firstURL(in: text) != nil else {
            errorMessage = "The clipboard doesn't contain a link."
            return
        }
        urlText = text
        submit()
    }

    @discardableResult
    private func enqueue(_ string: String) -> Bool {
        do {
            try service.add(urlString: string, quality: quality)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Offers to download a recognised link from the clipboard, once per clipboard change.
    private func checkClipboard() {
        guard settings.autoDetectClipboard, PasteboardHelper.changeCount != lastClipboardChange else { return }
        lastClipboardChange = PasteboardHelper.changeCount
        clipboardURL = PasteboardHelper.clipboardVideoURL()
    }
}
