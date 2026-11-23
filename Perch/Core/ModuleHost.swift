import Foundation
import Observation

/// Owns the loaded modules and exposes the activity that currently wins the notch.
@Observable
final class ModuleHost {
    let modules: [any PerchModule]

    init(modules: [any PerchModule]) {
        self.modules = modules
    }

    var current: Activity? {
        Arbiter.select(modules.compactMap(\.activity), now: .now)
    }

    func module(id: String) -> (any PerchModule)? {
        modules.first { $0.id == id }
    }

    func start() {
        modules.forEach { $0.start() }
    }

    func stop() {
        modules.forEach { $0.stop() }
    }
}
