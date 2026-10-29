import SwiftUI

struct AskTab: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var assistant = Assistant.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            transcript
            inputBar
        }
        .onAppear {
            assistant.checkOnline()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
        .onChange(of: focused) { _, isFocused in viewModel.hold("typing", isFocused) }
        .onChange(of: assistant.isThinking) { _, thinking in viewModel.hold("thinking", thinking) }
        .onDisappear {
            viewModel.hold("typing", false)
            viewModel.hold("thinking", false)
        }
    }

    // MARK: Transcript

    @ViewBuilder private var transcript: some View {
        if assistant.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(AuraStyle.gradient)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ask Aura").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AuraStyle.secondary)
                    }
                }
                suggestionRow(["Timer 25m", "What's next?", "Battery", "Next song"])
                HStack(spacing: 6) {
                    Chip(title: "Summarize clipboard", symbol: "doc.text.magnifyingglass") { assistant.runOnClipboard("Summarize") }
                    Chip(title: "Explain clipboard", symbol: "questionmark.bubble") { assistant.runOnClipboard("Explain simply") }
                    Chip(title: "Fix grammar", symbol: "textformat") { assistant.runOnClipboard("Fix the grammar and spelling of") }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                AuraScroll {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(assistant.entries) { entry in
                            EntryBubble(entry: entry, isStreaming: assistant.isThinking && entry.id == assistant.entries.last?.id)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: assistant.entries) { _, entries in
                    if let last = entries.last { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear { if let last = assistant.entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var statusText: String {
        switch assistant.isOnline {
        case true?: return "Local AI via Ollama (\(Pref.string(.ollamaModel))) · quick commands work offline"
        case false?: return "Quick commands ready · start Ollama for open-ended questions"
        case nil: return "Checking for Ollama…"
        }
    }

    private func suggestionRow(_ items: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Chip(title: item) { assistant.submit(item) }
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(assistant.isOnline == true ? Color.green : (assistant.isOnline == false ? Color.orange : Color.gray))
                .frame(width: 6, height: 6)
                .help(assistant.isOnline == true ? "Ollama connected" : "Ollama not reachable — quick commands still work")
            AuraTextField("Ask anything, or try “timer 10m”, “todo call mom”, “open Safari”…", text: $assistant.input)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .focused($focused)
                .onSubmit { assistant.submit() }
            if assistant.isThinking {
                IconButton(symbol: "stop.fill", size: 10, diameter: 24, help: "Stop") { assistant.stop() }
            } else if !assistant.entries.isEmpty {
                IconButton(symbol: "doc.on.doc", size: 10, diameter: 24, tint: AuraStyle.secondary, help: "Copy last answer") { assistant.copyLastAnswer() }
                IconButton(symbol: "trash", size: 10, diameter: 24, tint: AuraStyle.secondary, help: "Clear conversation") { assistant.clear() }
            }
            IconButton(symbol: "arrow.up", size: 11, diameter: 26, tint: .black, help: "Send") { assistant.submit() }
                .background(Circle().fill(assistant.input.isEmpty ? Color.white.opacity(0.3) : Color.white))
                .disabled(assistant.input.isEmpty)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focused ? AnyShapeStyle(AuraStyle.gradient.opacity(0.7)) : AnyShapeStyle(Color.clear), lineWidth: 1))
    }
}

private struct EntryBubble: View {
    let entry: Assistant.Entry
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(Circle().fill(tint.opacity(0.15)))
            Group {
                if entry.text.isEmpty && isStreaming {
                    ThinkingDots()
                } else {
                    Text(entry.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 12.5, weight: entry.role == .user ? .semibold : .regular, design: .rounded))
            .foregroundStyle(entry.role == .error ? Color.orange : (entry.role == .user ? Color.white : Color.white.opacity(0.88)))
            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        switch entry.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .action: return "bolt.fill"
        case .error: return "exclamationmark"
        }
    }

    private var tint: Color {
        switch entry.role {
        case .user: return .white
        case .assistant: return AuraStyle.violet
        case .action: return .green
        case .error: return .orange
        }
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.white.opacity(0.7))
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * abs(sin(t * 3 + Double(i) * 0.6)))
                }
            }
            .frame(height: 16)
        }
    }
}
