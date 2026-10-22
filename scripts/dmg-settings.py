# dmgbuild settings for the release DMG. scripts/release.sh passes:
#   -D app=<path to TobyShot.app> -D background=<path to background.png>
# dmgbuild combines background.png with the background@2x.png beside it for
# Retina displays. Keep the canvas size and icon centers in sync with
# scripts/dmg-background.swift.
import os.path

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
# Don't hide the .app extension: that writes Finder info onto the bundle,
# which fails strict code signature verification.

background = defines["background"]
# The frame includes Finder's 28-point title bar above the 660 x 400 canvas.
window_rect = ((200, 160), (660, 428))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 14
label_pos = "bottom"
arrange_by = None
icon_locations = {
    os.path.basename(app): (170, 186),
    "Applications": (490, 186),
}

format = "UDZO"
filesystem = "HFS+"
