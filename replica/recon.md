# Recon map: Lightshot Screenshot (macOS) → Choxieshoot

Scope: the local capture-and-annotate loop (menu bar, area selection, annotation editor, save/copy/OCR), not the prntscr cloud.
For: people who want a fast, local-only Lightshot-style screenshot tool on macOS.
Date: 2026-11-05

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | installed app bundle | `/Applications/Lightshot Screenshot.app` | Info.plist, Mach-O strings/symbols, 70+ toolbar resources; no execution |
| 2 | App Store listing | https://apps.apple.com/us/app/lightshot-screenshot/id526298438?mt=12 | description + 3 public screenshots |
| 3 | App Store screenshot 1 | `replica/screens/lightshot-appstore-1.jpg` | editor chrome: selection badge top-left, vertical tool rail right, action bar below |
| 4 | App Store screenshot 2 | `replica/screens/lightshot-appstore-2.jpg` | in-context annotation over a browser page |
| 5 | App Store screenshot 3 | `replica/screens/lightshot-appstore-3.jpg` | menu-bar menu + preferences (custom hotkey) |
| 6 | Hacker News comments | `replica/reviews.csv` | what users say about the capture workflow, privacy and platforms (linked quotes only) |

No Lightshot code, assets, copy, logo or brand colour is reused. Icons are SF Symbols, type is the system font, accent is Choxieshoot teal.

## Core loop

Press a global shortcut → drag a region → annotate it immediately → copy, save or OCR the result — without creating an account or uploading anything.

## Screens

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Menu-bar menu | click status item | start capture, delayed capture, about, quit | menu items, status icon | idle |
| S02 | Selection overlay | ⌘⇧2 or menu item | pick the capture region | dimmed backdrop, crosshair guides, hint card, size badge, handles | idle, dragging, cancelled (Esc) |
| S03 | Annotation editor | release drag | annotate and export | canvas, size badge, toolbar, toast | empty history, annotated, undo/redo available, OCR busy, toast |
| S04 | Save panel | ⌘S / save button | write PNG, optionally copy too | save field, format, “Also copy to clipboard” checkbox | default, cancel |
| S05 | About / permission prompts | menu / first capture | explain shortcuts, privacy, screen-recording permission | alert | info, warning |

## Flows

```
F01 Capture an area and copy it
    S01/S02 -> S03
    happy path: hotkey, drag, release, ⌘C
    edge: capture cancelled, 8px minimum, permission denied, multi-display

F02 Annotate and save
    S02 -> S03 -> S04
    happy path: drag, pick tool, draw, ⌘S, choose path
    edge: save cancelled, no annotations, very tall capture (scaled to fit)

F03 Undo / redo
    S03
    happy path: draw, ⌘Z, ⇧⌘Z
    edge: undo to empty, redo cleared by a new annotation, eraser deletion undo

F04 Copy text from the screenshot (OCR)
    S03
    happy path: ⇧⌘C, wait, paste text elsewhere
    edge: no text found, OCR error, repeated taps while busy, non-English text

F05 Change style
    S03
    happy path: pick tool, colour, width
    edge: white on white, very thin/thick strokes

F06 Text annotation
    S03
    happy path: text tool, click, type, Return
    edge: Esc cancels, empty text, text near canvas edge

F07 Share / print
    S03
    happy path: share sheet
    edge: no share target; print is not implemented (parity gap)

F08 Delayed capture
    S01
    happy path: menu “Take Screenshot in 3 Seconds”, arrange menus, selection opens
    edge: repeated click, cancel
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Toolbar | single row; compact two-row | idle, hover, selected tool, disabled actions | S03 |
| Tool button | 9 tools | default, hover, selected, focus, disabled | S03 |
| Action button | undo, redo, OCR, copy, save, share, close | default, hover, disabled, busy (OCR) | S03 |
| Colour well + swatches | 8 preset + custom | default, selected ring, hover | S03 |
| Width slider | 1–20 px | default, focus | S03 |
| Canvas badge | size + optional scale % | static | S03 |
| Toast | info, success, error | fade in/out | S03 |
| Selection overlay | hint card, crosshair, border, handles, badge | idle, dragging | S02 |
| Editor window | borderless floating | key/non-key, fade-in, close | S03 |

## Inferred data model

Local-only; no account, network or database.

```
CaptureSession   image, pixel size, display scale, source screen rect, createdAt
                 evidence: S02/S03, screenshot sizes
                 confidence: high
Annotation       toolType, bezier path, colour, lineWidth, text, textPosition, filled
                 evidence: toolbar + canvas, all tools
                 confidence: high
HistorySnapshot  [Annotation] stack + index (undo/redo)
                 evidence: undo/redo buttons
                 confidence: high
Preferences      hotkey (fixed), theme (system), last save directory (panel memory)
                 evidence: menu, Info.plist
                 confidence: medium
```

Relationships: CaptureSession 1-n Annotation; CaptureSession 1-n HistorySnapshot (linear stack).

## Feature matrix

See `features.csv`. Must: 15, should: 11, could: 10, skip: 3. Parity score 88.1 with all 15 must-haves done (see `parity.md`).

## Out of scope (cannot or should not be cloned)

- prntscr.com upload and short links: the original's private service and network.
- prntscr cloud gallery, login and account sync.
- “Search visually similar images”: remote service.
- Lightshot's logo, feathered app icon, brand colour, marketing copy, resource art.
- Printing (parity gap, not a service limitation) and configurable hotkey/preferences.

## Size

Screens 5, flows 8, entities 4. Hard parts: screen-recording permission, Retina coordinate mapping, multi-display overlay, OCR ordering, window teardown. Size: M.
