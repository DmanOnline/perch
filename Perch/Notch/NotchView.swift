import SwiftUI

struct NotchView: View {
    let model: NotchModel

    private var state: NotchState { model.state }
    private var ear: CGFloat { NotchMetrics.earRadius(for: state) }

    var body: some View {
        let body = model.bodySize
        let shape = NotchShape(earRadius: ear, bottomRadius: NotchMetrics.bottomRadius(for: state))
        ZStack(alignment: .top) {
            shape.fill(.black)
            content
                .padding(.horizontal, ear)
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
        case .closed:
            Color.clear
        case .compact:
            if let activity = model.host.current, let module = model.host.module(id: activity.moduleID) {
                HStack(spacing: 0) {
                    module.compactLeading()
                        .frame(width: NotchMetrics.compactWingWidth)
                    Spacer(minLength: model.geometry.notchSize.width)
                    module.compactTrailing()
                        .frame(width: NotchMetrics.compactWingWidth)
                }
                .frame(height: model.geometry.notchSize.height)
                .transition(.opacity)
            }
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

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(model.host.modules, id: \.id) { module in
                Button {
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
