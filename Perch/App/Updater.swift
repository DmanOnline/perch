import AppKit
import Observation
import Sparkle

/// Updates through Sparkle: once a day Perch reads the appcast attached to
/// the latest GitHub release and offers a newer version, which it installs
/// only when its EdDSA signature matches the key in Info.plist.
@Observable
final class Updater {
    static let shared = Updater()

    @ObservationIgnored private let controller: SPUStandardUpdaterController

    private init() {
        // As the unit-test host, never start checking.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        controller = SPUStandardUpdaterController(startingUpdater: !isTesting, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    func checkNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
