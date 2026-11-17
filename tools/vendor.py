"""Vendor LibForeverData into Libs/LibForeverData (bundled with BubbleQuest, unmodified).

  python tools/vendor.py            install the release pinned in tools/toolchain.json
  python tools/vendor.py --update   pin the newest lib-v* release, then install it

Downloads the release zip and its SHA256SUMS, refuses to install on a checksum mismatch or an unsafe
zip entry, then replaces Libs/LibForeverData. Requires curl and Python 3.12+.
"""

from __future__ import annotations

import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
TOOLCHAIN = ROOT / "tools" / "toolchain.json"
DEST = ROOT / "Libs" / "LibForeverData"
TAG_PREFIX = "lib-v"


def fetch(url: str) -> bytes:
  # curl uses the OS certificate store (see lint.py).
  return subprocess.run(["curl", "-fsSL", url], check=True, capture_output=True).stdout


def latest_tag(repo: str) -> str:
  releases = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases?per_page=50"))
  tags = [r["tag_name"] for r in releases if r["tag_name"].startswith(TAG_PREFIX) and not r["draft"]]
  if not tags:
    raise SystemExit("vendor: no LibForeverData release found")
  return tags[0]  # the API lists newest first


def install(repo: str, tag: str) -> None:
  version = tag[len(TAG_PREFIX):]
  asset = f"LibForeverData-{version}.zip"
  base = f"https://github.com/{repo}/releases/download/{tag}"
  print(f"vendor: downloading {asset}")
  data = fetch(f"{base}/{asset}")
  sums = fetch(f"{base}/SHA256SUMS").decode("utf-8")

  expected = next((line.split()[0] for line in sums.splitlines() if line.strip().endswith(asset)), None)
  actual = hashlib.sha256(data).hexdigest()
  if expected != actual:
    raise SystemExit(f"vendor: checksum mismatch for {asset}: expected {expected}, got {actual}")

  with zipfile.ZipFile(io.BytesIO(data)) as zf:
    for name in zf.namelist():
      path = PurePosixPath(name)
      if path.is_absolute() or ".." in path.parts or path.parts[0] != "LibForeverData":
        raise SystemExit(f"vendor: refusing unexpected zip entry {name!r}")
    with tempfile.TemporaryDirectory() as tmp:
      zf.extractall(tmp)
      if DEST.exists():
        shutil.rmtree(DEST)
      DEST.parent.mkdir(parents=True, exist_ok=True)
      shutil.move(str(Path(tmp) / "LibForeverData"), DEST)
  files = sorted(p.relative_to(DEST).as_posix() for p in DEST.rglob("*") if p.is_file())
  print(f"vendor: installed {tag} ({len(files)} files) in {DEST.relative_to(ROOT).as_posix()}")


def main() -> int:
  cfg = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))
  lib = cfg["libforeverdata"]
  if "--update" in sys.argv[1:]:
    lib["tag"] = latest_tag(lib["repo"])
    TOOLCHAIN.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    print(f"vendor: pinned {lib['tag']}")
  install(lib["repo"], lib["tag"])
  return 0


if __name__ == "__main__":
  sys.exit(main())
