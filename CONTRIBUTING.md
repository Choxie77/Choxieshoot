# Contributing to Choxieshoot

Thank you for your interest in improving Choxieshoot! We welcome bug fixes, documentation improvements, feature additions, and test cases.

## Design Philosophy

- **Native First**: Written in pure Objective-C / Cocoa for instant startup, zero dependencies, and tiny resource footprint.
- **Privacy & Offline**: 100% offline. No telemetry, no background network calls, and no cloud accounts.
- **Fast & Responsive**: Clean keyboard shortcuts, responsive layouts, and smooth animations.

## Getting Started

### Prerequisites
- macOS 11.0 Big Sur or later.
- Xcode Command Line Tools (`xcode-select --install`).
- That's it! No third-party package managers, Node, or Cocoapods needed.

### Building
Clone the repo and run the build script:
```bash
git clone https://github.com/Choxie77/Choxieshoot.git
cd Choxieshoot
./build.sh
```

The script compiles the source, packages `build/Choxieshoot.app`, signs it ad-hoc, and creates `build/Choxieshoot.dmg`.

### Running Tests
Choxieshoot features a comprehensive built-in test suite:
```bash
B="build/Choxieshoot.app/Contents/MacOS/Choxieshoot"

# Screenshot & Annotation tests
"$B" --selftest      # Capture + renderer + undo/redo
"$B" --drawtest      # Synthetic drawing & pixel assertions
"$B" --copytest      # Image pasteboard copy
"$B" --savetest      # Image compositing to PNG

# Vision OCR tests
"$B" --ocrselftest   # Vision OCR reading order & detection
"$B" --ocrflowtest   # OCR to clipboard pipeline

# Video Studio & Recording tests
"$B" --videotest     # End-to-end video recording, trimmer, crop, rotation, GIF & frame export
```

## Pull Request Guidelines

1. Fork the repo and create your branch from `main`: `git checkout -b feature/amazing-feature`
2. Ensure your changes compile without warnings: `./build.sh`
3. Run the automated tests to verify no regressions:
   ```bash
   ./build/Choxieshoot.app/Contents/MacOS/Choxieshoot --selftest
   ./build/Choxieshoot.app/Contents/MacOS/Choxieshoot --drawtest
   ./build/Choxieshoot.app/Contents/MacOS/Choxieshoot --videotest
   ```
4. Write clear, concise commit messages.
5. Push to your fork and submit a Pull Request against `main`.
