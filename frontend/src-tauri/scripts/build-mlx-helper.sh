#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_TAURI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER_DIR="${SRC_TAURI_DIR}/mlx-helper"
BINARIES_DIR="${SRC_TAURI_DIR}/binaries"
TARGET_TRIPLE="aarch64-apple-darwin"
OUTPUT="${BINARIES_DIR}/mlx-helper-${TARGET_TRIPLE}"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

echo "==> Building mlx-helper (release)"
echo "    DEVELOPER_DIR=${DEVELOPER_DIR}"
echo "    package dir=${HELPER_DIR}"

cd "${HELPER_DIR}"
xcrun swift build -c release

BUILT_BIN="${HELPER_DIR}/.build/release/mlx-helper"
if [[ ! -f "${BUILT_BIN}" ]]; then
    echo "ERROR: build did not produce ${BUILT_BIN}" >&2
    exit 1
fi

mkdir -p "${BINARIES_DIR}"
cp "${BUILT_BIN}" "${OUTPUT}"
chmod +x "${OUTPUT}"

echo "==> Copied sidecar to:"
echo "    ${OUTPUT}"

CMLX_BUNDLE="${HELPER_DIR}/.build/release/mlx-swift_Cmlx.bundle"
if [[ ! -d "${CMLX_BUNDLE}" ]]; then
    echo "ERROR: missing ${CMLX_BUNDLE} (MLX Metal resources)" >&2
    exit 1
fi
rm -rf "${SRC_TAURI_DIR}/mlx-swift_Cmlx.bundle"
cp -R "${CMLX_BUNDLE}" "${SRC_TAURI_DIR}/mlx-swift_Cmlx.bundle"

echo "==> Staged Metal resources to:"
echo "    ${SRC_TAURI_DIR}/mlx-swift_Cmlx.bundle"
