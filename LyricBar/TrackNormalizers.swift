import Foundation

enum TrackTitleNormalizer {
    private static let versionWords = [
        "feat\\.", "featuring", "ft\\.", "with", "remastered", "deluxe", "explicit",
        "live", "radio edit", "mono", "stereo", "sped up", "slowed", "instrumental"
    ]

    static func normalizedTitle(_ title: String) -> String {
        var value = title.precomposedStringWithCanonicalMapping
        value = value.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(
            of: #"(?i)\b(\#(versionWords.joined(separator: "|")))\b.*$"#,
            with: " ",
            options: .regularExpression
        )
        return cleanSeparators(value)
    }

    static func comparable(_ text: String) -> String {
        cleanSeparators(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func cleanSeparators(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[\-–—_/|]+$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\-–—_/|]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ArtistNormalizer {
    private static let splitPattern = #"(?i)\s*(,|&|\+|/| x | feat\.? | featuring | ft\.? | with )\s*"#

    static func searchArtists(from artist: String) -> [String] {
        let original = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return [] }

        let pieces = original
            .components(separatedBy: try! NSRegularExpression(pattern: splitPattern))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = [original]
        if let main = pieces.first, main != original {
            result.append(main)
        }
        return Array(NSOrderedSet(array: result)) as? [String] ?? result
    }

    static func mainArtist(from artist: String) -> String {
        searchArtists(from: artist).dropFirst().first ?? artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        var parts: [String] = []
        var cursor = startIndex

        regex.enumerateMatches(in: self, range: range) { match, _, _ in
            guard let matchRange = match?.range,
                  let swiftRange = Range(matchRange, in: self) else { return }
            parts.append(String(self[cursor..<swiftRange.lowerBound]))
            cursor = swiftRange.upperBound
        }

        parts.append(String(self[cursor..<endIndex]))
        return parts
    }
}
