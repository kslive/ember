import Foundation

/// Minimal OpenAI-compatible DeepSeek API client (https://api.deepseek.com).
/// Used ONLY as an optional cloud path for summaries: the user supplies a key in
/// Settings; every failure falls back to the local MLX model. Model ids are always
/// fetched from GET /models (never hardcoded — DeepSeek renames/deprecates them).
public enum DeepSeekClient {
    public enum ClientError: LocalizedError {
        case http(Int, String)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case let .http(code, body): "DeepSeek HTTP \(code): \(body.prefix(200))"
            case .emptyResponse: "DeepSeek returned an empty response"
            }
        }
    }

    private static let base = URL(string: "https://api.deepseek.com")!

    /// Long timeouts: a full-meeting summary generation can take minutes server-side.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    /// Models available to THIS key (also serves as the key-validation call).
    public static func listModels(key: String) async throws -> [String] {
        var req = URLRequest(url: base.appendingPathComponent("models"))
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
        return try decodeModels(data)
    }

    /// One chat completion (non-streaming). Throws on any transport/HTTP/parse issue —
    /// the caller falls back to the local model. `timeout` overrides the session's
    /// 300s default per-request — the live overlay needs a short one (~15s) so a
    /// stall degrades to the local model instead of freezing the context.
    public static func chat(key: String, model: String, system: String, user: String,
                            maxTokens: Int = 8000, timeout: TimeInterval? = nil) async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.6,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
        return try decodeChat(data)
    }

    /// Streaming chat completion (SSE, `stream: true`). `onText` receives the FULL
    /// accumulated text after every delta — send-the-whole-buffer makes delivery
    /// order-insensitive for actor-hopping callers. Returns the final text.
    ///
    /// DeepSeek under load keeps the connection alive with `: keep-alive` SSE
    /// comment lines for up to 10 minutes — an IDLE timeout never fires against
    /// that, so callers MUST wrap this in a wall-clock deadline and cancel.
    public static func chatStream(key: String, model: String, system: String, user: String,
                                  maxTokens: Int, onText: @escaping @Sendable (String) -> Void) async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.6,
            "stream": true,
            // LIVE path only: v4 models default into thinking mode and burn the
            // whole small token budget inside delta.reasoning_content — content
            // arrives empty (the overlay's "cloud returned nothing" bug). The
            // non-streaming summary path keeps DeepSeek's defaults.
            "thinking": ["type": "disabled"]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (bytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 300 { break }
            }
            throw ClientError.http(http.statusCode, body)
        }
        var text = ""
        loop: for try await line in bytes.lines {
            switch streamEvent(line) {
            case let .delta(piece):
                text += piece
                onText(text)
            case .done:
                break loop
            case .ignore:
                continue
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.emptyResponse }
        return trimmed
    }

    /// One SSE line → event. Tolerates `: keep-alive` comments, empty lines and
    /// `event:` fields (all `.ignore`); `data: [DONE]` ends the stream.
    enum StreamEvent: Equatable {
        case delta(String)
        case done
        case ignore
    }

    static func streamEvent(_ line: String) -> StreamEvent {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("data:") else { return .ignore }
        let payload = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(DeepSeekStreamChunk.self, from: data),
              let piece = chunk.choices.first?.delta.content, !piece.isEmpty
        else { return .ignore }
        return .delta(piece)
    }

    /// A model id that is STILL SERVED — DeepSeek retires ids (deepseek-chat /
    /// deepseek-reasoner die 2026-07-24), so a stored id must be re-validated
    /// against GET /models. `preferFast` picks a "flash" non-thinking id (the live
    /// overlay: a thinking model's ~55s first token is useless in real time).
    public static func resolveModel(key: String, stored: String?, preferFast: Bool) async throws -> String? {
        try await pickModel(from: listModels(key: key), stored: stored, preferFast: preferFast)
    }

    /// Pure selection (unit-tested): stored-if-valid, else flash, else first sane.
    static func pickModel(from models: [String], stored: String?, preferFast: Bool) -> String? {
        if preferFast {
            if let stored, models.contains(stored), !isThinking(stored), isFast(stored) { return stored }
            if let flash = models.first(where: { isFast($0) && !isThinking($0) }) { return flash }
            return models.first { !isThinking($0) } ?? models.first
        }
        if let stored, models.contains(stored) { return stored }
        return models.first { !isThinking($0) } ?? models.first
    }

    static func isThinking(_ id: String) -> Bool {
        id.localizedCaseInsensitiveContains("reasoner") || id.localizedCaseInsensitiveContains("think")
    }

    static func isFast(_ id: String) -> Bool {
        id.localizedCaseInsensitiveContains("flash") || id.localizedCaseInsensitiveContains("lite")
    }

    private static func checkHTTP(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(bytes: data, encoding: .utf8) ?? "")
        }
    }

    /// Split out for unit tests (no network).
    static func decodeModels(_ data: Data) throws -> [String] {
        try JSONDecoder().decode(DeepSeekModelsResponse.self, from: data).data.map(\.id)
    }

    static func decodeChat(_ data: Data) throws -> String {
        let text = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ClientError.emptyResponse }
        return text
    }
}

struct DeepSeekModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

struct DeepSeekChatResponse: Decodable {
    struct Message: Decodable { let content: String? }
    struct Choice: Decodable { let message: Message }
    let choices: [Choice]
}

struct DeepSeekStreamChunk: Decodable {
    struct Delta: Decodable { let content: String? }
    struct Choice: Decodable { let delta: Delta }
    let choices: [Choice]
}
