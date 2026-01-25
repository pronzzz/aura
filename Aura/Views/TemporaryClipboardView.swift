import SwiftUI

/// View showing temporary clipboard items in the notch
struct TemporaryClipboardView: View {
    @ObservedObject var clipboardManager = TemporaryClipboardManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !clipboardManager.items.isEmpty {
                // Header
                HStack {
                    Image(systemName: "tray.fill")
                        .font(.caption)
                    Text("Temporary Clips")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button(action: { clipboardManager.clearAll() }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(themeManager.widgetBackground.opacity(0.5))
                
                Divider()
                
                // Items
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clipboardManager.items) { item in
                            ClipboardItemCard(item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 120)
            }
        }
        .background(themeManager.backgroundColor)
        .foregroundColor(themeManager.textColor)
    }
}

struct ClipboardItemCard: View {
    let item: TemporaryClipboardManager.ClipboardItem
    @ObservedObject var clipboardManager = TemporaryClipboardManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon and type
            HStack {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Spacer()
                
                Button(action: { clipboardManager.removeItem(item.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            
            // Preview content
            Group {
                switch item.content {
                case .text(let text):
                    Text(text)
                        .font(.caption)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 100, maxHeight: 60)
                        .cornerRadius(4)
                    
                case .file(let url):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(2)
                        Text(url.pathExtension.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                case .color(let color):
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: color))
                        .frame(width: 60, height: 40)
                }
            }
            
            // Actions
            HStack(spacing: 4) {
                Button(action: { clipboardManager.copyToPasteboard(item) }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                
                Button(action: { clipboardManager.quickUse(item) }) {
                    Image(systemName: "arrow.down.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Quick paste")
            }
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(10)
        .frame(width: 140)
        .background(themeManager.widgetBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
    }
}

/// Drop zone overlay for the notch
struct NotchDropZone: View {
    @ObservedObject var clipboardManager = TemporaryClipboardManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Invisible but active drop zone
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Visual feedback when dragging
                if clipboardManager.isReceivingDrag {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                        .foregroundColor(.accentColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.largeTitle)
                                    .foregroundColor(.accentColor)
                                Text("Drop to Save Temporarily")
                                    .font(.headline)
                            }
                        )
                        .padding(8)
                }
            }
        }
        .onDrop(of: [.plainText, .image, .fileURL], isTargeted: $clipboardManager.isReceivingDrag) { providers in
            clipboardManager.handleDropProviders(providers)
            return true
        }
    }
}

#Preview {
    VStack {
        TemporaryClipboardView()
        NotchDropZone()
            .frame(width: 300, height: 200)
    }
    .background(Color.black)
}
