# Plan: Mousepad Clone as a Native macOS App

Docs in this folder:
- `01-mousepad-analysis.md` — what the original does (feature reference)
- `02-concepts.md` — ideas you need to know (section J = macOS specifics)
- `03-plan.md` — this file: decisions, architecture, phases
- `04-checklist.md` — tick-box list per phase
- `05-ui-style.md` — the look: palette, type, layout rules, mockups

Goal: a small, fast, native macOS text editor with Mousepad 0.4.2's features and a 1990s "terminal brutalist" look (black, monospace, square boxes, one orange accent). Linux is out of scope for now.

Your machine today: macOS 26.6, Swift 6.3.3 via Command Line Tools, no Xcode, FiraCode Nerd Font Mono installed.

---

## 1. Decisions

| # | Decision | Choice | Why |
|---|---|---|---|
| 1 | Language + toolkit | **Swift 6 + AppKit** | Native. Fastest start (~50 ms), smallest RAM (~30 MB), ~2 MB binary. `NSTextView` + `NSDocument` give ~60% of Mousepad for free. macOS-only removes the only reason to use Qt. |
| 2 | UI framework | AppKit only. No SwiftUI, no storyboards, no Interface Builder. | Text editors need AppKit's `NSTextView`. Code-built UI works without Xcode and is easier to style. |
| 3 | Build system | **SwiftPM** + a shell script that assembles `Mousepad.app` | You have no Xcode. `swift build` compiles AppKit apps. Xcode optional later (open `Package.swift`). |
| 4 | Text engine | `NSTextView` with **TextKit 1** (opt in by touching `layoutManager` once) | Line-number rulers and highlighting have ten years of TextKit 1 examples. TextKit 2 has few. |
| 5 | Document model | `NSDocument` + `NSDocumentController` | Free: open/save/save-as/revert/recent/close-prompt/externally-modified/atomic save/Finder open/Dock drop. |
| 6 | Tabs | Native `NSWindow` tabbing for v1 | Zero code: tab bar, Cmd+Shift+[ ], Move Tab to New Window (= Detach), merge. Custom brutalist tab bar is v1.1. |
| 7 | Find / replace | `NSTextFinder` find bar for v1 | Free: incremental, regex, match case, wrap, highlight all, replace, replace all, in-selection. Custom brutalist bar is v1.1. |
| 8 | Syntax highlighting | v1: regex-based highlighter, ~10 languages. v1.1: tree-sitter via `Neon` + `SwiftTreeSitter`. | Zero deps first. Tree-sitter when regex is not enough. |
| 9 | Settings | `UserDefaults` | Native, zero code, `defaults read` for debugging. |
| 10 | Font | Default `SF Mono` (system monospace). User can pick FiraCode / JetBrains Mono via Font panel. Bundle JetBrains Mono in v1.1. | No bundling work in v1. |
| 11 | Look | Native chrome (menubar, title bar, tab bar, alerts, find bar) in **dark appearance**; everything inside the window is custom per `05-ui-style.md`. | Native chrome cannot be fully restyled. Mac users expect native menus and alerts anyway. |
| 12 | Deployment target | macOS 14 (Sonoma) | Modern APIs, still runs on machines two releases back. |
| 13 | Distribution | v1: ad-hoc `codesign`, zip. Later: Developer ID + notarize + DMG. | Personal use first. Signing needs a paid Apple account. |
| 14 | Scope v1 | Mousepad 0.4.2 minus: toolbar, paste-as-column, print line numbers, whitespace drawing. | Toolbar contradicts the look. The rest is v1.1. |

Assumptions made for you (say so if wrong): Swift is fine to write; native tab bar is acceptable in v1; personal distribution is enough.

---

## 2. Architecture

```
mousepad/
  Package.swift
  Sources/Mousepad/
    main.swift                  # NSApplication bootstrap, no storyboard
    AppDelegate.swift           # app lifecycle, Templates menu, Preferences, Open Recent charset memory
    MainMenu.swift              # whole NSMenu tree built in code: titles, actions, key equivalents
    Document.swift              # NSDocument subclass: read/write bytes <-> text, encoding, EOL, BOM, language
    TextFile.swift              # PURE Swift: BOM detect, EOL detect/convert, encode/decode. No AppKit. Tested.
    Encodings.swift             # charset table with display names and groups. Tested.
    DocumentWindowController.swift  # window setup, appearance, status bar, ruler, find bar host
    EditorTextView.swift        # NSTextView subclass: smart Home, indent keys, auto indent, ops entry points
    TextOps.swift               # PURE string ops: case, transpose, tabs<->spaces, strip, move lines, duplicate. Tested.
    LineNumberRuler.swift       # NSRulerView subclass
    StatusBarView.swift         # custom NSView
    Highlighter.swift           # regex rules per language, guess by extension/shebang, apply attributes. Tested.
    Languages.swift             # language table: name, section, extensions, rules
    Theme.swift                 # palette + fonts from 05-ui-style.md, color schemes
    Settings.swift              # UserDefaults keys, defaults, typed accessors, change notifications
    PreferencesWindowController.swift
    EncodingSheet.swift         # "not valid UTF-8, pick encoding" with preview
    GoToSheet.swift
    TabSizeSheet.swift
  Tests/MousepadTests/
    TextFileTests.swift
    TextOpsTests.swift
    HighlighterTests.swift
  Resources/
    Info.plist                  # bundle id, document types (UTIs), icon
    AppIcon.icns
  Scripts/
    make-app.sh                 # swift build -c release -> Mousepad.app -> codesign
```

Rules:
- `TextFile`, `TextOps`, `Encodings`, `Highlighter` import only `Foundation`. They are unit-tested with `swift test`.
- One `NSMenuItem` per command with a selector and key equivalent. AppKit's responder chain enables/disables items automatically when the target implements the selector.
- All UI classes are `@MainActor`.
- Every setting has one key constant, one default, one type in `Settings.swift`.

## 3. Data Flow for the Main Paths

**Open**: Finder / `open -a` / File → Open / Dock drop → `NSDocumentController` → `Document.read(from data:)` → `TextFile.decode(data, preferred: charset from recent memory)` → success: text + meta → `NSTextStorage` → guess language → highlight. Failure (not valid in encoding): throw; `Document` presents `EncodingSheet` with preview, retries with chosen charset.

**Save**: Cmd+S → `NSDocument` runs its own checks (untitled → Save panel; file changed on disk → alert; locked → alert) → `Document.data(ofType:)` → `TextFile.encode(text, meta)` (EOL, BOM, charset) → `NSDocument` writes atomically (temp + rename, keeps permissions) → clears modified → re-guess language if user did not force one.

**Search**: Cmd+F → `NSTextFinder` find bar attached to the scroll view. Cmd+G / Shift+Cmd+G → `performTextFinderAction`. Cmd+R → same bar with replace field shown. Go To (Cmd+L) → `GoToSheet` → select line range, scroll.

**Tabs**: `window.tabbingMode = .preferred`. New document → new window → macOS puts it in a tab. Cmd+1…9 → custom: `window.tabbedWindows[n].makeKeyAndOrderFront`. Detach → `moveTabToNewWindow:` (built in).

**Settings**: change in Preferences → `UserDefaults` → `NotificationCenter` `UserDefaults.didChangeNotification` → every window re-applies `Theme` and editor options.

## 4. Feature → AppKit Mapping (what is free, what you write)

| Mousepad feature | AppKit | You write |
|---|---|---|
| Undo, redo, cut, copy, paste, delete, select all | `NSTextView` + `NSUndoManager` | nothing |
| Open, Save, Save As, Revert, Open Recent, Save All, Close with "Save changes?" | `NSDocument`, `NSDocumentController` | nothing (Save All = loop) |
| External modification alert, read-only handling, atomic save, keep permissions | `NSDocument` | nothing |
| Autosave + Versions (bonus, not in Mousepad) | `NSDocument` (`autosavesInPlace`) | one override |
| Single instance, Finder "Open With", Dock drop, `open -a Mousepad file` | macOS app model | `Info.plist` document types |
| Tabs, next/prev tab, detach tab, new window, merge | `NSWindow` tabbing | Cmd+1…9, cycle setting |
| Find bar: incremental, regex, case, wrap, highlight all, replace, replace all, in selection | `NSTextFinder` | attach + Cmd+R shortcut |
| Font panel | `NSFontPanel`, `changeFont:` | persist choice |
| Fullscreen | native | nothing |
| Print with page setup, headers, wrapping | `NSPrintOperation`, `NSPrintInfo` | ~30 lines |
| Case: upper / lower / title | `uppercaseWord:` etc. work per word; whole-selection needs code | ~20 lines in `TextOps` |
| Transpose chars | `transpose:` (Ctrl+T) | words / lines in `TextOps` |
| Encoding decode/encode, BOM, EOL | `String.Encoding`, `Data` | `TextFile` (~150 lines) |
| Encoding sheet with preview | — | `EncodingSheet` |
| Line numbers | `NSRulerView` | ~100 lines |
| Current line highlight, right margin line | `drawBackground` override | ~30 lines |
| Word wrap toggle | `NSTextContainer` size / `widthTracksTextView` | ~15 lines |
| Tab width, insert spaces, auto indent, smart Home, indent/unindent | `keyDown`, `NSParagraphStyle.tabStops` | ~120 lines |
| Bracket matching | temporary attributes on cursor move | ~40 lines |
| Move line up/down, duplicate, strip trailing, tabs↔spaces | — | `TextOps` (~150 lines, tested) |
| Clipboard history (10) | — | ~40 lines |
| Syntax highlighting + Filetype menu + language guess | — | `Highlighter` + `Languages` (~300 lines) |
| Color schemes | — | `Theme` (~60 lines) |
| Statusbar | — | `StatusBarView` (~80 lines) |
| Settings + Preferences window | `UserDefaults` | ~250 lines |
| Go To line/column | — | `GoToSheet` (~60 lines) |
| Templates menu from `~/Templates` | — | ~50 lines |
| Recent-file charset memory | — | `UserDefaults` dict path→charset |
| Root warning, D-Bus, menubar hide, toolbar | not applicable on macOS | drop |

Rough total new code for v1: **2,500–3,500 lines of Swift**. Original is 18,000 lines of C.

## 5. Phases

Each phase ends with a `Mousepad.app` you can double-click.

### Phase 0 — Skeleton (½ day)
SwiftPM package, `main.swift` starts `NSApplication`, one black window with a monospace `NSTextView`, `make-app.sh` produces `Mousepad.app`, ad-hoc signed, launches from Finder.

### Phase 1 — TextFile, no UI (1 day)
`TextFile` + `Encodings` with tests: BOM detect/strip/write (correct BOM per encoding), EOL detect/normalise/convert, trailing newline, decode with fallback, encode errors. Do this before any document code; this is where data loss lives.

### Phase 2 — Document (1–2 days)
`Document` subclass wired to `TextFile`. Open, Save, Save As, Revert, Open Recent, Finder open, untitled naming, window title `*name` / `[Read Only]`, Encoding sheet on decode failure, charset memory per path, Line Ending + BOM document menu.

### Phase 3 — Editor look and feel (2–3 days)
`Theme` from `05-ui-style.md`: black background, orange insertion point, dim-orange selection, current line, right margin, line-number ruler, status bar (filetype, encoding, EOL, tab size, line/col/sel, INS/OVR), word wrap, tab width, insert spaces, auto indent, smart Home/End, Cmd+Home/End, overwrite mode. Window: transparent title bar, dark appearance, full-size content.

### Phase 4 — Menus and edit operations (2 days)
Full `MainMenu` tree with key equivalents per `01` §3. `TextOps` with tests: indent/unindent, case ×4, tabs↔spaces (column-aware), strip trailing, move line up/down, duplicate, transpose words/lines, clipboard history popup. Editor context menu.

### Phase 5 — Find, replace, go to (1 day)
`NSTextFinder` find bar (Cmd+F/G/Shift+G/R), persist finder options, Go To sheet (Cmd+L). Verify regex, whole word via `\b`, in-selection replace.

### Phase 6 — Syntax highlighting (2 days)
`Highlighter`: rules for Swift, Python, JavaScript/TypeScript, Rust, Go, C, Shell, Markdown, JSON, HTML/CSS, YAML. Guess by extension then shebang/first line. Filetype submenu grouped by section, statusbar click menu, "Plain Text", user-forced language survives Save As. Color Scheme submenu with 3 schemes (default black/orange, a grey one, a light one). Highlight only visible range + debounce so typing never lags.

### Phase 7 — Preferences and settings (1–2 days)
`Settings` keys from `01` §8 (minus Linux-only). Preferences window with three sections (View, Editor, Window), controls bound live. Remember window size/position/state. Statusbar toggle. Always-show-tabs, cycle-tabs.

### Phase 8 — Tabs polish, templates, print (1–2 days)
Cmd+1…9, cycle setting, Detach, New Window. Templates submenu. Print with page setup and headers.

### Phase 9 — Packaging (1 day)
`.icns` icon, `Info.plist` with `CFBundleDocumentTypes` (`public.plain-text`, `public.source-code`, `public.text`), `LSHandlerRank`, ad-hoc `codesign --deep`, zip. Test on a fresh macOS user account: Finder open, Open With, Dock drop, Quick Look, `open -a`. Optional: Developer ID sign + `notarytool` + DMG.

### Phase 10 — v1.1
Custom brutalist tab bar and find bar (replace native), bundled JetBrains Mono, tree-sitter highlighting via Neon, whitespace/EOL glyph drawing, paste as column, print line numbers, localisation with `String(localized:)`.

**Rough total: 2–3 weeks part-time for v1.**

## 6. Risks

| Risk | Mitigation |
|---|---|
| No Xcode: no Interface Builder, no asset catalogs, no Instruments GUI | All UI in code (planned anyway). Icon via `iconutil` (in CLT). Profile with `sample`/`xctrace` from CLT. Install Xcode later if wanted; `Package.swift` opens directly. |
| `notarytool` may need full Xcode | v1 is ad-hoc signed. Verify `xcrun notarytool` availability before Phase 9 stretch goal. |
| TextKit 2 default on macOS 12+ | Access `textView.layoutManager` once at setup to force TextKit 1. Document this in `EditorTextView`. |
| Native chrome cannot match the brutalist look | Accept in v1 (dark appearance is close). Custom tab bar + find bar in v1.1. |
| Swift 6 strict concurrency friction with AppKit | Mark UI classes `@MainActor`. If it fights you, set `swiftLanguageModes: [.v5]` in `Package.swift`. |
| Regex highlighter wrong on tricky syntax (nested comments, template strings) | Acceptable for a simple editor. Tree-sitter path exists. |
| Huge files (>10 MB) slow in `NSTextView` | Out of scope, same as original. Disable highlighting above 2 MB. |

## 7. Open Questions

1. Native tab bar in v1, or custom brutalist tab bar from the start (adds ~2 days)?
2. Bundle JetBrains Mono now (needs the font files in `Resources`), or SF Mono default is fine for v1?
3. App name and bundle id: `Mousepad` / `com.<you>.mousepad`? (Different name avoids confusion with the Xfce app.)

Defaults if you say nothing: native tab bar, SF Mono, name "Mousepad", bundle id `dev.siddharth.mousepad`.
