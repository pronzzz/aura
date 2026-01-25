import Foundation

/// Ollama local LLM provider
/// Connects to Ollama running locally at localhost:11434
class OllamaProvider: AIProvider {
    private let baseURL = URL(string: "http://localhost:11434")!
    private let defaultModel = "llama3.2:3b"  // Fast, efficient local model
    
    var modelName: String { defaultModel }
    var isAvailable: Bool = false
    
    // MARK: - Availability Check
    
    func checkAvailability() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                isAvailable = httpResponse.statusCode == 200
                return isAvailable
            }
        } catch {
            isAvailable = false
        }
        
        return false
    }
    
    // MARK: - Completion
    
    func complete(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": defaultModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.3,
                "top_p": 0.9,
                "num_predict": 256
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.networkError(NSError(domain: "OllamaProvider", code: -1))
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseText = json["response"] as? String {
            return responseText
        }
        
        throw AIError.invalidResponse
    }
    
    // MARK: - Streaming
    
    func streamComplete(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("api/generate")
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let body: [String: Any] = [
                        "model": defaultModel,
                        "prompt": prompt,
                        "stream": true
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let responseText = json["response"] as? String {
                            continuation.yield(responseText)
                            
                            if json["done"] as? Bool == true {
                                break
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
