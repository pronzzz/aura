import AppKit
import Combine
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case file, text, image, link
    }

    var id = UUID()
    var kind: Kind
    /// File path for `.file` and `.image` (images are saved into Aura's tray folder).
    var path: String?
    /// Text content for `.text`, absolute string for `.link`.
    var text: String?
    var name: String
    var added = Date()

    var fileURL: URL? { path.map { URL(fileURLWithPath: $0) } }
    var linkURL: URL? { kind == .link ? text.flatMap(URL.init(string:)) : nil }

    /// Anything shareable (AirDrop etc.).
    var shareable: Any? {
        switch kind {
        case .file, .image: return fileURL
        case .link: return linkURL
        case .text: return text
        }
    }
}

/// A shelf for files, images, links and snippets dropped onto the notch. Survives restarts.
@MainActor
final class TrayStore: ObservableObject {
    static let shared = TrayStore()

    @Published private(set) var items: [TrayItem] = [] { didSet { persist() } }

    let folder: URL
    private let maxItems = 40
    private var indexURL: URL { folder.appendingPathComponent("tray.json") }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("Aura/Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .utf8PlainText, .plainText, .text]

    // MARK: - Adding

    @discardableResult
    func add(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { TrayStore.shared.addURL(url) } }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { TrayStore.shared.addURL(url) } }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { TrayStore.shared.addImage(image) } }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { TrayStore.shared.addText(text) } }
                }
            }
        }
        return handled
    }

    func addURL(_ url: URL) {
        if url.isFileURL {
            addFiles([url])
        } else {
            insert(TrayItem(kind: .link, text: url.absoluteString, name: url.host ?? url.absoluteString))
        }
    }

    func addFiles(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.path == url.path }) {
            insert(TrayItem(kind: .file, path: url.path, name: url.lastPathComponent))
        }
    }

    func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), !trimmed.contains(" ") {
            addURL(url)
            return
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        insert(TrayItem(kind: .text, text: trimmed, name: String(firstLine.prefix(40))))
    }

    func addImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Image \(formatter.string(from: Date())).png"
        let url = folder.appendingPathComponent(name)
        do {
            try png.write(to: url)
            insert(TrayItem(kind: .image, path: url.path, name: name))
        } catch {
            NSLog("Aura: could not save tray image: \(error.localizedDescription)")
        }
    }

    /// Adds whatever is on the general clipboard.
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addFiles(urls)
        } else if let image = NSImage(pasteboard: pasteboard), pasteboard.types?.contains(.string) != true {
            addImage(image)
        } else if let text = pasteboard.string(forType: .string) {
            addText(text)
        }
    }

    private func insert(_ item: TrayItem) {
        items.insert(item, at: 0)
        while items.count > maxItems { remove(items[items.count - 1]) }
    }

    // MARK: - Actions

    func remove(_ item: TrayItem) {
        if item.kind == .image, let url = item.fileURL, url.path.hasPrefix(folder.path) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
    }

    func clear() { items.forEach(remove) }

    func open(_ item: TrayItem) {
        switch item.kind {
        case .file, .image: if let url = item.fileURL { NSWorkspace.shared.open(url) }
        case .link: if let url = item.linkURL { NSWorkspace.shared.open(url) }
        case .text: copy(item)
        }
    }

    func reveal(_ item: TrayItem) {
        if let url = item.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func copy(_ item: TrayItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .file, .image: if let url = item.fileURL { pasteboard.writeObjects([url as NSURL]) }
        case .link, .text: pasteboard.setString(item.text ?? "", forType: .string)
        }
    }

    func airDrop(_ items: [TrayItem]) {
        let payload = items.compactMap(\.shareable)
        guard !payload.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: payload)
    }

    func airDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
        }
    }

    func dragProvider(for item: TrayItem) -> NSItemProvider {
        switch item.kind {
        case .file, .image:
            if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
            return NSItemProvider()
        case .link:
            return item.linkURL.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        }
    }

    func icon(for item: TrayItem) -> NSImage {
        switch item.kind {
        case .image:
            if let url = item.fileURL, let image = NSImage(contentsOf: url) { return image }
            return NSWorkspace.shared.icon(for: .png)
        case .file:
            return item.fileURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .data)
        case .link:
            return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        case .text:
            return NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
        }
    }

    func applyDemo(_ demo: [TrayItem]) { items = demo }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([TrayItem].self, from: data) else { return }
        // Drop entries whose files were moved or deleted.
        items = saved.filter { item in
            guard let path = item.path else { return true }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    private func persist() {
        guard !Runtime.isSnapshot else { return }
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
