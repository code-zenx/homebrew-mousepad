# Concepts You Need to Build a Text Editor

Simple explanations of every idea the Mousepad clone touches. Read this before the plan.
Each entry: what it is, why it matters, how Mousepad does it, and the one thing to get right.

---

## A. Text Storage

### Text buffer
The in-memory copy of the document. The UI widget shows it; all edits go through it.
It stores **UTF-8 text with `\n` line endings only**, no matter what the file on disk uses. 
Keep one buffer per open tab. Never let two widgets share one buffer unless you mean split view.

### Text iterator (position)
A pointer to a spot in the buffer: (line, column). Columns count **characters**, not bytes.
A multi-byte character like `é` or `日` is one column. Tabs are one character but display as up to `tab-width` cells. 
Mousepad has a helper `get_real_line_offset` that computes the visual column by expanding tabs. You need this for "Tabs to Spaces" and "Go to column".

### Mark
A named position that moves with the text as you edit. "insert" (cursor) and "selection_bound" are marks.
Use marks, not raw offsets, when you must remember a spot across edits (e.g. while doing replace all).

### Undo / redo stack
A list of reversible edits. Group related edits into **one user action** so one Ctrl+Z undoes the whole "Replace All" or "Indent selection".
Every toolkit has this. Do not write your own.

### Modified flag
A boolean on the buffer: "differs from disk?". Set false after load and after save. Drives the `*` in the title, the red tab label, and the "Save changes?" dialog.

---

## B. Files and Bytes

### Character encoding (charset)
A rule for turning bytes into characters. UTF-8 is the modern default. Old files may be Latin-1 (ISO-8859-1), Windows-1252, Shift-JIS, etc.
Mousepad's rule: try UTF-8. If bytes are invalid, ask the user to pick from a list and show a preview.
Remember the charset per file (in recent history) so the next open works silently.

### BOM (byte order mark)
Optional first bytes that name the encoding: `EF BB BF` = UTF-8, `FF FE` = UTF-16 LE, `FE FF` = UTF-16 BE, `FF FE 00 00` = UTF-32 LE, `00 00 FE FF` = UTF-32 BE.
On load: detect, strip, remember. On save: write it back only if the file had one or the user turned it on.

### Line endings (EOL)
`\n` (LF, Unix, macOS today), `\r\n` (CRLF, Windows), `\r` (CR, classic Mac). 
Detect from the first line break in the file. Normalise to `\n` in the buffer. Convert back on save. Let the user change it in the Document menu.

### Trailing newline
POSIX text files end with `\n`. Editors hide that final newline so the cursor does not land on an empty last line.
Mousepad strips it on load and adds it on save (for Unix and Mac; not for DOS).

### Atomic save
Original does `open(O_TRUNC)` then `write`. A crash mid-write leaves an empty file.
Better: write to `name.tmp` in the same folder, `fsync`, then `rename` over the original. `rename` is atomic on POSIX (both macOS and Linux). Keep file mode bits (permissions) from the original.

### External modification check
Store the file's `mtime` (last-modified time) after load and save. Before overwriting, `stat` again. If it changed, someone else edited it: ask "Save anyway / Save As / Cancel".
Optional upgrade: a file watcher (`inotify` on Linux, `FSEvents`/`kqueue` on macOS, wrapped by Qt's `QFileSystemWatcher` or GLib's `GFileMonitor`) to warn as soon as the file changes.

### Read-only detection
After load, check write permission (`os.access(path, W_OK)` or `stat` mode bits). Show "[Read Only]" in title and route Save to Save As.

### Memory-mapped read
Mousepad `mmap`s the file to avoid copying. For a clone, just `read()` the whole file. Files a text editor opens are small enough.

### Language guessing (filetype)
Pick the syntax highlighter from the filename extension first, then from the first bytes (shebang `#!/bin/bash`, `<?xml`, etc.).
Mousepad uses the desktop's MIME database (`g_content_type_guess`) plus GtkSourceView's language list. Pygments or KSyntaxHighlighting can do the same.

---

## C. Editing Operations

### Selection vs. whole line
Many commands act on "selection, or the current line if nothing is selected" (duplicate, indent, move line). Write one helper that returns the line range to act on, and reuse it.

### Indentation
`tab-width` = how wide a tab looks. `indent-width` = how much Indent adds (default: same as tab width). `insert-spaces` = whether Tab key inserts spaces.
Auto-indent = new line copies the leading whitespace of the previous line.

### Smart Home
Home key toggles between column 0 and first non-blank character. Four modes: disabled, before, after, always. Most editors only need "before" (go to first text; press again for column 0).

### Case conversion
Use Unicode-aware functions (`str.lower()`, `str.upper()`, `str.title()` in Python; `QString::toLower` in Qt). Title case = capitalise first letter of each word. Opposite case = swap per character.

### Transpose
Three behaviours by selection shape: swap two chars, reverse words in one line, reverse lines. Small feature, but users of the original expect Ctrl+T.

### Column (block) paste
Split clipboard text by lines. Paste line *i* at the cursor column on line (cursor + *i*). Pad with spaces or add lines as needed. Mousepad matches by pixel x offset; matching by character column is simpler and good enough.

### Clipboard history
Keep the last 10 texts the user copied or cut. Show them in a popup. Just a list in memory, cleared on exit.

---

## D. Search

### Search flags
Case sensitive, whole word, regular expression, wrap around, direction. Pack them into one options object and pass it to one search function. Keep the search bar and the replace dialog on the same function.

### Regular expression (regex)
Pattern matching language. Use the toolkit's engine (Qt `QRegularExpression`, Python `re`, GLib `GRegex`). Regex replace supports back-references like `\1`.

### Whole word
Match only if the characters before and after the hit are not word characters. Regex `\b` does this.

### Incremental (as-you-type) search
Search bar searches on every keystroke, starting from the selection start so the same match stays selected as you type more. Colour the entry red when nothing is found.

### Highlight all
Mark every match with a background colour. Needs a scan of the whole document. On big files, do it lazily or in chunks (Mousepad's TODO notes this slows down on large files).

### Replace in selection
Replace only inside the selected range. Trick from Mousepad: copy the selection into a scratch buffer, replace there, put it back as one edit. Or just constrain the search range if the toolkit allows.

### Search across all open documents
Loop over every tab's buffer. Only used by "Replace All in: All Documents".

---

## E. Application Structure

### Single instance
Second launch should open files in the existing window, not start a second process. Mousepad uses D-Bus (Linux only).
Cross-platform options: a local socket (`QLocalServer` / Unix domain socket) with a lock file; or the toolkit's built-in app uniqueness (`GtkApplication` with an app ID handles this on both Linux and macOS; `QtSingleApplication` pattern for Qt).
On macOS, opening a file from Finder also arrives as an "open file" event to the running app; handle that too.

### Document / Window / Application objects
- **Application**: one per process. Owns windows, settings, recent list, clipboard history.
- **Window**: owns tabs, menus, statusbar. Tracks the active document.
- **Document**: one tab. Owns buffer, view, file metadata, search state.
Keep this split. It is what makes "detach tab into new window" and "search all documents" simple.

### Actions (commands)
Name every command once (`file.save`, `edit.undo`) and bind it to menu item, toolbar button, shortcut, and context menu. Enable/disable the action, and all its UI follows.
Qt: `QAction`. GTK: `GAction` + `GMenu`.

### Menubar on macOS
macOS puts the menubar at the top of the screen, not in the window. Qt does this automatically. GTK4's macOS backend also supports it. Standard macOS items: app menu with "About", "Preferences…" (Cmd+,), "Quit" (Cmd+Q). Put them there or the app feels foreign.

### Shortcuts on macOS vs Linux
Ctrl on Linux = Cmd on macOS. Qt's `QKeySequence.StandardKey` and GTK's `<Primary>` modifier map this for you. Never hard-code "Ctrl".

### Settings storage
Key/value store with defaults and change notification. 
- GTK: GSettings (dconf on Linux, keyfile elsewhere). 
- Qt: `QSettings` (plist on macOS, `.conf` on Linux). 
- Plain: a JSON or TOML file in the user config dir (`~/.config/app/` on Linux, `~/Library/Application Support/app/` on macOS).
Bind each preference widget to its key so the dialog needs no "Apply" button.

### Recent files
List of recently opened paths with per-file charset. Linux: `~/.local/share/recently-used.xbel` (shared with other apps). macOS: `NSDocumentController` recents. Simplest cross-platform: your own list in settings.

### Templates
`~/Templates` folder (XDG special dir on Linux). "New from template" copies a file's content into a new untitled tab and sets its filetype. macOS has no such convention; use the same folder path or a config dir.

### Drag and drop
Accept `text/uri-list` (file drops) on the window and the text view. Tab drag between windows is toolkit-specific (GtkNotebook has it; Qt `QTabBar` needs `setMovable` plus custom code for cross-window).

### Printing
Render the buffer to pages with a monospace font, optional line numbers and headers, optional syntax colours. Qt: `QPrinter` + `QTextDocument.print()`. GTK: `GtkPrintOperation` + `GtkSourcePrintCompositor`.

### Fullscreen with auto-hidden bars
Hide menubar/toolbar/statusbar when fullscreen, with a per-bar three-state setting (auto/no/yes). Small feature; do after everything else works.

---

## F. Syntax Highlighting

### Lexer / language definition
Rules that split text into tokens (keyword, string, comment, number) and name each token type.
- GtkSourceView ships `.lang` XML files for ~200 languages.
- KSyntaxHighlighting (KDE) ships ~300 and has Qt bindings.
- Pygments (Python) ships ~500 lexers; plug into `QSyntaxHighlighter` by re-lexing each changed block.

### Style scheme (colour scheme)
Maps token types to colours and font styles. "none" = no highlighting. Ship a few (light, dark, solarized). GtkSourceView schemes are XML; for Qt/Pygments, use Pygments styles.

### Incremental highlighting
Re-highlight only changed lines, not the whole file, or typing lags on big files. `QSyntaxHighlighter` does this per block. Multi-line constructs (block comments) need "block state" carried from the previous line.

---

## G. Cross-Platform Packaging

### Linux
- AppImage: single executable, works on most distros. 
- Flatpak: sandboxed, needs a manifest, good for GTK apps. 
- `.deb` / `.rpm` for specific distros. 
- Or `pip install` / Homebrew if the target is developers.
Ship a `.desktop` file, an icon, and register MIME types so "Open with" works.

### macOS
- `.app` bundle: a folder with `Info.plist`, binary, resources. Users expect this. 
- Tools: `pyinstaller` or `briefcase` (Python), `macdeployqt` (Qt C++), `gtk-mac-bundler` (GTK).
- Code signing and notarization are needed to run without a Gatekeeper warning. Needs an Apple Developer account. Can be skipped for personal use (right-click → Open).
- `Info.plist` lists document types so the app appears in "Open With".

### Paths that differ
| Thing | Linux | macOS |
|---|---|---|
| Config | `~/.config/<app>/` | `~/Library/Application Support/<app>/` |
| Templates | `~/Templates` | no standard |
| Monospace font | "Monospace" (fontconfig alias) | "Menlo" / "SF Mono" |
| Primary modifier | Ctrl | Cmd |
| Single instance | D-Bus / socket | app uniqueness + `openFile` events |

Use the toolkit's "standard paths" API (`QStandardPaths`, `g_get_user_config_dir`) instead of hard-coding.

---

## H. Internationalisation (i18n)

Wrap every user-visible string in a translate call (`_("Save")`, `tr("Save")`). Mousepad ships ~60 translations via gettext `.po` files. For the clone: wrap strings from day one, ship English only, add languages later. Skipping the wrap now means touching every string later.

---

## I. Testing a GUI Editor

- **Unit-test the file layer with no GUI**: load/save with every encoding, BOM, EOL, trailing newline, read-only, missing file. This is where bugs cost data.
- **Unit-test text operations on a plain buffer**: indent, case, transpose, tabs↔spaces, column paste. Feed a string, assert the string out.
- **Unit-test search** with flags on fixed text.
- **Smoke-test the GUI manually** from a Finder-launched `.app`. Automated GUI tests are slow to write; do them last if at all.

---

## J. macOS and AppKit Concepts (the chosen stack)

### NSApplication and the run loop
One `NSApplication` object per process. `app.run()` starts the event loop that delivers key presses, clicks, and timers. Everything UI happens on the main thread. In Swift 6, mark UI classes `@MainActor` so the compiler checks this.

### AppDelegate
The object that gets app-level events: finished launching, open these files, should quit. Also where the main menu is built when you do not use a storyboard.

### Responder chain
Menu items send a message (a selector like `save:`) to "the first responder" and up a chain: text view → its window → window controller → document → app delegate. Whoever implements the method handles it. This is why a menu item with target `nil` "just works" for the focused window, and why items grey out when nobody can handle them. Your custom actions (`moveLineUp:`) go on `EditorTextView` or `Document`; menu items point at `nil`.

### NSDocument
A class that represents one file. Subclass it and override two methods: `read(from:ofType:)` (bytes in) and `data(ofType:)` (bytes out). In return you get: Open/Save/Save As/Revert/Duplicate, "Save changes?" on close, "file changed on disk" alerts, atomic safe-save that keeps permissions, Open Recent, Finder integration, untitled naming, the modified dot in the title bar, optional autosave and Versions.
`NSDocumentController` is the app-wide list of open documents. Ask it to open files or iterate documents for Save All.

### UTI (Uniform Type Identifier)
macOS names file kinds by strings like `public.plain-text`, `public.source-code`, `public.json`. `Info.plist` lists which UTIs your app opens (`CFBundleDocumentTypes`). This is what makes Finder show your app in "Open With" and lets `open -a` work.

### TextKit 1 stack
Four objects make a text view:
- `NSTextStorage` — the text plus attributes (font, color). Subclass of `NSAttributedString`.
- `NSLayoutManager` — turns characters into glyphs and lines; knows which line a character is on.
- `NSTextContainer` — the rectangle the text flows into. Set its width to control wrapping.
- `NSTextView` — the view that draws and handles input.
TextKit 2 is newer with a different layout API. Touching `textView.layoutManager` once forces TextKit 1, which has more examples for rulers and highlighting.

### Attributes and temporary attributes
Syntax colors are attributes on ranges of `NSTextStorage`. Setting them marks the document as edited unless you wrap the change in `beginEditing`/`endEditing` and avoid the undo manager. Alternative: `layoutManager.addTemporaryAttributes` colors text **without** touching the storage. Use temporary attributes for highlighting and bracket matching; use real attributes only for font.

### NSRulerView
A strip beside a scroll view. Subclass it and draw line numbers by asking the layout manager which lines are visible. Set it as `scrollView.verticalRulerView` and turn `rulersVisible` on.

### NSTextFinder
Apple's find/replace engine and bar. Set `textView.usesFindBar = true` and it appears on Cmd+F with incremental search, regex, match case, wrap, highlight all, replace, and replace in selection. You call `performTextFinderAction` for Find Next/Previous. Its bar is native-looking; you can keep the engine and draw your own bar later.

### NSUndoManager
Every `NSTextView` edit goes through the undo manager. To make one Ctrl+Z undo a whole operation, call `shouldChangeText(in:replacementString:)` before and `didChangeText()` after, and group with `undoManager.beginUndoGrouping()` / `endUndoGrouping()`.

### Key equivalents
Each `NSMenuItem` has a `keyEquivalent` string and `keyEquivalentModifierMask`. Cmd is the default modifier. Standard Mac shortcuts: Cmd+, Preferences, Cmd+W close, Cmd+Q quit, Cmd+Shift+[ / ] tabs, Cmd+E use selection for find, Cmd+G find next. Keep them; Mac users' hands expect them.

### Window tabbing
Since macOS 10.12 any `NSWindow` can be a tab. Set `window.tabbingMode = .preferred` and give windows the same `tabbingIdentifier`. macOS then provides the tab bar, drag to reorder, "Move Tab to New Window", "Merge All Windows", and Cmd+Shift+[ ]. The tab bar's look is native and cannot be restyled; replace it with your own view if you need the brutalist look.

### NSAppearance
`darkAqua` vs `aqua`. Set `window.appearance` to force dark chrome regardless of the user's system setting. Native controls (checkbox, popup, alert) pick colors from the appearance.

### UserDefaults
Key/value store backed by a plist in `~/Library/Preferences/<bundle id>.plist`. `register(defaults:)` sets defaults without writing them. Read from Terminal with `defaults read <bundle id>`. Cocoa bindings can tie a checkbox directly to a key.

### Sheets vs. alerts
A **sheet** is a panel attached to a window (Save panel, your Encoding sheet). An **alert** (`NSAlert`) is the standard "Save changes?" box; run it as a sheet with `beginSheetModal(for:)`. Use `NSAlert` for yes/no questions; build a custom sheet only for forms.

### App bundle
`Mousepad.app` is a folder: `Contents/Info.plist`, `Contents/MacOS/Mousepad` (the binary), `Contents/Resources/` (icon, fonts). You can assemble it with a shell script after `swift build`. `iconutil` converts an `.iconset` folder of PNGs into `.icns`.

### Code signing, Gatekeeper, notarization
- **Ad-hoc signing** (`codesign --sign -`): no certificate. Runs on your Mac. Other Macs show a Gatekeeper warning; user right-clicks → Open once.
- **Developer ID signing**: needs a paid Apple Developer account. Removes the "unidentified developer" block.
- **Notarization**: upload to Apple (`xcrun notarytool`), they scan it, you staple the ticket. Removes the last warning. Needed for public distribution, not for personal use.
- **Hardened runtime** and **App Sandbox** are entitlements. Sandbox is required only for the App Store; skip it. Hardened runtime is required for notarization.

### SwiftPM without Xcode
`Package.swift` declares an executable target. `swift build -c release` produces the binary in `.build/release/`. `swift test` runs tests. AppKit links automatically on macOS. What you lose without Xcode: Interface Builder, asset catalogs, the Instruments GUI, and the one-click Archive. None are needed for this project.

### Swift concurrency and AppKit
AppKit is main-thread only. Swift 6 enforces this with `@MainActor`. Background work (encoding tests in the Encoding sheet, full-file highlight pass) goes in a `Task.detached` and hops back with `await MainActor.run { }`. If the strict checking fights you early on, set `swiftLanguageModes: [.v5]` in `Package.swift` and tighten later.
