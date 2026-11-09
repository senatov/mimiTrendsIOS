on run argv
    set volumeName to item 1 of argv
    set mountedVolume to POSIX file ("/Volumes/" & volumeName) as alias
    tell application "Finder"
        activate
        set installerWindow to make new Finder window
        set target of installerWindow to mountedVolume
        delay 1
        tell installerWindow
            set bounds to {120, 100, 1120, 740}
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            tell its icon view options
                set arrangement to not arranged
                set icon size to 96
                set text size to 13
            end tell
            set position of item "mimiTrends-iOS.app" of installerWindow to {750, 185}
            set position of item "How to Install.app" of installerWindow to {500, 185}
            set position of item "Applications" of installerWindow to {250, 185}
        end tell
    end tell
end run
