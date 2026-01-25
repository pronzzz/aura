import SwiftUI

/// Command bar view for natural language input
struct CommandBarView: View {
    @StateObject private var aiService = AIService.shared
    @ObservedObject var contextEngine: ContextEngine
    @StateObject private var themeManager = ThemeManager.shared
    
    @State private var inputText = ""
    @State private var isExpanded = false
    @State private var response: String?
    @State private var suggestions: [SuggestedAction] = []
    
    var body: some View {
        VStack(spacing: 8) {
            // Input field
            HStack(spacing: 8) {
                Image(systemName: aiService.isAvailable ? "sparkles" : "text.cursor")
                    .foregroundColor(aiService.isAvailable ? .purple : themeManager.secondaryTextColor)
                
                TextField("Ask Aura...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        processCommand()
                    }
                
                if aiService.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if !inputText.isEmpty {
                    Button(action: processCommand) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeManager.widgetBackground)
            .cornerRadius(10)
            
            // Response area
            if let response = response {
                Text(response)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.textColor)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeManager.widgetBackground.opacity(0.5))
                    .cornerRadius(8)
            }
            
            // Suggestions
            if !suggestions.isEmpty && inputText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            SuggestionPill(suggestion: suggestion) {
                                executeSuggestion(suggestion)
                            }
                        }
                    }
                }
            }
        }
        .foregroundColor(themeManager.textColor)
        .onAppear {
            loadSuggestions()
        }
    }
    
    private func processCommand() {
        guard !inputText.isEmpty else { return }
        
        let command = inputText
        inputText = ""
        
        // Try rule-based parsing first (instant)
        let intent = CommandParser.parse(command)
        
        if case .unknown = intent {
            // Fall back to AI if available
            if aiService.isAvailable {
                Task {
                    do {
                        let snapshot = createContextSnapshot()
                        let aiResponse = try await aiService.processCommand(command, context: snapshot)
                        await MainActor.run {
                            response = aiResponse.response
                        }
                    } catch {
                        await MainActor.run {
                            response = "Sorry, I couldn't process that command."
                        }
                    }
                }
            } else {
                response = "I'm not sure what you mean. Try 'show battery' or 'hide clock'."
            }
        } else {
            // Execute rule-based command
            CommandParser.execute(intent, widgetManager: WidgetManager.shared)
            response = "Done!"
            
            // Clear response after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                response = nil
            }
        }
    }
    
    private func loadSuggestions() {
        Task {
            let snapshot = createContextSnapshot()
            suggestions = await aiService.suggestActions(for: snapshot)
        }
    }
    
    private func executeSuggestion(_ suggestion: SuggestedAction) {
        switch suggestion.action {
        case .widgetCommand(let cmd):
            let intent = CommandParser.parse(cmd)
            CommandParser.execute(intent, widgetManager: WidgetManager.shared)
        case .systemCommand(let cmd):
            // Handle system commands
            if cmd == "dnd" || cmd == "focus" {
                CommandParser.execute(.toggleFocus, widgetManager: WidgetManager.shared)
            }
        case .url(let url):
            NSWorkspace.shared.open(url)
        }
    }
    
    private func createContextSnapshot() -> ContextSnapshot {
        ContextSnapshot(
            currentApp: contextEngine.currentApp,
            isFocusMode: contextEngine.isFocusMode,
            isInMeeting: contextEngine.isInMeeting,
            batteryLevel: contextEngine.batteryLevel,
            isCharging: contextEngine.isCharging,
            isScreenSharing: contextEngine.isScreenSharing,
            timeOfDay: contextEngine.timeOfDay,
            isWorkHours: contextEngine.isWorkHours
        )
    }
}

struct SuggestionPill: View {
    let suggestion: SuggestedAction
    let action: () -> Void
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 10))
                Text(suggestion.title)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(themeManager.widgetBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .foregroundColor(themeManager.textColor)
    }
}

#Preview {
    CommandBarView(contextEngine: ContextEngine.shared)
        .frame(width: 300)
        .padding()
        .background(Color.black)
}
