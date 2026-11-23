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
        HStack(spacing: 0) {
            ForEach(model.host.enabledModules, id: \.id) { module in
                HeaderButton(symbol: module.symbol, size: 12,
                             isSelected: model.expandedModule?.id == module.id, help: module.title) {
                    model.selectedModuleID = module.id
                }
            }
            Spacer(minLength: model.geometry.notchSize.width)
            HeaderButton(symbol: "gearshape.fill", size: 11, help: "Perch Settings") {
                SettingsWindowController.shared.show()
            }
            HeaderButton(symbol: "power", size: 11, help: "Quit Perch") {
                NSApp.terminate(nil)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
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

/// An icon button in the notch header. The capsule you see is small, but the
/// whole padded square around it takes the click, and it lights up on hover
/// so you can tell you are on it.
private struct HeaderButton: View {
    let symbol: String
    let size: CGFloat
    var isSelected = false
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 24)
                .background(
                    Capsule().fill(.white.opacity(isSelected ? 0.14 : isHovered ? 0.08 : 0))
                )
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(help)
    }
}
