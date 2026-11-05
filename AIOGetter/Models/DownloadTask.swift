import Foundation
import Observation

/// Output quality / format choices offered in the UI.
enum DownloadQuality: String, CaseIterable, Identifiable, Codable {
    case best, p1080, p720, audioMP3

    var id: String { rawValue }

    var label: String {
        switch self {
        case .best:     "Best (MP4)"
        case .p1080:    "1080p"
        case .p720:     "720p"
        case .audioMP3: "Audio only (MP3)"
        }
    }

    /// Audio extraction and stream merging both need ffmpeg.
    var requiresFFmpeg: Bool { self == .audioMP3 }

    /// yt-dlp format arguments. Without ffmpeg we can't merge separate
    /// video+audio streams, so fall back to single-file progressive MP4s.
    func formatArguments(hasFFmpeg: Bool) -> [String] {
        switch self {
        case .audioMP3:
            return ["-f", "bestaudio/best", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        case .best:
            return hasFFmpeg
                ? ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b", "--merge-output-format", "mp4"]
                : ["-f", "b[ext=mp4]/b"]
        case .p1080, .p720:
            let h = self == .p1080 ? 1080 : 720
            return hasFFmpeg
                ? ["-f", "bv*[height<=\(h)][ext=mp4]+ba[ext=m4a]/b[height<=\(h)][ext=mp4]/b[height<=\(h)]/b",
                   "--merge-output-format", "mp4"]
                : ["-f", "b[height<=\(h)][ext=mp4]/b[height<=\(h)]/b"]
        }
    }
}

enum DownloadState: Equatable {
    case queued, fetching, downloading, processing, completed, cancelled
    case failed(String)

    /// A yt-dlp process is currently running for this task.
    var isRunning: Bool {
        switch self {
        case .fetching, .downloading, .processing: true
        default: false
        }
    }

    /// Waiting or running (not yet in a terminal state).
    var isInFlight: Bool { self == .queued || isRunning }
}

/// One entry in the live queue. Reference type so views observe fine-grained progress updates.
@Observable
final class DownloadTask: Identifiable {
    let id = UUID()
    let url: URL
    let quality: DownloadQuality
    var title: String
    var state: DownloadState = .queued
    var progress: Double = 0          // 0...1 for the current stream
    var speed: String = ""
    var eta: String = ""
    var totalSize: String = ""
    var streamIndex: Int = 1          // video and audio download as separate streams
    var outputURL: URL?

    init(url: URL, quality: DownloadQuality) {
        self.url = url
        self.quality = quality
        self.title = url.host ?? url.absoluteString
    }
}

/// A finished download, persisted so it survives relaunches.
struct DownloadRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var sourceURL: String
    var filePath: String
    var date = Date()

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var fileExists: Bool { FileManager.default.fileExists(atPath: filePath) }
}
