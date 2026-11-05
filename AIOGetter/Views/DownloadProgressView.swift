import SwiftUI

/// Card for one queued / running / failed download.
struct DownloadProgressView: View {
    let task: DownloadTask
    @Environment(VideoDownloaderService.self) private var service

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(task.title).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                actions
            }
            detail
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var detail: some View {
        switch task.state {
        case .queued:
            Text("Waiting in queue…").font(.caption).foregroundStyle(.secondary)
        case .fetching:
            ProgressView().progressViewStyle(.linear)
            Text("Fetching video info…").font(.caption).foregroundStyle(.secondary)
        case .downloading:
            ProgressView(value: task.progress)
            HStack(spacing: 12) {
                Text("\(Int(task.progress * 100))%")
                if !task.totalSize.isEmpty { Text(task.totalSize) }
                if !task.speed.isEmpty { Label(task.speed, systemImage: "speedometer") }
                if !task.eta.isEmpty { Label(task.eta, systemImage: "clock") }
                if task.streamIndex > 1 { Text("stream \(task.streamIndex)") }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        case .processing:
            ProgressView().progressViewStyle(.linear)
            Text("Processing (merging / converting)…").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        case .completed:
            EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        switch task.state {
        case .failed, .cancelled:
            Button("Retry") { service.retry(task) }
            Button { service.dismiss(task) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        default:
            Button("Stop", role: .destructive) { service.cancel(task) }
        }
    }

    private var icon: String {
        switch task.state {
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "stop.circle.fill"
        case .processing: "gearshape.2.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private var iconColor: Color {
        switch task.state {
        case .failed: .red
        case .cancelled: .secondary
        default: .accentColor
        }
    }
}
