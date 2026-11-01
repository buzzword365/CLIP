# CLIP for macOS

![CLIP app icon](Assets/CLIPLogo.png)

**Instant replay, designed for Mac.** CLIP is a lightweight native macOS app that keeps a short local recording buffer, then saves recent gameplay or desktop activity when you press **⌘ Shift S**.

Built with **SwiftUI**, **ScreenCaptureKit**, and **AVFoundation**. No accounts, cloud uploads, analytics, or subscriptions are required for local clipping.

## Features

- **Instant replay:** Press **⌘ Shift S** to save your recent footage as an MP4.
- **Rotary replay dial:** Choose 15 seconds, 30 seconds, 1, 2, 3, 5, or 10 minutes.
- **Audio control:** Include system/game audio; optionally enable microphone recording.
- **Quality settings:** 720p, 1080p, 1440p or native resolution; 30 or 60 FPS targets.
- **Clip library:** Browse thumbnails, preview clips, show videos in Finder, and move unwanted recordings to Trash.
- **Glass UI:** Translucent controls, trackpad haptics where supported, motion accessibility support.
- **Menu bar:** Background capture, quick save/pause, and launch-at-login preference.
- **Local files:** Saved videos live in `~/Movies/CLIP`.

> **Preview release:** CLIP is an early project, not a production-equivalent replacement for Medal. Current capture uses the first available display rather than game-specific capture. Some games, protected videos, and system configurations may not capture perfectly. Microphone capture is selectable but has not been extensively field-tested.

## Download and install

Get the latest **CLIP-macOS-arm64.zip** from [Releases](../../releases).

1. Unzip the download and move **CLIP.app** to **Applications**.
2. Open CLIP. On first launch, macOS may block the app because this preview build is **not Apple-notarized**. Review the application and use macOS **Privacy & Security → Open Anyway** if you trust this release.
3. Grant **Screen & System Audio Recording** access to CLIP.
4. CLIP will maintain a rolling recording buffer. Press **⌘ Shift S** to save a replay.
5. Use Settings to change duration, microphone, quality, frame rate, notification and login options.

**Requirements:** Apple Silicon Mac, macOS **15.0 or later**. Liquid Glass appearance is best on macOS 26.

**Privacy:** CLIP captures only after macOS grants recording permission. It stores clips locally. Be considerate of other people's privacy and obtain appropriate consent.

### About signing

Prebuilt preview downloads are **ad-hoc signed**, but **not notarized** or distributed with a Developer ID certificate. Gatekeeper warnings are expected. Do not disable Gatekeeper system-wide. A future public production release should be signed with Developer ID and notarized through Apple.

## Build from source

Install full Xcode and its command-line tools, then run:

```bash
git clone https://github.com/buzzword365/CLIP.git
cd CLIP
zsh build.sh
open ~/Applications/CLIP.app
```

To sign the local build with a code-signing identity you own:

```bash
CLIP_SIGN_IDENTITY="Your code signing identity" zsh build.sh
```

To place the build elsewhere, set `CLIP_APP_OUTPUT` to the desired `.app` path.

To regenerate the logo artwork from source:

```bash
swift Tools/render_icon.swift
```

## Repository layout

```text
Sources/           SwiftUI app, UI interactions, recording engine
Assets/            Original CLIP icon artwork and macOS .icns
Tools/             Script to regenerate logo artwork
Info.plist         macOS bundle metadata and privacy descriptions
build.sh           Portable Apple Silicon build script
```

## Known limitations

- Captures the first detected display. Selecting specific windows/games isn't implemented.
- No timeline editor, webcam overlay or automatic highlight detection yet.
- File format uses H.264/AAC. Frame rate and output dimensions depend on the captured display and system performance.
- Mac screen and microphone permissions are controlled by macOS.
- Advanced audio mixing and long-session stress testing need additional QA.

## License

**No open-source license has been granted.** The source is publicly visible for inspection and education; reuse or redistribution of this project requires the copyright holder's permission. The project is unaffiliated with Medal.tv.

## Security

Please report security issues privately to the repository maintainer rather than posting sensitive recordings publicly.
