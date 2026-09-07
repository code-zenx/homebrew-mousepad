import AppKit

/// All preferences. One key, one default, one type. Stored in UserDefaults.
/// `defaults read dev.siddharth.mousepad` shows them.
enum Settings {
    enum Key: String, CaseIterable {
        case fontName, fontSize
        case showLineNumbers, highlightCurrentLine, showRightMargin, rightMarginColumn, wordWrap, blockCursor, matchBrackets
        case tabWidth, insertSpaces, autoIndent, smartHome
        case colorScheme, statusBarVisible, pathInTitle, rememberWindowFrame, defaultTabSizes
    }

    static let defaults: [String: Any] = [
        Key.fontName.rawValue: "",
        Key.fontSize.rawValue: 13,
        Key.showLineNumbers.rawValue: true,
        Key.highlightCurrentLine.rawValue: true,
        Key.showRightMargin.rawValue: false,
        Key.rightMarginColumn.rawValue: 80,
        Key.wordWrap.rawValue: false,
        Key.blockCursor.rawValue: false,
        Key.matchBrackets.rawValue: true,
        Key.tabWidth.rawValue: 4,
        Key.insertSpaces.rawValue: false,
        Key.autoIndent.rawValue: true,
        Key.smartHome.rawValue: true,
        Key.colorScheme.rawValue: "mocha",
        Key.statusBarVisible.rawValue: true,
        Key.pathInTitle.rawValue: true,
        Key.rememberWindowFrame.rawValue: true,
        Key.defaultTabSizes.rawValue: "2,3,4,8",
    ]

    static func registerDefaults() { UserDefaults.standard.register(defaults: defaults) }

    private static var d: UserDefaults { .standard }

    static func bool(_ k: Key) -> Bool { d.bool(forKey: k.rawValue) }
    static func int(_ k: Key) -> Int { d.integer(forKey: k.rawValue) }
    static func string(_ k: Key) -> String { d.string(forKey: k.rawValue) ?? "" }
    static func set(_ v: Any?, _ k: Key) { d.set(v, forKey: k.rawValue) }
    static func toggle(_ k: Key) { set(!bool(k), k) }

    static var font: NSFont {
        let size = CGFloat(max(6, int(.fontSize)))
        let name = string(.fontName)
        if !name.isEmpty, let f = NSFont(name: name, size: size) { return f }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var tabSizes: [Int] {
        let sizes = string(.defaultTabSizes).split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return sizes.isEmpty ? [2, 3, 4, 8] : sizes
    }
}
