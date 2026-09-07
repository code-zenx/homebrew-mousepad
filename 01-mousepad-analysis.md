# Mousepad: What It Is and How It Works

Source studied: `github.com/codebrainz/mousepad` (mirror of Xfce Mousepad, version 0.4.2, snapshot from 2020-09-27).

Mousepad is a small text editor for the Xfce desktop. It is written in C with GTK 3 and GtkSourceView 3.
Total size: about 18,000 lines of C. One big file (`mousepad-window.c`, 6,000 lines) holds most of the UI logic.

This doc lists **what the original does**. Use it as the feature reference for the clone.

---

## 1. Module Map

| File | Lines | Job |
|---|---|---|
| `main.c` | 200 | Parse command line. Talk to running instance over D-Bus. Otherwise open a window. |
| `mousepad-application.c` | 550 | App singleton. Owns windows. Loads menu XML. Builds Filetype and Color Scheme menus. |
| `mousepad-window.c` | 6,050 | Main window. Menubar, toolbar, tab notebook, statusbar. All menu actions. Recent files. Templates. Paste history. Drag and drop. |
| `mousepad-document.c` | 550 | One tab. Wraps a text buffer, a text view, a file object, and a search context. Tab label with close button. |
| `mousepad-view.c` | 1,930 | The editor widget (subclass of GtkSourceView). Text operations: indent, case change, transpose, move lines, duplicate, tabs/spaces, strip trailing spaces, column paste. |
| `mousepad-file.c` | 960 | Load and save one file. Encoding, BOM, line endings, read-only flag, modification time, language guessing. |
| `mousepad-encoding.c` | 190 | Table of ~60 charsets with display names. |
| `mousepad-encoding-dialog.c` | 510 | Dialog shown when a file is not valid UTF-8. Tests encodings in the background. |
| `mousepad-search-bar.c` | 560 | Bottom search bar (Ctrl+F). |
| `mousepad-replace-dialog.c` | 650 | Find and Replace dialog (Ctrl+R). |
| `mousepad-util.c` | 990 | Helpers. The core `mousepad_util_search()` function lives here. Word-boundary iterators. |
| `mousepad-print.c` | 820 | Print with page setup, headers, line numbers, syntax colors. |
| `mousepad-prefs-dialog.c` + `.glade` | 580 | Preferences dialog. Widgets bound to settings keys. |
| `mousepad-settings.c` + `-store.c` | 700 | Thin layer over GSettings. Optional keyfile backend (plain `.ini` file). |
| `mousepad-statusbar.c` | 320 | Statusbar: filetype, line/column/selection, OVR/INS toggle. |
| `mousepad-dialogs.c` | 510 | Small dialogs: about, error, go-to line, save changes, externally modified, revert, clear history, tab size. |
| `mousepad-dbus.c` | 270 | Single-instance. Exposes `LaunchFiles` and `Terminate` on the session bus. |
| `mousepad-close-button.c` | 70 | Tiny flat close button used on tab labels. |
| `mousepad-window.ui` | | Menu structure in XML (GMenu). Also the right-click menus. |
| `org.xfce.mousepad.gschema.xml` | | All settings, with types and defaults. |

---

## 2. Object Model (who owns what)

```
Application (singleton)
 └── Window (0..n)  — GtkApplicationWindow
      ├── Menubar, Toolbar, Search bar, Statusbar
      └── Notebook (tabs)
           └── Document (1..n)  — GtkScrolledWindow
                ├── File        — path, encoding, EOL, mtime, read-only, language
                ├── Buffer      — GtkSourceBuffer (text + undo + syntax)
                ├── SearchContext — GtkSourceSearchContext (bound to buffer)
                └── View        — MousepadView (GtkSourceView subclass)
```

Every tab has its own File, Buffer, View, and search context. A window only points to the "active" document.

---

## 3. Feature Inventory (from menus and actions)

### File menu
| Item | Shortcut | Notes |
|---|---|---|
| New | Ctrl+N | Empty tab named "Untitled N" |
| New Window | Shift+Ctrl+N | |
| New From Template | | Submenu built from `~/Templates` (XDG templates dir). Subfolders become submenus. |
| Open... | Ctrl+O | Multi-select file chooser. Has an **Encoding** combo box. |
| Open Recent | | Submenu, max N items (setting). Stores charset per file in recent-item description. Has "Clear History". |
| Save | Ctrl+S | If file is new or read-only, runs Save As. Checks for external modification first. |
| Save As... | Shift+Ctrl+S | |
| Save All | | |
| Revert | | Reloads from disk. Asks first if buffer is modified. |
| Print... | Ctrl+P | |
| Detach Tab | Ctrl+D | Moves tab into a new window. |
| Close Tab | Ctrl+W | Asks to save if modified. |
| Close Window | Ctrl+Q | |

### Edit menu
| Item | Shortcut |
|---|---|
| Undo / Redo | Ctrl+Z / Ctrl+Y |
| Cut / Copy / Paste | Ctrl+X / C / V |
| Paste Special ▸ Paste from History | Popup menu of last 10 copied texts |
| Paste Special ▸ Paste as Column | Splits clipboard by line, inserts one piece per line at same column |
| Delete | |
| Select All | |
| Convert ▸ To Lowercase / Uppercase / Title Case / Opposite Case | |
| Convert ▸ Tabs to Spaces / Spaces to Tabs | Works on selection or whole doc |
| Convert ▸ Strip Trailing Spaces | |
| Convert ▸ Transpose | Ctrl+T. Swaps chars, words, or lines depending on selection |
| Move Selection ▸ Line Up / Line Down | |
| Duplicate Line / Selection | |
| Increase / Decrease Indent | |
| Preferences | |

### Search menu
| Item | Shortcut | Notes |
|---|---|---|
| Find | Ctrl+F | Shows bottom search bar. Searches as you type. Esc hides. Enter = next, Shift+Enter = previous. |
| Find Next / Previous | Ctrl+G / Shift+Ctrl+G | |
| Find and Replace... | Ctrl+R | Dialog. Options: direction, wrap, match case, whole word, regex. "Replace all in: Selection / Document / All Documents". Shows hit count. Remembers search and replace history in combo boxes. |
| Go to... | Ctrl+L | Dialog with line and column spin buttons. |

Search bar options: Match case, Regular expression, Highlight All.

### View menu
| Item | Shortcut |
|---|---|
| Select Font... | |
| Color Scheme ▸ (list of GtkSourceView style schemes) | |
| Line Numbers | |
| Menubar / Toolbar / Statusbar (toggles) | Ctrl+M for menubar |
| Fullscreen | F11 |

### Document menu (per tab)
| Item | Shortcut |
|---|---|
| Word Wrap | |
| Auto Indent | |
| Tab Size ▸ 2 / 3 / 4 / 8 / Other... | List comes from setting `default-tab-sizes` |
| Tab Size ▸ Insert Spaces | |
| Filetype ▸ (languages grouped by section) | |
| Line Ending ▸ Unix (LF) / Mac (CR) / DOS (CR LF) | |
| Write Unicode BOM | Only enabled for Unicode encodings |
| Previous / Next Tab | Ctrl+PageUp / Ctrl+PageDown |
| Go to tab N | Alt+1 .. Alt+9 |

### Help menu
Contents (F1, opens docs URL), About.

### Toolbar (hidden by default)
New, Open, Save, Save As, Revert, Close Tab, Undo, Redo, Cut, Copy, Paste, Find, Find and Replace, Go to, Fullscreen.

### Right-click menus
- **Text view**: Undo, Redo, Cut, Copy, Paste, Paste Special, Delete, Select All, Convert, Move Selection, Duplicate, Indent. Plus "Menubar" toggle when menubar is hidden.
- **Tab label**: Save, Save As, Revert, Detach Tab, Close Tab.

### Tab bar behaviours
- Tabs scrollable. Tabs draggable between windows (same group name). Drop on empty space creates a new window.
- Middle click on tab = close. Double click on empty tab area = new document.
- Tab label turns red when modified. Tooltip shows full path.
- Tabs hidden when only one file open, unless `always-show-tabs`.
- Ctrl+PageUp/Down wrap around only if `cycle-tabs`.

### Statusbar
- "Filetype: X" (click to open filetype menu)
- "Line: N Column: M" and "Selection: K" when text is selected
- "OVR" / "INS" (click to toggle overwrite)
- Menu item tooltips shown here on hover.

### Window title
- `*name - Mousepad` when modified
- `name [Read Only] - Mousepad` when not writable
- `name` is full path if `path-in-title`, else basename.

### Other
- Root warning banner if running as root (`geteuid() == 0`).
- Drag and drop of files onto window opens them.
- Window remembers size, position, maximized, fullscreen (settings).
- Fullscreen can auto-hide menubar/toolbar/statusbar (three-state settings: auto / no / yes).
- Keyboard accelerators saved to `accels.scm` in config dir so users can rebind.

---

## 4. Command Line

```
mousepad [OPTIONS] [FILES...]
  --disable-server   do not register on D-Bus
  -q, --quit         tell running instance to quit
  -v, --version
```

Flow in `main()`:
1. Parse options.
2. If `--quit`: call `Terminate` on D-Bus and exit.
3. Unless `--disable-server`: try `LaunchFiles(cwd, files)` on D-Bus. If a running instance answers, exit.
4. Else create the app, open a window with the files, register D-Bus service, run main loop.

---

## 5. File Load Algorithm (`mousepad_file_open`)

1. If path does not exist: treat as new file with that name. Return OK.
2. Memory-map the file.
3. Look for a BOM at the start. Recognised: UTF-8, UTF-16 LE/BE, UTF-32 LE/BE, UTF-7. If found, set encoding, set `write_bom = true`, skip the BOM bytes.
4. If encoding is UTF-8: validate. Invalid → return `ERROR_NOT_UTF8_VALID`.
5. Else: convert from charset to UTF-8 with `g_convert`. Fail → `ERROR_CONVERTING_FAILED`. Then validate.
6. Detect line ending from the **first** `\n` or `\r` seen: `\n` = Unix, `\r\n` = DOS, lone `\r` = Mac.
7. Drop the final trailing newline (the text view does not want it).
8. Insert text into buffer. `\r` and `\r\n` are normalised to `\n` inside the buffer.
9. Cursor to start. `stat()` the file: read-only if not writable by owner. Remember `mtime`.
10. Guess language from filename + first 255 bytes (content type sniffing).
11. Mark buffer unmodified.

On error the window then:
- Looks up the charset stored for this file in recent history and retries.
- Else shows the **Encoding dialog**: radio buttons "Default (UTF-8)", "System (X)", "Other: [combo]". A background job tries each charset and shows a preview.

## 6. File Save Algorithm (`mousepad_file_save`)

1. `open(O_WRONLY | O_CREAT | O_TRUNC, 0666)`. **Not atomic**: the file is truncated first. (Clone should do better: write temp file then rename.)
2. Get buffer text (always `\n` inside).
3. Convert line endings: Mac → replace `\n` with `\r`; DOS → join with `\r\n`.
4. If `write_bom` and encoding is Unicode: prepend UTF-8 BOM bytes `EF BB BF`. (Only UTF-8 BOM is ever written, even for UTF-16. A small bug in the original.)
5. Append a final newline for Unix/Mac (DOS gets none). 
6. If encoding is not UTF-8: convert with `g_convert`.
7. Write loop, retry on `EAGAIN`/`EINTR`.
8. `fstat` → store new `mtime`. Mark unmodified, clear read-only. Re-guess language if user has not forced one.

Before save, the window checks `externally_modified`: compares stored `mtime` to current `stat().st_mtime`. If different → dialog "Cancel / Save As / Save".

## 7. Search Engine (`mousepad_util_search`)

One function drives search bar, replace dialog, and highlight. It takes flag bits:

- **Area**: entire area, selection only, all documents
- **Start point**: selection start, selection end
- **Direction**: forward, backward
- **Options**: match case, regex, whole word, wrap around
- **Action**: highlight on, highlight off, select match, replace

Key tricks:
- "Replace all in selection" copies the selected text into a throwaway buffer, replaces there, then puts the result back as a single undo step.
- Occurrence count comes from GtkSourceSearchContext, which scans lazily. The code forces a full scan by searching both directions until the count is known.
- Search settings (case, regex, whole word, wrap, direction, replace-all target) persist in the `state.search` settings group.

## 8. Settings (GSettings schema)

Three groups. Types: `b` bool, `i` int, `s` string, or enum.

**preferences.view**
| Key | Default |
|---|---|
| auto-indent | false |
| font-name | "Monospace" |
| use-default-monospace-font | true |
| show-whitespace | false |
| show-line-endings | false |
| highlight-current-line | false |
| indent-on-tab | true |
| indent-width | -1 (= same as tab width) |
| insert-spaces | false |
| right-margin-position | 80 |
| show-line-marks | false |
| show-line-numbers | false |
| show-right-margin | false |
| smart-home-end | disabled / before / after / always |
| tab-width | 8 |
| word-wrap | false |
| match-braces | false |
| color-scheme | "none" |

**preferences.window**
| Key | Default |
|---|---|
| toolbar-style | icons / text / both / both-horiz |
| toolbar-icon-size | small-toolbar |
| always-show-tabs | false |
| cycle-tabs | false |
| default-tab-sizes | "2,3,4,8" |
| path-in-title | true |
| recent-menu-items | 10 |
| remember-size / remember-position / remember-state | true / false / true |
| menubar-visible / toolbar-visible / statusbar-visible | true / false / false |
| menubar-visible-in-fullscreen etc. | auto / no / yes |

**state.search**: direction, wrap-around, match-case, enable-regex, match-whole-word, replace-all, replace-all-location, highlight-all.

**state.window**: width 640, height 480, top, left, maximized, fullscreen.

Preferences dialog has three tabs: **View** (Display, Font, Colour scheme), **Editor** (Indentation, Home/End keys), **Window** (General, Toolbar, Notebook tabs).

## 9. Editor Widget Details (`mousepad-view.c`)

Built on GtkSourceView, which gives for free: syntax highlighting, line numbers, current-line highlight, right margin, bracket matching, whitespace drawing, auto indent, smart Home/End, undo/redo, style schemes.

Custom key handling:
- **Home**: if at line start, jump to first non-blank character. Ctrl+Home = document start. Shift extends selection.
- **Ctrl+End**: document end.
- **Delete** with a column selection deletes it.

Custom operations (all wrapped in one undo action):
- **Indent / unindent**: adds or removes one tab-width per line of the selection. Uses tabs or spaces per the `insert-spaces` setting.
- **Case conversion**: lower, upper, title (capitalise each word), opposite (swap case).
- **Tabs ↔ spaces**: respects real column position (tab stops), not just char count.
- **Strip trailing spaces**: on selection or whole document.
- **Move line up/down**: cuts the selected lines and reinserts one line above or below, keeps selection.
- **Duplicate**: copies selection, or the whole line if nothing selected.
- **Transpose**: no selection → swap the two chars around the cursor. Selection inside one line → reverse the words. Multi-line selection → reverse line order.
- **Paste as column**: split clipboard on newlines, insert piece *i* on line (cursor line + i) at the same x pixel offset. Adds new lines at end of buffer if needed.

Font: "Monospace" by default, or the system monospace font read from xfconf/GSettings.

## 10. Single Instance (D-Bus)

Name `org.xfce.Mousepad`, object `/org/xfce/Mousepad`.
- `LaunchFiles(working_directory: s, filenames: as)` → opens files in a new window of the running process. Relative paths resolved against `working_directory`.
- `Terminate()` → quit.

## 11. Printing

Uses GtkPrintOperation + GtkSourcePrintCompositor. Custom tab "Document Settings":
- Page setup button
- Print page headers (filename, page N of M)
- Print line numbers, numbering interval
- Enable text wrapping
- Enable syntax highlighting
- Fonts: header, body, line numbers

Print settings saved to a keyfile in the config dir.

## 12. Things the Original Does Not Do (for scope clarity)

- No session restore of open files (only window geometry).
- No file-change *watching* (only a `mtime` check at save time).
- No autosave, no backup files.
- No plugins, no spell check (added in later 0.5.x versions upstream).
- No split view, no minimap, no multi-cursor.
- Save is not atomic (truncate then write).
