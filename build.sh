#!/bin/zsh
set -euo pipefail

# Build CLIP on any Apple Silicon Mac with Xcode's macOS SDK.
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${CLIP_APP_OUTPUT:-$HOME/Applications/CLIP.app}"
# Screen recording permission is tied to the signing requirement. Re-signing with
# "-" (ad-hoc) on each build changes that requirement and invalidates old grants.
# Prefer a persistent Apple Development identity when installed on this Mac.
SIGN_IDENTITY="${CLIP_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' | head -n 1)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  echo "Warning: no Apple Development signing identity available; screen capture permissions may need re-granting after updates." >&2
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(
  "$ROOT/Sources/CLIPApp.swift"
  "$ROOT/Sources/CLIPGlassView.swift"
  "$ROOT/Sources/ReplayDurationDial.swift"
  "$ROOT/Sources/InteractionStyles.swift"
  "$ROOT/Sources/NativeClipPlayer.swift"
  "$ROOT/Sources/ClipTrimEditor.swift"
  "$ROOT/Sources/ClipTrimExporter.swift"
  "$ROOT/Sources/ReplayEngine.swift"
  "$ROOT/Sources/CLIPFrameRetiming.swift"
  "$ROOT/Sources/ReplayWindowPolicy.swift"
)

echo "Compiling CLIP for Apple Silicon…"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 \
  "${SOURCES[@]}" -o "$APP/Contents/MacOS/CLIP"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/CLIP.icns" "$APP/Contents/Resources/CLIP.icns"
cp "$ROOT/Assets/CLIPLogo.png" "$APP/Contents/Resources/CLIPLogo.png"

# Explicitly override with CLIP_SIGN_IDENTITY if you use a different stable identity.
echo "Signing CLIP with: $SIGN_IDENTITY"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
