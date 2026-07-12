# LyricBar

LyricBar is a macOS Apple Music lyric display app for the Touch Bar and the main app window.

## Features

- Reads the current Apple Music track and playback position through Apple Events.
- Fetches synchronized lyrics from LRCLIB, with an unofficial NetEase LRC fallback.
- Supports user-imported `.lrc` files.
- Shows the current lyric line in the main window and Touch Bar.
- Stores per-track lyric sync offsets so timing can be nudged earlier or later.

## Requirements

- macOS 15.0 or later.
- Apple Music.

## Distribution Notes

This build is suitable for local or Developer ID distribution. It is not App Store friendly because it intentionally uses private Touch Bar APIs for Control Strip behavior and an unofficial lyric fallback source.

The target keeps Hardened Runtime enabled, disables App Sandbox for Apple Music automation reliability, and includes Apple Events plus network client entitlements.

## Install From DMG

Open `LyricBar-1.0.dmg`, then drag `LyricBar.app` onto the `Applications` folder shortcut in the DMG window. Launch LyricBar from `/Applications`.

For unsigned build verification:

```sh
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar -configuration Release CODE_SIGNING_ALLOWED=NO build
```

For an installable release build, sign with a Developer ID Application certificate and notarize the exported app.
