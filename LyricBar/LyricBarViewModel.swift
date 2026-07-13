import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LyricBarViewModel: ObservableObject {
    @Published private(set) var trackTitle = "LyricBar"
    @Published private(set) var artistText = ""
    @Published private(set) var albumText = "Apple Music에서 음악을 재생하세요."
    @Published private(set) var playbackText = "대기 중"
    @Published private(set) var timeText = "0:00 / 0:00"
    @Published private(set) var previousLyric = ""
    @Published private(set) var currentLyric = "대기 중"
    @Published private(set) var nextLyric = ""
    @Published private(set) var statusText = LyricsState.idle.label
    @Published private(set) var detailText = ""
    @Published private(set) var sourceText = ""
    @Published private(set) var selectedLRCLIBText = ""
    @Published private(set) var appleMusicDebugText = ""
    @Published private(set) var appleMusicAutomationDebugText = ""
    @Published private(set) var updateStatusText = ""
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var pendingUpdate: UpdateInfo?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var canImportLRC = false
    @Published private(set) var canDeleteUserLyrics = false
    @Published private(set) var canAdjustLyricSync = false
    @Published private(set) var lyricSyncOffsetText = "+0.0s"
    @Published private(set) var currentTrackInfo: TrackInfo?
    @Published var showsDebugInfo = false
    @Published var isTouchBarLyricsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTouchBarLyricsEnabled, forKey: Self.touchBarLyricsEnabledKey)
        }
    }
    @Published var touchBarFontWeight: TouchBarLyricFontWeight {
        didSet {
            UserDefaults.standard.set(touchBarFontWeight.rawValue, forKey: Self.touchBarFontWeightKey)
        }
    }

    private let appleMusicService: AppleMusicService
    private let lrclibService: LRCLIBService
    private let netEaseLRCService: NetEaseLRCService
    private let updateService: UpdateService
    private let cache: LyricsCache
    private var pollingTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var isRefreshInFlight = false
    private var hasStartedFirstFetch = false
    private var currentTrack: TrackInfo?
    private var loadedTrackKey: TrackKey?
    private var lyricLines: [LyricLine] = []
    private var plainLyrics: String?
    private var activeResult: LyricsResult?
    private var latestPlaybackPosition: TimeInterval?
    private var currentLyricSyncOffset: TimeInterval = 0
    private var lyricSyncOffsets: [String: TimeInterval]
    private static let touchBarLyricsEnabledKey = "touchBarLyricsEnabled"
    private static let touchBarFontWeightKey = "touchBarFontWeight"
    private static let lyricSyncOffsetsKey = "lyricSyncOffsetsByTrack"
    private static let lyricSyncStep: TimeInterval = 0.2
    private static let lyricSyncOffsetLimit: TimeInterval = 10

    init(
        appleMusicService: AppleMusicService? = nil,
        lrclibService: LRCLIBService? = nil,
        netEaseLRCService: NetEaseLRCService? = nil,
        updateService: UpdateService? = nil,
        cache: LyricsCache? = nil
    ) {
        self.appleMusicService = appleMusicService ?? AppleMusicService()
        self.lrclibService = lrclibService ?? LRCLIBService()
        self.netEaseLRCService = netEaseLRCService ?? NetEaseLRCService()
        self.updateService = updateService ?? UpdateService()
        self.cache = cache ?? LyricsCache()
        self.lyricSyncOffsets = Self.loadLyricSyncOffsets()
        self.touchBarFontWeight = Self.loadTouchBarFontWeight()
        if UserDefaults.standard.object(forKey: Self.touchBarLyricsEnabledKey) == nil {
            self.isTouchBarLyricsEnabled = true
        } else {
            self.isTouchBarLyricsEnabled = UserDefaults.standard.bool(forKey: Self.touchBarLyricsEnabledKey)
        }
        updateLyricSyncOffsetText()
        debugLog("init ViewModel id=\(objectIdentifierText)")
    }

    func start() {
        debugLog("start 호출 ViewModel id=\(objectIdentifierText)")
        guard pollingTimer == nil else {
            debugLog("start 무시: Timer 이미 생성됨 ViewModel id=\(objectIdentifierText)")
            return
        }

        Task { @MainActor [weak self] in
            await self?.refresh()
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.debugLog("Timer tick ViewModel id=\(self.objectIdentifierText)")
                await self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
        debugLog("Timer 생성 및 RunLoop 등록 ViewModel id=\(objectIdentifierText)")
    }

    func stop() {
        debugLog("stop 호출 ViewModel id=\(objectIdentifierText)")
        pollingTimer?.invalidate()
        pollingTimer = nil
        searchTask?.cancel()
        searchTask = nil
    }

    func importLRCFile() {
        guard let currentTrack else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let lrc = try String(contentsOf: url, encoding: .utf8)
            let result = try cache.saveUserLyrics(lrc, for: currentTrack)
            apply(result, at: nil)
        } catch {
            setState(.parsingError(error.localizedDescription))
        }
    }

    func deleteUserLyrics() {
        guard let currentTrack else { return }
        cache.deleteUserLyrics(for: currentTrack)
        clearLyrics()
        startRemoteSearch(for: currentTrack, ignoringCache: true)
    }

    func retrySearch() {
        guard let currentTrack else { return }
        cache.deleteAutomaticLyrics(for: currentTrack)
        clearLyrics()
        startRemoteSearch(for: currentTrack, ignoringCache: true)
    }

    func nudgeLyricSyncEarlier() {
        adjustLyricSync(by: Self.lyricSyncStep)
    }

    func nudgeLyricSyncLater() {
        adjustLyricSync(by: -Self.lyricSyncStep)
    }

    func resetLyricSyncOffset() {
        guard let currentTrack else { return }
        currentLyricSyncOffset = 0
        lyricSyncOffsets.removeValue(forKey: currentTrack.key.value)
        saveLyricSyncOffsets()
        updateLyricSyncOffsetText()
        refreshCurrentLyricAfterSyncChange()
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        updateStatusText = "업데이트 확인 중..."
        pendingUpdate = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await updateService.checkForUpdates(currentVersion: appVersion)
                await MainActor.run {
                    self.apply(updateCheckResult: result)
                }
            } catch {
                await MainActor.run {
                    self.isCheckingForUpdates = false
                    self.updateStatusText = error.localizedDescription
                }
            }
        }
    }

    func openPendingUpdate() {
        guard let pendingUpdate else { return }
        NSWorkspace.shared.open(pendingUpdate.downloadURL)
    }

    private func refresh() async {
        guard !isRefreshInFlight else {
            debugLog("fetch 건너뜀: 이전 fetch 진행 중 ViewModel id=\(objectIdentifierText)")
            return
        }

        isRefreshInFlight = true
        defer {
            isRefreshInFlight = false
        }

        if !hasStartedFirstFetch {
            hasStartedFirstFetch = true
            showCheckingState()
        }

        debugLog("fetch 시작 ViewModel id=\(objectIdentifierText)")
        do {
            let snapshot = try await appleMusicService.currentPlayback()
            debugLog("fetch 완료 snapshot=\(snapshot.debugSummary) ViewModel id=\(objectIdentifierText)")
            updateAppleMusicDebugText()
            updateTrackDisplay(with: snapshot)

            guard snapshot.hasTrack else {
                searchTask?.cancel()
                resetLyrics()
                return
            }

            let track = snapshot.trackInfo
            latestPlaybackPosition = snapshot.position
            currentTrack = track
            currentTrackInfo = track
            if loadedTrackKey != track.key {
                loadTrack(track)
            }

            updateCurrentLyric(at: snapshot.position)
        } catch let error as AppleMusicError {
            debugLog("fetch 오류 \(error.debugDescription) ViewModel id=\(objectIdentifierText)")
            updateAppleMusicDebugText(error: error.debugDescription)
            handleAppleMusicError(error)
        } catch {
            debugLog("fetch 오류 \(error.localizedDescription) ViewModel id=\(objectIdentifierText)")
            setState(.appleMusicPermissionError(error.localizedDescription))
            updateAppleMusicDebugText(error: error.localizedDescription)
            trackTitle = "Apple Music 권한 필요"
            artistText = ""
            albumText = "시스템 설정에서 LyricBar의 자동화 권한을 허용하세요."
            currentLyric = "Apple Music을 읽을 수 없습니다."
            progress = 0
        }
    }

    private func showCheckingState() {
        trackTitle = "LyricBar"
        artistText = ""
        albumText = "Apple Music 상태를 확인하고 있습니다."
        playbackText = "확인 중"
        timeText = "0:00 / 0:00"
        currentLyric = "Apple Music 확인 중..."
        statusText = "Apple Music 확인 중"
        detailText = ""
        progress = 0
    }

    private func handleAppleMusicError(_ error: AppleMusicError) {
        artistText = ""
        progress = 0

        switch error {
        case .automationPermissionDenied:
            setState(.appleMusicPermissionError(error.localizedDescription))
            trackTitle = "Apple Music 권한 필요"
            albumText = "시스템 설정에서 LyricBar의 자동화 권한을 허용하세요."
            currentLyric = "Apple Music을 읽을 수 없습니다."
        case .applicationNotRunning:
            setState(.musicAppNotRunning)
            trackTitle = "Apple Music이 실행 중이 아닙니다"
            albumText = "Music 앱을 열고 곡을 재생하세요."
            playbackText = "미실행"
            currentLyric = "Apple Music을 실행하세요"
        case .noCurrentTrack:
            setState(.noTrack)
            trackTitle = "재생 중인 곡 없음"
            albumText = error.localizedDescription
            playbackText = "정지됨"
            currentLyric = "재생 중인 곡 없음"
        case .scriptError, .invalidResponse:
            setState(.appleMusicPermissionError(error.localizedDescription))
            trackTitle = "Apple Music을 읽을 수 없습니다"
            albumText = error.localizedDescription
            currentLyric = "Apple Music을 읽을 수 없습니다."
        }
    }

    private func loadTrack(_ track: TrackInfo) {
        searchTask?.cancel()
        loadedTrackKey = track.key
        loadLyricSyncOffset(for: track)
        clearLyrics()

        if let cached = cache.load(for: track) {
            apply(cached, at: nil)
            return
        }

        startRemoteSearch(for: track, ignoringCache: false)
    }

    private func startRemoteSearch(for track: TrackInfo, ignoringCache: Bool) {
        searchTask?.cancel()
        setState(.loading)
        isLoadingLyrics = true
        canImportLRC = false
        canAdjustLyricSync = false

        let key = track.key
        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                if !ignoringCache, let cached = self.cache.load(for: track) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard self.loadedTrackKey == key else { return }
                        self.apply(cached, at: nil)
                    }
                    return
                }

                let result = try await self.fetchLyrics(for: track)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.loadedTrackKey == key else { return }
                    try? self.cache.save(result)
                    self.apply(result, at: nil)
                }
            } catch is CancellationError {
                return
            } catch let error as LRCLIBError {
                await MainActor.run {
                    guard self.loadedTrackKey == key else { return }
                    self.handleLRCLIBError(error)
                }
            } catch let error as NetEaseLRCError {
                await MainActor.run {
                    guard self.loadedTrackKey == key else { return }
                    self.handleNetEaseLRCError(error)
                }
            } catch {
                await MainActor.run {
                    guard self.loadedTrackKey == key else { return }
                    self.setState(.networkError(error.localizedDescription))
                    self.currentLyric = "가사를 불러오지 못했습니다."
                    self.isLoadingLyrics = false
                    self.canImportLRC = true
                }
            }
        }
    }

    private func fetchLyrics(for track: TrackInfo) async throws -> LyricsResult {
        do {
            let result = try await lrclibService.fetchLyrics(for: track)
            if result.hasSyncedLyrics {
                return result
            }

            do {
                return try await netEaseLRCService.fetchLyrics(for: track)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return result
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                return try await netEaseLRCService.fetchLyrics(for: track)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw error
            }
        }
    }

    private func apply(_ result: LyricsResult, at position: TimeInterval?) {
        activeResult = result
        lyricLines = result.parsedLines
        plainLyrics = result.plainLyrics
        isLoadingLyrics = false
        canImportLRC = true
        canDeleteUserLyrics = result.source == .user
        canAdjustLyricSync = !lyricLines.isEmpty
        sourceText = sourceLabel(for: result.source)
        selectedLRCLIBText = selectedTrackDebugText(from: result)

        if result.source == .user {
            setState(.localLyrics)
        } else if result.hasSyncedLyrics {
            setState(.syncedLyrics)
        } else if result.hasPlainLyrics {
            setState(.plainLyrics)
        } else {
            setState(.noLyrics)
        }

        if let position {
            updateCurrentLyric(at: position)
        } else if !lyricLines.isEmpty {
            previousLyric = ""
            currentLyric = lyricLines.first?.text ?? "..."
            nextLyric = lyricLines.dropFirst().first?.text ?? ""
        } else if let plainLyrics {
            previousLyric = ""
            currentLyric = plainLyrics
            nextLyric = ""
        }
    }

    private func handleLRCLIBError(_ error: LRCLIBError) {
        switch error {
        case .networkFailed, .requestFailed:
            setState(.networkError(error.localizedDescription))
        case .decodingFailed:
            setState(.parsingError(error.localizedDescription))
        default:
            setState(.noLyrics)
        }
        currentLyric = error.localizedDescription
        isLoadingLyrics = false
        canImportLRC = true
        canAdjustLyricSync = false
    }

    private func handleNetEaseLRCError(_ error: NetEaseLRCError) {
        switch error {
        case .networkFailed, .requestFailed:
            setState(.networkError(error.localizedDescription))
        case .decodingFailed:
            setState(.parsingError(error.localizedDescription))
        default:
            setState(.noLyrics)
        }
        currentLyric = error.localizedDescription
        isLoadingLyrics = false
        canImportLRC = true
        canAdjustLyricSync = false
    }

    private func updateTrackDisplay(with snapshot: PlaybackSnapshot) {
        switch snapshot.state {
        case .notRunning:
            trackTitle = "Apple Music이 실행 중이 아닙니다"
            artistText = ""
            albumText = "Music 앱을 열고 곡을 재생하세요."
            playbackText = "미실행"
            timeText = "0:00 / 0:00"
            currentLyric = "Apple Music을 실행하세요"
            progress = 0
            setState(.musicAppNotRunning)
            detailText = ""
            currentTrackInfo = nil
        case .stopped:
            trackTitle = "재생 중인 곡 없음"
            artistText = ""
            albumText = "Apple Music에서 곡을 선택하세요."
            playbackText = "정지됨"
            timeText = "0:00 / 0:00"
            currentLyric = "재생 중인 곡 없음"
            progress = 0
            setState(.noTrack)
            currentTrackInfo = nil
        default:
            trackTitle = snapshot.title
            artistText = snapshot.artist
            albumText = snapshot.album
            playbackText = snapshot.state == .playing ? "재생 중" : "일시정지"
            timeText = "\(formatTime(snapshot.position)) / \(formatTime(snapshot.duration))"
            progress = snapshot.duration > 0 ? min(max(snapshot.position / snapshot.duration, 0), 1) : 0
        }
    }

    private func updateCurrentLyric(at position: TimeInterval) {
        guard !lyricLines.isEmpty else {
            if let plainLyrics {
                currentLyric = plainLyrics
                previousLyric = ""
                nextLyric = ""
            }
            return
        }

        let adjustedPosition = max(0, position + currentLyricSyncOffset)

        guard let index = SyncedLyricsParser.currentLineIndex(in: lyricLines, at: adjustedPosition) else {
            previousLyric = ""
            currentLyric = "..."
            nextLyric = lyricLines.first?.text ?? ""
            return
        }

        previousLyric = index > 0 ? lyricLines[index - 1].text : ""
        currentLyric = lyricLines[index].text
        nextLyric = index + 1 < lyricLines.count ? lyricLines[index + 1].text : ""
    }

    private func setState(_ state: LyricsState) {
        statusText = state.label
        detailText = state.message == state.label ? "" : state.message
    }

    private func updateAppleMusicDebugText(error: String? = nil) {
        let fetchText = appleMusicService.didCallFetchSnapshot ? "fetchSnapshot 호출됨" : "fetchSnapshot 미호출"
        appleMusicAutomationDebugText = [
            "ViewModel: \(objectIdentifierText)",
            "마지막 폴링: \(appleMusicService.lastPollingText)",
            fetchText
        ].joined(separator: " / ")
        appleMusicDebugText = error ?? ""
    }

    private func resetLyrics() {
        loadedTrackKey = nil
        currentTrack = nil
        currentTrackInfo = nil
        latestPlaybackPosition = nil
        currentLyricSyncOffset = 0
        updateLyricSyncOffsetText()
        clearLyrics()
        canImportLRC = false
    }

    private func clearLyrics() {
        lyricLines = []
        plainLyrics = nil
        activeResult = nil
        previousLyric = ""
        currentLyric = "가사 검색 중..."
        nextLyric = ""
        sourceText = ""
        selectedLRCLIBText = ""
        canDeleteUserLyrics = false
        canAdjustLyricSync = false
    }

    private func adjustLyricSync(by delta: TimeInterval) {
        guard let currentTrack else { return }
        let adjusted = currentLyricSyncOffset + delta
        currentLyricSyncOffset = min(max(adjusted, -Self.lyricSyncOffsetLimit), Self.lyricSyncOffsetLimit)

        if abs(currentLyricSyncOffset) < 0.01 {
            lyricSyncOffsets.removeValue(forKey: currentTrack.key.value)
            currentLyricSyncOffset = 0
        } else {
            lyricSyncOffsets[currentTrack.key.value] = currentLyricSyncOffset
        }

        saveLyricSyncOffsets()
        updateLyricSyncOffsetText()
        refreshCurrentLyricAfterSyncChange()
    }

    private func loadLyricSyncOffset(for track: TrackInfo) {
        currentLyricSyncOffset = lyricSyncOffsets[track.key.value] ?? 0
        updateLyricSyncOffsetText()
    }

    private func refreshCurrentLyricAfterSyncChange() {
        guard let latestPlaybackPosition, !lyricLines.isEmpty else { return }
        updateCurrentLyric(at: latestPlaybackPosition)
    }

    private func updateLyricSyncOffsetText() {
        lyricSyncOffsetText = String(format: "%+.1fs", currentLyricSyncOffset)
    }

    private func apply(updateCheckResult result: UpdateCheckResult) {
        isCheckingForUpdates = false

        switch result {
        case .upToDate(let currentVersion):
            pendingUpdate = nil
            updateStatusText = "최신 버전입니다. \(currentVersion)"
        case .updateAvailable(let update):
            pendingUpdate = update
            updateStatusText = "새 버전 \(update.latestVersion)을 사용할 수 있습니다."
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func saveLyricSyncOffsets() {
        UserDefaults.standard.set(lyricSyncOffsets, forKey: Self.lyricSyncOffsetsKey)
    }

    private static func loadLyricSyncOffsets() -> [String: TimeInterval] {
        guard let stored = UserDefaults.standard.dictionary(forKey: lyricSyncOffsetsKey) else {
            return [:]
        }

        return stored.reduce(into: [String: TimeInterval]()) { partialResult, element in
            if let value = element.value as? TimeInterval {
                partialResult[element.key] = value
            } else if let number = element.value as? NSNumber {
                partialResult[element.key] = number.doubleValue
            }
        }
    }

    private static func loadTouchBarFontWeight() -> TouchBarLyricFontWeight {
        guard let rawValue = UserDefaults.standard.string(forKey: touchBarFontWeightKey),
              let weight = TouchBarLyricFontWeight(rawValue: rawValue) else {
            return .light
        }
        return weight
    }

    private func selectedTrackDebugText(from result: LyricsResult) -> String {
        guard result.source == .lrclib || result.source == .netease else { return "" }
        return [
            sourceLabel(for: result.source),
            result.lrclibTrackName,
            result.lrclibArtistName,
            result.lrclibAlbumName,
            result.lrclibDuration.map { formatTime($0) }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
    }

    private func sourceLabel(for source: LyricsSource) -> String {
        switch source {
        case .lrclib:
            return "LRCLIB"
        case .netease:
            return "NetEase LRC"
        case .user:
            return "사용자 LRC"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private var objectIdentifierText: String {
        String(describing: ObjectIdentifier(self))
    }

    var debugIdentifier: String {
        objectIdentifierText
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LyricBarVerboseLogging") else { return }
        NSLog("[LyricBar ViewModel] %@", message)
        #endif
    }
}
