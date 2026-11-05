import SwiftUI
import AppKit

/// Compact tray popover: quick paste, live progress, open window, quit.
struct MenuBarView: View {
    @Environment(VideoDownloaderService.self) private var service
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                pasteAndDownload()
            } label: {
                Label("Paste & Download", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let message { Text(message).font(.caption).foregroundStyle(.red) }

            ForEach(service.inFlightTasks) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.caption).lineLimit(1).truncationMode(.middle)
                    ProgressView(value: task.state == .downloading ? task.progress : nil)
                    if task.state == .downloading {
                        Text("\(task.speed)  ETA \(task.eta)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack {
                Button("Open Window") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func pasteAndDownload() {
        guard let text = PasteboardHelper.string() else { message = "Clipboard is empty."; return }
        do {
            try service.add(urlString: text, quality: settings.defaultQuality)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
