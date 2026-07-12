import Foundation

struct LyricsCandidateScore {
    let track: LRCLIBTrack
    let score: Double
}

enum LyricsMatcher {
    static func bestCandidate(from tracks: [LRCLIBTrack], for track: TrackInfo, allowPlainLyrics: Bool) -> LRCLIBTrack? {
        tracks
            .compactMap { scoredCandidate($0, for: track, allowPlainLyrics: allowPlainLyrics) }
            .sorted { $0.score > $1.score }
            .first?
            .track
    }

    static func scoredCandidate(_ candidate: LRCLIBTrack, for track: TrackInfo, allowPlainLyrics: Bool) -> LyricsCandidateScore? {
        let hasSynced = candidate.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasPlain = candidate.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasSynced || (allowPlainLyrics && hasPlain) else { return nil }

        let titleScore = textScore(candidate.trackName, track.title)
        let normalizedTitleScore = textScore(
            TrackTitleNormalizer.normalizedTitle(candidate.trackName),
            TrackTitleNormalizer.normalizedTitle(track.title)
        )
        let artistScore = textScore(candidate.artistName, track.artist)
        let mainArtistScore = textScore(candidate.artistName, ArtistNormalizer.mainArtist(from: track.artist))

        if let duration = candidate.duration, track.duration > 0, abs(duration - track.duration) > 12 {
            return nil
        }

        if max(titleScore, normalizedTitleScore) < 0.35 && max(artistScore, mainArtistScore) < 0.35 {
            return nil
        }

        var score = 0.0

        // Synced lyrics are the MVP's best result. Plain lyrics are kept as a fallback only.
        score += hasSynced ? 1000 : 100
        score += titleScore * 240
        score += normalizedTitleScore * 220
        score += artistScore * 160
        score += mainArtistScore * 120

        if let albumName = candidate.albumName, !albumName.isEmpty, !track.album.isEmpty {
            score += textScore(albumName, track.album) * 70
        }

        if let duration = candidate.duration, track.duration > 0 {
            score += max(0, 80 - abs(duration - track.duration) * 8)
        }

        if candidate.instrumental == true {
            score -= hasSynced ? 40 : 160
        }

        if !hasSynced && !allowPlainLyrics {
            score -= 500
        }

        return LyricsCandidateScore(track: candidate, score: score)
    }

    private static func textScore(_ lhs: String, _ rhs: String) -> Double {
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
