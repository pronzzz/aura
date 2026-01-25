import SwiftUI

/// Container view that renders widgets in a horizontal layout
struct WidgetContainer: View {
    @ObservedObject var widgetManager = WidgetManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    let isExpanded: Bool
    
    var body: some View {
        HStack(spacing: isExpanded ? 12 : 8) {
            ForEach(widgetManager.activeWidgets) { widget in
                WidgetView(widget: widget, showExpanded: isExpanded)
            }
        }
    }
}

/// Individual widget view wrapper
struct WidgetView: View {
    let widget: AnyAuraWidget
    let showExpanded: Bool
    @StateObject private var themeManager = ThemeManager.shared
    
    private var displaySize: WidgetSize {
        showExpanded ? widget.size : .small
    }
    
    var body: some View {
        widget.body(for: displaySize)
            .onAppear { widget.onAppear() }
            .onDisappear { widget.onDisappear() }
    }
}

// MARK: - Base Widget View Components

/// Standard widget background
struct WidgetBackground: View {
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(themeManager.widgetBackground)
    }
}

/// Widget with icon and optional label
struct IconWidget: View {
    let icon: String
    let label: String?
    let value: String?
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    init(icon: String, label: String? = nil, value: String? = nil, size: WidgetSize = .small) {
        self.icon = icon
        self.label = label
        self.value = value
        self.size = size
    }
    
    var body: some View {
        Group {
            switch size {
            case .small:
                smallView
            case .medium:
                mediumView
            case .expanded:
                expandedView
            }
        }
        .foregroundColor(themeManager.textColor)
    }
    
    private var smallView: some View {
        Image(systemName: icon)
            .font(.system(size: 14))
    }
    
    private var mediumView: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 16))
            if let label = label {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
    }
    
    private var expandedView: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                if let label = label {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                }
                if let value = value {
                    Text(value)
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WidgetBackground())
    }
}

#Preview("WidgetContainer") {
    VStack(spacing: 20) {
        WidgetContainer(isExpanded: false)
            .padding()
            .background(Color.black)
        
        WidgetContainer(isExpanded: true)
            .padding()
            .background(Color.black)
    }
}
