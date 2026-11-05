import Foundation

nonisolated enum ProcessEvent: Sendable {
    case line(String, isStderr: Bool)
    case terminated(Int32)
}

/// Splits raw pipe chunks into lines on `\n` or `\r` (yt-dlp redraws progress with `\r`).
/// Each instance must be fed from a single reader.
nonisolated final class LineBuffer {
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let idx = data.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = data[data.startIndex..<idx]
            data.removeSubrange(data.startIndex...idx)
            if !lineData.isEmpty { lines.append(String(decoding: lineData, as: UTF8.self)) }
        }
        return lines
    }

    func flush() -> String? {
        defer { data.removeAll() }
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
}

/// Runs one external process and streams its output line by line.
nonisolated final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Launches the process and yields ordered events. The stream ends after
    /// `.terminated`; cancelling the consuming task terminates the process.
    func stream(executable: URL,
                arguments: [String],
                environment: [String: String]? = nil) -> AsyncThrowingStream<ProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardInput = FileHandle.nullDevice

            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Finish only once both pipes hit EOF *and* the process exited,
            // so no trailing output is lost.
            let group = DispatchGroup()
            let outBuffer = LineBuffer(), errBuffer = LineBuffer()

            func attach(_ pipe: Pipe, _ buffer: LineBuffer, isStderr: Bool) {
                group.enter()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {              // EOF
                        handle.readabilityHandler = nil
                        group.leave()
                        return
                    }
                    for line in buffer.append(chunk) {
                        continuation.yield(.line(line, isStderr: isStderr))
                    }
                }
            }
            attach(outPipe, outBuffer, isStderr: false)
            attach(errPipe, errBuffer, isStderr: true)

            group.enter()
            process.terminationHandler = { _ in group.leave() }

            group.notify(queue: .global()) {
                if let rest = outBuffer.flush() { continuation.yield(.line(rest, isStderr: false)) }
                if let rest = errBuffer.flush() { continuation.yield(.line(rest, isStderr: true)) }
                continuation.yield(.terminated(process.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { [weak self] reason in
                if case .cancelled = reason { self?.cancel() }
            }

            lock.lock()
            self.process = process
            let alreadyCancelled = cancelled
            lock.unlock()
            if alreadyCancelled { continuation.finish(); return }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stops the process (SIGTERM). Safe to call from any thread, any number of times.
    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }

    /// Runs a short command to completion and returns trimmed stdout, or nil on failure.
    static func capture(_ executable: URL, arguments: [String]) -> String? {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Finds command-line tools. GUI apps don't inherit your shell PATH, so we probe
/// the usual Homebrew locations first and fall back to asking a login shell.
nonisolated enum ToolLocator {
    static var searchDirectories: [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", "/opt/local/bin", "/usr/bin"]
    }

    static func locate(_ name: String, custom: String? = nil) -> URL? {
        let fm = FileManager.default
        if let custom, !custom.isEmpty {
            let path = NSString(string: custom).expandingTildeInPath
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        for dir in searchDirectories {
            let path = dir + "/" + name
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        if let out = ProcessRunner.capture(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "command -v \(name)"]),
           let last = out.split(separator: "\n").last.map(String.init),
           last.hasPrefix("/"), fm.isExecutableFile(atPath: last) {
            return URL(fileURLWithPath: last)
        }
        return nil
    }

    /// Environment for child processes, with Homebrew on PATH so yt-dlp can find ffmpeg/python.
    static var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = searchDirectories.joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }
}
