import Foundation
import Observation

/// Owns the loaded modules and exposes the activity that currently wins the notch.
/// Modules switched off in the settings are stopped and left out entirely.
@Observable
final class ModuleHost {
    let modules: [any PerchModule]
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private var isStarted = false

    init(modules: [any PerchModule], preferences: Preferences = .shared) {
        self.modules = modules
        self.preferences = preferences
    }

    var enabledModules: [any PerchModule] {
        modules.filter { preferences.isEnabled($0.id) }
    }

    var current: Activity? {
        Arbiter.select(enabledModules.compactMap(\.activity), now: .now)
    }

    func module(id: String) -> (any PerchModule)? {
        enabledModules.first { $0.id == id }
    }

    func start() {
        isStarted = true
        sync()
    }

    func stop() {
        isStarted = false
        sync()
    }

    /// Starts and stops modules to match the settings, then waits for the next change.
    private func sync() {
        let wanted = isStarted ? Set(enabledModules.map(\.id)) : []
        for module in modules {
            if wanted.contains(module.id), !running.contains(module.id) {
                module.start()
                running.insert(module.id)
            } else if !wanted.contains(module.id), running.contains(module.id) {
                module.stop()
                running.remove(module.id)
            }
        }
        guard isStarted else { return }
        withObservationTracking {
            _ = preferences.disabledModules
        } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
    }
}
