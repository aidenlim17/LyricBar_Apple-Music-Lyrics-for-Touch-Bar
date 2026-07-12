import AppKit

extension NSTouchBar.CustomizationIdentifier {
    static let lyricBar = NSTouchBar.CustomizationIdentifier("com.aiden.LyricBar.touchBar")
}

extension NSTouchBarItem.Identifier {
    static let lyricBarCurrent = NSTouchBarItem.Identifier("com.aiden.LyricBar.touchBar.current")
    static let lyricBarSystemTray = NSTouchBarItem.Identifier("com.aiden.LyricBar.touchBar.systemTray")
}
