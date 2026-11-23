import SwiftUI

@main
struct PerchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("Settings arrive in 0.1.")
                .padding(40)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: ModuleHost?
    private var notch: NotchController?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the unit-test host, stay inert: no notch, no helper processes.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let host = ModuleHost(modules: [MusicModule(), BatteryModule()])
        host.start()
        let notch = NotchController(host: host)
        notch.start()
        self.host = host
        self.notch = notch
        quitCleanlyOnSIGTERM()
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
        host?.stop()
    }
}
