import Foundation

enum LyricsCacheError: LocalizedError {
    case invalidUserLyrics

    var errorDescription: String? {
        switch self {
        case .invalidUserLyrics:
            return "유효한 LRC 시간 태그가 없습니다."
        }
    }
}

final class LyricsCache {
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        directoryURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LyricBar", isDirectory: true)

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(for track: TrackInfo) -> LyricsResult? {
        let url = cacheURL(for: track)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LyricsResult.self, from: data)
    }

    func save(_ result: LyricsResult) throws {
        let data = try encoder.encode(result)
        try data.write(to: cacheURL(for: result.track), options: .atomic)
    }

    func saveUserLyrics(_ lrc: String, for track: TrackInfo) throws -> LyricsResult {
        let parsed = SyncedLyricsParser.parse(lrc)
        guard !parsed.isEmpty else {
            throw LyricsCacheError.invalidUserLyrics
        }

        let result = LyricsResult(
            track: track,
            lrclibID: nil,
            lrclibTrackName: nil,
            lrclibArtistName: nil,
            lrclibAlbumName: nil,
            lrclibDuration: nil,
            syncedLyrics: lrc,
            plainLyrics: nil,
            source: .user,
            savedAt: Date()
        )
        try save(result)
        return result
    }

    func deleteUserLyrics(for track: TrackInfo) {
        guard load(for: track)?.source == .user else { return }
        try? FileManager.default.removeItem(at: cacheURL(for: track))
    }

    func deleteAutomaticLyrics(for track: TrackInfo) {
        guard load(for: track)?.source != .user else { return }
        try? FileManager.default.removeItem(at: cacheURL(for: track))
    }

    func cacheURL(for track: TrackInfo) -> URL {
        directoryURL.appendingPathComponent(track.key.filename).appendingPathExtension("json")
    }
}
