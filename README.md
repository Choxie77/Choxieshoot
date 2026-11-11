# Choxieshoot

[![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue.svg)](https://apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-teal.svg)](LICENSE)
[![Latest Release](https://img.shields.io/badge/release-v1.7-emerald.svg)](https://github.com/Choxie77/Choxieshoot/releases)

A lightweight, native Lightshot-style screenshot and screen recording utility for macOS. Built with pure Objective-C and Cocoa — zero external dependencies, ultra-fast launch, 100% offline and privacy-first.

The app lives in your Dock and menu bar, captures any screen region with a dimmed drag-selection overlay, and opens a responsive floating editor with a complete suite of annotation, OCR, and video recording tools.

---

## Quick Start

### Download Prebuilt
1. Download the latest release from [GitHub Releases](https://github.com/Choxie77/Choxieshoot/releases).
2. Unzip `Choxieshoot-1.7.zip` and move `Choxieshoot.app` to your `/Applications` folder.
3. Launch the app and grant Screen Recording access in macOS System Settings when prompted.

### Or Build From Source
```bash
git clone https://github.com/Choxie77/Choxieshoot.git
cd Choxieshoot
./build.sh
open build/Choxieshoot.app
```
*Requires Xcode Command Line Tools (`xcode-select --install`). No third-party dependencies, no Node, no package manager.*

---

## Features

### 📸 Screenshot & Annotations
- **Region, Fullscreen & Delayed Capture** — ⌘⇧2, menu bar, launcher, or Dock menu. Dimmed crosshair overlay with live dimension badge and corner drag handles.
- **Floating Responsive Editor** — Automatically adapts between single-row and two-row toolbars depending on capture size; hugs your screenshot with zero wasted margins.
- **Full Annotation Suite** — Pencil, line, arrow, rectangle, ellipse, highlighter, text, eyedropper, and eraser. 8-color quick palette + macOS native color panel; 1–20 px stroke width slider.
- **Rich Text Tool** — Multi-line text annotations with live sizing, 10–72 pt font sizes, bold styling, optional solid background, and drop shadow for maximum legibility on any background.
- **Eyedropper & Color Inspector** — Hover any pixel for a live HEX/RGB loupe under your cursor. Color Inspector panel displays **HEX, RGB, HSB, and HSL** with one-click copy buttons.
- **On-Device Vision OCR** — Extract text directly from screenshots to your clipboard (⇧⌘C) using Apple Vision; multi-column reading order detection with toast feedback.
- **One-Click Save & Copy** — Save directly to disk (⌘S) with an optional *"Also copy to clipboard"* checkbox, or copy annotated images straight to your pasteboard (⌘C).
- **Undo / Redo History** — Full snapshot history including eraser deletions (⌘Z / ⇧⌘Z).

### 🎥 Video Screen Recording (v1.7)
- **Region Video Recording** — Capture designated screen regions into smooth H.264 `.mp4` video.
- **Audio Capture** — Optional microphone recording for voiceovers and tutorials.
- **Motion Blur & Cursor Tracking** — Configurable shutter motion blur (Subtle, Cinematic, Heavy) and cursor smoothing.
- **Built-in Timeline Trimmer** — Non-destructive in-app video trimming, cropping, and instant preview before export.

### 🔒 Privacy & Performance
- **100% Local & Offline** — No cloud accounts, no background analytics, no telemetry, and zero network calls.
- **Native Cocoa / Objective-C** — Zero electron/web bloat. Instant startup, tiny memory footprint, and low CPU usage.
- **Smart Permission Diagnostic** — Probes real window capture access to avoid false-negative TCC permission traps on ad-hoc builds.

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧2 | Capture screen region |
| ⌘N | New screenshot from editor |
| ⌘S | Save PNG |
| ⌘C | Copy image to clipboard |
| ⇧⌘C | Copy text via OCR |
| ⌘Z | Undo |
| ⇧⌘Z | Redo |
| Esc | Close editor / cancel selection |
| Drag background | Move the editor window |

---

## Building & Testing

### Compile
```bash
./build.sh
```
Frameworks used: `Cocoa`, `Carbon`, `CoreGraphics`, `CoreImage`, `Vision`, `AVFoundation`, `AVKit`, `CoreMedia`, `CoreVideo`, `UniformTypeIdentifiers`.

### Run Self-Tests
```bash
B=build/Choxieshoot.app/Contents/MacOS/Choxieshoot
$B --selftest      # Capture + renderer + undo/redo
$B --ocrselftest   # Vision OCR reading order & detection
$B --ocrflowtest   # OCR to clipboard pipeline
$B --drawtest      # Synthetic drawing & pixel assertions
$B --copytest      # Image pasteboard copy
$B --savetest      # Image compositing to PNG
$B --uitest        # Compact editor layout test
$B --uitestwide    # Wide editor toolbar test
$B --uitestcolor   # Eyedropper & Color Inspector test
$B --uitesttext    # Text annotation panel test
$B --flowtest      # End-to-end capture to editor flow
```

---

## Project Structure

```
Choxieshoot/
├── build.sh                     # Clang compile + .app bundle + ad-hoc sign script
├── LICENSE                      # MIT License
├── README.md                    # Project documentation
├── Choxieshoot/                 # Application source code
│   ├── main.m                   # Entry point + test mode dispatcher
│   ├── AppDelegate.{h,m}        # App lifecycle, status bar item, hotkeys, dock menu
│   ├── SelectionWindow.{h,m}    # Dimmed full-screen selection overlay
│   ├── EditorWindow.{h,m}       # Floating annotation editor window
│   ├── CanvasView.{h,m}         # Screenshot canvas, annotation rendering, eyedropper
│   ├── ToolbarView.{h,m}        # Responsive action and toolbars
│   ├── ColorInspectorView.{h,m} # HEX/RGB/HSB/HSL color inspector
│   ├── LauncherWindow.{h,m}     # Main launcher & permission manager
│   ├── PreferencesWindow.{h,m}  # App preferences & recording settings
│   ├── VideoRecorder.{h,m}      # AVFoundation screen & audio recording engine
│   ├── VideoPreviewWindow.{h,m} # Video player & timeline trimmer
│   ├── TextRecognizer.{h,m}     # Vision OCR engine
│   ├── CSTheme.{h,m}            # Semantic design tokens & WCAG AA colors
│   ├── Info.plist               # App metadata
│   └── AppIcon.icns             # Application icon
├── replica/                     # Research artifacts, design tokens & test plans
└── swift-reference/             # Earlier Swift implementation (reference only)
```

---

## Granting Screen Recording Permission

macOS requires explicit Screen Recording permission for apps capturing window contents.

1. Launch Choxieshoot.
2. In the launcher window, check the **Screen Recording** card. If green, you're ready!
3. If red: click **Grant Access**, toggle **Choxieshoot** ON in **System Settings → Privacy & Security → Screen Recording**, then return and click **Restart App**.
4. If permissions ever get stuck after updating, click **Reset Access** (or run `tccutil reset ScreenCapture com.choxieshoot.app`).

---

## Contributing

Contributions, bug reports, and pull requests are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add awesome feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

Choxieshoot is licensed under the [MIT License](LICENSE).
