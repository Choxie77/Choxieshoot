# Choxieshoot component specs (replica-design)

Typeface: system SF Pro (no licensed font copied). Icons: SF Symbols (open,
system-provided). Spacing: 4/8/12/16/24. Radius: 6/10/12. Motion: 120/160 ms.
Accent: Choxieshoot teal, never the target's brand colour.

## Editor window

```
Window
  size        capture width × (capture height + toolbar + 8px gap); min 600 wide
  chrome      borderless, floating level, 12px radius, 1px border, shadow
  tokens      bg surface, border border, radius lg, shadow window
  states      fade-in 160 ms; movable by background drag
  a11y        can become key; Esc closes; focus starts on the canvas
  used on     S03
```

## Toolbar

```
Toolbar
  layouts     single row ≥880 px (64 px high); compact two rows <880 px (96 px high)
  row 1       tool group, colour well + 8 swatches, width slider 64 px
  row 2       undo redo | OCR copy save share | close, centred
  tokens      bg controlSurface, top hairline border, radius none (inside window)
  states      tools selected (accent 28% fill), hover (accent 12%), disabled 35% alpha
  a11y        every control has an accessibility label and tooltip; pointer cursor
  used on     S03
```

## Tool button

```
ToolButton (9: pencil, line, arrow, rectangle, ellipse, marker, text,
            eyedropper, eraser)
  size        30×30, radius 6
  states      default, hover, selected, focus-visible, disabled
  tokens      icon text, selected bg accent/28%, hover bg accent/12%
  a11y        NSButton with label = tool name; keyboard focus ring exterior
  used on     S03
```

## Action button

```
ActionButton (undo, redo, OCR, copy, save, share, close)
  size        28×28, radius 6
  states      default, hover, disabled, OCR busy (hourglass, disabled)
  tokens      icon text; OCR tint accent; close tint danger
  a11y        label + tooltip; busy state announced by tooltip
  used on     S03
```

## Colour controls

```
ColourWell          24×24; system colour panel; label “Custom colour”
Swatch ×8           12×12; selected = 2px text-colour ring, else 1px border
  tokens            accent is not used for swatches (user colours are arbitrary)
  used on           S03
```

## Width slider

```
Slider       64 px wide, 1–20, label “3px” in mono 10px, muted text
  a11y       label “Stroke width”
  used on    S03
```

## Canvas badge

```
Badge
  content    “W × H” in capture points, plus scale % when the editor scales down
  position   bottom-right of the canvas, 10px inset
  tokens     bg accent, text on-accent, radius 5, mono 11 semibold
  contrast   7.09:1 (dark), 4.89:1 (light)
  used on    S02, S03
```

## Toast

```
Toast
  content    action confirmation (“Image copied”, “Saved …”, “Copied N characters”, errors)
  position   centred above the toolbar, 16px gap
  tokens     bg black/80%, text white, radius 6, shadow toast
  motion     fade in 160 ms, fade out 220 ms; single-line, tail truncation
  max width  window width − 40px
  used on    S03
```

## Selection overlay

```
Overlay
  backdrop   full screen union, black/42%
  selection  1.5px dashed white border, 8×8 corner handles, accent badge
  guides     accent/30% full-width + full-height crosshair lines
  hint card  “Drag to capture an area” 18 semibold / “Press Esc to cancel” 12;
             black/66% rounded 12 card with accent/55% border, centred
  states     idle (hint), dragging (border + badge), cancelled (Esc)
  a11y       crosshair cursor, Esc cancels
  used on    S02
```

## States checklist

Every control has: default, hover, focus-visible, disabled. The OCR action also
has a busy state. Empty/error states live in toasts and alerts.
