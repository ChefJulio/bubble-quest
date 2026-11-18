"""Build a release zip locally: .release/BubbleQuest-<version>.zip, holding a BubbleQuest/ folder and one
folder per companion addon beside it (BubbleMap/, and Questmarker/: the stub that hands the old
Questmarker settings over to BubbleQuest, docs/design/bubble-suite.md).

Releases are built by the BigWigs packager on GitHub (.github/workflows/release.yml, on a version tag);
this builds the same zip locally for testing, and checks that the two agree on what ships.

Ships only what the game loads or the licenses require: each TOC and every file it lists, Media/, the
whole bundled LibForeverData folder (its licenses and notice travel with it), LICENSE,
THIRD-PARTY-NOTICES, README.md and CHANGELOG.md. Tools, docs and the hint triage data stay out. Files
come from git (committed content only), so stray local files never ship; uncommitted changes to shipped
files stop the build. Each TOC's @project-version@ is replaced by `git describe` (the packager uses the
tag).

Companions live in repo subfolders and the packager moves them out (.pkgmeta `move-folders`); COMPANIONS
below must list the same folders.

Usage:
  python tools/package.py           build the zip
  python tools/package.py --check   only check that .pkgmeta's ignore list ships the same files
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ADDON = "BubbleQuest"
# Repo subfolders shipped as their own addon folders: Questmarker (the settings hand-off stub) for a few
# releases after the rename. BubbleMap also lives in this repo until the split but ships on its own
# (.pkgmeta ignores it).
COMPANIONS = ["Questmarker"]
ROOT = Path(__file__).resolve().parent.parent
TOC = f"{ADDON}.toc"
EXTRA_FILES = ["LICENSE", "THIRD-PARTY-NOTICES", "README.md", "CHANGELOG.md"]
EXTRA_DIRS = ["Media/", "Libs/LibForeverData/"]
VERSION_TOKEN = "@project-version@"


def git(*args: str) -> str:
  return subprocess.check_output(["git", *args], cwd=ROOT, text=True)


def toc_files(toc_text: str, prefix: str = "") -> list[str]:
  """The files a TOC lists, as repo paths (a companion's are under its folder)."""
  return [prefix + line.strip().replace("\\", "/") for line in toc_text.splitlines()
          if line.strip() and not line.startswith("#")]


def tocs() -> list[str]:
  """Every TOC that ships: BubbleQuest's, then each companion's."""
  return [TOC, *(f"{name}/{name}.toc" for name in COMPANIONS)]


def shipped(tracked: set[str]) -> set[str]:
  ship = {TOC, *toc_files((ROOT / TOC).read_text(encoding="utf-8")), *EXTRA_FILES}
  ship |= {f for f in tracked if any(f.startswith(d) for d in EXTRA_DIRS)}
  for name in COMPANIONS:
    toc = f"{name}/{name}.toc"
    ship |= {toc, *toc_files((ROOT / toc).read_text(encoding="utf-8"), f"{name}/")}
  return ship


def zip_path(f: str) -> str:
  """Where a repo file goes in the zip: a companion's files at the top level, the rest in BubbleQuest/."""
  if any(f.startswith(name + "/") for name in COMPANIONS):
    return f
  return f"{ADDON}/{f}"


def pkgmeta_ignores() -> list[str]:
  """The `ignore:` list of .pkgmeta (a plain YAML list of paths)."""
  ignores, inside = [], False
  for line in (ROOT / ".pkgmeta").read_text(encoding="utf-8").splitlines():
    if re.match(r"^\S", line):
      inside = line.startswith("ignore:")
    elif inside and line.strip().startswith("- "):
      ignores.append(line.strip()[2:].strip().rstrip("/"))
  return ignores


def pkgmeta_moves() -> dict[str, str]:
  """The `move-folders:` map of .pkgmeta (source: destination)."""
  moves, inside = {}, False
  for line in (ROOT / ".pkgmeta").read_text(encoding="utf-8").splitlines():
    if re.match(r"^\S", line):
      inside = line.startswith("move-folders:")
    elif inside and ":" in line and not line.strip().startswith("#"):
      source, dest = (part.strip() for part in line.split(":", 1))
      moves[source] = dest
  return moves


def check(ship: set[str], tracked: set[str]) -> int:
  ignores = pkgmeta_ignores()
  packager = {f for f in tracked if not any(f == p or f.startswith(p + "/") for p in ignores)}
  extra, missing = sorted(packager - ship), sorted(ship - packager)
  expected_moves = {f"{ADDON}/{name}": name for name in COMPANIONS}
  moves = pkgmeta_moves()
  if extra or missing or moves != expected_moves:
    if extra:
      print("package --check: the packager would ship these, package.py wouldn't (add them to .pkgmeta "
            "ignore, or to package.py):\n  " + "\n  ".join(extra))
    if missing:
      print("package --check: package.py ships these, the packager would drop them:\n  "
            + "\n  ".join(missing))
    if moves != expected_moves:
      print(f"package --check: .pkgmeta move-folders {moves} doesn't match COMPANIONS {expected_moves}")
    return 1
  print(f"package --check: OK ({len(ship)} files, {1 + len(COMPANIONS)} addons)")
  return 0


def main() -> int:
  tracked = set(git("ls-files").splitlines())
  missing_tocs = [toc for toc in tocs() if toc not in tracked]
  if missing_tocs:
    print("package: not committed (or missing):\n  " + "\n  ".join(missing_tocs))
    return 1
  ship = shipped(tracked)

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
  toc_set = set(tocs())
  with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for f in sorted(ship):
      # From git, not the working tree: exactly the committed bytes.
      data = subprocess.check_output(["git", "show", f"HEAD:{f}"], cwd=ROOT)
      if f in toc_set:
        data = data.replace(VERSION_TOKEN.encode(), version.encode())
      zf.writestr(zip_path(f), data)
  print(f"package: {out.relative_to(ROOT)} ({len(ship)} files, {1 + len(COMPANIONS)} addons, "
        f"{out.stat().st_size / 1024 / 1024:.1f} MB)")
  return 0


if __name__ == "__main__":
  sys.exit(main())
