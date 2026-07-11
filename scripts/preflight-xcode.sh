#!/usr/bin/env bash
# Fail fast if the Metal compiler is missing (Command Line Tools alone are not enough).
#
# MLX Swift needs the full Xcode.app Metal toolchain at runtime / when packaging
# metallib. With only Command Line Tools, `swift build` can still succeed, but
# the binary fails with: Failed to load the default metallib
#
# Usage: ./scripts/preflight-xcode.sh
# Exit 0 if metal is available; non-zero with an actionable message otherwise.
set -euo pipefail

if ! command -v xcrun >/dev/null 2>&1; then
  cat >&2 <<'EOF'
error: xcrun not found.

MacWispr requires full Xcode.app (not only Command Line Tools).

  1. Install Xcode from the Mac App Store
  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. xcodebuild -runFirstLaunch
  4. (if needed) xcodebuild -downloadComponent MetalToolchain

Then re-run your build or: ./bench.sh
EOF
  exit 1
fi

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  cat >&2 <<'EOF'
error: Metal compiler not found (xcrun -sdk macosx metal --version failed).

Command Line Tools alone cannot compile Metal shaders. That leads to the
runtime MLX error:
  Failed to load the default metallib

Install full Xcode.app and point the active developer directory at it:

  1. Install Xcode from the Mac App Store (or developer.apple.com)
  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. xcodebuild -runFirstLaunch
  4. If metal is still missing:
       xcodebuild -downloadComponent MetalToolchain
  5. Verify:
       xcrun -sdk macosx metal --version

See README.md → Requirements and Troubleshooting.
EOF
  exit 1
fi
