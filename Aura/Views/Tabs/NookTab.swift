import SwiftUI

struct NookTab: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            MediaCard()
                .frame(width: 300)
            if viewModel.showMirror {
                MirrorCard(viewModel: viewModel)
            } else {
                CalendarCard()
            }
            QuickCard(viewModel: viewModel)
                .frame(width: 128)
        }
    }
}

// MARK: - Media

struct MediaCard: View {
    @ObservedObject private var media = NowPlayingService.shared
    @AppStorage(Pref.Key.colorfulSpectrum.rawValue) private var colorful = true

    var body: some View {
        NookCard {
            if let track = media.track {
                player(track)
            } else {
                empty
            }
        }
    }

    private func player(_ track: NowPlayingTrack) -> some View {
        let accent = colorful ? Color(nsColor: media.accent) : .white
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { media.openSourceApp() } label: {
                    ArtworkView(image: media.artwork, size: 66, radius: 12)
                        .shadow(color: accent.opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .help("Open \(media.source.displayName)")

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(media.source.displayName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(AuraStyle.tertiary)
                        Spacer(minLength: 0)
                        SpectrumView(color: accent, isPlaying: media.isPlaying, barCount: 4, barWidth: 2.4)
                            .frame(width: 16, height: 12)
                    }
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AuraStyle.secondary)
                        .lineLimit(1)
                }
            }

            Scrubber(accent: accent)

            HStack(spacing: 18) {
                Spacer()
                IconButton(symbol: "backward.fill", size: 15, diameter: 32, help: "Previous") { media.previous() }
                IconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 20, diameter: 38, help: "Play/Pause") {
                    media.togglePlayPause()
                }
                IconButton(symbol: "forward.fill", size: 15, diameter: 32, help: "Next") { media.next() }
                Spacer()
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: nil, size: 66, radius: 12).opacity(0.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing playing")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Play something in Music or Spotify")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(AuraStyle.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if NowPlayingService.isInstalled(.music) {
                    Chip(title: "Open Music", symbol: "music.note") { media.launch(.music) }
                }
                if NowPlayingService.isInstalled(.spotify) {
                    Chip(title: "Open Spotify", symbol: "headphones") { media.launch(.spotify) }
                }
            }
        }
    }
}

/// Progress bar with elapsed/remaining time. Drag or click to seek.
struct Scrubber: View {
    var accent: Color
    @ObservedObject private var media = NowPlayingService.shared
    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = max(media.duration, 0)
            let position = dragValue ?? media.position
            let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0

            HStack(spacing: 8) {
                Text(Self.format(position))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(accent).frame(width: max(4, geo.size.width * fraction))
                    }
                    .frame(height: hovering || dragValue != nil ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                dragValue = Double(min(max(0, value.location.x / geo.size.width), 1)) * duration
                            }
                            .onEnded { _ in
                                if let target = dragValue { media.seek(to: target) }
                                dragValue = nil
                            }
                    )
                }
                .frame(height: 12)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                Text(duration > 0 ? "-" + Self.format(max(0, duration - position)) : "--:--")
            }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AuraStyle.secondary)
            .opacity(duration > 0 ? 1 : 0.4)
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Calendar

struct CalendarCard: View {
    @ObservedObject private var calendar = CalendarService.shared

    var body: some View {
        NookCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Date(), format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .textCase(.uppercase)
                    Text(Date(), format: .dateTime.day())
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Spacer()
                    IconButton(symbol: "calendar", size: 11, diameter: 22, tint: AuraStyle.secondary, help: "Open Calendar") {
                        calendar.openCalendarApp()
                    }
                }

                if !calendar.isAuthorized {
                    Spacer(minLength: 0)
                    Text("See upcoming events and join meetings from the notch.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AuraStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Chip(title: "Connect Calendar", symbol: "calendar.badge.plus", prominent: true) {
                        Task { await calendar.requestAccess() }
                    }
                } else if calendar.events.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "sun.max.fill").font(.system(size: 18)).foregroundStyle(.yellow)
                            Text("Nothing scheduled").font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AuraStyle.secondary)
                        }
                        Spacer()
                    }
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendar.events.prefix(3)) { event in
                            EventRow(event: event)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(Calendar.current.isDateInToday(event.start) || event.isHappeningNow
                     ? event.relativeDescription
                     : "Tomorrow · " + event.timeDescription)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(event.isHappeningNow ? Color(nsColor: event.color) : AuraStyle.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                Chip(title: "Join", symbol: "video.fill", prominent: true) { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: - Mirror

struct MirrorCard: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var camera = CameraService.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if camera.authorization == .authorized {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                NookCard {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill").font(.system(size: 20)).foregroundStyle(AuraStyle.secondary)
                        Text(camera.authorization == .notDetermined ? "Allow camera access to use Mirror" : "Camera access is off. Enable it in System Settings → Privacy.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AuraStyle.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            IconButton(symbol: "xmark", size: 10, diameter: 22, help: "Close Mirror") {
                viewModel.showMirror = false
            }
            .background(Circle().fill(.black.opacity(0.45)))
            .padding(6)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Quick column

struct QuickCard: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var stats = SystemStatsService.shared
    @ObservedObject private var power = PowerService.shared
    @ObservedObject private var shortcuts = ShortcutsService.shared

    var body: some View {
        NookCard(padding: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    RingGauge(value: stats.cpu, symbol: "cpu", label: "\(Int(stats.cpu * 100))%", tint: .cyan)
                    RingGauge(value: stats.memory, symbol: "memorychip", label: "\(Int(stats.memory * 100))%", tint: AuraStyle.violet)
                }
                VStack(spacing: 5) {
                    QuickAction(symbol: viewModel.showMirror ? "calendar" : "person.crop.square", title: viewModel.showMirror ? "Calendar" : "Mirror") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { viewModel.showMirror.toggle() }
                    }
                    ForEach(shortcuts.favorites.prefix(viewModel.showMirror ? 1 : 2), id: \.self) { name in
                        QuickAction(symbol: "square.stack.3d.up.fill", title: name) { shortcuts.run(name) }
                    }
                    if shortcuts.favorites.isEmpty {
                        QuickAction(symbol: "plus", title: "Shortcuts") {
                            viewModel.close()
                            SettingsWindowController.shared.show(section: .shortcuts)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { stats.acquire() }
        .onDisappear { stats.release() }
    }
}

private struct QuickAction: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 14)
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}
