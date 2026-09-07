# Mousepad for macOS

A small, fast, native text editor. Same feature set as Xfce's Mousepad, 1990s terminal look:
black, monospace, square, one orange accent. Swift + AppKit, no Xcode required.

## Build and run

```sh
./Scripts/make-app.sh        # -> dist/Mousepad.app (release, ad-hoc signed)
open dist/Mousepad.app
open -a dist/Mousepad.app some/file.txt
```

Development:

```sh
swift build && .build/debug/Mousepad file.txt   # debug run
swift run MousepadCheck                          # core self-checks (TextFile, TextOps, Highlighter)
```

The command line tools ship no XCTest, so checks are plain asserts in `Tests/MousepadCheck`.

First launch on another Mac: right-click the app, Open (ad-hoc signature, no notarization).

## Layout

| Path | What |
|---|---|
| `Sources/MousepadCore/` | Pure Foundation: `TextFile` (encoding, BOM, line endings), `TextOps` (edit commands), `Languages` + `Highlighter` (regex syntax colors), `Encodings` |
| `Sources/Mousepad/` | AppKit app: `Document` (NSDocument), `DocumentWindowController`, `EditorTextView`, `LineNumberRuler` (gutter), `StatusBarView`, `MainMenu`, `Theme`, `Settings`, `PreferencesWindowController` |
| `Tests/MousepadCheck/` | `swift run MousepadCheck` |
| `Scripts/make-app.sh` | Builds and signs the `.app`; generates the icon on first run |
| `Resources/Info.plist` | Bundle id `dev.siddharth.mousepad`, document types |
| `01-…05-*.md` | Analysis of the original, concepts, plan, checklist, UI style |

## Settings

Stored in UserDefaults. Inspect with `defaults read dev.siddharth.mousepad`.
Preferences window: Cmd+, (comma).

## Dev aid: window snapshot without screen-recording permission

```sh
MOUSEPAD_SNAPSHOT=/tmp/win.pdf .build/debug/Mousepad file.swift
sips -s format png /tmp/win.pdf --out /tmp/win.png
```

Writes the front window as a PDF and quits. `-wordWrap YES` style arguments override any setting for that run.

```sh
MOUSEPAD_SMOKE=1 .build/debug/Mousepad a.txt b.txt c.txt
```

Drives the tab flows that need a live window (switch, edit, undo, new, close, move to new window) and exits 0 or 1.

## Keys (Cmd unless noted)

New N · Open O · Save S · Save As ⇧S · Close tab W · Close window ⇧W · Print P · Find F · Next G · Previous ⇧G ·
Replace R · Go to line L · Duplicate line D · Indent ] · Unindent [ · Move line ⌃⌘↑/↓ ·
Transpose ⌃T · Paste from history ⇧V · Tabs ⇧[ ⇧] and 1…9 · Preferences , · Full screen ⌃F ·
Home/End smart · Insert key toggles overwrite.

## Status

v1 core is in. See `04-checklist.md` for what is done and what is v1.1.
