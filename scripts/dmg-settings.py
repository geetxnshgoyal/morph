# dmgbuild layout for Morph.dmg; scripts/bundle.sh --dmg passes the paths in as defines.
# Icon positions are icon centres and must match the bubbles in make-dmg-background.swift.

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["volume_icon"]
background = defines["background"]

format = "UDZO"
compression_level = 9

# 640×420 content area; the window bounds include the title bar.
window_rect = ((200, 140), (640, 448))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {
    "Morph.app": (170, 220),
    "Applications": (470, 220),
}
hide_extensions = ["Morph.app"]
