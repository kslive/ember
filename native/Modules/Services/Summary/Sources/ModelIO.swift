import Core
import Foundation
import MLXLMCommon
import Tokenizers

/// Local-first model IO for the 3.x MLX stack. mlx-swift-lm dropped its built-in
/// hub client, so Ember downloads repo files itself (same URLSession pattern as
/// the GigaAM files) into `ModelPaths.mlxModelDir` and loads models from that
/// directory — presence checks, byte progress and delete flows keep working on
/// the exact same paths they always used.
enum HubFetch {
    struct RepoFile: Decodable {
        let rfilename: String
        let size: Int64?
    }

    private struct RepoInfo: Decodable {
        let siblings: [RepoFile]
    }

    static func files(repo: String) async throws -> [RepoFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(RepoInfo.self, from: data).siblings.filter { file in
            !file.rfilename.hasPrefix(".") && !file.rfilename.lowercased().hasPrefix("readme")
        }
    }

    /// Downloads every repo file into `dir`, skipping files already present with
    /// the expected size (cheap resume after a cancelled download).
    static func download(repo: String, into dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in try await files(repo: repo) {
            try Task.checkCancellation()
            let dest = dir.appendingPathComponent(file.rfilename)
            if let size = file.size,
               let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
               (attrs[.size] as? Int64) == size { continue }
            guard let src = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file.rfilename)") else {
                throw URLError(.badURL)
            }
            let (tmp, response) = try await URLSession.shared.download(from: src)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }
}

/// swift-transformers `AutoTokenizer` adapted to the `MLXLMCommon.Tokenizer`
/// protocol — the hand-written equivalent of the MLXHuggingFace macro expansion,
/// avoiding the macro package and its HuggingFace-client dependency (the
/// swift-transformers stack is already in the app via WhisperKit).
struct EmberTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        var template: String?
        let jinja = directory.appendingPathComponent("chat_template.jinja")
        if let text = try? String(contentsOf: jinja, encoding: .utf8), !text.isEmpty {
            template = text
        } else if (try? upstream.applyChatTemplate(messages: [["role": "user", "content": "x"]])) == nil {
            template = Self.chatML
        }
        return TokenizerBridge(upstream, templateOverride: template)
    }

    /// Some MLX conversions (e.g. the 2507 DWQ repos) strip the chat template
    /// entirely; without it prompts degrade to plain concatenated text and the
    /// model rambles to the token limit. Every model in Ember's catalog is
    /// Qwen3-family, so plain ChatML is the correct shape.
    private static let chatML =
        "{% for message in messages %}<|im_start|>{{ message['role'] }}\n"
            + "{{ message['content'] }}<|im_end|>\n{% endfor %}<|im_start|>assistant\n"
}

final class TokenizerBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: any Tokenizers.Tokenizer
    private let templateOverride: String?

    init(_ upstream: any Tokenizers.Tokenizer, templateOverride: String? = nil) {
        self.upstream = upstream
        self.templateOverride = templateOverride
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? {
        upstream.bosToken
    }

    var eosToken: String? {
        upstream.eosToken
    }

    var unknownToken: String? {
        upstream.unknownToken
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        let plain = messages.map { $0 as [String: Any] }
        if let templateOverride {
            return try upstream.applyChatTemplate(messages: plain, chatTemplate: templateOverride)
        }
        do {
            return try upstream.applyChatTemplate(
                messages: plain,
                tools: tools.map { $0.map { $0 as [String: Any] } },
                additionalContext: additionalContext.map { $0 as [String: Any] }
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
