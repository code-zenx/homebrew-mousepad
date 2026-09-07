import Foundation

public enum TokenKind: Int, CaseIterable, Sendable {
    case keyword, type, string, comment, number, preprocessor
}

public struct Rule: Sendable, Equatable {
    public let kind: TokenKind
    public let pattern: String
    public init(_ kind: TokenKind, _ pattern: String) {
        self.kind = kind
        self.pattern = pattern
    }
}

public struct Language: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let section: String
    public let extensions: [String]
    public let filenames: [String]
    public let shebang: [String]
    /// Applied in order. A later rule paints over an earlier one, so comments go last.
    public let rules: [Rule]

    public static func == (a: Language, b: Language) -> Bool { a.id == b.id }
}

// Regex fragments shared between languages. Raw strings: what you see is the pattern.
private enum P {
    static let dq = #""(?:\\.|[^"\\\n])*""#
    static let sq = #"'(?:\\.|[^'\\\n])*'"#
    static let bq = #"`[^`]*`"#
    static let triple = #"(?s)("""|''').*?\1"#
    static let slashComment = #"//.*"#
    static let hashComment = #"#.*"#
    static let blockComment = #"(?s)/\*.*?\*/"#
    static let number = #"\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#
    static let type = #"\b[A-Z][A-Za-z0-9_]*\b"#

    static func kw(_ words: String) -> String {
        #"\b(?:"# + words.split(separator: " ").joined(separator: "|") + #")\b"#
    }
}

public enum Languages {
    public static let plainText = Language(id: "plain", name: "Plain Text", section: "Other",
                                           extensions: ["txt", "text", ""], filenames: [], shebang: [], rules: [])

    public static let all: [Language] = [
        Language(id: "swift", name: "Swift", section: "Sources", extensions: ["swift"], filenames: [], shebang: ["swift"], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("associatedtype class deinit enum extension func import init inout internal let operator private protocol public static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as catch is nil rethrows super self Self throw throws true false try await async actor any some open fileprivate final lazy override required mutating nonmutating convenience weak unowned indirect")),
            Rule(.preprocessor, #"[@#]\w+"#),
            Rule(.string, P.dq), Rule(.string, P.triple),
            Rule(.comment, P.slashComment), Rule(.comment, P.blockComment),
        ]),
        Language(id: "python", name: "Python", section: "Scripts", extensions: ["py", "pyw", "pyi"], filenames: [], shebang: ["python"], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield self match case print")),
            Rule(.preprocessor, #"@\w[\w.]*"#),
            Rule(.string, P.dq), Rule(.string, P.sq), Rule(.string, P.triple),
            Rule(.comment, P.hashComment),
        ]),
        Language(id: "javascript", name: "JavaScript", section: "Scripts", extensions: ["js", "mjs", "cjs", "jsx"], filenames: [], shebang: ["node"], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set null undefined true false")),
            Rule(.string, P.dq), Rule(.string, P.sq), Rule(.string, P.bq),
            Rule(.comment, P.slashComment), Rule(.comment, P.blockComment),
        ]),
        Language(id: "typescript", name: "TypeScript", section: "Scripts", extensions: ["ts", "tsx", "mts", "cts"], filenames: [], shebang: [], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set null undefined true false interface type enum implements declare namespace readonly abstract public private protected any number string boolean never unknown keyof as satisfies")),
            Rule(.string, P.dq), Rule(.string, P.sq), Rule(.string, P.bq),
            Rule(.comment, P.slashComment), Rule(.comment, P.blockComment),
        ]),
        Language(id: "rust", name: "Rust", section: "Sources", extensions: ["rs"], filenames: [], shebang: [], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("as break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while async await")),
            Rule(.preprocessor, #"#!?\[[^\]\n]*\]"#),
            Rule(.string, P.dq),
            Rule(.comment, P.slashComment), Rule(.comment, P.blockComment),
        ]),
        Language(id: "go", name: "Go", section: "Sources", extensions: ["go"], filenames: [], shebang: [], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var nil true false iota")),
            Rule(.string, P.dq), Rule(.string, P.bq),
            Rule(.comment, P.slashComment), Rule(.comment, P.blockComment),
        ]),
        Language(id: "c", name: "C / C++", section: "Sources", extensions: ["c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm"], filenames: [], shebang: [], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false nullptr class namespace template typename public private protected virtual override new delete this using try catch throw")),
            Rule(.preprocessor, #"^\s*#\s*\w+.*"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.slashComment), Rule(.comment, P.blockComment),
        ]),
        Language(id: "shell", name: "Shell", section: "Scripts", extensions: ["sh", "bash", "zsh", "fish"], filenames: [".bashrc", ".zshrc", ".profile", ".bash_profile"], shebang: ["sh", "bash", "zsh"], rules: [
            Rule(.number, P.number),
            Rule(.keyword, P.kw("if then else elif fi for while until do done case esac in function select return exit export local readonly declare set unset source alias echo cd")),
            Rule(.preprocessor, #"\$\{?\w+\}?"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.hashComment),
        ]),
        Language(id: "ruby", name: "Ruby", section: "Scripts", extensions: ["rb", "rake", "gemspec"], filenames: ["Gemfile", "Rakefile"], shebang: ["ruby"], rules: [
            Rule(.type, P.type), Rule(.number, P.number),
            Rule(.keyword, P.kw("alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require attr_accessor attr_reader puts")),
            Rule(.preprocessor, #"[@$]\w+|:\w+"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.hashComment),
        ]),
        Language(id: "markdown", name: "Markdown", section: "Markup", extensions: ["md", "markdown"], filenames: [], shebang: [], rules: [
            Rule(.preprocessor, #"\[[^\]\n]*\]\([^)\n]*\)"#),
            Rule(.type, #"\*\*[^*\n]+\*\*"#),
            Rule(.string, #"`[^`\n]+`"#),
            Rule(.comment, #"^\s*>.*"#),
            Rule(.keyword, #"^#{1,6} .*"#),
        ]),
        Language(id: "html", name: "HTML / XML", section: "Markup", extensions: ["html", "htm", "xml", "svg", "xhtml", "plist"], filenames: [], shebang: [], rules: [
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.type, #"</?[A-Za-z][^>]*>"#),
            Rule(.comment, #"(?s)<!--.*?-->"#),
        ]),
        Language(id: "css", name: "CSS", section: "Markup", extensions: ["css", "scss", "less"], filenames: [], shebang: [], rules: [
            Rule(.type, #"^[^{}\n]+(?=\{)"#),
            Rule(.keyword, #"\b[a-z-]+(?=\s*:)"#),
            Rule(.number, #"\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg)?"#),
            Rule(.preprocessor, #"#[0-9a-fA-F]{3,8}\b"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.blockComment),
        ]),
        Language(id: "json", name: "JSON", section: "Data", extensions: ["json", "jsonc"], filenames: [], shebang: [], rules: [
            Rule(.number, P.number),
            Rule(.keyword, P.kw("true false null")),
            Rule(.string, P.dq),
            Rule(.type, #""[^"\n]*"(?=\s*:)"#),
        ]),
        Language(id: "yaml", name: "YAML", section: "Data", extensions: ["yml", "yaml"], filenames: [], shebang: [], rules: [
            Rule(.number, P.number),
            Rule(.keyword, #"^\s*-?\s*[\w.-]+(?=\s*:)"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.hashComment),
        ]),
        Language(id: "toml", name: "TOML", section: "Data", extensions: ["toml"], filenames: [], shebang: [], rules: [
            Rule(.number, P.number),
            Rule(.keyword, #"^\s*[\w.-]+(?=\s*=)"#),
            Rule(.type, #"^\s*\[[^\]\n]*\]"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.hashComment),
        ]),
        Language(id: "makefile", name: "Makefile", section: "Other", extensions: ["mk", "make"], filenames: ["makefile", "gnumakefile"], shebang: [], rules: [
            Rule(.keyword, P.kw("ifeq ifneq ifdef ifndef else endif include export define endef")),
            Rule(.type, #"^[A-Za-z0-9_./-]+(?=\s*:)"#),
            Rule(.preprocessor, #"\$\([^)\n]*\)"#),
            Rule(.string, P.dq), Rule(.string, P.sq),
            Rule(.comment, P.hashComment),
        ]),
    ]

    public static var sections: [String] {
        var seen: [String] = []
        for l in all where !seen.contains(l.section) { seen.append(l.section) }
        return seen
    }

    public static func language(id: String) -> Language? {
        id == plainText.id ? plainText : all.first { $0.id == id }
    }

    /// Filename first (exact names, then extension), then the shebang line, then plain text.
    public static func guess(filename: String?, firstLine: String) -> Language {
        if let f = filename?.lowercased() {
            if let l = all.first(where: { $0.filenames.contains(f) }) { return l }
            let ext = (f as NSString).pathExtension
            if !ext.isEmpty, let l = all.first(where: { $0.extensions.contains(ext) }) { return l }
        }
        if firstLine.hasPrefix("#!") {
            if let l = all.first(where: { l in l.shebang.contains { firstLine.contains($0) } }) { return l }
        }
        let lower = firstLine.lowercased()
        if lower.hasPrefix("<?xml") || lower.hasPrefix("<!doctype html") { return language(id: "html") ?? plainText }
        return plainText
    }
}
