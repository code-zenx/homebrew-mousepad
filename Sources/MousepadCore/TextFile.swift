import Foundation

/// Line ending stored on disk. The in-memory buffer always uses "\n".
public enum LineEnding: Int, CaseIterable, Sendable {
    case lf = 0, cr = 1, crlf = 2

    public var string: String {
        switch self {
        case .lf: return "\n"
        case .cr: return "\r"
        case .crlf: return "\r\n"
        }
    }
    public var label: String { ["LF", "CR", "CRLF"][rawValue] }
    public var menuTitle: String { ["Unix (LF)", "Mac (CR)", "DOS / Windows (CR LF)"][rawValue] }
}

/// Everything about a file that is not its text.
public struct TextMeta: Equatable, Sendable {
    public var encoding: String.Encoding
    public var writeBOM: Bool
    public var lineEnding: LineEnding

    public init(encoding: String.Encoding = .utf8, writeBOM: Bool = false, lineEnding: LineEnding = .lf) {
        self.encoding = encoding
        self.writeBOM = writeBOM
        self.lineEnding = lineEnding
    }
}

public enum TextFileError: Error, LocalizedError, Equatable {
    case undecodable(String.Encoding)
    case unencodable(String.Encoding)

    public var errorDescription: String? {
        switch self {
        case .undecodable(let e): return "The file is not valid \(Encodings.name(for: e)) text."
        case .unencodable(let e): return "The text cannot be saved as \(Encodings.name(for: e))."
        }
    }
}

/// Bytes <-> text. Pure Foundation, no AppKit, fully tested.
public enum TextFile {
    private static let boms: [(bytes: [UInt8], encoding: String.Encoding)] = [
        ([0xEF, 0xBB, 0xBF], .utf8),
        ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),   // must be checked before UTF-16 LE
        ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
        ([0xFF, 0xFE], .utf16LittleEndian),
        ([0xFE, 0xFF], .utf16BigEndian),
    ]

    public static func detectBOM(_ data: Data) -> (encoding: String.Encoding, length: Int)? {
        for bom in boms where data.count >= bom.bytes.count {
            if data.prefix(bom.bytes.count).elementsEqual(bom.bytes) { return (bom.encoding, bom.bytes.count) }
        }
        return nil
    }

    public static func bom(for encoding: String.Encoding) -> [UInt8]? {
        boms.first { $0.encoding == encoding }?.bytes
    }

    /// Decided by the first line break found. Empty or single-line text is LF.
    public static func detectLineEnding(_ text: String) -> LineEnding {
        var it = text.unicodeScalars.makeIterator()
        while let s = it.next() {
            if s == "\n" { return .lf }
            if s == "\r" { return it.next() == "\n" ? .crlf : .cr }
        }
        return .lf
    }

    /// Bytes -> text. Strips BOM, normalises line endings to "\n", drops one trailing newline.
    public static func decode(_ data: Data, preferred: String.Encoding? = nil) throws -> (text: String, meta: TextMeta) {
        var meta = TextMeta()
        var body = data
        if let bom = detectBOM(data) {
            meta.encoding = bom.encoding
            meta.writeBOM = true
            body = Data(data.dropFirst(bom.length))
        } else if let p = preferred {
            meta.encoding = p
        }
        guard var text = String(data: body, encoding: meta.encoding) else {
            throw TextFileError.undecodable(meta.encoding)
        }
        meta.lineEnding = detectLineEnding(text)
        if text.unicodeScalars.contains("\r") {
            text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        }
        if text.hasSuffix("\n") { text.removeLast() }
        return (text, meta)
    }

    /// Text -> bytes. Adds the final newline back, converts line endings, writes the right BOM.
    public static func encode(_ text: String, meta: TextMeta) throws -> Data {
        var out = text
        // Same rule as Mousepad: LF and CR files end with a newline, CRLF files do not.
        if !out.isEmpty && meta.lineEnding != .crlf { out += "\n" }
        if meta.lineEnding != .lf { out = out.replacingOccurrences(of: "\n", with: meta.lineEnding.string) }
        guard var data = out.data(using: meta.encoding) else {
            throw TextFileError.unencodable(meta.encoding)
        }
        if meta.writeBOM, let bom = bom(for: meta.encoding) { data.insert(contentsOf: bom, at: 0) }
        return data
    }
}
