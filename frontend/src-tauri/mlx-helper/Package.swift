// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mlx-helper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.25.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.25.5"),
    ],
    targets: [
        .executableTarget(
            name: "mlx-helper",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            path: "Sources/mlx-helper"
        ),
    ]
)
