import AppKit
import MousepadCore

/// Palette from 05-ui-style.md. Every color in the app comes from here.
struct Theme {
    let name: String
    let isLight: Bool
    let bg: NSColor
    let panel: NSColor
    let panelRaised: NSColor
    let border: NSColor
    let borderStrong: NSColor
    let text: NSColor
    let textBright: NSColor
    let muted: NSColor
    let accent: NSColor
    let ok: NSColor
    let error: NSColor
    let onAccent: NSColor
    let tokens: [TokenKind: NSColor]

    /// Menu label.
    var title: String { name == "mocha" ? "Catppuccin Mocha" : name.capitalized }

    var accentDim: NSColor { accent.withAlphaComponent(0.28) }
    var currentLine: NSColor { accent.withAlphaComponent(isLight ? 0.10 : 0.12) }

    static let uiFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    static let terminal = Theme(
        name: "terminal", isLight: false,
        bg: c("000000"), panel: c("0B0B0D"), panelRaised: c("050507"),
        border: c("28282C"), borderStrong: c("3A3A3F"),
        text: c("D7D7D9"), textBright: c("F0F0F1"), muted: c("AAAAB0"),
        accent: c("FF5A36"), ok: c("B4C96F"), error: c("FF4D4D"), onAccent: c("111111"),
        tokens: [.keyword: c("FF5A36"), .type: c("F0F0F1"), .string: c("B4C96F"),
                 .comment: c("6E6E74"), .number: c("E0B356"), .preprocessor: c("AAAAB0")])

    static let grey = Theme(
        name: "grey", isLight: false,
        bg: c("000000"), panel: c("0B0B0D"), panelRaised: c("050507"),
        border: c("28282C"), borderStrong: c("3A3A3F"),
        text: c("D7D7D9"), textBright: c("F0F0F1"), muted: c("AAAAB0"),
        accent: c("D7D7D9"), ok: c("B4C96F"), error: c("FF4D4D"), onAccent: c("111111"),
        tokens: [.keyword: c("F0F0F1"), .type: c("D7D7D9"), .string: c("AAAAB0"),
                 .comment: c("6E6E74"), .number: c("D7D7D9"), .preprocessor: c("AAAAB0")])

    static let paper = Theme(
        name: "paper", isLight: true,
        bg: c("F4F4F2"), panel: c("EBEBE8"), panelRaised: c("E0E0DC"),
        border: c("D0D0CC"), borderStrong: c("B8B8B3"),
        text: c("1A1A1A"), textBright: c("000000"), muted: c("6B6B6B"),
        accent: c("FF5A36"), ok: c("4F7A1F"), error: c("C0392B"), onAccent: c("111111"),
        tokens: [.keyword: c("D94A2A"), .type: c("1A1A1A"), .string: c("4F7A1F"),
                 .comment: c("8A8A8A"), .number: c("9A6A00"), .preprocessor: c("6B6B6B")])

    /// Catppuccin Mocha (MIT, github.com/catppuccin). Base/Mantle/Crust for surfaces,
    /// Mauve accent, the usual token mapping: keyword Mauve, type Yellow, string Green,
    /// number Peach, comment Overlay0, attribute Blue.
    static let mocha = Theme(
        name: "mocha", isLight: false,
        bg: c("1E1E2E"), panel: c("181825"), panelRaised: c("11111B"),
        border: c("313244"), borderStrong: c("45475A"),
        text: c("CDD6F4"), textBright: c("F5E0DC"), muted: c("7F849C"),
        accent: c("CBA6F7"), ok: c("A6E3A1"), error: c("F38BA8"), onAccent: c("11111B"),
        tokens: [.keyword: c("CBA6F7"), .type: c("F9E2AF"), .string: c("A6E3A1"),
                 .comment: c("6C7086"), .number: c("FAB387"), .preprocessor: c("89B4FA")])

    static let all = [mocha, terminal, grey, paper]

    static func named(_ n: String) -> Theme { all.first { $0.name == n } ?? terminal }
}

private func c(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
