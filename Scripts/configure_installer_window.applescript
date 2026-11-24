on run argv
    set mountPath to item 1 of argv
    set mountedVolume to POSIX file mountPath as alias
    tell application "Finder"
        activate
        open mountedVolume
        set installerWindow to front Finder window
        if (POSIX path of (target of installerWindow as alias)) is not (mountPath & "/") then error "Wrong installer window"
        tell installerWindow
            set bounds to {120, 100, 780, 580}
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            tell its icon view options
                set arrangement to not arranged
                set icon size to 128
                set text size to 13
                set background picture to (POSIX file (mountPath & "/.background/background.png") as alias)
            end tell
            set position of item "mimiTrends-iOS.app" of installerWindow to {170, 190}
            set position of item "Applications" of installerWindow to {490, 190}
        end tell
        update mountedVolume without registering applications
        close installerWindow
    end tell
end run
