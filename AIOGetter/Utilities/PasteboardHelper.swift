import AppKit

enum PasteboardHelper {
    /// Hosts we proactively recognise in the clipboard. Manual entry accepts any
    /// http(s) link, since yt-dlp supports far more sites than this list.
    static let knownHosts = [
        "tiktok.com", "instagram.com", "youtube.com", "youtu.be", "x.com", "twitter.com",
        "reddit.com", "redd.it", "pinterest.com", "pin.it", "facebook.com", "fb.watch",
        "vimeo.com", "twitch.tv", "dailymotion.com", "threads.net", "bsky.app",
    ]

    static var changeCount: Int { NSPasteboard.general.changeCount }

    static func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// First http(s) URL found in free text.
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), isWebURL(url) { return url }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector?.matches(in: trimmed, range: range)
            .compactMap(\.url)
            .first(where: isWebURL)
    }

    nonisolated static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return !(url.host ?? "").isEmpty
    }

    static func isKnownVideoHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return knownHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// A clipboard URL from a recognised video site, if any.
    static func clipboardVideoURL() -> URL? {
        guard let text = string(), let url = firstURL(in: text), isKnownVideoHost(url) else { return nil }
        return url
    }
}
