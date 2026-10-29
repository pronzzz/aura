import AppKit
import Combine

/// Commands Aura handles instantly, without a language model.
enum AssistantIntent: Equatable {
    case timer(seconds: TimeInterval, label: String?)
    case todo(String)
    case playPause, play, pause, nextTrack, previousTrack
    case openApp(String)
    case nextMeeting
    case battery
    case runShortcut(String)
    case settings
    case clearTray
}

enum IntentParser {
    static func parse(_ raw: String) -> AssistantIntent? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }

        // Timers: "timer 5m", "start a 20 minute timer", "pomodoro", "focus 45m"
        if lower.contains("timer") || lower.hasPrefix("pomodoro") || lower.hasPrefix("focus") {
            if let seconds = duration(in: lower) {
                return .timer(seconds: seconds, label: lower.hasPrefix("focus") || lower.hasPrefix("pomodoro") ? "Focus" : nil)
            }
            if lower.hasPrefix("pomodoro") || lower.hasPrefix("focus") { return .timer(seconds: 25 * 60, label: "Focus") }
        }

        // Todos
        for prefix in ["add todo ", "add task ", "todo ", "task ", "remind me to "] where lower.hasPrefix(prefix) {
            let item = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !item.isEmpty { return .todo(item) }
        }

        // Media
        switch lower {
        case "play": return .play
        case "pause", "stop music", "pause music": return .pause
        case "play/pause", "toggle music", "playpause": return .playPause
        case "next", "skip", "next song", "next track", "skip song": return .nextTrack
        case "previous", "prev", "back", "previous song", "previous track", "last song": return .previousTrack
        case "settings", "preferences", "open settings": return .settings
        case "clear tray", "empty tray": return .clearTray
        default: break
        }

        // Shortcuts
        for prefix in ["run shortcut ", "shortcut "] where lower.hasPrefix(prefix) {
            return .runShortcut(String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }

        // Apps
        for prefix in ["open ", "launch ", "start "] where lower.hasPrefix(prefix) {
            let name = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !name.contains(" timer") { return .openApp(name) }
        }

        if lower.contains("next meeting") || lower.contains("what's next") || lower.contains("whats next")
            || lower.contains("my schedule") || lower.contains("next event") {
            return .nextMeeting
        }
        if lower.contains("battery") { return .battery }
        return nil
    }

    /// Parses "1h 30m", "90 sec", "5 minutes", "2.5h".
    static func duration(in text: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var total: TimeInterval = 0
        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }
            let unit = text[unitRange]
            if unit.hasPrefix("h") { total += value * 3600 } else if unit.hasPrefix("m") { total += value * 60 } else { total += value }
        }
        if total > 0 { return total }
        // A bare number next to "timer" means minutes.
        if let bare = text.split(separator: " ").compactMap({ Double($0) }).first { return bare * 60 }
        return nil
    }
}

/// The "Ask" tab: instant local commands first, then a local LLM through Ollama.
@MainActor
final class Assistant: ObservableObject {
    static let shared = Assistant()

    struct Entry: Identifiable, Equatable {
        enum Role { case user, assistant, action, error }
        let id = UUID()
        var role: Role
        var text: String
    }

    @Published var input = ""
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isThinking = false
    @Published private(set) var isOnline: Bool?

    private var task: Task<Void, Never>?
    private var history: [ChatMessage] = []

    private init() {}

    func checkOnline() {
        Task { isOnline = await OllamaClient.configured.isReachable() }
    }

    func submit(_ override: String? = nil) {
        let text = (override ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        entries.append(Entry(role: .user, text: text))

        if let intent = IntentParser.parse(text) {
            entries.append(Entry(role: .action, text: perform(intent)))
            trim()
            return
        }
        ask(text)
    }

    /// Sends clipboard text to the model with an instruction ("Summarize", "Explain", …).
    func runOnClipboard(_ instruction: String) {
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else {
            entries.append(Entry(role: .error, text: "The clipboard has no text."))
            return
        }
        let snippet = String(clip.prefix(6000))
        entries.append(Entry(role: .user, text: "\(instruction) clipboard (\(clip.count) characters)"))
        ask("\(instruction) the following text:\n\n\(snippet)")
    }

    func stop() {
        task?.cancel()
        task = nil
        isThinking = false
    }

    func clear() {
        stop()
        entries.removeAll()
        history.removeAll()
    }

    func copyLastAnswer() {
        guard let last = entries.last(where: { $0.role == .assistant }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
    }

    func applyDemo(_ demo: [Entry]) {
        entries = demo
        isOnline = true
    }

    // MARK: - LLM

    private func ask(_ prompt: String) {
        isThinking = true
        history.append(ChatMessage(role: "user", content: prompt))
        let messages = [ChatMessage(role: "system", content: systemPrompt())] + history.suffix(12)
        entries.append(Entry(role: .assistant, text: ""))
        let index = entries.count - 1

        task = Task { [weak self] in
            guard let self else { return }
            var reply = ""
            do {
                for try await token in OllamaClient.configured.chat(messages) {
                    reply += token
                    if index < self.entries.count { self.entries[index].text = reply }
                }
                self.isOnline = true
                self.history.append(ChatMessage(role: "assistant", content: reply))
                if reply.isEmpty, index < self.entries.count { self.entries.remove(at: index) }
            } catch {
                if case .unreachable? = error as? OllamaClient.ClientError {
                    self.isOnline = false
                } else {
                    self.isOnline = true
                }
                if index < self.entries.count {
                    self.entries[index] = Entry(role: .error, text: error.localizedDescription)
                }
                _ = self.history.popLast()
            }
            self.isThinking = false
            self.trim()
        }
    }

    private func systemPrompt() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        var context = ["Current date and time: \(formatter.string(from: Date()))."]
        let power = PowerService.shared
        if power.hasBattery { context.append("Battery: \(power.level)%\(power.isPluggedIn ? ", plugged in" : "").") }
        if let track = NowPlayingService.shared.track {
            context.append("Now playing: \(track.title) by \(track.artist).")
        }
        if let event = CalendarService.shared.nextEvent {
            context.append("Next event: \(event.title) at \(event.timeDescription).")
        }
        let todos = TodoStore.shared.items.filter { !$0.isDone }.prefix(5).map(\.text)
        if !todos.isEmpty { context.append("Open todos: \(todos.joined(separator: "; ")).") }

        return """
        You are Aura, a concise and friendly assistant that lives in the Mac's notch. \
        Keep answers short (under 120 words) unless the user asks for detail. Use plain text, no markdown headings.
        Context: \(context.joined(separator: " "))
        """
    }

    private func trim() {
        if entries.count > 40 { entries.removeFirst(entries.count - 40) }
    }

    // MARK: - Local intents

    @discardableResult
    func perform(_ intent: AssistantIntent) -> String {
        let media = NowPlayingService.shared
        switch intent {
        case .timer(let seconds, let label):
            let timer = TimerService.shared.start(seconds: seconds, label: label)
            return "Started a \(TimerService.format(seconds)) \(timer.label.lowercased()) timer."
        case .todo(let text):
            TodoStore.shared.add(text)
            return "Added “\(text)” to your tasks."
        case .playPause:
            media.togglePlayPause()
            return media.isPlaying ? "Playing." : "Paused."
        case .play:
            if !media.isPlaying { media.togglePlayPause() }
            return media.track.map { "Playing \($0.title)." } ?? "Asked your music app to play."
        case .pause:
            if media.isPlaying { media.togglePlayPause() }
            return "Paused."
        case .nextTrack:
            media.next()
            return "Skipping to the next track."
        case .previousTrack:
            media.previous()
            return "Going back a track."
        case .openApp(let name):
            return AppLauncher.open(named: name) ? "Opening \(name)." : "I couldn't find an app called “\(name)”."
        case .nextMeeting:
            let calendar = CalendarService.shared
            guard calendar.isAuthorized else { return "Connect your calendar in Aura Settings → Permissions." }
            guard let event = calendar.nextEvent else { return "Nothing else on your calendar today or tomorrow." }
            let link = event.meetingURL != nil ? " It has a meeting link." : ""
            return "Next up: \(event.title), \(event.relativeDescription) (\(event.timeDescription)).\(link)"
        case .battery:
            let power = PowerService.shared
            guard power.hasBattery else { return "This Mac doesn't have a battery." }
            let state = power.isCharging ? "charging" : (power.isPluggedIn ? "plugged in" : "on battery")
            return "Battery is at \(power.level)%, \(state)" + (power.remainingDescription.map { ", \($0)." } ?? ".")
        case .runShortcut(let name):
            ShortcutsService.shared.run(name)
            return "Running the “\(name)” shortcut."
        case .settings:
            SettingsWindowController.shared.show()
            return "Opening settings."
        case .clearTray:
            TrayStore.shared.clear()
            return "Cleared the tray."
        }
    }
}

enum AppLauncher {
    /// Finds an app by (case-insensitive) name in the usual folders and opens it.
    @discardableResult
    static func open(named name: String) -> Bool {
        guard let url = find(named: name) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }

    static func find(named name: String) -> URL? {
        let target = name.lowercased().replacingOccurrences(of: ".app", with: "")
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var fuzzy: URL?
        for folder in folders {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for file in contents where file.hasSuffix(".app") {
                let base = file.dropLast(4).lowercased()
                if base == target { return URL(fileURLWithPath: folder).appendingPathComponent(file) }
                if fuzzy == nil, base.hasPrefix(target) { fuzzy = URL(fileURLWithPath: folder).appendingPathComponent(file) }
            }
        }
        return fuzzy
    }
}
