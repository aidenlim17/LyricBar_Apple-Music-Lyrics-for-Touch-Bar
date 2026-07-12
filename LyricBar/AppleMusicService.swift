import AppKit
import Foundation

struct PlaybackSnapshot: Equatable {
    enum State: String {
        case playing
        case paused
        case stopped
        case notRunning
        case unknown
    }

    let state: State
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let persistentID: String

    var trackKey: String {
        trackInfo.key.value
    }

    var hasTrack: Bool {
        !title.isEmpty && state != .notRunning && state != .stopped
    }
}

enum AppleMusicError: LocalizedError {
    case automationPermissionDenied(number: Int, message: String)
    case applicationNotRunning(number: Int, message: String)
    case noCurrentTrack(number: Int?, message: String)
    case scriptError(number: Int?, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Apple Music 자동화 권한이 거부되었습니다."
        case .applicationNotRunning:
            return "Apple Music이 실행 중이 아닙니다."
        case .noCurrentTrack(_, let message), .scriptError(_, let message):
            return message
        case .invalidResponse:
            return "Apple Music 응답을 읽을 수 없습니다."
        }
    }

    var debugDescription: String {
        switch self {
        case .automationPermissionDenied(let number, let message),
             .applicationNotRunning(let number, let message):
            return "AppleScript error \(number): \(message)"
        case .noCurrentTrack(let number, let message):
            return "AppleScript no current track \(number.map(String.init) ?? "unknown"): \(message)"
        case .scriptError(let number, let message):
            return "AppleScript error \(number.map(String.init) ?? "unknown"): \(message)"
        case .invalidResponse:
            return "AppleScript response did not contain the expected 7 items."
        }
    }
}

final class AppleMusicService {
    private static let musicBundleIdentifier = "com.apple.Music"

    private(set) var lastPollingText = "아직 없음"
    private(set) var didCallFetchSnapshot = false

    private let scriptRunner = AppleMusicScriptRunner()

    func currentPlayback() async throws -> PlaybackSnapshot {
        debugLog("currentPlayback 시작")
        guard isMusicRunning else {
            debugLog("Music 실행 여부: false")
            return notRunningSnapshot
        }

        debugLog("Music 실행 여부: true, fetchSnapshot 호출")
        didCallFetchSnapshot = true
        lastPollingText = Self.format(Date())
        let snapshot = try await scriptRunner.fetchSnapshot()
        debugLog("currentPlayback 완료: \(snapshot.debugSummary)")
        return snapshot
    }

    private var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == Self.musicBundleIdentifier
        }
    }

    private var notRunningSnapshot: PlaybackSnapshot {
        PlaybackSnapshot(
            state: .notRunning,
            title: "",
            artist: "",
            album: "",
            duration: 0,
            position: 0,
            persistentID: ""
        )
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LyricBarVerboseLogging") else { return }
        NSLog("[LyricBar AppleMusicService] %@", message)
        #endif
    }
}

private actor AppleMusicScriptRunner {
    private let script = NSAppleScript(source: """
    on safeText(v)
        if v is missing value then return ""
        return v as text
    end safeText

    tell application id "com.apple.Music"
        set playbackState to player state as text

        if playbackState is "stopped" then
            return {"stopped", "", "", "", 0, 0, ""}
        end if

        set currentTrack to current track
        set trackName to my safeText(name of currentTrack)
        set artistName to my safeText(artist of currentTrack)
        set albumName to my safeText(album of currentTrack)
        set trackDuration to duration of currentTrack as real
        set trackPosition to player position as real
        set trackPersistentID to my safeText(persistent ID of currentTrack)

        return {playbackState, trackName, artistName, albumName, trackDuration, trackPosition, trackPersistentID}
    end tell
    """)

    func fetchSnapshot() throws -> PlaybackSnapshot {
        debugLog("fetchSnapshot 시작")
        var errorInfo: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&errorInfo) else {
            let error = makeScriptError(from: errorInfo)
            debugLog("fetchSnapshot 오류: \(error.debugDescription)")
            throw error
        }

        guard descriptor.numberOfItems == 7 else {
            debugLog("fetchSnapshot 오류: invalid response itemCount=\(descriptor.numberOfItems)")
            throw AppleMusicError.invalidResponse
        }

        let state = PlaybackSnapshot.State(rawValue: descriptor.string(at: 1)) ?? .unknown
        let title = descriptor.string(at: 2)
        let artist = descriptor.string(at: 3)
        let album = descriptor.string(at: 4)
        let duration = descriptor.double(at: 5)
        let position = descriptor.double(at: 6)
        let persistentID = descriptor.string(at: 7)

        if state != .stopped && title.isEmpty {
            let error = AppleMusicError.noCurrentTrack(number: nil, message: "Apple Music에서 현재 재생 곡을 찾을 수 없습니다.")
            debugLog("fetchSnapshot 오류: \(error.debugDescription)")
            throw error
        }

        let snapshot = PlaybackSnapshot(
            state: state,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            persistentID: persistentID
        )
        debugLog("fetchSnapshot 완료: \(snapshot.debugSummary)")
        return snapshot
    }

    private func makeScriptError(from errorInfo: NSDictionary?) -> AppleMusicError {
        let message = errorInfo?[NSAppleScript.errorMessage] as? String
            ?? "Apple Music AppleScript 실행에 실패했습니다."
        let number = errorInfo?[NSAppleScript.errorNumber] as? Int

        switch number {
        case -1743:
            return .automationPermissionDenied(number: -1743, message: message)
        case -600:
            return .applicationNotRunning(number: -600, message: message)
        case -1728 where message.localizedCaseInsensitiveContains("current track"):
            return .noCurrentTrack(number: -1728, message: message)
        default:
            return .scriptError(number: number, message: message)
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LyricBarVerboseLogging") else { return }
        NSLog("[LyricBar AppleMusicScriptRunner] %@", message)
        #endif
    }
}

extension PlaybackSnapshot {
    nonisolated var debugSummary: String {
        "state=\(state.rawValue), title=\(title), artist=\(artist), position=\(position), duration=\(duration)"
    }
}

private extension NSAppleEventDescriptor {
    nonisolated func string(at index: Int) -> String {
        atIndex(index)?.stringValue ?? ""
    }

    nonisolated func double(at index: Int) -> Double {
        atIndex(index)?.doubleValue ?? 0
    }
}
