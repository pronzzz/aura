import AppKit
import ImageIO
import SwiftUI

/// Renders the notch in each state with demo data: `Aura --snapshot <folder>`.
/// Used to produce the README screenshots and to eyeball layout changes without a notch.
@MainActor
enum SnapshotRenderer {
    static func renderAll(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        seedDemoData()

        let geometry = NotchGeometry.preview
        let cases: [(String, Bool, NotchTab, LiveActivityKind?, Peek?)] = [
            ("closed-music", false, .nook, .music, nil),
            ("closed-timer", false, .nook, .timer, nil),
            ("closed-charging", false, .nook, .charging, nil),
            ("peek-music", false, .nook, .music, Peek(kind: .music, title: "Midnight City", subtitle: "M83",
                                                     icon: "music.note", tint: .pink, artwork: demoArtwork)),
            ("open-nook", true, .nook, .music, nil),
            ("open-tray", true, .tray, .music, nil),
            ("open-tasks", true, .tasks, .timer, nil),
            ("open-ask", true, .ask, .music, nil),
        ]

        for (name, open, tab, activity, peek) in cases {
            let viewModel = NotchViewModel(geometry: geometry, observeCenter: false)
            viewModel.configureForPreview(open: open, tab: tab, activity: activity, peek: peek)
            let size = viewModel.shapeSize
            let canvas = CGSize(width: max(size.width + 120, 820), height: size.height + 70)

            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.32), Color(red: 0.05, green: 0.18, blue: 0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: geometry.notchSize.height)
                NotchBody(viewModel: viewModel)
            }
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            renderer.colorMode = .nonLinear
            if let image = renderer.cgImage, writePNG(image, to: folder.appendingPathComponent("\(name).png")) {
                print("wrote \(name).png")
            }
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        // Convert to sRGB so wide-gamut content (app icons) doesn't wash out the file.
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, converted, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static var demoArtwork: NSImage = {
        let size = NSSize(width: 300, height: 300)
        return NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.95, green: 0.3, blue: 0.55, alpha: 1),
                                               NSColor(calibratedRed: 0.35, green: 0.2, blue: 0.85, alpha: 1)])
            gradient?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 95, dy: 95)).fill()
            return true
        }
    }()

    private static func seedDemoData() {
        NowPlayingService.shared.applyDemo(track: NowPlayingTrack(title: "Midnight City", artist: "M83",
                                                                  album: "Hurry Up, We're Dreaming", duration: 244),
                                           playing: true, position: 86, artwork: demoArtwork, source: .spotify)
        let now = Date()
        let tomorrowMorning = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
            .addingTimeInterval(7.5 * 3600)
        CalendarService.shared.applyDemo([
            CalendarEvent(id: "1", title: "Design review", start: now.addingTimeInterval(14 * 60), end: now.addingTimeInterval(44 * 60),
                          isAllDay: false, color: .systemPurple, location: nil, meetingURL: URL(string: "https://meet.google.com/abc")),
            CalendarEvent(id: "2", title: "1:1 with Sam", start: now.addingTimeInterval(75 * 60), end: now.addingTimeInterval(105 * 60),
                          isAllDay: false, color: .systemTeal, location: nil, meetingURL: nil),
            CalendarEvent(id: "3", title: "Gym", start: tomorrowMorning, end: tomorrowMorning.addingTimeInterval(3600),
                          isAllDay: false, color: .systemOrange, location: nil, meetingURL: nil),
        ])
        TimerService.shared.applyDemo([
            AuraTimer(label: "Focus", duration: 1500, endDate: now.addingTimeInterval(1122)),
            AuraTimer(label: "Tea", duration: 240, endDate: nil, pausedRemaining: 95),
        ])
        TodoStore.shared.applyDemo([
            TodoItem(text: "Ship Aura 2.0 release notes"),
            TodoItem(text: "Reply to design feedback"),
            TodoItem(text: "Book flights", isDone: true),
        ])
        SystemStatsService.shared.applyDemo(cpu: 0.23, memory: 0.61)
        TrayStore.shared.applyDemo([
            TrayItem(kind: .link, text: "https://github.com/pronzzz/aura", name: "github.com"),
            TrayItem(kind: .text, text: "Remember: the notch is a canvas.", name: "Remember: the notch is a canvas."),
            TrayItem(kind: .file, path: "/System/Applications/Calendar.app", name: "Calendar.app"),
            TrayItem(kind: .file, path: "/System/Applications/Notes.app", name: "Notes.app"),
        ])
        Assistant.shared.applyDemo([
            Assistant.Entry(role: .user, text: "timer 25m"),
            Assistant.Entry(role: .action, text: "Started a 25:00 focus timer."),
            Assistant.Entry(role: .user, text: "What should I prep before the design review?"),
            Assistant.Entry(role: .assistant, text: "Bring the latest notch mockups, a short list of open questions about the Tray, and two options for the onboarding flow. Keep it to 10 minutes and leave time for feedback."),
        ])
    }
}
