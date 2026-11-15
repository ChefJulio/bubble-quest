"""Build the release zip for upload: .release/Questmarker-<version>.zip, holding a Questmarker/ folder.

Ships only what the game loads or the licenses require: the TOC, every file it lists, Media/, the whole
bundled LibForeverData folder (its licenses and notice travel with it), LICENSE, THIRD-PARTY-NOTICES and
README.md. Tools, docs and the hint triage data stay out. Files come from git (committed content only),
so stray local files never ship; uncommitted changes to shipped files stop the build.

Usage: python tools/package.py
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ADDON = "Questmarker"
ROOT = Path(__file__).resolve().parent.parent
TOC = f"{ADDON}.toc"
EXTRA_FILES = ["LICENSE", "THIRD-PARTY-NOTICES", "README.md"]
EXTRA_DIRS = ["Media/", "Libs/LibForeverData/"]


def git(*args: str) -> str:
  return subprocess.check_output(["git", *args], cwd=ROOT, text=True)


def main() -> int:
  toc_text = (ROOT / TOC).read_text(encoding="utf-8")
  version = re.search(r"^## Version:\s*(\S+)", toc_text, re.M)
  if not version:
    print(f"package: no '## Version:' in {TOC}")
    return 1

  listed = [line.strip().replace("\\", "/") for line in toc_text.splitlines()
            if line.strip() and not line.startswith("#")]
  tracked = set(git("ls-files").splitlines())

  ship = {TOC, *listed, *EXTRA_FILES}
  ship |= {f for f in tracked if any(f.startswith(d) for d in EXTRA_DIRS)}

  missing = sorted(f for f in ship if f not in tracked)
  if missing:
    print("package: not committed (or missing):\n  " + "\n  ".join(missing))
    return 1
  dirty = [f for f in git("status", "--porcelain", "--", *sorted(ship)).splitlines() if f]
  if dirty:
    print("package: uncommitted changes to shipped files:\n  " + "\n  ".join(dirty))
    return 1

  out = ROOT / ".release" / f"{ADDON}-{version.group(1)}.zip"
  out.parent.mkdir(exist_ok=True)
  with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for f in sorted(ship):
      # From git, not the working tree: exactly the committed bytes.
      data = subprocess.check_output(["git", "show", f"HEAD:{f}"], cwd=ROOT)
      zf.writestr(f"{ADDON}/{f}", data)
  print(f"package: {out.relative_to(ROOT)} ({len(ship)} files, {out.stat().st_size / 1024 / 1024:.1f} MB)")
  return 0


if __name__ == "__main__":
  sys.exit(main())
