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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = ModuleHost(modules: [BatteryModule()])
        host.start()
        let notch = NotchController(host: host)
        notch.start()
        self.host = host
        self.notch = notch
    }

    func applicationWillTerminate(_ notification: Notification) {
        host?.stop()
    }
}
