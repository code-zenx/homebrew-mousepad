# UI Style: Terminal Brutalist

Reference look: `plugins.omarchy.org`. Black, monospace, square, one orange accent. Feels like a 1990s terminal app in a window.

Rule of thumb: **if a native control can be restyled, restyle it; if not, keep it native in dark appearance.** Menubar, title bar, alerts, file panels, and (in v1) the find bar stays native. Everything inside the document window is ours.

---

## 1. Palette

| Token | Hex | Use |
|---|---|---|
| `bg` | `#000000` | editor background, window background |
| `panel` | `#0B0B0D` | status bar, sheets, gutter, custom bars |
| `panelRaised` | `#050507` | pressed / active button background |
| `border` | `#28282C` | every 1 px line |
| `borderStrong` | `#3A3A3F` | focused control border, hover |
| `text` | `#D7D7D9` | body text |
| `textBright` | `#F0F0F1` | headings, active tab title |
| `muted` | `#AAAAB0` | labels, line numbers, inactive tab titles, hints |
| `accent` | `#FF5A36` | cursor, active marks, primary buttons, modified `*`, links, current line number |
| `accentDim` | `#FF5A36` at 25 % | selection background, current line background, match highlight |
| `ok` | `#B4C96F` | "saved", "verified"-style status |
| `error` | `#FF4D4D` | not-found entry, error text |
| `onAccent` | `#111111` | text on accent-filled buttons |

Color schemes for the editor (View → Color Scheme) swap `bg`, `text`, `accent`, and the token colors below. The chrome (status bar, sheets) always uses the scheme's `panel`/`border`/`muted` so the window stays coherent.

Syntax token colors, `terminal` scheme:

| Token | Color |
|---|---|
| keyword | `#FF5A36` accent |
| type | `#F0F0F1` bright |
| string | `#B4C96F` ok green |
| comment | `#6E6E74` (muted −30 %), italic |
| number | `#E0B356` |
| preprocessor / attribute | `#AAAAB0` muted |
| operator / punctuation | `#D7D7D9` text |

`grey` scheme: accent → `#D7D7D9`, keyword bold instead of colored. `paper` scheme: bg `#F4F4F2`, text `#1A1A1A`, panel `#EBEBE8`, border `#D0D0CC`, accent unchanged.

`mocha` scheme (default; Catppuccin Mocha, MIT): bg Base `#1E1E2E`, panel Mantle `#181825`, raised Crust `#11111B`, border Surface0 `#313244`, strong Surface1 `#45475A`, text `#CDD6F4`, bright Rosewater `#F5E0DC`, muted Overlay1 `#7F849C`, accent Mauve `#CBA6F7`, ok Green `#A6E3A1`, error Red `#F38BA8`. Tokens: keyword Mauve, type Yellow `#F9E2AF`, string Green, number Peach `#FAB387`, comment Overlay0 `#6C7086`, attribute Blue `#89B4FA`. Same layout rules; only the palette changes.

## 2. Typography

| Role | Font | Size | Case | Tracking |
|---|---|---|---|---|
| Editor text | user font; default SF Mono (v1.1: JetBrains Mono bundled) | 13 pt | as typed | 0 |
| Line numbers | same as editor | same | — | 0 |
| Chrome labels (status bar, sheet labels, buttons) | same mono family | 11 pt | **UPPERCASE** | +0.08 em |
| Sheet titles | mono | 13 pt | lowercase | 0 |
| Key hints | mono | 10 pt | as is (`⌘K`, `^T`) | 0 |

No bold except sheet titles. Italic only for comments. No sans-serif anywhere in our views.

## 3. Layout Rules

- **Zero corner radius** on everything we draw. No shadows. No gradients. No blur. No translucency.
- **1 px borders** in `border`. Use borders, not background tints, to separate regions.
- **8 pt grid**: padding 8 / 16, control height 24, bar height 24 (status) / 28 (tab bar, find bar v1.1).
- **Icons**: none. Use text: `→` for actions, `×` close, `*` modified, `^` `⌘` key hints, `[x]` / `[ ]` checkboxes in custom bars.
- **Focus**: 1 px `borderStrong` → `accent` border on the focused field. No glow rings.
- **Hover**: background `panelRaised`, border `borderStrong`.
- **Disabled**: `muted` text, border stays.
- **Primary button**: filled `accent`, `onAccent` text, label like `SAVE →`. **Secondary**: outlined `border`, `text`. **Danger**: outlined `error`, `error` text. Only one primary per sheet.
- **Motion**: none. No fades, no slides. Things appear.

## 4. Components

### Window
- `NSAppearance.darkAqua` forced regardless of system setting when scheme is dark; `aqua` for `paper`.
- `titlebarAppearsTransparent = true`, `styleMask += .fullSizeContentView`, `backgroundColor = bg`.
- Title shows `name` with the native modified dot. Subtitle (macOS 11+) shows full path when the setting is on.
- No toolbar. Ever.

### Tab bar
Custom, drawn by `TabBarView`. One window hosts many documents; AppKit window tabbing is off.

```
┌ main.swift ──┬ *notes.txt ──┬ Untitled ─────────────────────────────── + ┐
```
- 28 pt, `panel` bg, 1 px `border` bottom.
- Tab: title in `muted`; active tab title `textBright` with 2 px `accent` line at the bottom; modified prefix `*` in `accent`; `×` appears on hover; 1 px `border` between tabs.
- `+` at the right end = New.

### Editor
```
   1 │ fn main() {
   2 │     println!("hi");      ← current line: accentDim band, number in accent
   3 │ }
     │                           ← right margin: 1 px border line at col 80
```
- Gutter: `panel` bg, numbers right-aligned in `muted`, 1 px `border` on its right edge, 8 pt padding each side.
- Cursor: 2 pt wide `accent` bar. (Block cursor is an option in Preferences for the full 90s feel.)
- Selection: `accentDim` background, text color unchanged.
- Bracket match: 1 px `accent` underline on both brackets.
- Find matches: `accentDim` background; current match `accent` background with `onAccent` text.
- No line-wrap indicator glyphs.

### Status bar
```
│ SWIFT   UTF-8   LF   TAB 4                         LN 2  COL 14  SEL 0   INS │
```
- 24 pt, `panel` bg, 1 px `border` top.
- Segments separated by 16 pt gaps, not lines. Clickable segments underline on hover.
- `SEL n` only when selection exists. `INS` / `OVR` toggles on click, `OVR` shown in `accent`.

### Find bar (v1: native `NSTextFinder`)
v1.1 custom spec:
```
│ FIND  println_                REPLACE  print_        [x] CASE [ ] REGEX [x] ALL   ‹ › REPLACE  ALL → │
```
- 28 pt, `panel`, 1 px `border` top and bottom.
- Fields: `bg` background, 1 px `border`, `accent` on focus, 24 pt tall.
- Not found: field border and text turn `error`.
- Esc closes.

### Sheets (Encoding, Go To, Tab Size, Preferences)
```
┌──────────────────────────────────────────────┐
│ not valid utf-8                              │
│ PICK AN ENCODING                             │
│                                              │
│ (•) UTF-8   ( ) SYSTEM (UTF-8)   ( ) OTHER ▾ │
│ ┌──────────────────────────────────────────┐ │
│ │ preview of the first lines …             │ │
│ └──────────────────────────────────────────┘ │
│                          CANCEL    OPEN →    │
└──────────────────────────────────────────────┘
```
- `panel` bg, 1 px `border`, 16 pt padding, title 13 pt lowercase, label 11 pt uppercase `muted`.
- Native `NSAlert` for "Save changes?", "file changed on disk", "revert?" — do not rebuild those.

### Preferences window
- Single window 480 × 560, `panel` bg. Three sections switched by a text segmented row at the top: `VIEW  EDITOR  WINDOW` (active = `accent` underline).
- Each section: groups with 11 pt uppercase `muted` headings, 1 px `border` under each heading, native checkboxes and popups (they restyle acceptably in dark appearance).

### Menus
Native. Titles per `01` §3. Keep macOS conventions: app menu, Window menu, Help menu. Use `…` for items that open a dialog.

## 5. Full window mock (v1.1 look; v1 has this tab bar and the native find bar)

```
 ● ● ●   main.swift — ~/code/mousepad/Sources/main.swift
┌ main.swift ──┬ *notes.txt ──┬ Untitled ─────────────────────────────── + ┐
│   1 │ import AppKit                                                        │
│   2 │                                                                      │
│   3 │ let app = NSApplication.shared                                       │
│   4 │ app.run()▎                                                           │
│     │                                                                      │
│     │                                                                      │
├──────────────────────────────────────────────────────────────────────────┤
│ FIND  app_                       [x] CASE  [ ] REGEX  [x] ALL     ‹  ›    │
├──────────────────────────────────────────────────────────────────────────┤
│ SWIFT   UTF-8   LF   TAB 4                         LN 4  COL 10       INS │
└──────────────────────────────────────────────────────────────────────────┘
```

## 6. Things to Avoid

- Rounded corners, drop shadows, vibrancy/blur, SF Symbols icons, colored icons, sans-serif text, animations, gradients, more than one accent color, toolbar, sidebar, breadcrumbs, minimap.
- Restyling native alerts or the menubar. It looks worse than leaving them native.
