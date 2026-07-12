import Foundation

enum LyricsSource: String, Codable, Equatable {
    case lrclib
    case netease
    case user
}

struct LyricsResult: Codable, Equatable {
    let track: TrackInfo
    let lrclibID: Int?
    let lrclibTrackName: String?
    let lrclibArtistName: String?
    let lrclibAlbumName: String?
    let lrclibDuration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
    let source: LyricsSource
    let savedAt: Date

    var hasSyncedLyrics: Bool {
        syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasPlainLyrics: Bool {
        plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var parsedLines: [LyricLine] {
        guard let syncedLyrics else { return [] }
        return SyncedLyricsParser.parse(syncedLyrics)
    }
}

enum LyricsState: Equatable {
    case idle
    case musicAppNotRunning
    case noTrack
    case loading
    case syncedLyrics
    case plainLyrics
    case noLyrics
    case networkError(String)
    case parsingError(String)
    case localLyrics
    case appleMusicPermissionError(String)

    var label: String {
        switch self {
        case .idle:
            return "대기 중"
        case .musicAppNotRunning:
            return "Apple Music 미실행"
        case .noTrack:
            return "재생 중인 곡 없음"
        case .loading:
            return "가사 검색 중"
        case .syncedLyrics:
            return "동기화 가사 사용 중"
        case .plainLyrics:
            return "일반 가사 사용 중"
        case .noLyrics:
            return "가사 없음"
        case .networkError:
            return "네트워크 오류"
        case .parsingError:
            return "가사 파싱 오류"
        case .localLyrics:
            return "사용자 LRC 사용 중"
        case .appleMusicPermissionError:
            return "Apple Music 권한 없음"
        }
    }

    var message: String {
        switch self {
        case .networkError(let message), .parsingError(let message), .appleMusicPermissionError(let message):
            return message
        default:
            return label
        }
    }
}
