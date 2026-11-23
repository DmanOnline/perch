import AppKit

nonisolated enum HapticStrength: String, CaseIterable, Sendable {
    case off
    case subtle
    case strong
}

/// The moments Perch taps the trackpad. The Force Touch trackpad only offers
/// three patterns at one fixed intensity, so "strong" comes from choosing the
/// firmer pattern and from short double taps, not from a louder tap.
/// Only felt while a finger rests on the trackpad.
enum Haptics {
    enum Moment {
        /// The pointer reaches the closed notch.
        case peek
        /// The notch opens.
        case open
        /// The notch closes.
        case close
        /// A tab or control is pressed inside the notch.
        case tap
        /// Something lights the notch up, such as power connecting.
        case event
    }

    static func play(_ moment: Moment, strength: HapticStrength = Preferences.shared.hapticStrength) {
        let taps: [(NSHapticFeedbackManager.FeedbackPattern, Double)]
        switch (strength, moment) {
        case (.off, _): taps = []
        case (.subtle, .peek): taps = [(.alignment, 0)]
        case (.subtle, .open): taps = [(.levelChange, 0)]
        case (.subtle, .close): taps = []
        case (.subtle, .tap): taps = [(.alignment, 0)]
        case (.subtle, .event): taps = [(.levelChange, 0)]
        case (.strong, .peek): taps = [(.levelChange, 0)]
        // A "thunk": the notch lands, then settles.
        case (.strong, .open): taps = [(.levelChange, 0), (.generic, 0.07)]
        case (.strong, .close): taps = [(.alignment, 0)]
        case (.strong, .tap): taps = [(.generic, 0)]
        case (.strong, .event): taps = [(.levelChange, 0)]
        }
        let performer = NSHapticFeedbackManager.defaultPerformer
        for (pattern, delay) in taps {
            if delay == 0 {
                performer.perform(pattern, performanceTime: .now)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    performer.perform(pattern, performanceTime: .now)
                }
            }
        }
    }
}
