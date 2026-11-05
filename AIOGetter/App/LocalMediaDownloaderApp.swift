import SwiftUI

@main
struct LocalMediaDownloaderApp: App {
    @State private var settings: AppSettings
    @State private var service: VideoDownloaderService

    init() {
        let settings = AppSettings()
        let service = VideoDownloaderService(settings: settings)
        _settings = State(initialValue: settings)
        _service = State(initialValue: service)
        Task { await service.refreshDependencies() }
    }

    var body: some Scene {
        // Single main window (re-openable from the menu bar item).
        Window("AIOGetter", id: "main") {
            MainView()
                .environment(settings)
                .environment(service)
        }
        .defaultSize(width: 620, height: 700)

        // Optional tray item; toggled in Settings.
        MenuBarExtra("AIOGetter", systemImage: "arrow.down.circle",
                     isInserted: Binding(get: { settings.showMenuBarExtra },
                                         set: { settings.showMenuBarExtra = $0 })) {
            MenuBarView()
                .environment(settings)
                .environment(service)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(service)
        }
    }
}
