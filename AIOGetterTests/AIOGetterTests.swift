import Testing
import Foundation
@testable import AIOGetter

struct ParserTests {
    @Test func parsesProgressLine() {
        let line = "[download]  45.3% of ~  10.50MiB at    2.30MiB/s ETA 00:05 (frag 3/10)"
        #expect(YtDlpOutputParser.parse(line) == .progress(percent: 45.3, size: "10.50MiB", speed: "2.30MiB/s", eta: "00:05"))
    }

    @Test func parsesPathLines() {
        #expect(YtDlpOutputParser.parse("[download] Destination: /tmp/A.f137.mp4") == .destination("/tmp/A.f137.mp4"))
        #expect(YtDlpOutputParser.parse("[Merger] Merging formats into \"/tmp/A.mp4\"") == .merged("/tmp/A.mp4"))
        #expect(YtDlpOutputParser.parse("[ExtractAudio] Destination: /tmp/A.mp3") == .extracted("/tmp/A.mp3"))
        #expect(YtDlpOutputParser.parse("[download] /tmp/A.mp4 has already been downloaded") == .existing("/tmp/A.mp4"))
        #expect(YtDlpOutputParser.parse("ERROR: [youtube] x: Private video") == .error("[youtube] x: Private video"))
        #expect(YtDlpOutputParser.parse("[youtube] Extracting URL") == .other)
    }

    @Test func titleStripsFormatSuffix() {
        #expect(YtDlpOutputParser.title(fromPath: "/tmp/My Clip.f137.mp4") == "My Clip")
        #expect(YtDlpOutputParser.title(fromPath: "/tmp/My Clip.mp4") == "My Clip")
    }

    @Test func friendlyErrors() {
        #expect(YtDlpOutputParser.friendlyError("Private video. Sign in if you've been granted access").contains("private"))
        #expect(YtDlpOutputParser.friendlyError("Unsupported URL: https://x").contains("isn't supported"))
    }

    @Test func formatArguments() {
        #expect(DownloadQuality.p720.formatArguments(hasFFmpeg: true).joined(separator: " ").contains("height<=720"))
        #expect(!DownloadQuality.best.formatArguments(hasFFmpeg: false).contains("--merge-output-format"))
        #expect(DownloadQuality.audioMP3.formatArguments(hasFFmpeg: true).contains("mp3"))
    }

    @Test func urlDetection() {
        #expect(PasteboardHelper.firstURL(in: "look https://www.tiktok.com/@a/video/1 wow")?.host == "www.tiktok.com")
        #expect(PasteboardHelper.firstURL(in: "not a link") == nil)
        #expect(PasteboardHelper.firstURL(in: "ftp://example.com/x") == nil)
        #expect(PasteboardHelper.isKnownVideoHost(URL(string: "https://m.youtube.com/watch?v=1")!))
        #expect(!PasteboardHelper.isKnownVideoHost(URL(string: "https://example.com")!))
    }
}

struct RunnerTests {
    @Test func streamsLinesIncludingCarriageReturns() async throws {
        let runner = ProcessRunner()
        var lines: [String] = []
        var exit: Int32 = -1
        for try await e in runner.stream(executable: URL(fileURLWithPath: "/bin/sh"),
                                         arguments: ["-c", "printf 'a\\rb\\nc'; echo err >&2; exit 3"]) {
            switch e {
            case .line(let l, _): lines.append(l)
            case .terminated(let c): exit = c
            }
        }
        #expect(Set(lines) == ["a", "b", "c", "err"])
        #expect(exit == 3)
    }

    @Test func cancelTerminatesProcess() async throws {
        let runner = ProcessRunner()
        let start = Date()
        Task { try await Task.sleep(for: .milliseconds(300)); runner.cancel() }
        var exit: Int32 = 0
        for try await e in runner.stream(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) {
            if case .terminated(let c) = e { exit = c }
        }
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(exit != 0)
    }

    @Test func missingExecutableThrows() async {
        let runner = ProcessRunner()
        await #expect(throws: (any Error).self) {
            for try await _ in runner.stream(executable: URL(fileURLWithPath: "/nonexistent/bin"), arguments: []) {}
        }
    }
}

@MainActor
struct ServiceTests {
    /// Drives the whole pipeline with a fake yt-dlp that prints realistic output.
    @Test func downloadFlowWithFakeYtDlp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fake-ytdlp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("yt-dlp")
        let body = """
        #!/bin/sh
        [ "$1" = "--version" ] && { echo 2099.01.01; exit 0; }
        echo "[youtube] Extracting URL"
        echo "[download] Destination: /tmp/Fake Video.f137.mp4"
        printf '[download]  50.0%% of 10.00MiB at 2.00MiB/s ETA 00:02\\r'
        printf '[download] 100.0%% of 10.00MiB at 2.00MiB/s ETA 00:00\\n'
        echo '[Merger] Merging formats into "/tmp/Fake Video.mp4"'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settings = AppSettings()
        let saved = settings.customYtDlpPath
        settings.customYtDlpPath = script.path
        defer { settings.customYtDlpPath = saved }
        let service = VideoDownloaderService(settings: settings)
        service.clearHistory()
        await service.refreshDependencies()
        #expect(service.ytDlpVersion == "2099.01.01")

        try service.add(urlString: "https://youtu.be/abc", quality: .best)
        for _ in 0..<100 where service.history.isEmpty { try await Task.sleep(for: .milliseconds(50)) }

        #expect(service.history.first?.title == "Fake Video")
        #expect(service.history.first?.filePath == "/tmp/Fake Video.mp4")
        #expect(service.tasks.isEmpty)
        service.clearHistory()
    }

    @Test func rejectsInvalidURL() async {
        let service = VideoDownloaderService(settings: AppSettings())
        #expect(throws: DownloadError.self) { try service.add(urlString: "hello", quality: .best) }
    }
}
