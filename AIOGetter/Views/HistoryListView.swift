import SwiftUI
import AppKit

/// Finished downloads with Finder / Play shortcuts.
struct HistoryListView: View {
    @Environment(VideoDownloaderService.self) private var service

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Completed").font(.headline)
                Spacer()
                if !service.history.isEmpty {
                    Button("Clear", role: .destructive) { service.clearHistory() }
                        .buttonStyle(.borderless)
                }
            }
            if service.history.isEmpty {
                ContentUnavailableView("No downloads yet", systemImage: "tray",
                                       description: Text("Finished videos appear here."))
            } else {
                List(service.history) { record in
                    row(record)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func row(_ record: DownloadRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.fileExists ? "film" : "questionmark.folder")
                .foregroundStyle(record.fileExists ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).lineLimit(1).truncationMode(.middle)
                Text(record.fileExists ? record.date.formatted(date: .abbreviated, time: .shortened)
                                       : "File moved or deleted")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showInFinder(record) } label: { Label("Show in Finder", systemImage: "folder") }
                .labelStyle(.iconOnly).help("Show in Finder")
            Button { NSWorkspace.shared.open(record.fileURL) } label: { Label("Play", systemImage: "play.fill") }
                .labelStyle(.iconOnly).help("Play video")
                .disabled(!record.fileExists)
            Button { service.removeFromHistory(record) } label: { Label("Remove", systemImage: "xmark") }
                .labelStyle(.iconOnly).help("Remove from list (keeps the file)")
        }
        .buttonStyle(.borderless)
    }

    private func showInFinder(_ record: DownloadRecord) {
        if record.fileExists {
            NSWorkspace.shared.selectFile(record.filePath, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(service.downloadsDirectory)
        }
    }
}
