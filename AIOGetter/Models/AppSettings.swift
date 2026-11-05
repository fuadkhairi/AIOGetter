import Foundation
import Observation

/// User preferences, persisted to UserDefaults.
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var defaultQuality: DownloadQuality {
        didSet { defaults.set(defaultQuality.rawValue, forKey: "defaultQuality") }
    }
    var autoDetectClipboard: Bool {
        didSet { defaults.set(autoDetectClipboard, forKey: "autoDetectClipboard") }
    }
    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: "showMenuBarExtra") }
    }
    /// Optional manual override for the yt-dlp location.
    var customYtDlpPath: String {
        didSet { defaults.set(customYtDlpPath, forKey: "customYtDlpPath") }
    }

    init() {
        defaultQuality = DownloadQuality(rawValue: defaults.string(forKey: "defaultQuality") ?? "") ?? .best
        autoDetectClipboard = defaults.object(forKey: "autoDetectClipboard") as? Bool ?? true
        showMenuBarExtra = defaults.object(forKey: "showMenuBarExtra") as? Bool ?? true
        customYtDlpPath = defaults.string(forKey: "customYtDlpPath") ?? ""
    }
}
