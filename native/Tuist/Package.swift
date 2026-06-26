// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    // External SPM products are built as dynamic frameworks so their symbols are
    // linked once (app modules are static frameworks that link against them).
    productTypes: [
        "WhisperKit": .framework,
        "MLXLLM": .framework,
        "MLXLMCommon": .framework,
        "MLX": .framework,
        // MLXNN (+ the other mlx-swift modules) MUST be shared dynamic frameworks
        // too. Otherwise MLXNN is statically embedded into BOTH MLXLLM and
        // MLXLMCommon → two distinct `Linear`/`QuantizedLinear` types → model
        // quantization crashes with `unableToCast("Linear")` (Module.swift try!)
        // — same duplicate-type class of bug as Tokenizers, surfaces in Release.
        "MLXNN": .framework,
        "MLXRandom": .framework,
        "MLXFast": .framework,
        "MLXFFT": .framework,
        "MLXLinalg": .framework,
        "MLXOptimizers": .framework,
        "GRDB": .framework,
        // swift-transformers + Jinja must be SHARED dynamic frameworks — otherwise
        // both WhisperKit and MLXLMCommon statically embed the Tokenizers/Hub
        // classes, causing duplicate Obj-C class conflicts and "mysterious crashes"
        // (the summary-generation crash) when MLX uses its tokenizer.
        "Transformers": .framework,
        "Tokenizers": .framework,
        "Hub": .framework,
        "Generation": .framework,
        "Models": .framework,
        "TensorUtils": .framework,
        "Jinja": .framework,
    ]
)
#endif

let package = Package(
    name: "EmberDependencies",
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.25.5"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ]
)
