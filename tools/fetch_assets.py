#!/usr/bin/env python3
"""Download the free (CC0) sky and ground assets the Godot race world can use.

Everything comes from Poly Haven (https://polyhaven.com, CC0: no attribution required) through its
public API, which gives exact file URLs and MD5 sums. Files land in godot/assets/, where
godot/scripts/ui/world_assets.gd picks them up; without them the game uses its procedural look.

    python3 tools/fetch_assets.py                 # full set: 13 skies at 2K, 4 ground materials at 1K
    python3 tools/fetch_assets.py --set minimal   # 4 skies and the asphalt/grass textures (~25 MB)
    python3 tools/fetch_assets.py --sky-res 4k --tex-res 2k
    python3 tools/fetch_assets.py --list          # show what would be downloaded
    python3 tools/fetch_assets.py --dest ~/Library/Application\\ Support/Godot/app_userdata/Seicento\\ 900\\ Cup/assets

See godot/ASSETS.md for what each file is for and for other (manual) downloads.
"""

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

API = "https://api.polyhaven.com/files/"
USER_AGENT = "SeicentoCup-asset-fetch/1.0 (Godot racing game; github.com)"
ROOT = Path(__file__).resolve().parent.parent

# The Qwantani pure-sky time-lapse: one location photographed from dawn to night, so blending
# neighbouring times of day stays seamless. Plus an overcast sky for rain.
SKIES_FULL = [
    "qwantani_dawn_puresky",
    "qwantani_sunrise_puresky",
    "qwantani_morning_puresky",
    "qwantani_mid_morning_puresky",
    "qwantani_noon_puresky",
    "qwantani_afternoon_puresky",
    "qwantani_late_afternoon_puresky",
    "qwantani_sunset_puresky",
    "qwantani_dusk_1_puresky",
    "qwantani_dusk_2_puresky",
    "qwantani_night_puresky",
    "qwantani_moonrise_puresky",
    "kloofendal_overcast_puresky",
]
SKIES_MINIMAL = [
    "qwantani_morning_puresky",
    "qwantani_noon_puresky",
    "qwantani_sunset_puresky",
    "kloofendal_overcast_puresky",
]

# assets/textures/<folder> -> Poly Haven texture id. Folder names are what race_world.gd asks for.
TEXTURES_FULL = {
    "asphalt": "asphalt_track",
    "pit_lane": "asphalt_pit_lane",
    "grass": "sparse_grass",
    "gravel": "gravelly_sand",
}
TEXTURES_MINIMAL = {k: TEXTURES_FULL[k] for k in ("asphalt", "grass")}

# Poly Haven map name -> file suffix; world_assets.gd recognises _diff, _nor_gl and _rough.
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough"}


def api(asset_id):
    req = urllib.request.Request(API + asset_id, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def download(url, md5, dest, dry):
    if dest.exists() and hashlib.md5(dest.read_bytes()).hexdigest() == md5:
        print(f"  ok       {dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest}")
        return 0
    if dry:
        print(f"  would get {url}")
        return 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if hashlib.md5(data).hexdigest() != md5:
        raise RuntimeError(f"checksum mismatch for {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    tmp.write_bytes(data)
    tmp.replace(dest)
    print(f"  fetched  {dest.name}  ({len(data) / 1e6:.1f} MB)")
    return len(data)


def pick(files, res):
    """The requested resolution, or the nearest smaller one the asset has."""
    order = ["8k", "4k", "2k", "1k"]
    for r in order[order.index(res):]:
        if r in files:
            return files[r]
    raise KeyError(res)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", choices=["full", "minimal"], default="full")
    ap.add_argument("--sky-res", choices=["1k", "2k", "4k"], default="2k",
                    help="HDRI size (2k: ~5 MB and ~8 MB of video memory each)")
    ap.add_argument("--tex-res", choices=["1k", "2k", "4k"], default="1k")
    ap.add_argument("--dest", type=Path, default=ROOT / "godot" / "assets")
    ap.add_argument("--no-sky", action="store_true")
    ap.add_argument("--no-textures", action="store_true")
    ap.add_argument("--list", action="store_true", help="only show what would be downloaded")
    args = ap.parse_args()

    skies = SKIES_MINIMAL if args.set == "minimal" else SKIES_FULL
    textures = TEXTURES_MINIMAL if args.set == "minimal" else TEXTURES_FULL
    total = 0
    failed = []

    if not args.no_sky:
        print(f"Skies ({args.sky_res}) -> {args.dest / 'sky'}")
        for sid in skies:
            try:
                f = pick(api(sid)["hdri"], args.sky_res)["hdr"]
                total += download(f["url"], f["md5"], args.dest / "sky" / Path(f["url"]).name, args.list)
            except Exception as e:  # keep going; report at the end
                failed.append(f"{sid}: {e}")
                print(f"  FAILED   {sid}: {e}")

    if not args.no_textures:
        print(f"Ground textures ({args.tex_res}) -> {args.dest / 'textures'}")
        for folder, tid in textures.items():
            try:
                files = api(tid)
                for key in MAPS:
                    f = pick(files[key], args.tex_res)["jpg"]
                    total += download(f["url"], f["md5"], args.dest / "textures" / folder / Path(f["url"]).name, args.list)
            except Exception as e:
                failed.append(f"{tid}: {e}")
                print(f"  FAILED   {tid}: {e}")

    print(f"\nDownloaded {total / 1e6:.1f} MB. Assets from Poly Haven, CC0 (https://polyhaven.com/license).")
    if failed:
        print("Some downloads failed:\n  " + "\n  ".join(failed))
        return 1
    print("Run the game (or reopen the Godot editor) to use them. Delete the folders to go back to the procedural look.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
