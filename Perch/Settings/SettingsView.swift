import ServiceManagement
import SwiftUI

enum SettingsStyle {
    static let background = Color(red: 0.047, green: 0.047, blue: 0.055)
    static let header = Color(red: 0.075, green: 0.075, blue: 0.086)
    static let accent = Color(red: 1.0, green: 0.70, blue: 0.14)
    static let hairline = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.48)
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case modules = "Modules"
    case about = "About"
    var id: Self { self }
}

struct SettingsView: View {
    static let width: CGFloat = 560

    let host: ModuleHost?
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(host: host, tab: $tab)
            ScrollView {
                Group {
                    switch tab {
                    case .general: GeneralPane()
                    case .modules: ModulesPane(host: host)
                    case .about: AboutPane()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.width, height: 560)
        .background(SettingsStyle.background)
        .tint(SettingsStyle.accent)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}

// MARK: - Header

/// A live copy of the notch hangs from the top of the window, showing what
/// the real one shows right now.
private struct SettingsHeader: View {
    let host: ModuleHost?
    @Binding var tab: SettingsTab
    @Namespace private var marker

    var body: some View {
        VStack(spacing: 0) {
            NotchPreview(host: host)
                .padding(.bottom, 22)
            HStack(spacing: 28) {
                ForEach(SettingsTab.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = item }
                    } label: {
                        VStack(spacing: 6) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: tab == item ? .semibold : .medium))
                                .foregroundStyle(tab == item ? .white : SettingsStyle.secondary)
                            ZStack {
                                if tab == item {
                                    Capsule()
                                        .fill(SettingsStyle.accent)
                                        .matchedGeometryEffect(id: "marker", in: marker)
                                }
                            }
                            .frame(width: 18, height: 3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                SettingsStyle.header
                RadialGradient(colors: [SettingsStyle.accent.opacity(0.10), .clear],
                               center: .top, startRadius: 0, endRadius: 260)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(SettingsStyle.hairline).frame(height: 1)
        }
    }
}

private struct NotchPreview: View {
    let host: ModuleHost?

    private let notch = CGSize(width: 186, height: 32)

    var body: some View {
        let activity = host?.current
        let module = activity.flatMap { host?.module(id: $0.moduleID) }
        let width = notch.width + (module == nil ? 0 : 2 * NotchMetrics.compactWingWidth)
        let ear = NotchMetrics.earRadius(for: .compact)
        ZStack {
            NotchShape(earRadius: ear, bottomRadius: NotchMetrics.bottomRadius(for: .compact))
                .fill(.black)
            if let module {
                HStack(spacing: 0) {
                    module.compactLeading().frame(width: NotchMetrics.compactWingWidth)
                    Spacer(minLength: notch.width)
                    module.compactTrailing().frame(width: NotchMetrics.compactWingWidth)
                }
                .padding(.horizontal, ear)
                .transition(.opacity)
            }
        }
        .frame(width: width + 2 * ear, height: notch.height)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: activity?.id)
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable private var preferences = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Startup")
            SettingRow("Open at login", hint: loginError ?? "Perch starts quietly with your Mac.") {
                Toggle("", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            SectionLabel("Opening the notch")
            SettingRow("Open on hover", hint: "Off: rest the pointer to peek, click to open.") {
                Toggle("", isOn: $preferences.openOnHover)
            }
            SettingRow("Hover delay", hint: "How long the pointer rests before the notch opens.",
                       dimmed: !preferences.openOnHover) {
                HStack(spacing: 10) {
                    Slider(value: $preferences.hoverDelay.snapped(to: 0.05), in: 0.05...0.8)
                        .frame(width: 150)
                    Text(String(format: "%.2f s", preferences.hoverDelay))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(SettingsStyle.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!preferences.openOnHover)
            }
            SettingRow("Trackpad feel", hint: hapticHint, last: true) {
                ChipPicker(selection: $preferences.hapticStrength, options: [
                    (.off, "Off"),
                    (.subtle, "Subtle"),
                    (.strong, "Strong"),
                ])
                .onChange(of: preferences.hapticStrength) { _, strength in
                    Haptics.play(.open, strength: strength)
                }
            }

            SectionLabel("At rest")
            SettingRow("Sneak peek", hint: restingHint, last: true) {
                ChipPicker(selection: $preferences.restingModule, options: [
                    ("", "Off"),
                    ("music", "Music"),
                    ("battery", "Battery"),
                ])
            }

            SectionLabel("Displays")
            SettingRow("Hide during full-screen video", hint: "Steps aside while you watch in full screen. Full-screen apps like Claude or Xcode keep the notch.") {
                Toggle("", isOn: $preferences.hideInFullScreen)
            }
            SettingRow("Show Perch on", hint: displayHint, last: true) {
                ChipPicker(selection: $preferences.displayMode, options: [
                    (.notchedScreens, "Notch"),
                    (.mainScreen, "Main"),
                    (.allScreens, "All"),
                ])
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var restingHint: String {
        switch preferences.restingModule {
        case "music": "Artwork stays beside the notch while something is loaded, even paused."
        case "battery": "The battery level stays beside the notch."
        default: "When nothing is happening, the notch is just the notch."
        }
    }

    private var hapticHint: String {
        switch preferences.hapticStrength {
        case .off: "No taps on the trackpad."
        case .subtle: "A light tick when you reach the notch and when it opens."
        case .strong: "A firm tap on reach, a landing thunk on open, and a tap for each pulse of charge."
        }
    }

    private var displayHint: String {
        switch preferences.displayMode {
        case .notchedScreens: "Screens with a notch, or the main screen if none has one."
        case .mainScreen: "Only the screen with the menu bar."
        case .allScreens: "Every screen; those without a notch get a virtual one."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Perch in System Settings › General › Login Items."
                : nil
        } catch {
            loginError = "Could not change this: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Modules

private struct ModulesPane: View {
    let host: ModuleHost?
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Modules")
            Text("Everything in the notch is a module. The one that matters most right now gets the notch; open it to switch between them.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            ForEach(Array((host?.modules ?? []).enumerated()), id: \.element.id) { index, module in
                let enabled = preferences.isEnabled(module.id)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: module.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(enabled ? SettingsStyle.accent : SettingsStyle.secondary)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(module.summary)
                                .font(.system(size: 11.5))
                                .foregroundStyle(SettingsStyle.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { preferences.isEnabled(module.id) },
                            set: { preferences.setEnabled($0, for: module.id) }
                        ))
                    }
                    .padding(.vertical, 12)

                    if enabled, let settings = module.settings() {
                        settings
                            .padding(.leading, 48)
                            .padding(.bottom, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .overlay(alignment: .bottom) {
                    if index < (host?.modules.count ?? 0) - 1 {
                        Rectangle().fill(SettingsStyle.hairline).frame(height: 1)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: enabled)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Perch")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("The open notch for your Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsStyle.secondary)
                Text(version)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(SettingsStyle.secondary)
                    .padding(.top, 6)
            }
            .padding(.top, 14)
            .padding(.bottom, 6)

            SectionLabel("Free software")
            Text("Perch is free software under the GNU General Public License v3. You may use, study, share and change it.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SectionLabel("Thanks to")
            Credit("mediaremote-adapter", "Jonas van den Berg, BSD 3-Clause. Reads what is playing.")
            Credit("boring.notch", "TheBoredTeam, GPL-3. The motion Perch is tuned against.")
            Credit("DynamicNotchKit", "Kai Azim, MIT. The shape of the notch.", last: true)
        }
    }
}

private struct Credit: View {
    let name: String
    let detail: String
    let last: Bool

    init(_ name: String, _ detail: String, last: Bool = false) {
        self.name = name
        self.detail = detail
        self.last = last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 12.5, weight: .semibold))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(SettingsStyle.secondary)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(SettingsStyle.hairline).frame(height: 1) }
        }
    }
}

// MARK: - Building blocks

extension Binding where Value == Double {
    /// Rounds to `step` as the slider moves. `Slider(step:)` would do the same
    /// but draws a row of tick marks under the track.
    func snapped(to step: Double) -> Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = ($0 / step).rounded() * step })
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(SettingsStyle.secondary.opacity(0.8))
            .padding(.top, 24)
            .padding(.bottom, 4)
    }
}

/// One setting: what it is and what it does on the left, the control on the right.
/// Rows are divided by hairlines, not boxed.
struct SettingRow<Control: View>: View {
    let title: String
    let hint: String?
    let dimmed: Bool
    let last: Bool
    let control: Control

    init(_ title: String, hint: String? = nil, dimmed: Bool = false, last: Bool = false,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.hint = hint
        self.dimmed = dimmed
        self.last = last
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
                .labelsHidden()
        }
        .padding(.vertical, 11)
        .opacity(dimmed ? 0.45 : 1)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(SettingsStyle.hairline).frame(height: 1) }
        }
        .animation(.smooth(duration: 0.2), value: dimmed)
    }
}

/// A few mutually exclusive choices as chips, the chosen one lit in the accent.
struct ChipPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var lit

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == value ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background {
                            if selection == value {
                                Capsule().fill(SettingsStyle.accent)
                                    .matchedGeometryEffect(id: "lit", in: lit)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.black))
    }
}
