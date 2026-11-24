"""Fetch the explicitly named UI test PNGs from an xcresult bundle."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
from tempfile import TemporaryDirectory

SCENES = ("weigh", "history", "rig", "share", "reweigh")
SHOT = re.compile(r"(?:store-en-\d{2}-[a-z]+|paid-01-paywall)")
EXPECTED = {f"store-en-{i:02d}-{s}" for i, s in enumerate(SCENES, 1)} | {"paid-01-paywall"}


def export_named(folder, output):
    manifest = folder / "manifest.json"
    if manifest.is_file():
        for group in json.loads(manifest.read_text(encoding="utf-8")):
            for attachment in group.get("attachments", []):
                name = SHOT.search(attachment.get("suggestedHumanReadableName") or "")
                path = folder / Path(attachment.get("exportedFileName") or "").name
                if name and path.is_file() and path.suffix.lower() == ".png":
                    shutil.copyfile(path, output / f"{name.group()}.png")
    for path in folder.glob("**/*.png"):
        if SHOT.fullmatch(path.stem) and not (output / path.name).is_file():
            shutil.copyfile(path, output / path.name)
    return {p.stem for p in output.glob("*.png") if SHOT.fullmatch(p.stem)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresult", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="tandemslide-xcresult-") as temp:
        folder = Path(temp)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path",
                        str(args.xcresult), "--output-path", str(folder)], check=True)
        names = export_named(folder, args.output)
    if missing := EXPECTED - names:
        parser.exit(1, "Missing screenshots: " + ", ".join(sorted(missing)) + "\n")
    print(f"Exported {len(EXPECTED)} named screenshots to {args.output}")


if __name__ == "__main__":
    main()
