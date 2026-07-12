import Foundation

struct LRCLIBTrack: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
    let instrumental: Bool?
}

enum LRCLIBError: LocalizedError {
    case missingURL
    case requestFailed(Int)
    case noLyrics
    case decodingFailed
    case networkFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "LRCLIB 검색 URL을 만들 수 없습니다."
        case .requestFailed(let statusCode):
            return "LRCLIB 요청 실패: HTTP \(statusCode)"
        case .noLyrics:
            return "가사를 찾지 못했습니다."
        case .decodingFailed:
            return "LRCLIB 응답을 해석할 수 없습니다."
        case .networkFailed(let message):
            return "네트워크 오류: \(message)"
        }
    }
}

final class LRCLIBService {
    private let session: URLSession
    private var responseCache: [String: [LRCLIBTrack]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for track: TrackInfo) async throws -> LyricsResult {
        var candidates: [LRCLIBTrack] = []
        var seenIDs = Set<Int>()

        for plan in searchPlans(for: track) {
            try Task.checkCancellation()
            let tracks = try await request(plan)
            for candidate in tracks where !seenIDs.contains(candidate.id) {
                seenIDs.insert(candidate.id)
                candidates.append(candidate)
            }

            if let bestSynced = LyricsMatcher.bestCandidate(from: candidates, for: track, allowPlainLyrics: false),
               bestSynced.syncedLyrics?.isEmpty == false {
                return makeResult(from: bestSynced, for: track)
            }
        }

        guard let best = LyricsMatcher.bestCandidate(from: candidates, for: track, allowPlainLyrics: true) else {
            throw LRCLIBError.noLyrics
        }

        return makeResult(from: best, for: track)
    }

    private func makeResult(from lrclibTrack: LRCLIBTrack, for track: TrackInfo) -> LyricsResult {
        LyricsResult(
            track: track,
            lrclibID: lrclibTrack.id,
            lrclibTrackName: lrclibTrack.trackName,
            lrclibArtistName: lrclibTrack.artistName,
            lrclibAlbumName: lrclibTrack.albumName,
            lrclibDuration: lrclibTrack.duration,
            syncedLyrics: lrclibTrack.syncedLyrics,
            plainLyrics: lrclibTrack.plainLyrics,
            source: .lrclib,
            savedAt: Date()
        )
    }

    private func searchPlans(for track: TrackInfo) -> [LRCLIBSearchPlan] {
        let normalizedTitle = TrackTitleNormalizer.normalizedTitle(track.title)
        let artists = ArtistNormalizer.searchArtists(from: track.artist)
        let mainArtist = artists.dropFirst().first ?? track.artist

        return [
            .exact(trackName: track.title, artistName: track.artist, albumName: track.album, duration: track.duration),
            .exact(trackName: track.title, artistName: track.artist, albumName: nil, duration: track.duration),
            .search(trackName: track.title, artistName: track.artist, albumName: track.album),
            .search(trackName: normalizedTitle, artistName: track.artist, albumName: nil),
            .search(trackName: normalizedTitle, artistName: mainArtist, albumName: nil),
            .search(trackName: track.title, artistName: nil, albumName: nil)
        ].deduplicated()
    }

    private func request(_ plan: LRCLIBSearchPlan) async throws -> [LRCLIBTrack] {
        let cacheKey = plan.cacheKey
        if let cached = responseCache[cacheKey] {
            return cached
        }

        guard let url = plan.url else {
            throw LRCLIBError.missingURL
        }

        var request = URLRequest(url: url)
        request.setValue("LyricBar/1.0 (https://lrclib.net)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LRCLIBError.networkFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LRCLIBError.networkFailed("잘못된 HTTP 응답입니다.")
        }

        if httpResponse.statusCode == 404 {
            responseCache[cacheKey] = []
            return []
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LRCLIBError.requestFailed(httpResponse.statusCode)
        }

        do {
            let tracks = try plan.kind == .exact
                ? [JSONDecoder().decode(LRCLIBTrack.self, from: data)]
                : JSONDecoder().decode([LRCLIBTrack].self, from: data)
            responseCache[cacheKey] = tracks
            return tracks
        } catch {
            throw LRCLIBError.decodingFailed
        }
    }
}

private enum LRCLIBPlanKind {
    case exact
    case search
}

private struct LRCLIBSearchPlan: Hashable {
    let kind: LRCLIBPlanKind
    let trackName: String
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?

    static func exact(trackName: String, artistName: String, albumName: String?, duration: TimeInterval) -> Self {
        Self(kind: .exact, trackName: trackName, artistName: artistName, albumName: albumName, duration: duration)
    }

    static func search(trackName: String, artistName: String?, albumName: String?) -> Self {
        Self(kind: .search, trackName: trackName, artistName: artistName, albumName: albumName, duration: nil)
    }

    var cacheKey: String {
        [kind == .exact ? "exact" : "search", trackName, artistName ?? "", albumName ?? "", duration.map { String(Int($0.rounded())) } ?? ""]
            .map { TrackTitleNormalizer.comparable($0) }
            .joined(separator: "|")
    }

    var url: URL? {
        var components = URLComponents(string: kind == .exact ? "https://lrclib.net/api/get" : "https://lrclib.net/api/search")
        components?.queryItems = queryItems
        return components?.url
    }

    private var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "track_name", value: trackName)]
        if let artistName, !artistName.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artistName))
        }
        if let albumName, !albumName.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: albumName))
        }
        if kind == .exact, let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        return items
    }
}

private extension Array where Element == LRCLIBSearchPlan {
    func deduplicated() -> [LRCLIBSearchPlan] {
        var seen = Set<String>()
        return filter { seen.insert($0.cacheKey).inserted }
    }
}
