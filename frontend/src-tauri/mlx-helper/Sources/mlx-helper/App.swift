import Foundation
import MLX
import MLXLLM
import MLXLMCommon

struct GenReq: Decodable {
    let type: String
    let prompt: String?
    let system: String?
    let model_path: String?
    let max_tokens: Int?
    let temperature: Float?
    let top_p: Float?
    let context_size: Int?
    let stop_tokens: [String]?
}

struct Resp: Encodable {
    let type: String
    let text: String?
    let error: String?
}

enum HelperError: Error { case notLoaded }

actor Engine {
    private var container: ModelContainer?
    private var loaded: String?
    private var didLimit = false

    func load(_ dir: String) async throws {
        if !didLimit {
            MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
            didLimit = true
        }
        if loaded == dir, container != nil { return }
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(directory: URL(fileURLWithPath: dir)))
        loaded = dir
    }

    func generate(
        system: String?, user: String,
        maxTokens: Int, temperature: Float, topP: Float, maxKV: Int
    ) async throws -> String {
        guard let container else { throw HelperError.notLoaded }
        let params = GenerateParameters(
            maxTokens: maxTokens, maxKVSize: maxKV, kvBits: 8, quantizedKVStart: 256,
            temperature: temperature, topP: topP)
        var out = ""
        try await container.perform { (ctx: ModelContext) in
            var chat: [Chat.Message] = []
            if let system, !system.isEmpty { chat.append(.system(system)) }
            chat.append(.user(user + "\n\n/no_think"))
            let input = try await ctx.processor.prepare(input: UserInput(chat: chat))
            var detok = NaiveStreamingDetokenizer(tokenizer: ctx.tokenizer)
            _ = try MLXLMCommon.generate(input: input, parameters: params, context: ctx) { tokens in
                guard let last = tokens.last else { return .more }
                detok.append(token: last)
                if let piece = detok.next(), !piece.isEmpty { out += piece }
                return .more
            }
        }
        return out
    }
}

func stripThink(_ s: String) -> String {
    var t = s
    if let r = t.range(of: "</think>") { t = String(t[r.upperBound...]) }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

func emit(_ r: Resp) {
    if let data = try? JSONEncoder().encode(r), let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    }
}

@main
struct MLXHelper {
    static func main() async {
        let engine = Engine()
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let req = try? JSONDecoder().decode(GenReq.self, from: data) else {
                emit(Resp(type: "response", text: nil, error: "invalid request"))
                continue
            }
            switch req.type {
            case "ping":
                emit(Resp(type: "pong", text: nil, error: nil))
            case "generate":
                do {
                    if let mp = req.model_path { try await engine.load(mp) }
                    let text = try await engine.generate(
                        system: req.system,
                        user: req.prompt ?? "",
                        maxTokens: req.max_tokens ?? 1024,
                        temperature: req.temperature ?? 0.7,
                        topP: req.top_p ?? 0.95,
                        maxKV: min(req.context_size ?? 8192, 8192))
                    emit(Resp(type: "response", text: stripThink(text), error: nil))
                } catch {
                    emit(Resp(type: "response", text: nil, error: String(describing: error)))
                }
            default:
                emit(Resp(type: "response", text: nil, error: "unknown type: \(req.type)"))
            }
        }
    }
}
