import SwiftUI

/// Fills the (fixed-size) panel and pins the animated notch to the top centre.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            NotchBody(viewModel: viewModel)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

struct NotchBody: View {
    @ObservedObject var viewModel: NotchViewModel

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        let size = viewModel.shapeSize
        let shape = NotchShape(topRadius: viewModel.topRadius, bottomRadius: viewModel.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(viewModel.phase == .closed ? 0 : 0.5),
                        radius: viewModel.phase == .open ? 22 : 10, y: viewModel.phase == .open ? 10 : 4)

            content
                .padding(.horizontal, viewModel.topRadius)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .opacity(viewModel.isInvisible ? 0 : 1)
        .contentShape(shape)
        .animation(spring, value: size)
        .animation(spring, value: viewModel.phase)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isInvisible)
        .if(!Runtime.isSnapshot) { view in
            view.onDrop(of: TrayStore.acceptedTypes, isTargeted: nil) { providers in
                TrayStore.shared.add(providers: providers)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .closed:
            ClosedActivityView(viewModel: viewModel)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
                .contentShape(Rectangle())
                .onTapGesture { viewModel.open() }
        case .peek:
            PeekView(viewModel: viewModel)
                .transition(.blurReplace)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.open() }
        case .open:
            OpenNotchView(viewModel: viewModel)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .top)))
        }
    }
}

// MARK: - Closed: live activity wings

struct ClosedActivityView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            ActivityWing(kind: viewModel.activity, side: .leading, height: viewModel.notchHeight)
                .frame(width: viewModel.wingWidth)
            Spacer(minLength: viewModel.notchWidth)
            ActivityWing(kind: viewModel.activity, side: .trailing, height: viewModel.notchHeight)
                .frame(width: viewModel.wingWidth)
        }
        .frame(height: viewModel.notchHeight)
    }
}

/// One side of a live activity. Leading shows the "what", trailing the "how much".
struct ActivityWing: View {
    enum Side { case leading, trailing }

    let kind: LiveActivityKind?
    let side: Side
    let height: CGFloat

    @ObservedObject private var media = NowPlayingService.shared
    @ObservedObject private var power = PowerService.shared
    @ObservedObject private var timers = TimerService.shared
    @AppStorage(Pref.Key.colorfulSpectrum.rawValue) private var colorful = true

    var body: some View {
        Group {
            switch (kind, side) {
            case (.music?, .leading):
                ArtworkView(image: media.artwork, size: height - 12, radius: 6)
                    .opacity(media.isPlaying ? 1 : 0.55)
            case (.music?, .trailing):
                SpectrumView(color: colorful ? Color(nsColor: media.accent) : .white, isPlaying: media.isPlaying,
                             barCount: 4, barWidth: 2.6)
                    .frame(width: 18, height: height * 0.42)
            case (.charging?, .leading):
                Image(systemName: "bolt.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
            case (.charging?, .trailing):
                batteryLabel(color: .green)
            case (.lowBattery?, .leading):
                Image(systemName: "battery.25").font(.system(size: 13, weight: .bold)).foregroundStyle(.red)
            case (.lowBattery?, .trailing):
                batteryLabel(color: .red)
            case (.timer?, .leading):
                timerRing
            case (.timer?, .trailing):
                if let timer = timers.primary {
                    Text(TimerService.format(timer.remaining(at: timers.now)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            default:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func batteryLabel(color: Color) -> some View {
        Text("\(power.level)%")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var timerRing: some View {
        let progress = timers.primary?.progress(at: timers.now) ?? 0
        return ZStack {
            Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: 1 - progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: height * 0.48, height: height * 0.48)
    }
}

// MARK: - Peek

struct PeekView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Music peeks show the artwork below, so keep the wings empty to avoid repeating it.
            if viewModel.peek?.artwork == nil {
                ClosedActivityView(viewModel: viewModel)
            } else {
                Color.clear.frame(height: viewModel.notchHeight)
            }
            if let peek = viewModel.peek {
                HStack(spacing: 10) {
                    if let artwork = peek.artwork {
                        ArtworkView(image: artwork, size: 30, radius: 7)
                    } else {
                        Image(systemName: peek.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(peek.tint)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(peek.tint.opacity(0.16)))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(peek.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(peek.subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AuraStyle.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if peek.kind == .music {
                        SpectrumView(color: peek.tint, isPlaying: true, barCount: 4, barWidth: 2.6)
                            .frame(width: 18, height: 14)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .id(peek.id)
            }
        }
    }
}
