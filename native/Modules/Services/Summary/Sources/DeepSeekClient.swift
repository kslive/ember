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
    /// the caller falls back to the local model.
    public static func chat(key: String, model: String, system: String, user: String,
                            maxTokens: Int = 8000) async throws -> String {
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
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
        return try decodeChat(data)
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
