import Foundation
import SwiftUI
import AppKit

/// Clipboard history plugin
class ClipboardPlugin: BasePlugin {
    @Published var history: [ClipboardItem] = []
    
    private var lastChangeCount: Int = 0
    private var clipboardTimer: Timer?
    private let maxHistorySize = 20
    
    struct ClipboardItem: Identifiable {
        let id = UUID()
        let content: String
        let timestamp: Date
        let type: ContentType
        
        enum ContentType {
            case text
            case url
            case code
        }
    }
    
    override func load() async throws {
        try await super.load()
        
        // Start monitoring clipboard
        await MainActor.run {
            lastChangeCount = NSPasteboard.general.changeCount
            clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkClipboard()
            }
        }
    }
    
    override func unload() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        super.unload()
    }
    
    override func widgetView(size: WidgetSize) -> AnyView {
        AnyView(ClipboardWidgetView(plugin: self))
    }
    
    override func handleCommand(_ command: String) async -> String? {
        let lowercased = command.lowercased()
        
        if lowercased.contains("clipboard") && lowercased.contains("history") {
            if history.isEmpty {
                return "Clipboard history is empty"
            }
            return "Last \(min(3, history.count)) clips: " + history.prefix(3).map { 
                $0.content.prefix(30) + ($0.content.count > 30 ? "..." : "") 
            }.joined(separator: ", ")
        }
        
        if lowercased.contains("paste") && lowercased.contains("last") {
            if let last = history.first {
                await MainActor.run { copyToClipboard(last.content) }
                return "Copied to clipboard: \(last.content.prefix(30))..."
            }
        }
        
        return nil
    }
    
    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            
            if let string = NSPasteboard.general.string(forType: .string) {
                addToHistory(string)
            }
        }
    }
    
    private func addToHistory(_ content: String) {
        // Don't add duplicates
        if history.first?.content == content { return }
        
        // Don't add empty or very short content
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 { return }
        
        let type: ClipboardItem.ContentType
        if content.hasPrefix("http://") || content.hasPrefix("https://") {
            type = .url
        } else if content.contains("{") || content.contains("func ") || content.contains("class ") {
            type = .code
        } else {
            type = .text
        }
        
        let item = ClipboardItem(content: content, timestamp: Date(), type: type)
        history.insert(item, at: 0)
        
        // Trim history
        if history.count > maxHistorySize {
            history.removeLast()
        }
    }
    
    func copyToClipboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    func clearHistory() {
        history.removeAll()
    }
}

struct ClipboardWidgetView: View {
    @ObservedObject var plugin: ClipboardPlugin
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.clipboard")
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                if !plugin.history.isEmpty {
                    Button(action: { plugin.clearHistory() }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if plugin.history.isEmpty {
                Text("No recent clips")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(plugin.history.prefix(10)) { item in
                            ClipboardItemRow(item: item) {
                                plugin.copyToClipboard(item.content)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .foregroundColor(themeManager.textColor)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardPlugin.ClipboardItem
    let onTap: () -> Void
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundColor(iconColor)
                
                Text(item.content)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(timeAgo)
                    .font(.system(size: 9))
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            .padding(6)
            .background(isHovered ? themeManager.widgetBackground : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var iconName: String {
        switch item.type {
        case .text: return "doc.text"
        case .url: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    private var iconColor: Color {
        switch item.type {
        case .text: return .gray
        case .url: return .blue
        case .code: return .orange
        }
    }
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(item.timestamp)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval/60))m"
        } else {
            return "\(Int(interval/3600))h"
        }
    }
}
