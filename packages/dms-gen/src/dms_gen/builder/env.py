"""Isolate pydcs from the local DCS installation.

pydcs looks up the DCS install and Saved Games folders through the Windows registry the first
time it needs liveries or unit payloads. On a machine with both Stable and OpenBeta it can pick
the wrong profile, and the result depends on whatever is installed. That makes generated
missions non-reproducible (for example, the AH-64D "default CAS" loadout came from the local
payload Lua files and was four fuel tanks).

``configure_dcs_environment()`` replaces the two lazy lookups with explicit values:

* Livery cache: empty by default, so every unit gets ``livery_id = ""``, which DCS treats as
  the default livery. If ``saved_games_dir`` or ``install_dir`` is given, only those paths are
  scanned.
* Payload directories: empty by default, so ``FlyingType.loadout()`` finds nothing and our own
  explicit loadouts (``dms_gen.builder.payloads``) are the only source. If ``install_dir`` or
  ``saved_games_dir`` is given, their ``UnitPayloads`` folders are used and named DCS payloads
  can be loaded by name.

It runs automatically (with no paths) the first time a ``MissionBuilder`` is created. Call it
explicitly before that to opt in to real paths. Environment variables ``DMS_DCS_INSTALL`` and
``DMS_DCS_SAVED_GAMES`` are honoured as defaults.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import os
from pathlib import Path

from dcs.liveries.liverycache import LiveryCache
from dcs.liveries.liveryscanner import LiveryScanner
from dcs.payloads import PayloadDirectories
from dcs.unittype import FlyingType

_configured = False


def configure_dcs_environment(
    install_dir: str | os.PathLike[str] | None = None,
    saved_games_dir: str | os.PathLike[str] | None = None,
) -> None:
    """Pin pydcs livery and payload lookups to explicit paths (or none). Idempotent per args."""
    global _configured
    install = Path(install_dir) if install_dir else _env_path("DMS_DCS_INSTALL")
    saved = Path(saved_games_dir) if saved_games_dir else _env_path("DMS_DCS_SAVED_GAMES")

    # Liveries
    if install is None and saved is None:
        LiveryCache._cache = {}
    else:
        scanner = LiveryScanner()
        if install is not None:
            scanner.scan_dcs_installation(str(install))
        if saved is not None:
            scanner.scan_custom_liveries(str(saved))
        LiveryCache._cache = scanner.map

    # Payloads
    dcs_dirs: list[Path] = []
    mod_dirs: list[Path] = []
    if install is not None:
        dcs_dirs.append(install / "MissionEditor" / "data" / "scripts" / "UnitPayloads")
        aircraft_dir = install / "CoreMods" / "aircraft"
        if aircraft_dir.exists():
            dcs_dirs.extend(p / "UnitPayloads" for p in aircraft_dir.iterdir())
    if saved is not None:
        mods = saved / "Mods" / "Aircraft"
        if mods.exists():
            mod_dirs.extend(p / "UnitPayloads" for p in mods.iterdir())
    PayloadDirectories._dcs = dcs_dirs
    PayloadDirectories._mod = mod_dirs
    PayloadDirectories._user = (
        saved / "MissionEditor" / "UnitPayloads"
        if saved is not None
        else Path(os.devnull) / "no-user-payloads"
    )
    # Drop anything cached by an earlier scan.
    FlyingType._payload_cache = None
    _reset_payload_class_cache()
    _configured = True


def ensure_configured() -> None:
    if not _configured:
        configure_dcs_environment()


def _env_path(name: str) -> Path | None:
    val = os.environ.get(name)
    return Path(val) if val else None


def _reset_payload_class_cache() -> None:
    from dcs import helicopters, planes

    for mapping in (planes.plane_map, helicopters.helicopter_map):
        for cls in mapping.values():
            if "payloads" in cls.__dict__:
                cls.payloads = None
