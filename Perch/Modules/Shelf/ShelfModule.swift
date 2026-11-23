import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A place to park files: drag them onto the notch, drag them out later,
/// or send them all with AirDrop. Files stay where they are; the shelf keeps
/// bookmarks, so a file that is renamed or moved is still found.
@Observable
final class ShelfModule: PerchModule {
    static let maxItems = 24

    let id = "shelf"
    let title = "Shelf"
    let summary = "Drop files on the notch to park them; drag them out or AirDrop them later."
    var symbol: String { items.isEmpty ? "tray" : "tray.full.fill" }

    private(set) var items: [URL] = []
    private(set) var activity: Activity?

    private static let storageKey = "shelf.bookmarks"

    func start() {
        let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [Data] ?? []
        items = stored.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return url
        }
    }

    func stop() {}

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in !items.contains { $0.standardizedFileURL == url.standardizedFileURL } }
        guard !fresh.isEmpty else { return }
        items = Array((items + fresh).suffix(Self.maxItems))
        Haptics.play(.tap)
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items)
    }

    private func save() {
        let bookmarks = items.compactMap { try? $0.bookmarkData() }
        UserDefaults.standard.set(bookmarks, forKey: Self.storageKey)
    }

    // MARK: Views

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }

    func expanded() -> AnyView {
        AnyView(ShelfView(module: self))
    }
}

private struct ShelfView: View {
    let module: ShelfModule

    var body: some View {
        if module.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 26, weight: .regular))
                Text("Drop files here to keep them close")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        } else {
            HStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(module.items, id: \.self) { url in
                            ShelfTile(url: url) { module.remove(url) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                VStack(spacing: 10) {
                    action("airplayaudio", label: "AirDrop", symbolOverride: "dot.radiowaves.up.forward") { module.airDrop() }
                    action("trash", label: "Clear") { module.clear() }
                }
            }
        }
    }

    private func action(_ symbol: String, label: String, symbolOverride: String? = nil,
                        perform: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            perform()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbolOverride ?? symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.12)))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// One file: its Finder icon and name. Drag it out to use it, double-click
/// to open, right-click for more.
private struct ShelfTile: View {
    let url: URL
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isHovered ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from Shelf", action: onRemove)
        }
        .help(url.path(percentEncoded: false))
    }
}
