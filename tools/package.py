"""Build a release zip locally: .release/Questmarker-<version>.zip, holding a Questmarker/ folder.

Releases are built by the BigWigs packager on GitHub (.github/workflows/release.yml, on a version tag);
this builds the same zip locally for testing, and checks that the two agree on what ships.

Ships only what the game loads or the licenses require: the TOC, every file it lists, Media/, the whole
bundled LibForeverData folder (its licenses and notice travel with it), LICENSE, THIRD-PARTY-NOTICES,
README.md and CHANGELOG.md. Tools, docs and the hint triage data stay out. Files come from git
(committed content only), so stray local files never ship; uncommitted changes to shipped files stop
the build. The TOC's @project-version@ is replaced by `git describe` (the packager uses the tag).

Usage:
  python tools/package.py           build the zip
  python tools/package.py --check   only check that .pkgmeta's ignore list ships the same files
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ADDON = "Questmarker"
ROOT = Path(__file__).resolve().parent.parent
TOC = f"{ADDON}.toc"
EXTRA_FILES = ["LICENSE", "THIRD-PARTY-NOTICES", "README.md", "CHANGELOG.md"]
EXTRA_DIRS = ["Media/", "Libs/LibForeverData/"]
VERSION_TOKEN = "@project-version@"


def git(*args: str) -> str:
  return subprocess.check_output(["git", *args], cwd=ROOT, text=True)


def shipped(toc_text: str, tracked: set[str]) -> set[str]:
  listed = [line.strip().replace("\\", "/") for line in toc_text.splitlines()
            if line.strip() and not line.startswith("#")]
  ship = {TOC, *listed, *EXTRA_FILES}
  ship |= {f for f in tracked if any(f.startswith(d) for d in EXTRA_DIRS)}
  return ship


def pkgmeta_ignores() -> list[str]:
  """The `ignore:` list of .pkgmeta (a plain YAML list of paths)."""
  ignores, inside = [], False
  for line in (ROOT / ".pkgmeta").read_text(encoding="utf-8").splitlines():
    if re.match(r"^\S", line):
      inside = line.startswith("ignore:")
    elif inside and line.strip().startswith("- "):
      ignores.append(line.strip()[2:].strip().rstrip("/"))
  return ignores


def check(ship: set[str], tracked: set[str]) -> int:
  ignores = pkgmeta_ignores()
  packager = {f for f in tracked if not any(f == p or f.startswith(p + "/") for p in ignores)}
  extra, missing = sorted(packager - ship), sorted(ship - packager)
  if extra or missing:
    if extra:
      print("package --check: the packager would ship these, package.py wouldn't (add them to .pkgmeta "
            "ignore, or to package.py):\n  " + "\n  ".join(extra))
    if missing:
      print("package --check: package.py ships these, the packager would drop them:\n  "
            + "\n  ".join(missing))
    return 1
  print(f"package --check: OK ({len(ship)} files)")
  return 0


def main() -> int:
  toc_text = (ROOT / TOC).read_text(encoding="utf-8")
  tracked = set(git("ls-files").splitlines())
  ship = shipped(toc_text, tracked)

  missing = sorted(f for f in ship if f not in tracked)
  if missing:
    print("package: not committed (or missing):\n  " + "\n  ".join(missing))
    return 1
  if "--check" in sys.argv[1:]:
    return check(ship, tracked)

  dirty = [f for f in git("status", "--porcelain", "--", *sorted(ship)).splitlines() if f]
  if dirty:
    print("package: uncommitted changes to shipped files:\n  " + "\n  ".join(dirty))
    return 1

  version = git("describe", "--tags", "--always").strip()
  out = ROOT / ".release" / f"{ADDON}-{version}.zip"
  out.parent.mkdir(exist_ok=True)
  with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for f in sorted(ship):
      # From git, not the working tree: exactly the committed bytes.
      data = subprocess.check_output(["git", "show", f"HEAD:{f}"], cwd=ROOT)
      if f == TOC:
        data = data.replace(VERSION_TOKEN.encode(), version.encode())
      zf.writestr(f"{ADDON}/{f}", data)
  print(f"package: {out.relative_to(ROOT)} ({len(ship)} files, {out.stat().st_size / 1024 / 1024:.1f} MB)")
  return 0


if __name__ == "__main__":
  sys.exit(main())
