import SwiftUI

@main
struct PerchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Perch has no menu bar; its settings live in their own window,
        // opened from the notch or by opening the app again.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: ModuleHost?
    private var notch: NotchController?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the unit-test host, stay inert: no notch, no helper processes.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let music = MusicModule()
        let devices = DevicesModule()
        let battery = BatteryModule()
        battery.devices = devices
        let host = ModuleHost(modules: [music, TimerModule(), ShelfModule(), devices, battery, HUDModule()])
        host.start()
        // The app whose media is playing, if any: its full-screen window is a film.
        let notch = NotchController(host: host) { music.nowPlaying.flatMap { $0.isPlaying ? $0.bundleID : nil } }
        notch.start()
        self.host = host
        self.notch = notch
        SettingsWindowController.shared.host = host
        quitCleanlyOnSIGTERM()
    }

    /// Opening Perch while it already runs (Finder, Spotlight) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// `kill`, logout and launchd send SIGTERM, which skips
    /// `applicationWillTerminate`. Route it there so helper processes stop too.
    private func quitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        Caffeine.shared.stop()
        host?.stop()
    }
}
