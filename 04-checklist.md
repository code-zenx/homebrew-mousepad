# Checklist: Mousepad Clone for macOS (Swift + AppKit)

Tick in order. Each phase ends with a `Mousepad.app` that launches from Finder.
Behaviour reference: `01-mousepad-analysis.md`. Look reference: `05-ui-style.md`.

## Status as of 2026-09-07

Built and verified (renders correctly, core checks pass, `.app` launches from Finder / `open -a`):
- Phase 0 skeleton, Phase 1 TextFile (as `swift run MousepadCheck`, no XCTest in command line tools)
- Phase 2 Document: open/save/save as/revert/recent, encoding sheet with preview, charset memory, line ending + BOM menu, Finder open, drag-drop via Dock
- Phase 3 look: theme, gutter (sibling view, not NSRulerView), current line, right margin, word wrap, tab width, insert spaces, auto indent, smart Home, overwrite mode, block cursor, bracket match, status bar with click menus
- Phase 4 menus + all TextOps + clipboard history + context menu
- Phase 5 find/replace via NSTextFinder, Go to line sheet
- Phase 6 regex highlighting for 16 languages, Filetype + Color Scheme menus, 3 schemes
- Phase 7 Settings + Preferences window (bound to UserDefaults), window frame autosave
- Phase 8 native window tabs, Cmd+1…9, New Window, templates menu, print (light colors on paper)
- Phase 9 icon, Info.plist document types, ad-hoc signed `dist/Mousepad.app`

Not yet verified by hand (needs a person at the keyboard): encoding sheet flow, print output,
font panel, tab drag between windows, Finder "Open With" on a fresh account.
Known deliberate gaps: see `ponytail:` comments in source and Phase 10 below.

---

## Phase 0 — Skeleton
- [ ] `swift package init --type executable --name Mousepad`; platforms `.macOS(.v14)`
- [ ] `main.swift`: create `NSApplication`, set `AppDelegate`, `app.run()`; no storyboard, no nib
- [ ] `AppDelegate`: `applicationDidFinishLaunching` opens one window with an `NSTextView` in an `NSScrollView`
- [ ] Window: `appearance = .darkAqua`, black background, `titlebarAppearsTransparent`, `.fullSizeContentView`
- [ ] Text view: monospace 13 pt, black background, light text, orange insertion point
- [ ] Minimal `MainMenu`: app menu (About, Preferences…, Quit), File (New, Open…, Close), Edit (standard), Window, Help
- [ ] `Resources/Info.plist`: bundle id, name, version, `LSMinimumSystemVersion`, `NSHighResolutionCapable`, `NSPrincipalClass = NSApplication`
- [ ] `Scripts/make-app.sh`: `swift build -c release` → copy binary to `Mousepad.app/Contents/MacOS/` → copy `Info.plist` + `Resources` → `codesign --force --deep --sign -`
- [ ] `open Mousepad.app` launches; Dock icon appears; Cmd+Q quits
- [ ] `swift test` runs (empty test target)

## Phase 1 — TextFile (pure Swift, tested)
### Decode
- [ ] `TextFile.decode(_ data: Data, preferred: String.Encoding?) throws -> (String, Meta)`
- [ ] BOM detect: UTF-8 `EF BB BF`, UTF-16 LE `FF FE`, UTF-16 BE `FE FF`, UTF-32 LE `FF FE 00 00`, UTF-32 BE `00 00 FE FF`; strip; set `hasBOM` + encoding
- [ ] No BOM: try preferred, else UTF-8; failure → `throw DecodeError.invalid(encoding)`
- [ ] EOL detect from first `\n` / `\r\n` / `\r`; default LF for empty
- [ ] Normalise all EOLs to `\n`
- [ ] Strip one trailing `\n`
- [ ] `Meta { encoding, hasBOM, eol, }`
### Encode
- [ ] `TextFile.encode(_ text: String, meta: Meta) throws -> Data`
- [ ] Convert `\n` → EOL
- [ ] Append final EOL for LF and CR (not CRLF) when text is non-empty
- [ ] Prepend the **correct** BOM for the encoding when `writeBOM` and encoding is Unicode (fixes original's UTF-8-only bug)
- [ ] Encode; failure → `throw EncodeError.unrepresentable`
### Encodings table
- [ ] `Encodings.all`: `String.Encoding` + display name + group (Unicode, Western, Central European, Cyrillic, Greek, Turkish, Hebrew, Arabic, Baltic, Japanese, Chinese, Korean, Thai, Vietnamese, Other)
- [ ] `Encodings.system` from `String.defaultCStringEncoding` / locale
### Tests
- [ ] Round-trip every EOL × BOM × {utf8, utf16LE, utf16BE, isoLatin1, windowsCP1252, shiftJIS}
- [ ] Trailing newline rules; empty text stays empty
- [ ] Invalid UTF-8 throws; same bytes decode as Latin-1
- [ ] Encode of non-Latin-1 text into Latin-1 throws

## Phase 2 — Document
- [ ] `Document: NSDocument` with `NSTextStorage` (or a `String` until the window loads)
- [ ] `read(from data: Data, ofType:)` → `TextFile.decode`; on failure store data, then present `EncodingSheet` from `windowControllerDidLoadNib`/`makeWindowControllers`
- [ ] `data(ofType:)` → `TextFile.encode`
- [ ] `readableTypes` / `writableTypes` → `public.plain-text`, `public.source-code`, `public.text`, `public.data` fallback
- [ ] `autosavesInPlace` → decide (true gives Versions; false matches Mousepad). Default: `false` for v1
- [ ] Untitled naming "Untitled", "Untitled 2", … (NSDocument default is fine)
- [ ] Window title: `NSDocument` shows name + modified dot; add `[Read Only]` via `displayName` override when file is not writable
- [ ] Setting `path-in-title`: show full path in title bar subtitle (`window.subtitle`)
- [ ] Open Recent: native. Store charset per path in `UserDefaults` after a successful non-UTF-8 open; use it as `preferred` next time
- [ ] Revert (native `revertToSaved:`) confirmed working
- [ ] Save All menu item: iterate `NSDocumentController.shared.documents`
- [ ] Externally-modified alert: native (verify by touching the file from Terminal, then Cmd+S)
- [ ] Read-only file: Save routes to Save As (verify with `chmod 444`)
- [ ] `EncodingSheet`: radio UTF-8 / System / Other (popup grouped), preview of first ~2 KB decoded, background test marking which encodings decode cleanly, Cancel closes the document
- [ ] Document menu: Line Ending (LF / CR / CRLF) radio; Write Unicode BOM checkbox enabled only for Unicode encodings; both mark document dirty
- [ ] Finder: double-click a `.txt` opens in Mousepad (after Phase 9 plist); `open -a Mousepad file.txt` works now
- [ ] Drag file onto window → opens (implement `NSDraggingDestination` on the window content view; Dock drop is free)

## Phase 3 — Editor look and feel
### Theme (`05-ui-style.md`)
- [ ] `Theme` struct: bg, panel, border, text, muted, accent, ok, selection, cursor, currentLine, gutterText, matchHighlight, error
- [ ] Three schemes: `terminal` (default), `grey`, `paper` (light)
- [ ] Editor font from settings; default `NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)`
- [ ] Insertion point color = accent; selection color = dim accent; `selectedTextAttributes`
### Window
- [ ] `EditorTextView: NSTextView`; force TextKit 1 (`_ = layoutManager`) with a comment saying why
- [ ] Scroll view: no border, black, thin overlay scrollers
- [ ] `LineNumberRuler: NSRulerView` as `verticalRulerView`; width grows with digit count; text muted, current line in text color; right-aligned; 1 px border line on the right
- [ ] Current line highlight (`drawBackground` override) toggled by setting
- [ ] Right margin line at column N (`drawBackground`, uses font advance width) toggled by setting
- [ ] Word wrap toggle: container width tracks view vs. very wide container + horizontal scroll
- [ ] Tab width: `NSParagraphStyle.defaultTabInterval` + `tabStops = []` from font advance × width
- [ ] Insert spaces: Tab key inserts spaces to next stop when on
- [ ] Auto indent: Return copies leading whitespace of current line when on
- [ ] Smart Home: Home / Cmd+Left toggles first non-blank ↔ column 0; Shift extends selection
- [ ] Cmd+Up / Cmd+Down document start/end (native); Ctrl+Home/End alias optional
- [ ] Overwrite mode: Insert key (Fn+Return on Mac keyboards) toggles; typing replaces
- [ ] Bracket match: on selection change, highlight matching `()[]{}` with a temporary attribute
### Status bar
- [ ] `StatusBarView`: 24 pt tall, panel bg, 1 px top border, 11 pt mono uppercase labels
- [ ] Left: `FILETYPE`, `ENCODING`, `EOL`, `TAB n`; each clickable → popup menu
- [ ] Right: `LN n COL n` (+ `SEL n` when selection), `INS`/`OVR` (click toggles)
- [ ] Updates on `NSTextView.didChangeSelectionNotification` and text change
- [ ] Toggle via View → Status Bar and setting

## Phase 4 — Menus and edit operations
### Menu tree (`01` §3), key equivalents with Cmd unless noted
- [ ] **App**: About, Preferences… (Cmd+,), Services, Hide, Quit
- [ ] **File**: New (Cmd+N), New Window (Shift+Cmd+N), New From Template ▸, Open… (Cmd+O), Open Recent ▸, Close (Cmd+W), Save (Cmd+S), Save As… (Shift+Cmd+S), Save All, Revert to Saved, Page Setup…, Print… (Cmd+P)
- [ ] **Edit**: Undo/Redo, Cut/Copy/Paste, Paste Special ▸ (Paste from History, Paste as Column [v1.1]), Delete, Select All, Convert ▸ (Lower, Upper, Title, Opposite, Tabs→Spaces, Spaces→Tabs, Strip Trailing Spaces, Transpose Ctrl+T), Move Line ▸ (Up Ctrl+Cmd+↑, Down Ctrl+Cmd+↓), Duplicate Line/Selection (Cmd+D), Indent (Cmd+]), Unindent (Cmd+[)
- [ ] **Search**: Find… (Cmd+F), Find Next (Cmd+G), Find Previous (Shift+Cmd+G), Find and Replace… (Cmd+R), Use Selection for Find (Cmd+E), Go To Line… (Cmd+L)
- [ ] **View**: Font ▸ (Show Fonts Cmd+T, Bigger Cmd+=, Smaller Cmd+-), Color Scheme ▸, Line Numbers, Word Wrap, Status Bar, Enter Full Screen
- [ ] **Document**: Auto Indent, Tab Size ▸ (2 3 4 8 Other…), Insert Spaces, Filetype ▸, Line Ending ▸, Write Unicode BOM
- [ ] **Window**: Minimize, Zoom, Show Previous Tab, Show Next Tab, Move Tab to New Window, Merge All Windows, Bring All to Front, [tab list]
- [ ] **Help**: Mousepad Help (opens README URL)
- [ ] Menu items enable/disable via responder chain (`validateMenuItem` where needed)
- [ ] Editor context menu: Undo, Redo, Cut, Copy, Paste, Delete, Select All, Convert ▸, Move Line ▸, Duplicate, Indent, Unindent
### `TextOps` (pure, tested: input string + selection range → output string + new range)
- [ ] Line range helper: selection or current line
- [ ] Indent / unindent (tabs or spaces per setting, respects partial indents)
- [ ] Lowercase, uppercase, title case, opposite case (Unicode-aware)
- [ ] Tabs → spaces / spaces → tabs, column-aware (tab stops)
- [ ] Strip trailing whitespace (selection or whole doc)
- [ ] Move lines up / down, selection preserved
- [ ] Duplicate selection or line
- [ ] Transpose: no selection → swap chars around cursor; one-line selection → reverse words; multi-line → reverse lines
- [ ] Every op applied inside one undo group (`textStorage.beginEditing`/`endEditing` + `shouldChangeText`/`didChangeText`)
### Clipboard history
- [ ] Track last 10 cut/copy strings; Paste from History shows a popup menu at the cursor

## Phase 5 — Find, replace, go to
- [ ] `textView.usesFindBar = true`, `isIncrementalSearchingEnabled = true`
- [ ] Cmd+F shows find bar with selection pre-filled; Cmd+R shows replace field (`performTextFinderAction` with `.showReplaceInterface`)
- [ ] Cmd+G / Shift+Cmd+G next / previous
- [ ] Finder options verified: match case, regex, whole word, wrap, highlight all, replace, replace all, replace in selection
- [ ] Options persist (`NSTextFinder` stores them in `UserDefaults` automatically; verify)
- [ ] Esc hides bar and clears highlights
- [ ] `GoToSheet` (Cmd+L): line spin 1…N, column spin, Jump; selects the line, scrolls to center

## Phase 6 — Syntax highlighting
- [ ] `Languages`: name, section (Scripts, Sources, Markup, Scientific, Other), extensions, shebang keywords, rule set
- [ ] Rule set: ordered regexes → token kind (keyword, type, string, comment, number, preprocessor, attribute)
- [ ] Languages v1: Swift, Python, JavaScript, TypeScript, Rust, Go, C/C++, Shell, Markdown, JSON, HTML, CSS, YAML, Plain Text
- [ ] `Highlighter.apply(to: NSTextStorage, range:)` sets `.foregroundColor` (+ italic for comments) from `Theme`
- [ ] Highlight visible range on scroll, changed paragraph range on edit, debounced 50 ms; full pass in background for files < 2 MB; none above
- [ ] Multi-line comments/strings: track state by re-scanning from paragraph start; accept imperfection
- [ ] Guess: extension → shebang first line → Plain Text
- [ ] Re-guess after Save As unless user forced language
- [ ] Filetype submenu grouped by section; radio marks current; "Plain Text"
- [ ] Status bar `FILETYPE` click → same menu
- [ ] Color Scheme submenu: terminal / grey / paper; applies to editor, gutter, status bar
- [ ] Tests: each language's rules on a sample snippet produce expected token ranges
- [ ] Typing in a 10k-line file shows no lag (measure with `sample` if in doubt)

## Phase 7 — Preferences and settings
- [ ] `Settings`: keys with defaults (font name/size, use system mono font, show line numbers, highlight current line, right margin on + column, word wrap, tab width, insert spaces, indent width, auto indent, smart home mode, match brackets, color scheme, status bar visible, path in title, remember window frame, always show tabs, cycle tabs, recent menu items, default tab sizes)
- [ ] `UserDefaults.register(defaults:)` at launch
- [ ] Observe `UserDefaults.didChangeNotification` → every window re-applies
- [ ] `PreferencesWindowController` (Cmd+,): single window, three sections in a segmented control or sidebar: **View** (line numbers, current line, right margin + column, brackets, word wrap, font + system-font checkbox, color scheme), **Editor** (tab width, insert spaces, auto indent, Home/End mode), **Window** (status bar, full path in title, remember frame, always show tabs, cycle tabs)
- [ ] Controls bound to `UserDefaults` via Cocoa bindings or manual target/action; no Apply button
- [ ] Window frame autosave: `window.setFrameAutosaveName("Main")` when `remember frame` is on
- [ ] Tab Size ▸ Other… sheet stores per-document; Preferences stores default

## Phase 8 — Tabs, templates, print
- [ ] `window.tabbingMode = .preferred`, `tabbingIdentifier = "mousepad"`; new documents open as tabs
- [ ] Always show tab bar setting → `window.toggleTabBar` state
- [ ] Cmd+1…9 select tab; cycle setting affects Next/Previous wrap
- [ ] Move Tab to New Window (native) confirmed; New Window (Shift+Cmd+N) creates a separate window, not a tab
- [ ] Templates: read `~/Templates` (create if missing on first use? no; just show "No templates" disabled item); subfolders → submenus; choosing one → new document with content + guessed language
- [ ] Page Setup… and Print… via `NSPrintOperation(view: textView)`; header with filename + page N; wrapping on; monospace font
- [ ] Print settings remembered (`NSPrintInfo.shared`)

## Phase 9 — Packaging
- [ ] `AppIcon.icns` from a 1024 px PNG via `iconutil` (brutalist: black square, orange "M" or `>_`)
- [ ] `Info.plist`: `CFBundleIconFile`, `CFBundleDocumentTypes` for `public.plain-text`, `public.source-code`, `public.text`, `public.shell-script`, `public.json`, `net.daringfireball.markdown`, `public.yaml`; `LSHandlerRank = Alternate`; `NSSupportsAutomaticTermination = false`
- [ ] `make-app.sh` produces signed app; `codesign --verify --deep --strict` passes
- [ ] Fresh macOS user account test: Finder double-click, Open With, Dock drop, `open -a`, Quick Look on documents
- [ ] Zip for sharing (`ditto -c -k --keepParent`)
- [ ] Optional: Developer ID cert, `codesign --options runtime`, `xcrun notarytool submit`, `stapler`, DMG via `hdiutil`
- [ ] README: build steps (`./Scripts/make-app.sh`), first-run Gatekeeper note (right-click → Open)

## Phase 10 — v1.1
- [ ] Custom brutalist tab bar (replaces native): 28 pt, panel bg, 1 px borders, active tab accent underline, `*` for modified, close `×` on hover, middle-click close, drag reorder
- [ ] Custom find bar matching `05-ui-style.md` (replaces `NSTextFinder` UI but keeps its engine)
- [ ] Bundle JetBrains Mono (OFL) in `Resources/Fonts`, register with `CTFontManagerRegisterFontsForURL`
- [ ] Tree-sitter highlighting via `Neon` + `SwiftTreeSitter` + grammar packages
- [ ] Show whitespace / line endings glyphs
- [ ] Paste as Column
- [ ] Print line numbers + numbering interval
- [ ] Localisation via `String(localized:)` + one extra language
- [ ] Custom key bindings (`~/Library/KeyBindings/DefaultKeyBinding.dict` already works for text; document it)

## Always
- [ ] `TextFile`, `TextOps`, `Highlighter` have tests; `swift test` green before each phase ends
- [ ] No hard-coded colors or fonts outside `Theme`
- [ ] All UI strings via `String(localized:)`
- [ ] Manual smoke test from a Finder-launched `.app`, not from `swift run`
