import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Manages temporary storage of dragged items (text, images, files)
class TemporaryClipboardManager: ObservableObject {
    static let shared = TemporaryClipboardManager()
    
    @Published var items: [ClipboardItem] = []
    @Published var isReceivingDrag: Bool = false
    
    private let maxItems = 5
    private let autoDeleteInterval: TimeInterval = 300 // 5 minutes
    
    struct ClipboardItem: Identifiable {
        let id = UUID()
        let content: ContentType
        let timestamp: Date
        var deleteTimer: Timer?
        
        enum ContentType {
            case text(String)
            case image(NSImage)
            case file(URL)
            case color(NSColor)
        }
        
        var preview: String {
            switch content {
            case .text(let text):
                return text.prefix(50) + (text.count > 50 ? "..." : "")
            case .image:
                return "Image"
            case .file(let url):
                return url.lastPathComponent
            case .color:
                return "Color"
            }
        }
        
        var icon: String {
            switch content {
            case .text: return "doc.text"
            case .image: return "photo"
            case .file: return "doc"
            case .color: return "paintpalette"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Adding Items
    
    func addText(_ text: String) {
        guard !text.isEmpty else { return }
        
        let item = ClipboardItem(content: .text(text), timestamp: Date())
        addItem(item)
    }
    
    func addImage(_ image: NSImage) {
        let item = ClipboardItem(content: .image(image), timestamp: Date())
        addItem(item)
    }
    
    func addFile(_ url: URL) {
        let item = ClipboardItem(content: .file(url), timestamp: Date())
        addItem(item)
    }
    
    func addColor(_ color: NSColor) {
        let item = ClipboardItem(content: .color(color), timestamp: Date())
        addItem(item)
    }
    
    private func addItem(_ item: ClipboardItem) {
        // Remove oldest if at max capacity
        if items.count >= maxItems {
            items.removeFirst()
        }
        
        var mutableItem = item
        
        // Setup auto-delete timer
        mutableItem.deleteTimer = Timer.scheduledTimer(withTimeInterval: autoDeleteInterval, repeats: false) { [weak self] _ in
            self?.removeItem(item.id)
        }
        
        items.append(mutableItem)
    }
    
    // MARK: - Drag Handling
    
    func handleDropProviders(_ providers: [NSItemProvider]) {
        isReceivingDrag = false
        
        for provider in providers {
            // Handle text
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, error in
                    if let data = data as? Data, let string = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self?.addText(string)
                        }
                    }
                }
            }
            
            // Handle images
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, error in
                    if let data = data as? Data, let nsImage = NSImage(data: data) {
                        DispatchQueue.main.async {
                            self?.addImage(nsImage)
                        }
                    } else if let url = data as? URL {
                        if let nsImage = NSImage(contentsOf: url) {
                            DispatchQueue.main.async {
                                self?.addImage(nsImage)
                            }
                        }
                    }
                }
            }
            
            // Handle file URLs
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] data, error in
                    if let url = data as? URL {
                        DispatchQueue.main.async {
                            self?.addFile(url)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Removing Items
    
    func removeItem(_ id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].deleteTimer?.invalidate()
            items.remove(at: index)
        }
    }
    
    func clearAll() {
        for item in items {
            item.deleteTimer?.invalidate()
        }
        items.removeAll()
    }
    
    // MARK: - Using Items
    
    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
            
        case .image(let image):
            pasteboard.writeObjects([image])
            
        case .file(let url):
            pasteboard.setString(url.path, forType: .fileURL)
            
        case .color(let color):
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                pasteboard.setData(data, forType: .color)
            }
        }
    }
    
    func quickUse(_ item: ClipboardItem) {
        copyToPasteboard(item)
        
        // Simulate paste (Cmd+V)
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Cmd+V down
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vKeyDown?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)
        
        // Cmd+V up
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vKeyUp?.flags = .maskCommand
        vKeyUp?.post(tap: .cghidEventTap)
    }
}
