#!/usr/bin/env bash
# sherpa-onnx-spm ships TWO binary xcframeworks (sherpa-onnx + onnxruntime) that BOTH
# place a root-level Headers/module.modulemap. Xcode copies each into the shared
# $(BUILT_PRODUCTS_DIR)/include/ → "Multiple commands produce …/include/module.modulemap".
# Nothing imports the `onnxruntime` clang module (the Swift wrapper only does
# `@_exported import sherpa_onnx`; onnxruntime is link-only), so deleting ITS
# modulemap resolves the collision without breaking anything.
#
# Run after EVERY `tuist install` (artifacts are re-extracted). package.sh calls this.
set -euo pipefail
cd "$(dirname "$0")/.."
find Tuist/.build/artifacts/sherpa-onnx-spm/onnxruntime -name module.modulemap -delete 2>/dev/null || true
echo "🔧 sherpa-onnx artifacts patched (onnxruntime modulemap removed)"
