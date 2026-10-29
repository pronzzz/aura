import SwiftUI

enum AuraStyle {
    static let gradient = LinearGradient(colors: [Color(red: 0.49, green: 0.36, blue: 1.0),
                                                  Color(red: 0.24, green: 0.77, blue: 1.0),
                                                  Color(red: 0.30, green: 1.0, blue: 0.71)],
                                         startPoint: .leading, endPoint: .trailing)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.06)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
}

/// Rounded translucent card used for every module inside the open notch.
struct NookCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AuraStyle.card)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AuraStyle.cardStroke))
            )
    }
}

/// Circular icon button with a hover highlight.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var diameter: CGFloat = 28
    var tint: Color = .white
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Pill button ("chip") used for presets and suggestions.
struct Chip: View {
    let title: String
    var symbol: String?
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(hovering ? 0.18 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Animated bars that bounce while music plays.
struct SpectrumView: View {
    var color: Color
    var isPlaying: Bool
    var barCount = 4
    var barWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.8) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Double(index) * 1.7
                    let level = isPlaying
                        ? 0.35 + 0.65 * abs(sin(t * (3.1 + Double(index) * 0.9) + phase) * cos(t * 1.3 + phase * 0.5))
                        : 0.22
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth)
                        .scaleEffect(x: 1, y: level, anchor: .center)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isPlaying)
        }
    }
}

/// A small ring gauge (CPU, memory, battery…).
struct RingGauge: View {
    var value: Double
    var symbol: String
    var label: String
    var tint: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, value)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 34, height: 34)
            .animation(.easeInOut(duration: 0.4), value: value)
            Text(label)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AuraStyle.secondary)
                .monospacedDigit()
        }
    }
}

/// Album artwork with a placeholder.
struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [AuraStyle.violet.opacity(0.7), .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// Applies `transform` only when `condition` is true.
    @ViewBuilder func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Snapshot-safe wrappers
// ImageRenderer can't draw AppKit-backed controls, so `--snapshot` swaps in plain views.

/// A text field that renders as plain text in snapshot mode.
struct AuraTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        if Runtime.isSnapshot {
            Text(text.isEmpty ? placeholder : text)
                .foregroundStyle(text.isEmpty ? AuraStyle.tertiary : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
    }
}

/// A scroll view that renders as a clipped stack in snapshot mode.
struct AuraScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder var content: Content

    var body: some View {
        if Runtime.isSnapshot {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: axis == .horizontal ? .topLeading : .top)
                .clipped()
        } else {
            ScrollView(axis, showsIndicators: false) { content }
        }
    }
}
