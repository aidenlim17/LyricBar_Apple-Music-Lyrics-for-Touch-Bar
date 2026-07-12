import Foundation

enum NetEaseLRCError: LocalizedError {
    case missingURL
    case requestFailed(Int)
    case decodingFailed
    case noLyrics
    case networkFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "NetEase LRC 검색 URL을 만들 수 없습니다."
        case .requestFailed(let statusCode):
            return "NetEase LRC 요청 실패: HTTP \(statusCode)"
        case .decodingFailed:
            return "NetEase LRC 응답을 해석할 수 없습니다."
        case .noLyrics:
            return "NetEase에서 동기화 가사를 찾지 못했습니다."
        case .networkFailed(let message):
            return "NetEase 네트워크 오류: \(message)"
        }
    }
}

final class NetEaseLRCService {
    private let session: URLSession
    private var searchCache: [String: [NetEaseSong]] = [:]
    private var lyricCache: [Int: String] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for track: TrackInfo) async throws -> LyricsResult {
        var candidates: [NetEaseSong] = []
        var seenIDs = Set<Int>()

        for query in searchQueries(for: track) {
            try Task.checkCancellation()
            let songs = try await search(query)
            for song in songs where seenIDs.insert(song.id).inserted {
                candidates.append(song)
            }
        }

        let scored = candidates
            .compactMap { scoredCandidate($0, for: track) }
            .sorted { $0.score > $1.score }

        for candidate in scored {
            try Task.checkCancellation()
            let lrc = try await lyric(for: candidate.song.id)
            guard !SyncedLyricsParser.parse(lrc).isEmpty else { continue }
            return makeResult(from: candidate.song, lrc: lrc, for: track)
        }

        throw NetEaseLRCError.noLyrics
    }

    private func makeResult(from song: NetEaseSong, lrc: String, for track: TrackInfo) -> LyricsResult {
        LyricsResult(
            track: track,
            lrclibID: song.id,
            lrclibTrackName: song.displayTitle,
            lrclibArtistName: song.displayArtist,
            lrclibAlbumName: song.al?.name,
            lrclibDuration: song.durationSeconds,
            syncedLyrics: lrc,
            plainLyrics: nil,
            source: .netease,
            savedAt: Date()
        )
    }

    private func searchQueries(for track: TrackInfo) -> [String] {
        [
            [track.artist, track.title].filter { !$0.isEmpty }.joined(separator: " "),
            [ArtistNormalizer.mainArtist(from: track.artist), TrackTitleNormalizer.normalizedTitle(track.title)]
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            track.title,
            TrackTitleNormalizer.normalizedTitle(track.title)
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .deduplicated()
    }

    private func search(_ query: String) async throws -> [NetEaseSong] {
        let cacheKey = TrackTitleNormalizer.comparable(query)
        if let cached = searchCache[cacheKey] {
            return cached
        }

        var components = URLComponents(string: "https://music.163.com/api/cloudsearch/pc")
        components?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components?.url else {
            throw NetEaseLRCError.missingURL
        }

        let response = try await request(url, as: NetEaseSearchResponse.self)
        let songs = response.result?.songs ?? []
        searchCache[cacheKey] = songs
        return songs
    }

    private func lyric(for id: Int) async throws -> String {
        if let cached = lyricCache[id] {
            return cached
        }

        var components = URLComponents(string: "https://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1")
        ]

        guard let url = components?.url else {
            throw NetEaseLRCError.missingURL
        }

        let response = try await request(url, as: NetEaseLyricResponse.self)
        let lrc = response.lrc?.lyric.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !lrc.isEmpty else {
            throw NetEaseLRCError.noLyrics
        }

        lyricCache[id] = lrc
        return lrc
    }

    private func request<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 LyricBar/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NetEaseLRCError.networkFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetEaseLRCError.networkFailed("잘못된 HTTP 응답입니다.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetEaseLRCError.requestFailed(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetEaseLRCError.decodingFailed
        }
    }

    private func scoredCandidate(_ song: NetEaseSong, for track: TrackInfo) -> NetEaseScoredSong? {
        let titleScore = max(
            textScore(song.displayTitle, track.title),
            song.alternativeTitles.map { textScore($0, track.title) }.max() ?? 0
        )
        let normalizedTitleScore = max(
            textScore(TrackTitleNormalizer.normalizedTitle(song.displayTitle), TrackTitleNormalizer.normalizedTitle(track.title)),
            song.alternativeTitles.map {
                textScore(TrackTitleNormalizer.normalizedTitle($0), TrackTitleNormalizer.normalizedTitle(track.title))
            }.max() ?? 0
        )
        let artistScore = max(
            textScore(song.displayArtist, track.artist),
            textScore(song.displayArtist, ArtistNormalizer.mainArtist(from: track.artist))
        )

        if let duration = song.durationSeconds, track.duration > 0, abs(duration - track.duration) > 18 {
            return nil
        }

        if max(titleScore, normalizedTitleScore) < 0.28 && artistScore < 0.25 {
            return nil
        }

        var score = 1000.0
        score += titleScore * 260
        score += normalizedTitleScore * 240
        score += artistScore * 190

        if let duration = song.durationSeconds, track.duration > 0 {
            score += max(0, 120 - abs(duration - track.duration) * 8)
        }

        return NetEaseScoredSong(song: song, score: score)
    }

    private func textScore(_ lhs: String, _ rhs: String) -> Double {
        let left = TrackTitleNormalizer.comparable(lhs)
        let right = TrackTitleNormalizer.comparable(rhs)

        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        if left.contains(right) || right.contains(left) { return 0.82 }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }

        let intersection = leftTokens.intersection(rightTokens).count
        let union = leftTokens.union(rightTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}

private struct NetEaseScoredSong {
    let song: NetEaseSong
    let score: Double
}

private struct NetEaseSearchResponse: Decodable {
    let result: NetEaseSearchResult?
}

private struct NetEaseSearchResult: Decodable {
    let songs: [NetEaseSong]?
}

private struct NetEaseSong: Decodable {
    let id: Int
    let name: String
    let tns: [String]?
    let alia: [String]?
    let ar: [NetEaseArtist]?
    let al: NetEaseAlbum?
    let dt: Double?

    var displayTitle: String {
        name
    }

    var alternativeTitles: [String] {
        (tns ?? []) + (alia ?? [])
    }

    var displayArtist: String {
        ar?.map(\.name).joined(separator: " ") ?? ""
    }

    var durationSeconds: Double? {
        guard let dt else { return nil }
        return dt / 1000
    }
}

private struct NetEaseArtist: Decodable {
    let name: String
}

private struct NetEaseAlbum: Decodable {
    let name: String
}

private struct NetEaseLyricResponse: Decodable {
    let lrc: NetEaseLyric?
}

private struct NetEaseLyric: Decodable {
    let lyric: String
}

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert(TrackTitleNormalizer.comparable($0)).inserted }
    }
}
