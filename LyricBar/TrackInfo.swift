import Foundation

struct TrackInfo: Codable, Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval

    var key: TrackKey {
        TrackKey(track: self)
    }
}

struct TrackKey: Codable, Hashable, CustomStringConvertible {
    let value: String

    init(track: TrackInfo) {
        let parts = [
            Self.canonical(track.title),
            Self.canonical(track.artist),
            Self.canonical(track.album),
            String(Int(track.duration.rounded()))
        ].filter { !$0.isEmpty }

        value = parts.joined(separator: "__")
    }

    var description: String { value }

    var filename: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        return value
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func canonical(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^0-9a-zA-Z가-힣一-龥ぁ-ゔァ-ヴー]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_ "))
            .lowercased()
    }
}

extension PlaybackSnapshot {
    var trackInfo: TrackInfo {
        TrackInfo(title: title, artist: artist, album: album, duration: duration)
    }
}
