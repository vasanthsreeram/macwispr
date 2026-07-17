# dmgbuild settings — used by scripts/build-dmg.sh
# Docs: https://dmgbuild.readthedocs.io/
# Note: dmgbuild exec()s this file without __file__ — use env vars only.

import os

# Injected by build-dmg.sh via environment
_version = os.environ.get("MACWISPR_VERSION", "1.2.4-beta.1")
_app = os.environ.get("MACWISPR_DMG_APP", "dist/MacWispr.app")
_bg = os.environ.get("MACWISPR_DMG_BG", "scripts/dmg-assets/background.png")

format = "UDZO"
files = [_app]
symlinks = {"Applications": "/Applications"}

# Clean drag canvas: App + Applications only (no extra files staged)
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

# Window size matches generate_background.py (720x440 content)
window_rect = ((200, 120), (720, 440))
default_view = "icon-view"
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    "MacWispr.app": (180, 190),
    "Applications": (540, 190),
}

background = _bg
include_icon_view_settings = True
include_list_view_settings = False
