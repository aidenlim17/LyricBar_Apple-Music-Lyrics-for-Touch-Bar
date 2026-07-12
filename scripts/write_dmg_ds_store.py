#!/usr/bin/env python3
import os
import sys

TOOLS_PATH = "/private/tmp/lyricbar_dmg_tools"
if os.path.isdir(TOOLS_PATH):
    sys.path.insert(0, TOOLS_PATH)

from ds_store import DSStore, DSStoreEntry
from ds_store.store import BookmarkCodec, ILocCodec, PlistCodec
from mac_alias import Bookmark


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: write_dmg_ds_store.py <mounted-volume>", file=sys.stderr)
        return 64

    volume = sys.argv[1]
    ds_store_path = os.path.join(volume, ".DS_Store")
    background_path = os.path.join(volume, ".background", "background.png")

    bwsp = {
        "ContainerShowSidebar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "WindowBounds": "{{120, 120}, {660, 420}}",
    }

    icvp = {
        "arrangeBy": "none",
        "backgroundColorBlue": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorRed": 1.0,
        "backgroundType": 2,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": 96.0,
        "labelOnBottom": True,
        "showIconPreview": True,
        "showItemInfo": False,
        "textSize": 13.0,
        "viewOptionsVersion": 1,
    }

    with DSStore.open(ds_store_path, "w+") as store:
        store.insert(DSStoreEntry(".", "bwsp", PlistCodec, bwsp))
        store.insert(DSStoreEntry(".", "icvp", PlistCodec, icvp))
        store.insert(DSStoreEntry(".", "pBBk", BookmarkCodec, Bookmark.for_file(background_path)))
        store.insert(DSStoreEntry("LyricBar.app", "Iloc", ILocCodec, (180, 224)))
        store.insert(DSStoreEntry("Applications", "Iloc", ILocCodec, (484, 224)))
        store.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
