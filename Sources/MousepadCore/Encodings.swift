import Foundation

public struct EncodingInfo: Equatable, Sendable {
    public let encoding: String.Encoding
    public let name: String
    public let group: String
}

private func cf(_ e: CFStringEncodings) -> String.Encoding {
    String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(e.rawValue)))
}

/// The charsets offered in menus, with display names, grouped like Mousepad's encoding dialog.
public enum Encodings {
    public static let all: [EncodingInfo] = [
        .init(encoding: .utf8, name: "UTF-8", group: "Unicode"),
        .init(encoding: .utf16LittleEndian, name: "UTF-16 LE", group: "Unicode"),
        .init(encoding: .utf16BigEndian, name: "UTF-16 BE", group: "Unicode"),
        .init(encoding: .utf32LittleEndian, name: "UTF-32 LE", group: "Unicode"),
        .init(encoding: .utf32BigEndian, name: "UTF-32 BE", group: "Unicode"),
        .init(encoding: .isoLatin1, name: "ISO-8859-1 (Latin-1)", group: "Western"),
        .init(encoding: cf(.isoLatin9), name: "ISO-8859-15 (Latin-9)", group: "Western"),
        .init(encoding: .windowsCP1252, name: "Windows-1252", group: "Western"),
        .init(encoding: .macOSRoman, name: "Mac OS Roman", group: "Western"),
        .init(encoding: .isoLatin2, name: "ISO-8859-2", group: "Central European"),
        .init(encoding: .windowsCP1250, name: "Windows-1250", group: "Central European"),
        .init(encoding: cf(.isoLatinCyrillic), name: "ISO-8859-5", group: "Cyrillic"),
        .init(encoding: .windowsCP1251, name: "Windows-1251", group: "Cyrillic"),
        .init(encoding: cf(.KOI8_R), name: "KOI8-R", group: "Cyrillic"),
        .init(encoding: cf(.KOI8_U), name: "KOI8-U", group: "Cyrillic"),
        .init(encoding: cf(.isoLatinGreek), name: "ISO-8859-7", group: "Greek"),
        .init(encoding: .windowsCP1253, name: "Windows-1253", group: "Greek"),
        .init(encoding: cf(.isoLatin5), name: "ISO-8859-9", group: "Turkish"),
        .init(encoding: .windowsCP1254, name: "Windows-1254", group: "Turkish"),
        .init(encoding: cf(.isoLatinHebrew), name: "ISO-8859-8", group: "Hebrew"),
        .init(encoding: cf(.windowsHebrew), name: "Windows-1255", group: "Hebrew"),
        .init(encoding: cf(.isoLatinArabic), name: "ISO-8859-6", group: "Arabic"),
        .init(encoding: cf(.windowsArabic), name: "Windows-1256", group: "Arabic"),
        .init(encoding: cf(.windowsBalticRim), name: "Windows-1257", group: "Baltic"),
        .init(encoding: .shiftJIS, name: "Shift JIS", group: "Japanese"),
        .init(encoding: .japaneseEUC, name: "EUC-JP", group: "Japanese"),
        .init(encoding: .iso2022JP, name: "ISO-2022-JP", group: "Japanese"),
        .init(encoding: cf(.GB_18030_2000), name: "GB18030", group: "Chinese"),
        .init(encoding: cf(.big5), name: "Big5", group: "Chinese"),
        .init(encoding: cf(.EUC_KR), name: "EUC-KR", group: "Korean"),
        .init(encoding: cf(.dosThai), name: "TIS-620 (Thai)", group: "Thai"),
        .init(encoding: cf(.windowsVietnamese), name: "Windows-1258", group: "Vietnamese"),
    ]

    public static var groups: [String] {
        var seen: [String] = []
        for e in all where !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }

    public static func info(for encoding: String.Encoding) -> EncodingInfo? {
        all.first { $0.encoding == encoding }
    }

    public static func name(for encoding: String.Encoding) -> String {
        info(for: encoding)?.name ?? "Encoding \(encoding.rawValue)"
    }

    public static func isUnicode(_ e: String.Encoding) -> Bool {
        [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian, .utf32BigEndian].contains(e)
    }

    public static let system: String.Encoding = .utf8
}
