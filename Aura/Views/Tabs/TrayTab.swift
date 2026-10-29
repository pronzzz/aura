import SwiftUI
import UniformTypeIdentifiers

struct TrayTab: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var tray = TrayStore.shared
    @State private var trayTargeted = false
    @State private var airDropTargeted = false

    var body: some View {
        Group {
            if viewModel.isDragTargeting || trayTargeted || airDropTargeted {
                dropTargets
            } else if tray.items.isEmpty {
                emptyState
            } else {
                shelf
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isDragTargeting)
    }

    // MARK: Drop targets (shown while dragging)

    private var dropTargets: some View {
        HStack(spacing: 10) {
            DropZone(symbol: "tray.and.arrow.down.fill", title: "Keep in Tray", subtitle: "Files, images, links and text",
                     tint: AuraStyle.violet, targeted: trayTargeted)
                .onDrop(of: TrayStore.acceptedTypes, isTargeted: $trayTargeted) { providers in
                    tray.add(providers: providers)
                }
            DropZone(symbol: "dot.radiowaves.left.and.right", title: "AirDrop", subtitle: "Send files to a nearby device",
                     tint: .cyan, targeted: airDropTargeted)
                .onDrop(of: [.fileURL], isTargeted: $airDropTargeted) { providers in
                    tray.airDrop(providers: providers)
                    return true
                }
                .frame(width: 200)
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(Color.white.opacity(0.2))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AuraStyle.gradient)
                    Text("Drop files, images, links or text here")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("They stay in the Tray until you drag them out — even after a restart.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AuraStyle.secondary)
                    Chip(title: "Paste from Clipboard", symbol: "doc.on.clipboard") { tray.pasteFromClipboard() }
                        .padding(.top, 4)
                }
            )
            .if(!Runtime.isSnapshot) { view in
                view.onDrop(of: TrayStore.acceptedTypes, isTargeted: $trayTargeted) { providers in
                    tray.add(providers: providers)
                }
            }
    }

    // MARK: Shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(tray.items.count) item\(tray.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AuraStyle.secondary)
                Text("Drag out to use · right-click for more")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AuraStyle.tertiary)
                Spacer()
                Chip(title: "Paste", symbol: "doc.on.clipboard") { tray.pasteFromClipboard() }
                Chip(title: "AirDrop All", symbol: "dot.radiowaves.left.and.right") { tray.airDrop(tray.items) }
                Chip(title: "Clear", symbol: "trash") { withAnimation { tray.clear() } }
            }
            AuraScroll(axis: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(tray.items) { item in
                        TrayTile(item: item)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
            }
            .if(!Runtime.isSnapshot) { view in
                view.onDrop(of: TrayStore.acceptedTypes, isTargeted: $trayTargeted) { providers in
                    tray.add(providers: providers)
                }
            }
        }
    }
}

private struct DropZone: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    let targeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(tint.opacity(targeted ? 0.28 : 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(targeted ? 0.9 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            )
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                    Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(AuraStyle.secondary)
                }
            )
            .scaleEffect(targeted ? 1.02 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
    }
}

private struct TrayTile: View {
    let item: TrayItem
    @ObservedObject private var tray = TrayStore.shared
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                preview
                    .frame(width: 64, height: 64)
                if hovering {
                    Button { withAnimation { tray.remove(item) } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            Text(item.name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 78)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0)))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { tray.open(item) }
        .if(!Runtime.isSnapshot) { view in
            view
                .onDrag { tray.dragProvider(for: item) }
                .contextMenu {
                    Button("Open") { tray.open(item) }
                    if item.fileURL != nil { Button("Show in Finder") { tray.reveal(item) } }
                    Button("Copy") { tray.copy(item) }
                    Button("AirDrop") { tray.airDrop([item]) }
                    Divider()
                    Button("Remove from Tray", role: .destructive) { tray.remove(item) }
                }
        }
        .help(item.text ?? item.path ?? item.name)
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image:
            Image(nsImage: tray.icon(for: item))
                .resizable().aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .file:
            Image(nsImage: tray.icon(for: item)).resizable().aspectRatio(contentMode: .fit)
        case .text, .link:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: item.kind == .link ? "link" : "text.quote").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(item.kind == .link ? .cyan : AuraStyle.violet)
                        Text(item.text ?? "")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(AuraStyle.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 4)
                    }
                )
        }
    }
}
