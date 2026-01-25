import Foundation
import Combine

/// Protocol for AI providers (Ollama, CoreML, or future cloud APIs)
protocol AIProvider {
    var isAvailable: Bool { get }
    var modelName: String { get }
    
    func complete(prompt: String) async throws -> String
    func streamComplete(prompt: String) -> AsyncThrowingStream<String, Error>
}

/// AI Service manages model selection and inference
class AIService: ObservableObject {
    static let shared = AIService()
    
    @Published var isProcessing: Bool = false
    @Published var lastResponse: String?
    @Published var activeProvider: AIProviderType = .ollama
    @Published var isAvailable: Bool = false
    
    private var ollamaProvider: OllamaProvider?
    private var cancellables = Set<AnyCancellable>()
    
    enum AIProviderType: String, CaseIterable {
        case ollama = "Ollama"
        case mlx = "MLX"  // Apple's ML framework for efficient local inference
    }
    
    private init() {
        setupProviders()
    }
    
    private func setupProviders() {
        ollamaProvider = OllamaProvider()
        checkAvailability()
    }
    
    func checkAvailability() {
        Task { @MainActor in
            switch activeProvider {
            case .ollama:
                isAvailable = await ollamaProvider?.checkAvailability() ?? false
            case .mlx:
                isAvailable = false  // MLX support TBD
            }
        }
    }
    
    // MARK: - Public API
    
    /// Process a natural language command
    func processCommand(_ input: String, context: ContextSnapshot) async throws -> AIResponse {
        guard isAvailable else {
            throw AIError.providerUnavailable
        }
        
        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }
        
        let prompt = buildPrompt(input: input, context: context)
        
        guard let provider = ollamaProvider else {
            throw AIError.providerUnavailable
        }
        
        let response = try await provider.complete(prompt: prompt)
        let parsed = parseResponse(response)
        
        await MainActor.run { lastResponse = response }
        
        return parsed
    }
    
    /// Quick action suggestions based on context
    func suggestActions(for context: ContextSnapshot) async -> [SuggestedAction] {
        // Generate contextual suggestions without AI if unavailable
        var suggestions: [SuggestedAction] = []
        
        // Low battery suggestion
        if context.batteryLevel < 20 && !context.isCharging {
            suggestions.append(SuggestedAction(
                title: "Enable Low Power Mode",
                icon: "battery.25",
                action: .systemCommand("lowpower")
            ))
        }
        
        // Meeting suggestion
        if context.isInMeeting {
            suggestions.append(SuggestedAction(
                title: "Mute Notifications",
                icon: "bell.slash",
                action: .systemCommand("dnd")
            ))
        }
        
        // Productivity app suggestions
        if let app = context.currentApp, app.isProductivity {
            suggestions.append(SuggestedAction(
                title: "Enable Focus Mode",
                icon: "moon.fill",
                action: .systemCommand("focus")
            ))
        }
        
        return suggestions
    }
    
    // MARK: - Prompt Building
    
    private func buildPrompt(input: String, context: ContextSnapshot) -> String {
        """
        You are Aura, a helpful macOS assistant that controls widgets and system features.
        
        Current Context:
        - Active App: \(context.currentApp?.name ?? "Unknown")
        - Focus Mode: \(context.isFocusMode ? "Active" : "Inactive")
        - In Meeting: \(context.isInMeeting ? "Yes" : "No")
        - Battery: \(context.batteryLevel)%\(context.isCharging ? " (Charging)" : "")
        - Time: \(context.timeOfDay.rawValue)
        - Work Hours: \(context.isWorkHours ? "Yes" : "No")
        
        User Request: \(input)
        
        Respond with a JSON object:
        {
            "intent": "widget_control" | "system_command" | "info_query" | "unknown",
            "action": "<specific action>",
            "target": "<widget name or system feature>",
            "parameters": {},
            "response": "<human readable response>"
        }
        """
    }
    
    private func parseResponse(_ response: String) -> AIResponse {
        // Try to parse JSON response
        if let data = response.data(using: .utf8),
           let json = try? JSONDecoder().decode(AIResponse.self, from: data) {
            return json
        }
        
        // Fallback to raw response
        return AIResponse(
            intent: .unknown,
            action: nil,
            target: nil,
            parameters: [:],
            response: response
        )
    }
}

// MARK: - Supporting Types

struct AIResponse: Codable {
    let intent: AIIntent
    let action: String?
    let target: String?
    let parameters: [String: String]
    let response: String
}

enum AIIntent: String, Codable {
    case widgetControl = "widget_control"
    case systemCommand = "system_command"
    case infoQuery = "info_query"
    case unknown
}

struct SuggestedAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: ActionType
    
    enum ActionType {
        case widgetCommand(String)
        case systemCommand(String)
        case url(URL)
    }
}

enum AIError: Error, LocalizedError {
    case providerUnavailable
    case invalidResponse
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "AI provider is not available. Please ensure Ollama is running."
        case .invalidResponse:
            return "Received an invalid response from the AI."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
