import AppKit
import ServiceManagement
import SwiftUI

/// Shown once, on the first launch: what Perch is, how to reach it, and the
/// two choices worth making now. Settings › About can show it again.
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private static let shownKey = "welcome.shown"

    var host: ModuleHost?
    private var window: NSWindow?

    func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.shownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        show()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.layoutIfNeeded()
        placeUnderNotch(window)
        window.makeKeyAndOrderFront(nil)
    }

    /// Centred on the notch, hanging just below the menu bar, as if it came
    /// out of the notch. The screen with a notch first; else the main screen.
    private func placeUnderNotch(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            window.center()
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                      y: max(screen.visibleFrame.minY, screen.visibleFrame.maxY - size.height - 8)))
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeView.width, height: WelcomeView.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Perch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(SettingsStyle.background)
        window.contentViewController = NSHostingController(rootView: WelcomeView(host: host))
        // The notch hangs from the top edge; "Get started" or Esc closes the window.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        return window
    }
}

struct WelcomeView: View {
    static let width: CGFloat = 480
    static let height: CGFloat = 660

    let host: ModuleHost?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Bindable private var preferences = Preferences.shared

    private var hud: HUDModule? { host?.module(id: "hud") as? HUDModule }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                NotchPreview(host: host)
                    .padding(.bottom, 26)
                Text("Welcome to Perch")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Your notch, now with something to say.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(SettingsStyle.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 26)
            .background(
                RadialGradient(colors: [SettingsStyle.accent.opacity(0.10), .clear],
                               center: .top, startRadius: 0, endRadius: 260)
            )

            VStack(alignment: .leading, spacing: 18) {
                point("cursorarrow.motionlines", "Rest the pointer on the notch, or click it",
                      "It opens with music, a timer, your batteries, the shelf and a mirror.")
                point("hand.draw", "Swipe over it with two fingers",
                      "Down opens, up closes, sideways skips a song or switches tabs.")
                point("sparkles", "Things come out by themselves",
                      "Music, charging, AirPods, a finished timer, volume, a camera turning on. Also on the lock screen.")
                point("tray.and.arrow.down", "Drag files onto the notch",
                      "They wait on the shelf until you drag them out or AirDrop them.")
            }
            .padding(.horizontal, 36)

            VStack(spacing: 0) {
                SettingRow("Open at login", hint: "Perch starts quietly with your Mac.") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: launchAtLogin) { _, enabled in
                            if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        }
                }
                SettingRow("Volume and brightness", hint: "Let Perch replace the grey pop-up. Needs Accessibility permission.") {
                    if hud?.catchesKeys == true {
                        Label("On", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsStyle.accent)
                    } else {
                        Button("Allow…") { hud?.requestKeyAccess() }
                            .controlSize(.small)
                    }
                }
                SettingRow("Equalizer", hint: preferences.musicVisualizer == .live
                           ? "Moves with what you hear. macOS asks once to share system audio; nothing is recorded."
                           : "Dances while music plays. Live follows the real sound.", last: true) {
                    ChipPicker(selection: $preferences.musicVisualizer, options: [
                        (.animated, "Animated"),
                        (.live, "Live"),
                    ])
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 22)

            Spacer(minLength: 16)

            Button {
                WelcomeWindowController.shared.close()
            } label: {
                Text("Get started")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 200, height: 38)
                    .background(Capsule().fill(SettingsStyle.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 30)
            Button("") { WelcomeWindowController.shared.close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .frame(width: Self.width, height: Self.height)
        .background(SettingsStyle.background)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SettingsStyle.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
