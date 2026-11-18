from pathlib import Path

app = Path(defines["app"]).resolve()
files = [(str(app), "VoiceShot.app")]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["VoiceShot.app"]

window_rect = ((160, 160), (520, 240))
default_view = "icon-view"
show_sidebar = False
show_toolbar = False
icon_size = 96
text_size = 14
icon_locations = {"VoiceShot.app": (130, 106), "Applications": (390, 106)}
