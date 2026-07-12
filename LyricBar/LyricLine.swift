import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum SyncedLyricsParser {
    private static let linePattern = /^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$/

    static func parse(_ lrc: String) -> [LyricLine] {
        lrc
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> LyricLine? in
                let line = String(rawLine)
                guard let match = line.wholeMatch(of: linePattern),
                      let minutes = TimeInterval(match.1),
                      let seconds = TimeInterval(match.2) else {
                    return nil
                }

                let fractionText = match.3.map(String.init) ?? "0"
                let fraction = TimeInterval(fractionText) ?? 0
                let divisor = pow(10, TimeInterval(fractionText.count))
                let text = String(match.4).trimmingCharacters(in: .whitespacesAndNewlines)

                return LyricLine(time: minutes * 60 + seconds + fraction / divisor, text: text)
            }
            .filter { !$0.text.isEmpty }
            .sorted { $0.time < $1.time }
    }

    static func currentLine(in lines: [LyricLine], at position: TimeInterval) -> LyricLine? {
        guard let index = currentLineIndex(in: lines, at: position) else { return nil }
        return lines[index]
    }

    static func currentLineIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }

        var low = 0
        var high = lines.count - 1
        var result: Int?

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result
    }
}
