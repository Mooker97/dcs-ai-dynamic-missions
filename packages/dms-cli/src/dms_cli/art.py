"""``dms art``: set a mission's briefing pictures.

The builder embeds ``briefing.png``/``.jpg`` then ``briefing-2``, ``briefing-3``, ... from the
mission folder as the DCS briefing pictures (see CONTRACTS "Briefing pictures"). This module
copies images into those names in the order given. Pictures it replaces are moved to
``out/replaced-art/`` (not committed), never deleted.
"""

from __future__ import annotations

import dataclasses
import re
import shutil
import time
from pathlib import Path

from .util import CliError

# Accepted source suffix -> suffix written in the mission folder.
IMAGE_EXTS = {".png": ".png", ".jpg": ".jpg", ".jpeg": ".jpg"}
_ART_NAME = re.compile(r"^briefing(?:-(\d+))?\.(?:png|jpg)$", re.IGNORECASE)
REPLACED_DIR = Path("out") / "replaced-art"


@dataclasses.dataclass(frozen=True)
class ArtChange:
    copied: list[tuple[Path, Path]]  # (source image, destination in the mission folder)
    moved: list[tuple[Path, Path]]  # (old picture, where it was moved)


def art_name(index: int, ext: str) -> str:
    """``briefing.png`` for 1, ``briefing-N.png`` after that."""
    return f"briefing{ext}" if index == 1 else f"briefing-{index}{ext}"


def _art_files(mdir: Path) -> list[tuple[int, Path]]:
    found = []
    for p in mdir.iterdir() if mdir.is_dir() else []:
        m = _ART_NAME.match(p.name)
        if m and p.is_file():
            found.append((int(m.group(1) or 1), p))
    return sorted(found, key=lambda ip: (ip[0], ip[1].name.lower()))


def current_art(mdir: Path) -> list[Path]:
    """The pictures the builder will embed, in display order."""
    from dms_gen.builder.docs import briefing_pictures

    return briefing_pictures(mdir)


def set_art(
    mdir: Path, images: list[Path], *, append: bool = False, dry_run: bool = False
) -> ArtChange:
    """Copy ``images`` in as the briefing pictures (replacing the current set unless ``append``)."""
    srcs: list[tuple[Path, str]] = []
    for img in images:
        p = img.expanduser().resolve()
        if not p.is_file():
            raise CliError(f"not found: {img}")
        ext = IMAGE_EXTS.get(p.suffix.lower())
        if ext is None:
            raise CliError(f"{img}: briefing pictures must be .png or .jpg")
        srcs.append((p, ext))
    if not srcs:
        raise CliError("no images given")

    existing = _art_files(mdir)
    start = (max(i for i, _ in existing) + 1 if existing else 1) if append else 1
    copied = [(src, mdir / art_name(start + n, ext)) for n, (src, ext) in enumerate(srcs)]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    trash = mdir / REPLACED_DIR / stamp
    moved = [] if append else [(p, trash / p.name) for _, p in existing]
    if dry_run:
        return ArtChange(copied, moved)

    # Read every source first: a source may be one of the pictures about to be moved.
    blobs = [src.read_bytes() for src, _ in copied]
    for old, dst in moved:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(old), str(dst))
    for (_, dst), blob in zip(copied, blobs, strict=True):
        dst.write_bytes(blob)
    return ArtChange(copied, moved)
