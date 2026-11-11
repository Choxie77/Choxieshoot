# Choxieshoot bug log (replica-test)

Only reproduced issues are listed. Severity: S1 data loss/security/core blocked,
S2 feature broken, S3 broken with workaround or visibly wrong, S4 cosmetic.

## B-01 — Esc during selection/editor could crash the app (S2, fixed)

- **Status:** fixed in v1.2, verified with stress runs
- **Steps:** press ⌘⇧2 to show the dimmed overlay, then press Esc; or open the
  editor and press Esc. Intermittent (roughly 3–8 of 10 runs in the harness).
- **Expected:** overlay/editor closes, app stays alive.
- **Actual:** `EXC_BAD_ACCESS` in `objc_release` during the autorelease-pool
  drain in `-[NSApplication run]`; process died with SIGSEGV. Instrumentation
  showed `-[SelectionWindow keyDown:]` → cancel block → `selectionWindow = nil`
  → `SelectionWindow dealloc` while AppKit was still handling the key event.
- **Evidence:** crash reports `Choxieshoot-2026-11-04-191935.ips`,
  `Choxieshoot-2026-11-04-192719.ips`, and the v1.2 reports from 2026-11-05;
  call stacks showed `keyDown:` → setter → dealloc, then the pool-drain crash.
- **Root cause:** the last strong reference to an `NSWindow` was dropped from
  inside that window's own event handling (and `releasedWhenClosed` defaults to
  YES), so AppKit continued with a deallocated window.
- **Fix:** `releasedWhenClosed = NO` on `SelectionWindow` and `EditorWindow`;
  dropping `selectionWindow` / removing an editor from `editingWindows` is now
  deferred one main-queue turn so AppKit finishes closing first.
- **Verification:** 15× `--overlaytest`, 10× `--flowtest`, 5× `--uitest` — zero
  failures, zero new crash reports; the earlier 20× overlay / 15× flow stress
  after the fix also passed.

## B-02 — Narrow captures were padded into a wide window (S3, fixed)

- **Steps:** capture a 520–640 px wide region; the v1.1 editor opened at a fixed
  860 px minimum width, so the screenshot sat between large empty margins and
  the single-row toolbar floated far wider than the image.
- **Expected:** editor hugs the capture; toolbar stays usable.
- **Actual:** large empty side margins, sparse toolbar (reproduced in
  `replica/clone-screens/before-v1.1-ui.png`).
- **Fix:** responsive toolbar: single row ≥880 px, two rows (tools above,
  actions below) below that; editor minimum width lowered to 600 px and the
  canvas is centred in the remaining space.
- **Verification:** `--uitest` → 640×504 compact window; `--uitestwide` →
  1000×492 single-row window; screenshots `final-compact.png` / `final-wide.png`.

## B-03 — Selection hint card was hard to read on busy screenshots (S4, fixed)

- **Steps:** show the selection overlay over a bright, detailed page.
- **Expected:** instruction text has a clear surface behind it.
- **Actual:** the 55% black card blended into the page; subtitle collided with
  page content (reproduced in `choxieshoot-overlay5.png`).
- **Fix:** 66% card, added an accent border, larger padding, title/subtitle
  spacing.
- **Verification:** `final-overlay.png`.

## B-04 — Light-mode input border failed WCAG non-text contrast (S4, fixed)

- **Steps:** run the replica-design contrast check on the light tokens.
- **Expected:** UI borders/focus rings ≥3:1.
- **Actual:** `border-input` 2.99:1 on `surface` (fail by 0.01).
- **Fix:** light `border-input` token changed `#8e8e93` → `#76767c`;
  re-checked 4.14:1, zero failures.
- **Evidence:** `replica/design/tokens-light.json`; contrast.py output in
  `test-artifacts/results.txt`.

## B-05 — Toolbar controls had no accessibility labels or pointer cursor (S4, fixed)

- **Steps:** VoiceOver / keyboard focus over the toolbar.
- **Expected:** every icon button announces its action; hover shows a pointer.
- **Actual:** only tooltips existed; no accessibility labels, no hover cursor.
- **Fix:** `setAccessibilityLabel:` on every control, exterior focus ring,
  pointing-hand cursor rects, OCR busy state announced through its tooltip.
- **Verification:** code audit; VoiceOver pass still on the manual checklist.

## B-07 — Screen Recording toggle ON but every capture was blocked (S2, fixed)

- **Steps:** with Choxieshoot enabled in System Settings → Screen Recording,
  open v1.4 and click New Screenshot.
- **Expected:** capture starts.
- **Actual:** the launcher kept saying “not granted” and v1.4 refused to start
  the selection overlay, because `CGPreflightScreenCaptureAccess()` returned
  false for this ad-hoc-signed build. The OS toggle was ON and captures actually
  worked, so the gate was a false negative.
- **Evidence:** user screenshot of the Screen Recording list with Choxieshoot ON;
  diagnostic `--capturetest` launched through LaunchServices reported
  `preflight=0 image=yes size=1470x956 blank=0` — real capture succeeded despite
  the API. `/tmp/choxieshoot-capturetest.log`.
- **Fix in v1.5:** removed the preflight gate; verify permission with a real
  capture/window-name probe; persist successful verification; blank captures
  still raise the permission card; added Reset Access and capture diagnostics.
- **Verification:** launcher shows “Screen Recording: granted” from the probe
  while preflight is false; all capture tests pass.

## B-08 — Captures included the desktop but not open app windows (S2, diagnostic + recovery fixed)

- **Steps:** with the Screen Recording toggle on, capture a region containing
  other apps.
- **Expected:** the apps’ windows appear in the screenshot.
- **Actual:** only the wallpaper/desktop appeared. That is the classic symptom of
  an effective denial even though the Settings toggle is on: the TCC grant is
  bound to an older ad-hoc signature/build.
- **Diagnosis:** `--capturetest` showed the app could produce a non-blank image
  (wallpaper), so the v1.5 “granted” probe was a false positive. v1.6’s stricter
  probe captures a corner of another app’s window with the desktop excluded and
  correctly reports not granted.
- **Recovery:** **Reset Access** (or `tccutil reset ScreenCapture
  com.choxieshoot.app`), reopen, Grant Access, enable the toggle for this build,
  and Restart App. Do not rebuild after granting; use a stable Developer ID for
  distribution.
- **Status:** app-side diagnostics/recovery fixed in v1.6; the final TCC toggle is
  user-controlled and must be performed on the final build.

## B-09 — Capture & launcher only worked in the Desktop Space where Choxieshoot was opened (S2, fixed in v1.7)

- **Steps:** open Choxieshoot on Desktop 1, switch to Desktop 2 (or a Full-Screen
  app Space), and press ⌘⇧2 or trigger a capture from the menu bar.
- **Expected:** selection overlay and editor appear on the current Desktop Space
  or Full-Screen app without switching Spaces.
- **Actual:** macOS either jumped back to Desktop 1 where `LauncherWindow` was
  opened, or failed the `screenCaptureProbe` on empty Desktops lacking an
  on-screen `layer == 0` window. In addition, the **Show Choxieshoot** menu bar
  and Dock menu item was disabled because `-showLauncher:` (with a colon) was
  not implemented.
- **Root cause:**
  1. `SelectionWindow` and `EditorWindow` were standard `NSWindow` instances and
     `SelectionWindow` ordered out for 150 ms before creating `EditorWindow`,
     leaving the active `Regular` app with zero visible windows on Desktop 2 while
     `LauncherWindow` was pinned to Desktop 1.
  2. `LauncherWindow` and `PreferencesWindow` lacked
     `NSWindowCollectionBehaviorCanJoinAllSpaces`.
  3. `screenCaptureProbe` only queried `kCGWindowListOptionOnScreenOnly` for
     `layer == 0` windows, returning `NO` on empty Desktop Spaces.
- **Fix in v1.7:**
  - `SelectionWindow` and `EditorWindow` now subclass `NSPanel` with
    `NSWindowStyleMaskNonactivatingPanel`, `floatingPanel = YES`, and
    `NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary`.
  - Added `CaptureScreenRectBelowWindow` (`kCGWindowListOptionOnScreenBelowWindow`)
    so the region below `SelectionWindow` is captured immediately and
    `EditorWindow` is ordered front before `SelectionWindow` closes (0 ms gap).
  - Added `NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary`
    to `LauncherWindow` and `PreferencesWindow`, and implemented `-showLauncher:`.
  - Updated `screenCaptureProbe` to probe windows across all Spaces when the
    current Desktop Space has no other open app windows.

## B-10 — Video save button didn't work and toolbar controls collided (S2, fixed)

- **Steps:** record a screen video, click Stop, and click the "Save MP4…" button
  in the Video Preview window.
- **Expected:** save sheet appears frontmost attached to the preview window with
  keyboard focus, pauses playback during save, offers an "Also copy to clipboard"
  option, and saves cleanly with .mp4 extension even if omitted.
- **Actual:** because `VideoPreviewWindow` was an `NSPanel` with
  `NSWindowStyleMaskNonactivatingPanel` and the app was not activated,
  `[panel runModal]` opened behind other windows or froze the window while
  blocking the main thread. Audio kept looping during save dialog. In addition,
  the bottom toolbar buttons ("Show in Finder" and "Copy Video") overlapped by
  14 px when the window was at default width, and the window was not resizable.
  Saving to a name without .mp4 produced extensionless files.
- **Fix:**
  1. Converted `[panel runModal]` to `[panel beginSheetModalForWindow:self completionHandler:...]`,
     activating the app (`[NSApp activateIgnoringOtherApps:YES]`) so the save
     sheet slides down directly on the preview window and takes focus immediately.
  2. Paused AVPlayer while the save dialog is open (and resume on cancel if
     previously playing).
  3. Added "Also copy to clipboard" checkbox in the save panel's accessory view.
  4. Switched to `allowedContentTypes` with `UTTypeMPEG4Movie` / `UTTypeQuickTimeMovie`
     and auto-appended `.mp4` if extension is omitted.
  5. Implemented dynamic responsive toolbar layout that prevents any control overlap
     at all widths, made the window resizable (`NSWindowStyleMaskResizable`),
     and set a sensible minimum size.
  6. Updated pasteboard copy to include `NSFilenamesPboardType` for maximum macOS
     app compatibility.
  7. Added `(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary)`.
- **Verification:** `--videotest` passes verifying video generation, extension
  auto-appending, and zero button overlap.

## Hardening (code-verified, not reproduced as a failure)

- OCR now ignores a second tap while a recognition is in progress and swaps the
  button to an hourglass; this prevents duplicate clipboard writes.
- OCR observations are grouped into visual line bands and each band sorted
  left-to-right, guarded by the two-column test.
- Save panel has an “Also copy to clipboard” checkbox so file + clipboard happen
  in one action (HN quote: always both copy and save).

## B-06 — Granting Screen Recording appeared to do nothing (S3, fixed)

- **Steps:** in v1.3, click Grant Access, switch Choxieshoot on in System
  Settings → Privacy & Security → Screen Recording, return to the app and click
  Check Again.
- **Expected:** the card turns green and capture works.
- **Actual:** the card still said “not granted” because macOS applies Screen
  Recording permission only to a newly launched process; v1.3 had no restart
  affordance, so the grant looked broken (reported with a screenshot of the
  v1.3 launcher).
- **Fix in v1.4:** **Restart App** in the permission card, **Restart
  Choxieshoot** in the app/status menus, and Check Again now offers **Restart
  Now** with an explanation. README documents the restart step and the
  `tccutil reset ScreenCapture com.choxieshoot.app` fallback for a stale entry.
- **Verification:** restart button and menu paths compile and appear in the
  launcher; automated permission changes cannot be simulated (TCC is
  user-controlled), so the final grant/restart is a one-time manual step.

## Known gaps / to check

- Print is not implemented (parity should-have).
- Configurable hotkey / preferences window not implemented (parity should-have).
- Multi-display overlay spans all screens but was only tested on the primary
  display.
- Share uses the macOS share sheet, not per-network buttons (partial parity).
- Manual checks: Esc/cancel paths, text tool, share sheet, VoiceOver, multi-display.
