on run argv
    set mountPath to item 1 of argv
    set mountedFolder to POSIX file mountPath as alias

    tell application "Finder"
        open mountedFolder
        delay 1

        set dmgWindow to container window of mountedFolder
        set current view of dmgWindow to icon view
        try
            set toolbar visible of dmgWindow to false
        end try
        try
            set statusbar visible of dmgWindow to false
        end try
        try
            set bounds of dmgWindow to {120, 120, 780, 540}
        end try

        set viewOptions to icon view options of dmgWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set backgroundImage to POSIX file (mountPath & "/.background/background.png") as alias
        try
            set background picture of viewOptions to backgroundImage
        end try

        try
            set position of item "LyricBar.app" of mountedFolder to {180, 224}
        end try
        try
            set position of item "Applications" of mountedFolder to {484, 224}
        end try

        try
            update mountedFolder
        end try
        delay 3
        close dmgWindow
        delay 2
    end tell
end run
