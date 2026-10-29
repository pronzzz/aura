import SwiftUI

struct TasksTab: View {
    var body: some View {
        HStack(spacing: 10) {
            TimersCard().frame(width: 300)
            TodosCard()
        }
    }
}

// MARK: - Timers

struct TimersCard: View {
    @ObservedObject private var timers = TimerService.shared
    @State private var custom = ""

    private let presets: [(String, TimeInterval)] = [("1m", 60), ("5m", 300), ("10m", 600), ("25m", 1500), ("1h", 3600)]

    var body: some View {
        NookCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Timers", systemImage: "timer")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                HStack(spacing: 5) {
                    ForEach(presets, id: \.0) { preset in
                        Chip(title: preset.0) { timers.start(seconds: preset.1) }
                    }
                    AuraTextField("e.g. 1h 15m", text: $custom)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .onSubmit(startCustom)
                }

                if timers.timers.isEmpty {
                    Spacer(minLength: 0)
                    Text("Tap a preset or type a duration. The countdown lives in the notch while it runs.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AuraStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    AuraScroll {
                        VStack(spacing: 6) {
                            ForEach(timers.timers) { timer in
                                TimerRow(timer: timer, now: timers.now)
                            }
                        }
                    }
                }
            }
        }
    }

    private func startCustom() {
        let text = custom.lowercased()
        if let seconds = IntentParser.duration(in: text.contains("timer") ? text : text + " timer") {
            timers.start(seconds: seconds)
            custom = ""
        }
    }
}

private struct TimerRow: View {
    let timer: AuraTimer
    let now: Date
    @ObservedObject private var timers = TimerService.shared

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.orange.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: 1 - timer.progress(at: now))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(TimerService.format(timer.remaining(at: now)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(timer.label + (timer.isRunning ? "" : " · paused"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AuraStyle.secondary)
            }
            Spacer()
            IconButton(symbol: "plus", size: 10, diameter: 24, help: "Add 1 minute") { timers.addTime(timer.id, seconds: 60) }
            IconButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", size: 10, diameter: 24, help: timer.isRunning ? "Pause" : "Resume") {
                timer.isRunning ? timers.pause(timer.id) : timers.resume(timer.id)
            }
            IconButton(symbol: "xmark", size: 10, diameter: 24, help: "Cancel") { timers.cancel(timer.id) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Todos

struct TodosCard: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var draft = ""

    var body: some View {
        NookCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Tasks", systemImage: "checklist")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Spacer()
                    if store.items.contains(where: \.isDone) {
                        Button("Clear done") { withAnimation { store.clearDone() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(AuraStyle.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(AuraStyle.secondary)
                    AuraTextField("Add a task and press Return", text: $draft)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .onSubmit {
                            withAnimation { store.add(draft) }
                            draft = ""
                        }
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))

                AuraScroll {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.items) { item in
                            TodoRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    @ObservedObject private var store = TodoStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.spring(response: 0.3)) { store.toggle(item.id) } } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isDone ? Color.cyan : AuraStyle.secondary)
            }
            .buttonStyle(.plain)
            Text(item.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? AuraStyle.tertiary : .white)
                .lineLimit(1)
            Spacer()
            if hovering {
                Button { withAnimation { store.remove(item.id) } } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AuraStyle.secondary)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
    }
}
