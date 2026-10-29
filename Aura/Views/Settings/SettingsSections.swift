import AVFoundation
import EventKit
import SwiftUI
import UserNotifications

// MARK: - General

struct GeneralSettings: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(Pref.Key.showMenuBarIcon.rawValue) private var showMenuBarIcon = true
    @AppStorage(Pref.Key.checkForUpdates.rawValue) private var checkForUpdates = true
    @AppStorage(Pref.Key.hotKeysEnabled.rawValue) private var hotKeys = true
    @AppStorage(Pref.Key.displayMode.rawValue) private var displayMode = DisplayMode.notched.rawValue
    @AppStorage(Pref.Key.hideInFullscreen.rawValue) private var hideInFullscreen = true
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch Aura at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in LaunchAtLogin.set(value) }
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            }
            Section("Displays") {
                Picker("Show the notch on", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Hide when an app is fullscreen", isOn: $hideInFullscreen)
            }
            Section {
                Toggle("Global keyboard shortcuts", isOn: $hotKeys)
                    .onChange(of: hotKeys) { _, on in
                        if on { HotKeyCenter.shared.install() } else { HotKeyCenter.shared.uninstall() }
                    }
                LabeledContent("Open or close the notch", value: "⌃⌥N")
                LabeledContent("Ask Aura", value: "⌃⌥A")
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Also available: aura://ask, aura://tray, aura://tasks and aura://settings links for Shortcuts and scripts.")
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                HStack {
                    Text(updates.lastMessage ?? "Aura \(AppInfo.version)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let release = updates.available {
                        Button("Download \(release.version)") { NSWorkspace.shared.open(release.url) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(updates.isChecking ? "Checking…" : "Check Now") {
                        Task { await updates.check(userInitiated: true) }
                    }
                    .disabled(updates.isChecking)
                }
            }
        }
    }
}

// MARK: - Notch

struct NotchSettings: View {
    @AppStorage(Pref.Key.openOnHover.rawValue) private var openOnHover = true
    @AppStorage(Pref.Key.hoverDelay.rawValue) private var hoverDelay = 0.12
    @AppStorage(Pref.Key.hapticsEnabled.rawValue) private var haptics = true
    @AppStorage(Pref.Key.gesturesEnabled.rawValue) private var gestures = true
    @AppStorage(Pref.Key.invertMediaGestures.rawValue) private var invert = false
    @AppStorage(Pref.Key.showFakeNotch.rawValue) private var fakeNotch = true
    @AppStorage(Pref.Key.rememberLastTab.rawValue) private var rememberLastTab = true
    @AppStorage(Pref.Key.defaultTab.rawValue) private var defaultTab = NotchTab.nook.rawValue

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Open when the pointer hovers the notch", isOn: $openOnHover)
                if openOnHover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $hoverDelay, in: 0...1, step: 0.05).frame(width: 200)
                            Text(String(format: "%.2fs", hoverDelay)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44)
                        }
                    }
                }
                Toggle("Remember the last tab", isOn: $rememberLastTab)
                if !rememberLastTab {
                    Picker("Open on", selection: $defaultTab) {
                        ForEach(NotchTab.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    }
                }
            }
            Section {
                Toggle("Trackpad gestures", isOn: $gestures)
                Toggle("Invert track-skip direction", isOn: $invert).disabled(!gestures)
                Toggle("Haptic feedback", isOn: $haptics)
            } header: {
                Text("Gestures")
            } footer: {
                Text("Swipe down on the notch to open it. Swipe left or right on it to change tracks. Haptics need a Force Touch trackpad.")
            }
            Section {
                Toggle("Show a notch on displays without one", isOn: $fakeNotch)
            } header: {
                Text("External displays")
            } footer: {
                Text("When off, the notch only appears while live activities run or when you hover the top centre of the screen.")
            }
        }
    }
}

// MARK: - Live activities

struct ActivitySettings: View {
    @AppStorage(Pref.Key.musicActivity.rawValue) private var music = true
    @AppStorage(Pref.Key.batteryActivity.rawValue) private var battery = true
    @AppStorage(Pref.Key.timerActivity.rawValue) private var timer = true
    @AppStorage(Pref.Key.activityLinger.rawValue) private var linger = 4.0
    @AppStorage(Pref.Key.lowBatteryThreshold.rawValue) private var lowThreshold = 20
    @AppStorage(Pref.Key.quickPeekEnabled.rawValue) private var quickPeek = true
    @AppStorage(Pref.Key.peekOnSongChange.rawValue) private var peekSong = true
    @AppStorage(Pref.Key.peekOnPower.rawValue) private var peekPower = true
    @AppStorage(Pref.Key.peekOnMeetings.rawValue) private var peekMeetings = true
    @AppStorage(Pref.Key.meetingPeekMinutes.rawValue) private var meetingMinutes = 5
    @AppStorage(Pref.Key.colorfulSpectrum.rawValue) private var colorful = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $music) { Label("Now playing", systemImage: "music.note") }
                Toggle(isOn: $battery) { Label("Charging & low battery", systemImage: "bolt.fill") }
                Toggle(isOn: $timer) { Label("Timers", systemImage: "timer") }
                Toggle("Tint the visualizer with album colours", isOn: $colorful)
            } header: {
                Text("Live activities")
            } footer: {
                Text("Live activities extend the closed notch with glanceable info — album art and a visualizer, battery level, or a countdown.")
            }
            Section("Timing") {
                LabeledContent("Hide after inactive for") {
                    HStack {
                        Slider(value: $linger, in: 1...30, step: 1).frame(width: 200)
                        Text("\(Int(linger))s").monospacedDigit().foregroundStyle(.secondary).frame(width: 36)
                    }
                }
                Stepper("Low battery at \(lowThreshold)%", value: $lowThreshold, in: 5...50, step: 5)
            }
            Section {
                Toggle("Quick Peek", isOn: $quickPeek)
                Group {
                    Toggle("When the song changes", isOn: $peekSong)
                    Toggle("When the charger is connected or removed", isOn: $peekPower)
                    Toggle("Before calendar events", isOn: $peekMeetings)
                    if peekMeetings {
                        Stepper("\(meetingMinutes) minutes before", value: $meetingMinutes, in: 1...30)
                    }
                }
                .disabled(!quickPeek)
            } header: {
                Text("Quick Peek")
            } footer: {
                Text("A Quick Peek briefly drops the notch down with a one-line update, then tucks itself away.")
            }
            Section {
                Button("Preview a Quick Peek") {
                    ActivityCenter.shared.showPeek(Peek(kind: .info, title: "This is a Quick Peek", subtitle: "Aura \(AppInfo.version)",
                                                        icon: "sparkles", tint: AuraStyle.violet), duration: 3)
                }
            }
        }
    }
}

// MARK: - Media

struct MediaSettings: View {
    @AppStorage(Pref.Key.webMediaDetection.rawValue) private var web = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Apple Music", value: NowPlayingService.isInstalled(.music) ? "Supported" : "Not installed")
                LabeledContent("Spotify", value: NowPlayingService.isInstalled(.spotify) ? "Supported" : "Not installed")
            } header: {
                Text("Players")
            } footer: {
                Text("Aura talks to Music and Spotify through Apple Events. The first time, macOS asks whether Aura may control each app — choose OK. You can change this later in System Settings → Privacy & Security → Automation.")
            }
            Section {
                Toggle("Detect YouTube Music & Spotify Web in browsers", isOn: $web)
            } header: {
                Text("Web players (experimental)")
            } footer: {
                Text("Reads tab titles in Safari, Chrome, Arc, Edge and Brave to show the song. Playback control uses the system media keys.")
            }
        }
    }
}

// MARK: - Tray

struct TraySettings: View {
    @ObservedObject private var tray = TrayStore.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Items in Tray", value: "\(tray.items.count)")
                HStack {
                    Button("Show Tray Folder") { NSWorkspace.shared.open(tray.folder) }
                    Button("Clear Tray", role: .destructive) { tray.clear() }.disabled(tray.items.isEmpty)
                }
            } footer: {
                Text("Drag anything onto the notch to keep it. Files stay where they are — the Tray keeps a reference. Images and snippets are saved in the Tray folder. Drop onto the AirDrop zone to send files straight to a nearby device.")
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettings: View {
    @ObservedObject private var shortcuts = ShortcutsService.shared

    var body: some View {
        Form {
            Section {
                if shortcuts.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if shortcuts.all.isEmpty {
                    Text("No shortcuts found. Create some in the Shortcuts app.").foregroundStyle(.secondary)
                } else {
                    ForEach(shortcuts.all, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { shortcuts.favorites.contains(name) },
                                                   set: { _ in shortcuts.toggleFavorite(name) }))
                    }
                }
            } header: {
                HStack {
                    Text("Pin to the Nook")
                    Spacer()
                    Button("Refresh") { Task { await shortcuts.load() } }.buttonStyle(.link)
                }
            } footer: {
                Text("Pinned shortcuts appear in the Nook for one-click runs. You can also say “run shortcut <name>” in Ask.")
            }
        }
        .task { await shortcuts.load() }
    }
}

// MARK: - Assistant

struct AssistantSettings: View {
    @AppStorage(Pref.Key.ollamaURL.rawValue) private var url = "http://localhost:11434"
    @AppStorage(Pref.Key.ollamaModel.rawValue) private var model = "llama3.2"
    @State private var models: [String] = []
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $url)
                if models.isEmpty {
                    TextField("Model", text: $model)
                } else {
                    Picker("Model", selection: $model) {
                        ForEach(models.contains(model) ? models : models + [model], id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    if let status { Text(status).foregroundStyle(.secondary) }
                    Spacer()
                    Button(checking ? "Checking…" : "Test Connection") { Task { await test() } }.disabled(checking)
                }
            } header: {
                Text("Ollama")
            } footer: {
                Text("Aura's assistant runs on your Mac through Ollama — nothing is sent to the cloud. Install it from ollama.com, then run “ollama pull llama3.2”.")
            }
            Section("Quick commands (work without Ollama)") {
                ForEach(["timer 10m · pomodoro · focus 45m", "todo buy milk · remind me to call mom",
                         "play · pause · next · previous", "open Safari · launch Xcode",
                         "what's next · battery", "run shortcut <name> · clear tray"], id: \.self) {
                    Text($0).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .task { await test() }
    }

    private func test() async {
        checking = true
        defer { checking = false }
        do {
            models = try await OllamaClient.configured.models()
            status = models.isEmpty ? "Connected — no models installed yet." : "Connected · \(models.count) model\(models.count == 1 ? "" : "s")"
            Assistant.shared.checkOnline()
        } catch {
            models = []
            status = "Not reachable"
        }
    }
}

// MARK: - Permissions

struct PermissionsSettings: View {
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var camera = CameraService.shared
    @State private var notifications: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                PermissionRow(title: "Calendar", detail: "Upcoming events and meeting links", symbol: "calendar", color: .red,
                              granted: calendar.isAuthorized, denied: calendar.status == .denied) {
                    Task { await calendar.requestAccess() }
                } openSettings: { openPrivacy("Privacy_Calendars") }
                PermissionRow(title: "Notifications", detail: "Timers and workflow alerts", symbol: "bell.badge.fill", color: .orange,
                              granted: notifications == .authorized, denied: notifications == .denied) {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in refreshNotifications() }
                } openSettings: { openPrivacy("Notifications") }
                PermissionRow(title: "Camera", detail: "Mirror in the Nook", symbol: "camera.fill", color: .green,
                              granted: camera.authorization == .authorized, denied: camera.authorization == .denied) {
                    camera.start()
                    camera.stop()
                } openSettings: { openPrivacy("Privacy_Camera") }
                PermissionRow(title: "Automation", detail: "Control Music and Spotify (asked on first use)", symbol: "applescript.fill", color: .gray,
                              granted: nil, denied: false) {
                    NowPlayingService.shared.refresh()
                } openSettings: { openPrivacy("Privacy_Automation") }
            } footer: {
                Text("Aura works without any of these — each one only unlocks the feature next to it. Nothing you grant leaves your Mac.")
            }
        }
        .onAppear(perform: refreshNotifications)
    }

    private func refreshNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { notifications = settings.authorizationStatus }
        }
    }

    private func openPrivacy(_ anchor: String) {
        let base = anchor == "Notifications"
            ? "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            : "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: base) { NSWorkspace.shared.open(url) }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let granted: Bool?
    let denied: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted == true {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else if denied {
                Button("Open Settings", action: openSettings)
            } else if granted == nil {
                Button("Open Settings", action: openSettings)
            } else {
                Button("Allow", action: request).buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: AuraStyle.violet.opacity(0.4), radius: 18, y: 6)
            Text("Aura").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Version \(AppInfo.version) (\(AppInfo.build))").foregroundStyle(.secondary)
            Text("Your Mac's notch, turned into a live, local-first command center.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("GitHub") { NSWorkspace.shared.open(AppInfo.repoURL) }
                Button("Release Notes") { NSWorkspace.shared.open(AppInfo.releasesURL) }
                Button("Report an Issue") { NSWorkspace.shared.open(AppInfo.issuesURL) }
            }
            Button("Show Welcome Screen Again") { OnboardingWindowController.shared.show() }
                .buttonStyle(.link)
            Spacer()
            Text("MIT License · Made by Pranav Dwivedi").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
