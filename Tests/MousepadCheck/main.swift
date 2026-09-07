// Self-check for MousepadCore. Run: swift run MousepadCheck
// ponytail: plain asserts instead of XCTest; the command line tools ship no test framework.
import Foundation
import MousepadCore

var failures = 0

func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: Int = #line) {
    if a != b {
        failures += 1
        print("FAIL line \(line): \(msg)\n   got:      \(String(reflecting: a))\n   expected: \(String(reflecting: b))")
    }
}

func ok(_ cond: Bool, _ msg: String, line: Int = #line) {
    if !cond { failures += 1; print("FAIL line \(line): \(msg)") }
}

func throwsError(_ msg: String, line: Int = #line, _ f: () throws -> Void) {
    do { try f(); failures += 1; print("FAIL line \(line): \(msg) did not throw") } catch {}
}

func r(_ loc: Int, _ len: Int = 0) -> NSRange { NSRange(location: loc, length: len) }

do {
    // MARK: TextFile round trips
    let sample = "héllo\nworld\n\ttab  end"
    let encodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .isoLatin1, .windowsCP1252]
    for enc in encodings {
        for eol in LineEnding.allCases {
            for bom in [false, true] {
                let meta = TextMeta(encoding: enc, writeBOM: bom, lineEnding: eol)
                let data = try TextFile.encode(sample, meta: meta)
                let (text, got) = try TextFile.decode(data, preferred: enc)
                let label = "\(Encodings.name(for: enc)) \(eol.label) bom=\(bom)"
                eq(text, sample, label)
                eq(got.lineEnding, eol, label)
                eq(got.encoding, enc, label)
                eq(got.writeBOM, bom && Encodings.isUnicode(enc), label)
            }
        }
    }

    // MARK: BOM
    eq(TextFile.detectBOM(Data([0xEF, 0xBB, 0xBF, 0x41]))?.encoding, .utf8)
    eq(TextFile.detectBOM(Data([0xFF, 0xFE, 0x68, 0x00]))?.encoding, .utf16LittleEndian)
    eq(TextFile.detectBOM(Data([0xFF, 0xFE, 0x00, 0x00]))?.encoding, .utf32LittleEndian)
    eq(TextFile.detectBOM(Data([0xFE, 0xFF, 0x00, 0x68]))?.encoding, .utf16BigEndian)
    ok(TextFile.detectBOM(Data([0x41, 0x42])) == nil, "no BOM in plain ascii")
    ok(TextFile.detectBOM(Data()) == nil, "no BOM in empty data")
    eq([UInt8](try TextFile.encode("a", meta: TextMeta(encoding: .utf16BigEndian, writeBOM: true)).prefix(2)), [0xFE, 0xFF], "UTF-16 BE BOM")
    eq([UInt8](try TextFile.encode("a", meta: TextMeta(encoding: .utf8, writeBOM: true)).prefix(3)), [0xEF, 0xBB, 0xBF], "UTF-8 BOM")
    eq([UInt8](try TextFile.encode("a", meta: TextMeta(encoding: .isoLatin1, writeBOM: true))), [0x61, 0x0A], "no BOM for Latin-1")

    // MARK: line endings
    eq(TextFile.detectLineEnding("a\nb"), .lf)
    eq(TextFile.detectLineEnding("a\r\nb"), .crlf)
    eq(TextFile.detectLineEnding("a\rb"), .cr)
    eq(TextFile.detectLineEnding("abc"), .lf)
    eq(TextFile.detectLineEnding(""), .lf)
    let mixed = try TextFile.decode("a\r\nb\rc\nd".data(using: .utf8)!)
    eq(mixed.text, "a\nb\nc\nd", "mixed endings normalised")
    eq(mixed.meta.lineEnding, .crlf)

    // MARK: trailing newline
    eq(String(data: try TextFile.encode("a", meta: TextMeta()), encoding: .utf8), "a\n")
    eq(String(data: try TextFile.encode("a", meta: TextMeta(lineEnding: .cr)), encoding: .utf8), "a\r")
    eq(String(data: try TextFile.encode("a", meta: TextMeta(lineEnding: .crlf)), encoding: .utf8), "a")
    eq(try TextFile.encode("", meta: TextMeta()).count, 0, "empty stays empty")
    eq(try TextFile.decode("a\n".data(using: .utf8)!).text, "a")
    eq(try TextFile.decode("a\n\n".data(using: .utf8)!).text, "a\n")
    eq(try TextFile.decode(Data()).text, "")

    // MARK: encoding errors
    let latin = Data([0x61, 0xE9, 0x62])
    throwsError("invalid UTF-8") { _ = try TextFile.decode(latin) }
    eq(try TextFile.decode(latin, preferred: .isoLatin1).text, "aéb")
    throwsError("unencodable in Latin-1") { _ = try TextFile.encode("日本", meta: TextMeta(encoding: .isoLatin1)) }
    eq(Encodings.name(for: .utf8), "UTF-8")
    eq(Encodings.groups.first, "Unicode")
    for e in Encodings.all { ok("abc".data(using: e.encoding) != nil, "\(e.name) cannot encode ASCII") }

    // MARK: TextOps
    eq(TextOps.indent("a\nb", r(0, 3), unit: "  ").apply(to: "a\nb"), "  a\n  b")
    eq(TextOps.indent("a\nb", r(0, 3), unit: "  ").selection, r(0, 7))
    eq(TextOps.unindent("\ta\n    b\n  c", r(0, 12), tabWidth: 4).apply(to: "\ta\n    b\n  c"), "a\nb\nc")
    eq(TextOps.indent("a\n\nb\n", r(0, 2), unit: "\t").apply(to: "a\n\nb\n"), "\ta\n\nb\n", "selection ending after newline stays on its line")
    eq(TextOps.indent("a\n\nb\n", r(0, 4), unit: "\t").apply(to: "a\n\nb\n"), "\ta\n\n\tb\n", "empty lines skipped")

    eq(TextOps.changeCase("abc", r(0, 3), .upper)?.replacement, "ABC")
    eq(TextOps.changeCase("ABC", r(0, 3), .lower)?.replacement, "abc")
    eq(TextOps.changeCase("hello world", r(0, 11), .title)?.replacement, "Hello World")
    eq(TextOps.changeCase("aBc1", r(0, 4), .opposite)?.replacement, "AbC1")
    ok(TextOps.changeCase("abc", r(1), .upper) == nil, "case change needs a selection")

    eq(TextOps.tabsToSpaces("\ta", r(0), tabWidth: 4).replacement, "    a")
    eq(TextOps.tabsToSpaces("a\tb", r(0), tabWidth: 4).replacement, "a   b")
    eq(TextOps.tabsToSpaces("ab\tc\n\td", r(0), tabWidth: 4).replacement, "ab  c\n    d")
    eq(TextOps.spacesToTabs("    a\n  b\n      c", r(0), tabWidth: 4).replacement, "\ta\n  b\n\t  c")

    eq(TextOps.stripTrailingSpaces("a  \nb\t\nc", r(0)).replacement, "a\nb\nc")
    eq(TextOps.stripTrailingSpaces("a  \nb  \nc  ", r(0, 1)).apply(to: "a  \nb  \nc  "), "a\nb  \nc  ", "strip only selected lines")

    let text = "a\nb\nc"
    ok(TextOps.moveLines(text as NSString, r(0), up: true) == nil, "first line cannot move up")
    let d = TextOps.moveLines(text as NSString, r(0), up: false)!
    eq(d.apply(to: text), "b\na\nc"); eq(d.selection, r(2))
    let u = TextOps.moveLines(text as NSString, r(4), up: true)!
    eq(u.apply(to: text), "a\nc\nb"); eq(u.selection, r(2))
    ok(TextOps.moveLines(text as NSString, r(4), up: false) == nil, "last line cannot move down")
    let block = TextOps.moveLines(text as NSString, r(0, 3), up: false)!
    eq(block.apply(to: text), "c\na\nb"); eq(block.selection, r(2, 3))

    eq(TextOps.duplicate("a\nb", r(0)).apply(to: "a\nb"), "a\na\nb")
    eq(TextOps.duplicate("a\nb", r(0)).selection, r(2))
    eq(TextOps.duplicate("a\nb", r(2)).apply(to: "a\nb"), "a\nb\nb")
    eq(TextOps.duplicate("abc", r(0, 2)).apply(to: "abc"), "ababc")
    eq(TextOps.duplicate("abc", r(0, 2)).selection, r(2, 2))

    let chars = TextOps.transpose("ab", r(1))!
    eq(chars.apply(to: "ab"), "ba"); eq(chars.selection, r(2))
    ok(TextOps.transpose("ab", r(0)) == nil, "nothing before cursor")
    ok(TextOps.transpose("a\nb", r(1)) == nil, "never swap across a newline")
    eq(TextOps.transpose("a b c", r(0, 5))?.replacement, "c b a")
    eq(TextOps.transpose("a\nb\nc\n", r(0, 6))?.replacement, "c\nb\na\n")
    eq(TextOps.transpose("a😀" as NSString, r(1))?.apply(to: "a😀"), "😀a", "surrogate pair kept whole")

    // MARK: Highlighter
    let h = Highlighter()
    let mess = "func main() { // hi\n  let x = \"s\" + 42 /* c */ }\n# hash\n<a href='x'>t</a>\n"
    for lang in Languages.all + [Languages.plainText] { _ = h.tokens(in: mess, language: lang) }   // every pattern compiles
    let src = "let x = \"hi\" // note\nstruct Foo {}"
    let tokens = h.tokens(in: src, language: Languages.language(id: "swift")!)
    let ns = src as NSString
    func has(_ kind: TokenKind, _ s: String) -> Bool { tokens.contains { $0.kind == kind && ns.substring(with: $0.range) == s } }
    ok(has(.keyword, "let"), "keyword let")
    ok(has(.keyword, "struct"), "keyword struct")
    ok(has(.string, "\"hi\""), "string")
    ok(has(.comment, "// note"), "comment")
    ok(has(.type, "Foo"), "type")
    eq(h.tokens(in: "// let x", language: Languages.language(id: "swift")!).last?.kind, .comment, "comment rule runs last")

    eq(Languages.guess(filename: "main.swift", firstLine: "").id, "swift")
    eq(Languages.guess(filename: "Makefile", firstLine: "").id, "makefile")
    eq(Languages.guess(filename: "run", firstLine: "#!/usr/bin/env python3").id, "python")
    eq(Languages.guess(filename: "x", firstLine: "<?xml version=\"1.0\"?>").id, "html")
    eq(Languages.guess(filename: "notes.txt", firstLine: "").id, "plain")
    eq(Languages.guess(filename: nil, firstLine: "").id, "plain")
    ok(!Languages.sections.isEmpty, "sections")
    eq(Languages.language(id: "plain")?.name, "Plain Text")
    ok(Languages.language(id: "nope") == nil, "unknown language")
} catch {
    failures += 1
    print("FAIL threw: \(error)")
}

if failures == 0 {
    print("OK: all checks passed")
    exit(0)
} else {
    print("\(failures) FAILURE(S)")
    exit(1)
}
