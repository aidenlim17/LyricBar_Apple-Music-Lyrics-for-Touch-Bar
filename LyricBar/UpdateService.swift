import AppKit
import Foundation

struct UpdateInfo {
    let latestVersion: String
    let downloadURL: URL
}

enum UpdateCheckResult {
    case upToDate(String)
    case updateAvailable(UpdateInfo)
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case noRelease
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "업데이트 정보를 읽을 수 없습니다."
        case .noRelease:
            return "업데이트 정보 파일을 찾을 수 없습니다."
        case .missingDownloadURL:
            return "다운로드 링크를 찾을 수 없습니다."
        }
    }
}

struct UpdateService {
    private let updateManifestURL = URL(string: "https://raw.githubusercontent.com/aidenlim17/LyricBar_Apple-Music-Lyrics-for-Touch-Bar/main/dist/latest.json")!

    func checkForUpdates(currentVersion: String) async throws -> UpdateCheckResult {
        var request = URLRequest(url: updateManifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LyricBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.noRelease
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw UpdateError.invalidResponse
        }

        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        let latestVersion = Self.normalizedVersion(manifest.version)
        let current = Self.normalizedVersion(currentVersion)

        guard Self.isVersion(latestVersion, newerThan: current) else {
            return .upToDate(currentVersion)
        }

        return .updateAvailable(UpdateInfo(latestVersion: latestVersion, downloadURL: manifest.downloadURL))
    }

    private static func normalizedVersion(_ version: String) -> String {
        var normalized = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        return normalized
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }

        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

private struct UpdateManifest: Decodable {
    let version: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case version
        case downloadURL = "download_url"
    }
}
