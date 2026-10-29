# Changelog

## 2.0.0 — 2026-10-29

Aura 2.0 is a ground-up rewrite. The notch is now a real, fast, gesture-driven surface with live activities, a file tray, timers and a local assistant, packaged in a universal app and a new installer.

### ✨ New

- **Rebuilt notch.** A new shape and spring animations, fitted exactly to your MacBook's notch. Macs and displays without a notch get a virtual one. Clicks pass through everywhere except the notch itself, so menu bar items next to it keep working.
- **Live activities** around the closed notch: timer countdown, charging, low battery, and now playing with album-tinted spectrum bars.
- **Quick Peek.** The notch briefly expands for a song change, plugging in or unplugging, a finished timer, or an upcoming meeting.
- **Nook tab.** A media card with artwork, scrubber and controls; a calendar card with a one-click **Join** for Zoom, Meet, Teams, Webex, FaceTime and others; CPU and memory rings; Mirror; and favourite Shortcuts.
- **Tray.** Drop files, text, images or links on the notch to stash them, then drag them back out anywhere. It also has an **AirDrop** drop target, AirDrop All, and paste from the clipboard. The Tray opens by itself when you start dragging toward the notch, and its contents persist between launches.
- **Tasks tab.** Multiple timers (presets or any typed duration) with pause, +1 min and cancel, plus a to-do list.
- **Ask tab.** Offline quick commands (timers, todos, music, open apps, next meeting, battery, run Shortcuts) and a streaming local assistant through Ollama, with one-tap clipboard actions: Summarize, Explain and Fix grammar.
- **Gestures.** Swipe down on the notch to open it, and swipe sideways to skip tracks. Haptic feedback is optional.
- **Automation workflows.** Battery, charger, app launch and quit, time of day, meeting-soon and launch triggers. Actions cover notifications, peeks, apps, URLs, Shortcuts, timers, todos, music, AppleScript and more. Five templates are included.
- **Global shortcuts.** `⌃⌥N` toggles the notch and `⌃⌥A` opens Ask.
- **`aura://` URL scheme** with `open`, `ask`, `tray`, `tasks` and `settings`.
- **New Settings window** with ten sections, live permission status and one-click fixes.
- **Welcome flow** for first launch.
- **Update check** against GitHub releases, shown in Settings and the menu bar menu.
- **Launch at login.**
- **Fullscreen aware.** The notch hides while an app is fullscreen.
- **Multi-display.** Show the notch on notched screens only, the main screen, or every display.

### 🎨 Design

- A new app icon and installer.
- The DMG now uses a custom background with clear drag-to-Applications guidance and Gatekeeper instructions, a Retina background, and a custom volume icon.

### 🛠 Under the hood

- The whole app is new Swift/SwiftUI code. Services are event-driven (IOKit power notifications, distributed music notifications, EventKit change notifications), with no constant polling.
- AppleScript runs on a background queue with compiled-script caching, so the UI never stalls.
- The project is generated from `project.yml` with XcodeGen.
- The app is a universal binary for Apple silicon and Intel.
- New `scripts/release.sh` builds the app and DMG in one step.
- New `scripts/make_art.swift` regenerates the icon and installer art.
- New `--snapshot` mode renders README screenshots from demo data.

### 🧹 Removed

- The v1 plugin system and its Weather and Pomodoro plugins. Timers are now built in. The Weather plugin needed a network service, which didn't fit Aura's local-first design.
- The v1 command bar, replaced by the Ask tab.
- Focus-mode and screen-share detectors.

### ⚠️ Notes

- Aura is ad-hoc signed and not notarized. On first launch, open **System Settings → Privacy & Security → Open Anyway**, or Control-click the app and choose **Open**.
- Requires macOS 14 Sonoma or later.

## 1.0.0 — 2026-01-25

- First public release.
