import SwiftUI

struct NotchView: View {
    let model: NotchModel

    private var state: NotchState { model.state }
    private var ear: CGFloat { NotchMetrics.earRadius(for: state) }
    private var currentModule: (any PerchModule)? {
        model.host.current.flatMap { model.host.module(id: $0.moduleID) }
    }

    var body: some View {
        let body = model.bodySize
        let shape = NotchShape(earRadius: ear, bottomRadius: NotchMetrics.bottomRadius(for: state))
        ZStack(alignment: .top) {
            shape.fill(.black)
            wings
                .padding(.horizontal, ear)
            content
                .padding(.horizontal, ear)
            if state == .compact, let overlay = currentModule?.compactOverlay() {
                overlay
                    .frame(height: model.geometry.notchSize.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: body.width + 2 * ear, height: body.height)
        .clipShape(shape)
        .shadow(color: state == .expanded ? .black.opacity(0.7) : .clear, radius: 6)
        .contentShape(shape)
        .onTapGesture {
            if state != .expanded { model.onRequestOpen?() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: model.host.current)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.isPeeking)
        .animation(state == .expanded ? NotchMetrics.openAnimation : NotchMetrics.closeAnimation, value: state)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .closed, .compact:
            Color.clear
        case .expanded:
            VStack(spacing: 0) {
                header
                    .frame(height: model.geometry.notchSize.height)
                if let module = model.expandedModule {
                    module.expanded()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .id(module.id)
                }
            }
            .transition(AnyTransition(.blurReplace).combined(with: .scale(scale: 0.94, anchor: .top)))
        }
    }

    /// The compact wings. Each side slides out from under the notch as the
    /// notch widens, and slides back under it as the notch folds in, so the
    /// content always looks like it comes from, and returns to, the notch.
    private var wings: some View {
        let module = state == .compact ? currentModule : nil
        return HStack(spacing: 0) {
            ZStack {
                if let module {
                    module.compactLeading()
                        .id(module.id)
                        .transition(.tucked(under: .trailing))
                }
            }
            .frame(width: NotchMetrics.compactWingWidth)
            Spacer(minLength: model.geometry.notchSize.width)
            ZStack {
                if let module {
                    module.compactTrailing()
                        .id(module.id)
                        .transition(.tucked(under: .leading))
                }
            }
            .frame(width: NotchMetrics.compactWingWidth)
        }
        .frame(height: model.geometry.notchSize.height)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(model.host.enabledModules, id: \.id) { module in
                Button {
                    Haptics.play(.tap)
                    model.selectedModuleID = module.id
                } label: {
                    Image(systemName: module.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 22)
                        .background(
                            Capsule().fill(model.expandedModule?.id == module.id ? Color.white.opacity(0.14) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(module.title)
            }
            Spacer(minLength: model.geometry.notchSize.width)
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("Perch Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("Quit Perch")
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 16)
    }
}


private struct Tucked: ViewModifier {
    /// The side the notch is on, as seen from the wing.
    let edge: HorizontalEdge
    let isTucked: Bool

    func body(content: Content) -> some View {
        let distance = NotchMetrics.compactWingWidth * 0.85
        content
            .offset(x: isTucked ? (edge == .trailing ? distance : -distance) : 0)
            .scaleEffect(isTucked ? 0.8 : 1)
            .blur(radius: isTucked ? 3 : 0)
            .opacity(isTucked ? 0 : 1)
    }
}

private extension AnyTransition {
    /// In from under the notch, and back under it on the way out.
    static func tucked(under edge: HorizontalEdge) -> AnyTransition {
        .modifier(active: Tucked(edge: edge, isTucked: true), identity: Tucked(edge: edge, isTucked: false))
    }
}
