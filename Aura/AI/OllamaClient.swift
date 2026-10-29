import Foundation

struct ChatMessage: Codable, Equatable {
    var role: String
    var content: String
}

/// Minimal client for a local Ollama server (https://ollama.com). Nothing leaves your Mac.
struct OllamaClient {
    var baseURL: URL
    var model: String

    static var configured: OllamaClient {
        let url = URL(string: Pref.string(.ollamaURL)) ?? URL(string: "http://localhost:11434")!
        return OllamaClient(baseURL: url, model: Pref.string(.ollamaModel))
    }

    enum ClientError: LocalizedError {
        case unreachable
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unreachable:
                return "Ollama isn't running. Install it from ollama.com, then run `ollama serve`."
            case .server(let message):
                return message
            }
        }
    }

    func isReachable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func models() async throws -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 4
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).sorted()
        } catch {
            throw ClientError.unreachable
        }
    }

    /// Streams the assistant reply token by token.
    func chat(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                struct Body: Encodable {
                    let model: String
                    let messages: [ChatMessage]
                    let stream: Bool
                }
                struct Chunk: Decodable {
                    struct Message: Decodable { let content: String }
                    let message: Message?
                    let done: Bool?
                    let error: String?
                }

                var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120
                request.httpBody = try? JSONEncoder().encode(Body(model: model, messages: messages, stream: true))

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                        throw ClientError.server("Model “\(model)” isn't installed. Run `ollama pull \(model)` or pick another model in Settings.")
                    }
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { continue }
                        if let error = chunk.error { throw ClientError.server(error) }
                        if let content = chunk.message?.content, !content.isEmpty { continuation.yield(content) }
                        if chunk.done == true { break }
                    }
                    continuation.finish()
                } catch let error as ClientError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: ClientError.unreachable)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
