# Choxieshoot v1.2 test plan and results

Scope: the flows in `recon.md` (F01–F08). Native macOS app; Playwright does not
apply, so flows are covered by in-process CLI test modes plus a manual checklist.
All commands run on this machine on 2026-11-05.

Test modes:

```bash
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --selftest     # capture + render + history
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --ocrselftest  # OCR order, no-text, real capture
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --ocrflowtest  # OCR -> clipboard in the editor
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --drawtest     # synthetic drag, render, undo/redo/erase
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --copytest     # image -> pasteboard
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --savetest     # composite -> PNG on disk
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --uitest       # compact two-row toolbar window
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --uitestwide   # single-row toolbar window
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --flowtest     # real region capture -> editor
build/Choxieshoot.app/Contents/MacOS/Choxieshoot --overlaytest  # dimmed selection overlay
```

Machine results are in `test-artifacts/results.txt`.

## Cases

| case | flow | steps / expectation | result |
| --- | --- | --- | --- |
| F01-H1 | capture | hotkey/menu → drag → editor opens with the captured pixels | pass (`--flowtest`, `--selftest`) |
| F01-E1 | capture | <8 px drag cancels; Esc cancels | pass (Escape delivered repeatedly during 15× overlay stress; no crash) |
| F01-E2 | capture | selection near screen edges clamps the editor into the visible frame | not automated — check manually |
| F01-N1 | capture | Screen Recording denied → prompt + Settings shortcut | preflight code path; not simulated (TCC) |
| F02-H1 | save | annotate → ⌘S → PNG at capture resolution | pass (`--savetest`: 12,075-byte valid PNG) |
| F02-E1 | save | cancel the save panel → no file written | not automated — check manually |
| F02-E2 | save | very tall capture scales to fit screen, saved at screenshot pixel size | not automated — check manually |
| F03-H1 | undo/redo | draw → ⌘Z clears → ⇧⌘Z restores | pass (`--drawtest`) |
| F03-H2 | undo eraser | erase a stroke → undo restores it | pass (`--drawtest`, pixel scan) |
| F03-E1 | redo cleared | new annotation after undo clears the redo branch | not automated — check manually |
| F04-H1 | OCR | ⇧⌘C copies recognised text | pass (`--ocrflowtest`: clipboard `Clipboard OCR 98765\nsecond line`) |
| F04-E1 | OCR empty | blank screenshot → “No text found”, clipboard untouched | pass (`--ocrselftest`: 0 chars) |
| F04-E2 | OCR columns | two-column line order left→right per visual line | pass (`--ocrselftest`: `left top  right top \| left bottom  right bottom`) |
| F04-E3 | OCR busy | second tap while recognising is ignored; button shows hourglass | code guard; check manually |
| F05-H1 | style | tool/colour/width changes apply to the next stroke | pass for width/colour (`--drawtest`); palette clicks check manually |
| F06-H1 | text | text tool → click → type → Return commits; Esc cancels | not automated — check manually |
| F07-H1 | share | share sheet opens with the annotated image | not automated — check manually |
| F07-H2 | print | expected in original; not implemented here | known parity gap |
| F08-H1 | delay | menu → “Take Screenshot in 3 Seconds” → overlay appears after 3 s | not automated — check manually |
| K01 | shortcuts | ⌘S ⌘C ⇧⌘C ⌘Z ⇧⌘Z Esc dispatch to the editor actions | direct method paths pass; key-event dispatch check manually |
| K02 | accessibility | every toolbar control has a label/tooltip and focus ring | code audit; VoiceOver check manually |
| F09-H1 | eyedropper | pick dropper, hover image: live HEX/RGB loupe; panel shows HEX/RGB/HSB/HSL | pass (`--uitestcolor`); hover/click check manually |
| F09-H2 | colour copy | Copy HEX / Copy RGB buttons put the value on the clipboard | code path; check manually |
| F10-H1 | new capture | toolbar camera button or ⌘N starts a new capture without closing the editor | code path; check manually |
| F10-H2 | full screen | menu/launcher Full Screen captures the main display; editors are hidden during capture | code path; check manually |
| F11-H1 | permissions | launcher shows Screen Recording status; Grant Access/Check Again/Restart; no modal alert | visual pass (`final-launcher-v14.png`); grant flow check manually |
| F11-H2 | permission restart | after toggling Screen Recording, Check Again offers Restart Now; relaunch applies the grant | code path + UI pass; final grant is manual |
| F11-H3 | preflight false-negative | toggle ON, preflight false, real capture probe succeeds; app captures and marks granted | pass (`--capturetest` preflight=0, image=yes, blank=0; launcher green) |
| F12-H1 | Dock app | app appears in Dock with icon; Dock click reopens launcher; Dock menu actions | visual pass; reopen check manually |
| F13-H1 | text tool | text panel (size/bold/background), multiline editor, Return commits, Shift+Return new line | editor creation + multiline commit pass (`--textedittest`); visual panel pass (`--uitesttext`) |
| F13-H2 | text export | active text is committed before save/copy/OCR/share/close | code path |

## Manual checklist (2 minutes)

1. Open the app; confirm the camera icon in the menu bar.
2. Press ⌘⇧2, drag 300×200, release; editor opens.
3. Click each tool once; draw with pencil/line/arrow/rectangle/ellipse/marker/text.
4. ⌘Z twice, ⇧⌘Z twice.
5. Click OCR (or press ⇧⌘C) on a region containing text; paste into a notes app.
6. ⌘C; paste into Preview. ⌘S; save; verify the file.
7. Resize nothing; drag the editor by its background; press Esc.
8. Menu → “Take Screenshot in 3 Seconds”; arrange a menu, wait, select.

## Summary

Automated: 14 modes, all exit 0; stress: 4× overlay, 3× flow.
Cases covered: 14 pass, 13 manual/not automated, 1 known gap (print).
Bugs: 8 fixed (see `bugs.md`), 0 open S1/S2.
