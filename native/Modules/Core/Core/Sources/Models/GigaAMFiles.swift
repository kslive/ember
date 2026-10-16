import Foundation

/// The sherpa-onnx export of GigaAM v3 (RNN-T, Russian) that Ember downloads file
/// by file into `ModelPaths.gigaAMModelDir(_:)`.
public enum GigaAMFiles {
    public static let repo = "csukuangfj/sherpa-onnx-nemo-transducer-giga-am-v3-russian-2025-12-16"

    /// Everything the recognizer needs; the model counts as downloaded only when all are present.
    public static let names = ["encoder.int8.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"]

    public static func url(_ name: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(name)")!
    }
}
