# Documentation tools

`python3 tools/project_index.py` refreshes the file index; add `--check` to validate
index freshness and Markdown links.

`fvm flutter test tools/ui_gallery.dart --no-pub --timeout 5m` regenerates the UI
gallery using production widgets in this demo and local test adapters. It loads
Roboto from the selected Flutter SDK cache. CJK/Thai language-list fallbacks use
macOS system fonts, or paths from `GALLERY_CJK_FONT` and `GALLERY_THAI_FONT` on
other systems. Fonts are not copied into the repository. Captures contain sample
account data, blank camera regions, and a bundled sample video's still frame.
