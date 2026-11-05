import Foundation
import Observation

// MARK: - yt-dlp output parsing

nonisolated enum YtDlpLine: Equatable {
    case progress(percent: Double, size: String, speed: String, eta: String)
    case destination(String)      // [download] Destination: …
    case merged(String)           // [Merger] Merging formats into "…"
    case extracted(String)        // [ExtractAudio] Destination: …
    case existing(String)         // [download] … has already been downloaded
    case postProcessing
    case error(String)
    case other
}

nonisolated enum YtDlpOutputParser {
    private static let progressRegex = try! NSRegularExpression(
        pattern: #"(\d+\.\d+)%\s+of\s+~?\s*([\d\.]+\w+)\s+at\s+([\d\.]+\w+/s)\s+ETA\s+([\d:]+)"#)

    static func parse(_ raw: String) -> YtDlpLine {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let range = NSRange(line.startIndex..., in: line)
        if let m = progressRegex.firstMatch(in: line, range: range),
           let pct = Double(line[Range(m.range(at: 1), in: line)!]) {
            return .progress(percent: pct,
                             size: String(line[Range(m.range(at: 2), in: line)!]),
                             speed: String(line[Range(m.range(at: 3), in: line)!]),
                             eta: String(line[Range(m.range(at: 4), in: line)!]))
        }
        if line.hasPrefix("ERROR:") {
            return .error(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
        }
        if let rest = line.removingPrefix("[download] Destination: ") { return .destination(rest) }
        if let rest = line.removingPrefix("[ExtractAudio] Destination: ") { return .extracted(rest) }
        if line.hasPrefix("[Merger] Merging formats into "),
           let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last {
            return .merged(String(line[line.index(after: first)..<last]))
        }
        if line.hasPrefix("[download] "), let r = line.range(of: " has already been downloaded") {
            return .existing(String(line[line.index(line.startIndex, offsetBy: 11)..<r.lowerBound]))
        }
        if ["[Merger]", "[ExtractAudio]", "[VideoConvertor]", "[VideoRemuxer]", "[Fixup", "[MoveFiles]"]
            .contains(where: line.hasPrefix) {
            return .postProcessing
        }
        return .other
    }

    /// "/…/My Clip.f137.mp4" → "My Clip"
    static func title(fromPath path: String) -> String {
        var stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if let r = stem.range(of: #"\.f[\w-]+$"#, options: .regularExpression) { stem.removeSubrange(r) }
        return stem
    }

    /// Turns raw yt-dlp errors into something readable.
    static func friendlyError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("private video") || lower.contains("login required") || lower.contains("sign in")
            || lower.contains("cookies") || lower.contains("log in") {
            return "This video is private or requires you to be logged in."
        }
        if lower.contains("unsupported url") { return "This link isn't supported by yt-dlp." }
        if lower.contains("http error 429") { return "The site is rate-limiting requests. Try again later." }
        if lower.contains("http error 404") || lower.contains("unavailable") || lower.contains("been removed")
            || lower.contains("does not exist") {
            return "This video is unavailable or has been removed."
        }
        if lower.contains("ffmpeg") || lower.contains("ffprobe") {
            return "ffmpeg is required for this format. Install it with: brew install ffmpeg"
        }
        if lower.contains("unable to download") || lower.contains("urlopen error") || lower.contains("network") {
            return "Network error. Check your connection and try again."
        }
        return String(raw.prefix(240))
    }
}

private extension String {
    nonisolated func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

// MARK: - Service

enum DownloadError: LocalizedError {
    case invalidURL, missingYtDlp, missingFFmpeg

    var errorDescription: String? {
        switch self {
        case .invalidURL:     "That doesn't look like a valid http(s) link."
        case .missingYtDlp:   "yt-dlp isn't installed. Run `brew install yt-dlp ffmpeg` (see Settings)."
        case .missingFFmpeg:  "MP3 extraction needs ffmpeg. Run `brew install ffmpeg` (see Settings)."
        }
    }
}

/// Owns the download queue, dependency detection and history.
@Observable
final class VideoDownloaderService {
    private(set) var ytDlpURL: URL?
    private(set) var ffmpegURL: URL?
    private(set) var ytDlpVersion: String?
    private(set) var isCheckingDependencies = false
    private(set) var tasks: [DownloadTask] = []
    private(set) var history: [DownloadRecord] = []

    private let settings: AppSettings
    private var runners: [UUID: ProcessRunner] = [:]
    private static let historyKey = "downloadHistory"
    private static let historyLimit = 100

    var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
    }

    var hasYtDlp: Bool { ytDlpURL != nil }
    var hasFFmpeg: Bool { ffmpegURL != nil }
    var inFlightTasks: [DownloadTask] { tasks.filter { $0.state.isInFlight } }

    init(settings: AppSettings) {
        self.settings = settings
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            history = saved
        }
    }

    // MARK: Dependencies

    func refreshDependencies() async {
        isCheckingDependencies = true
        defer { isCheckingDependencies = false }
        let custom = settings.customYtDlpPath
        let (ytdlp, ffmpeg, version) = await Task.detached { () -> (URL?, URL?, String?) in
            let ytdlp = ToolLocator.locate("yt-dlp", custom: custom)
            let ffmpeg = ToolLocator.locate("ffmpeg")
            let version = ytdlp.flatMap { ProcessRunner.capture($0, arguments: ["--version"]) }
            return (ytdlp, ffmpeg, version)
        }.value
        ytDlpURL = ytdlp
        ffmpegURL = ffmpeg
        ytDlpVersion = version
    }

    // MARK: Queue

    /// Validates the link and appends it to the queue.
    @discardableResult
    func add(urlString: String, quality: DownloadQuality) throws -> DownloadTask {
        guard let url = PasteboardHelper.firstURL(in: urlString) else { throw DownloadError.invalidURL }
        guard hasYtDlp else { throw DownloadError.missingYtDlp }
        if quality.requiresFFmpeg && !hasFFmpeg { throw DownloadError.missingFFmpeg }
        let task = DownloadTask(url: url, quality: quality)
        tasks.append(task)
        startNextIfIdle()
        return task
    }

    func cancel(_ task: DownloadTask) {
        guard task.state.isInFlight else { return }
        task.state = .cancelled
        runners[task.id]?.cancel()   // no-op for queued tasks
    }

    func retry(_ task: DownloadTask) {
        dismiss(task)
        _ = try? add(urlString: task.url.absoluteString, quality: task.quality)
    }

    func dismiss(_ task: DownloadTask) {
        guard !task.state.isRunning else { return }
        tasks.removeAll { $0.id == task.id }
    }

    /// One download at a time keeps bandwidth and yt-dlp rate limits sane.
    private func startNextIfIdle() {
        guard !tasks.contains(where: { $0.state.isRunning }),
              let next = tasks.first(where: { $0.state == .queued }) else { return }
        next.state = .fetching
        let runner = ProcessRunner()
        runners[next.id] = runner
        Task { await execute(next, runner: runner) }
    }

    private func execute(_ task: DownloadTask, runner: ProcessRunner) async {
        defer {
            runners[task.id] = nil
            startNextIfIdle()
        }
        guard let ytDlp = ytDlpURL else { fail(task, DownloadError.missingYtDlp.localizedDescription); return }

        var args = ["--newline", "--progress", "--no-playlist", "--no-mtime",
                    "-o", downloadsDirectory.path + "/%(title).150B.%(ext)s"]
        if let ffmpegURL { args += ["--ffmpeg-location", ffmpegURL.deletingLastPathComponent().path] }
        args += task.quality.formatArguments(hasFFmpeg: hasFFmpeg)
        args += ["--", task.url.absoluteString]

        var lastError: String?
        var exitCode: Int32 = -1
        do {
            for try await event in runner.stream(executable: ytDlp, arguments: args,
                                                 environment: ToolLocator.processEnvironment) {
                switch event {
                case .line(let text, _): apply(YtDlpOutputParser.parse(text), to: task, lastError: &lastError)
                case .terminated(let code): exitCode = code
                }
            }
        } catch {
            fail(task, "Couldn't launch yt-dlp: \(error.localizedDescription)")
            return
        }

        if task.state == .cancelled { return }
        if exitCode == 0 {
            complete(task)
        } else {
            fail(task, lastError.map(YtDlpOutputParser.friendlyError) ?? "yt-dlp exited with code \(exitCode).")
        }
    }

    private func apply(_ line: YtDlpLine, to task: DownloadTask, lastError: inout String?) {
        guard task.state != .cancelled else { return }
        switch line {
        case let .progress(percent, size, speed, eta):
            task.state = .downloading
            task.progress = min(percent / 100, 1)
            task.totalSize = size
            task.speed = speed
            task.eta = eta
        case .destination(let path):
            if let previous = task.outputURL, previous.path != path { task.streamIndex += 1; task.progress = 0 }
            else { task.title = YtDlpOutputParser.title(fromPath: path) }
            task.outputURL = URL(fileURLWithPath: path)
        case .merged(let path), .extracted(let path):
            task.outputURL = URL(fileURLWithPath: path)
            task.title = YtDlpOutputParser.title(fromPath: path)
            task.state = .processing
        case .existing(let path):
            task.outputURL = URL(fileURLWithPath: path)
            task.title = YtDlpOutputParser.title(fromPath: path)
            task.progress = 1
        case .postProcessing:
            task.state = .processing
            task.progress = 1
        case .error(let message):
            lastError = message
        case .other:
            break
        }
    }

    private func complete(_ task: DownloadTask) {
        task.state = .completed
        // If we never saw a file path, point history at the Downloads folder instead of failing.
        let path = (task.outputURL ?? downloadsDirectory).path
        history.insert(DownloadRecord(title: task.title, sourceURL: task.url.absoluteString, filePath: path), at: 0)
        saveHistory()
        tasks.removeAll { $0.id == task.id }
    }

    private func fail(_ task: DownloadTask, _ message: String) {
        task.state = .failed(message)
    }

    // MARK: History

    func removeFromHistory(_ record: DownloadRecord) {
        history.removeAll { $0.id == record.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        history = Array(history.prefix(Self.historyLimit))
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
}
