#!/bin/zsh
set -euo pipefail

# Build CLIP on any Apple Silicon Mac with Xcode's macOS SDK.
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${CLIP_APP_OUTPUT:-$HOME/Applications/CLIP.app}"
SIGN_IDENTITY="${CLIP_SIGN_IDENTITY:--}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(
  "$ROOT/Sources/CLIPApp.swift"
  "$ROOT/Sources/CLIPGlassView.swift"
  "$ROOT/Sources/ReplayDurationDial.swift"
  "$ROOT/Sources/InteractionStyles.swift"
  "$ROOT/Sources/NativeClipPlayer.swift"
  "$ROOT/Sources/ReplayEngine.swift"
  "$ROOT/Sources/ReplayWindowPolicy.swift"
)

echo "Compiling CLIP for Apple Silicon…"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 \
  "${SOURCES[@]}" -o "$APP/Contents/MacOS/CLIP"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/CLIP.icns" "$APP/Contents/Resources/CLIP.icns"
cp "$ROOT/Assets/CLIPLogo.png" "$APP/Contents/Resources/CLIPLogo.png"

# Default ad-hoc for reproducible local builds.
# Set CLIP_SIGN_IDENTITY to a Developer ID or Apple Development identity if available.
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
