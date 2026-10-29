import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in
                Pref.set(true, .onboardingDone)
                self?.window?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotchCoordinator.shared.open(tab: .nook)
                }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 640, height: 560))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @ObservedObject private var calendar = CalendarService.shared

    private let features: [(String, String, String, Color)] = [
        ("waveform", "Live Activities", "Album art and a visualizer, charging status and countdowns hug the notch.", .pink),
        ("square.grid.2x2.fill", "The Nook", "Hover the notch for music controls, your next meetings, system stats and a mirror.", .blue),
        ("tray.full.fill", "Tray & AirDrop", "Drag files onto the notch to keep them handy or AirDrop them in one move.", .cyan),
        ("sparkles", "Ask Aura", "Quick commands and a private, on-device assistant through Ollama.", .purple),
        ("bolt.horizontal.fill", "Automation", "“When my battery hits 15%…” — workflows that run on their own.", .orange),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                AuraStyle.gradient.opacity(0.35)
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                    Text("Welcome to Aura").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Your notch is now a live, local-first command center.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 26)
            }
            .frame(height: 190)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(features, id: \.1) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.0)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(feature.3.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.1).font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(feature.2).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 22)

            Spacer(minLength: 12)

            HStack {
                if !calendar.isAuthorized {
                    Button("Connect Calendar") { Task { await calendar.requestAccess() } }
                }
                Button("Open Settings") { SettingsWindowController.shared.show() }
                Spacer()
                Text("Tip: press ⌃⌥N anytime").font(.caption).foregroundStyle(.secondary)
                Button("Get Started", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
    }
}
