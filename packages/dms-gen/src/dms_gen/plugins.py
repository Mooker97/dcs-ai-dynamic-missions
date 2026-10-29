"""Optional pinned Lua plugins (MIST, Skynet-IADS, MOOSE) and the DMS adapters for them.

The DMS core never depends on these (ADR 0003). A mission opts in with ``plugins: [skynet]`` in
mission-spec.yaml; the planner then embeds the pinned files as ``DO SCRIPT FILE`` actions in this
order (docs/CONTRACTS.md "Optional plugins")::

    mist -> moose -> skynet -> dms_config.lua (-> dms_test.lua) -> dms.lua -> adapters

Dependencies are added automatically (``skynet`` pulls in ``mist`` and the Skynet adapter).
Vendored files live in ``lua/plugins/<name>/<version>/``; the pins (URL, tag, sha256) are
recorded here and in ``lua/plugins/PINS.md``. ``dms check`` uses :data:`PLUGINS` to verify
order, dependencies and hashes of embedded plugin files.
"""

from __future__ import annotations

import hashlib
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Plugin:
    """One pinned plugin release (or a DMS adapter when ``adapter`` is True)."""

    name: str
    version: str
    file: str
    """Repo-relative source path (resolved against the repo root like ``dist/dms.lua``)."""
    sha256: str
    """sha256 of the vendored file; empty for DMS-owned adapters (not pinned upstream code)."""
    url: str
    requires: tuple[str, ...] = ()
    adapters: tuple[str, ...] = ()
    adapter: bool = False
    """Adapters load after dms.lua (they use DMS.Log/Clock/Bus) and no-op without their plugin."""
    order: int = 0

    @property
    def basename(self) -> str:
        return Path(self.file).name


PLUGINS: dict[str, Plugin] = {
    "mist": Plugin(
        name="mist",
        version="4.5.126",
        file="lua/plugins/mist/4.5.126/mist_4_5_126.lua",
        sha256="85e78e6cb5d2191b4148241e1a77c4884049b51295508d3d38b20793a0968c39",
        url="https://github.com/mrSkortch/MissionScriptingTools/releases/tag/4.5.126",
        order=10,
    ),
    "moose": Plugin(
        name="moose",
        version="2.9.19",
        file="lua/plugins/moose/2.9.19/Moose_.lua",
        sha256="3873e6d392e69177f0e18ae0a0766a2b64bd3c4ea55d112329f1cbaa82426ecd",
        url="https://github.com/FlightControl-Master/MOOSE/releases/tag/2.9.19",
        order=20,
    ),
    "skynet": Plugin(
        name="skynet",
        version="3.3.0",
        file="lua/plugins/skynet/3.3.0/skynet-iads-compiled.lua",
        sha256="6b95b407f99ddf3933addcf3cfda2288d53519af652ffb90b779c26ba7608ba7",
        url="https://github.com/walder/Skynet-IADS/releases/tag/3.3.0",
        requires=("mist",),
        adapters=("skynet_adapter",),
        order=30,
    ),
    "skynet_adapter": Plugin(
        name="skynet_adapter",
        version="dms",
        file="lua/plugins/adapters/skynet_adapter.lua",
        sha256="",
        url="",
        requires=("skynet",),
        adapter=True,
        order=100,
    ),
}
"""Every known plugin by name. ``order`` is the load order among plugins."""

BY_BASENAME: dict[str, Plugin] = {p.basename: p for p in PLUGINS.values()}
"""Plugin by embedded file name (``l10n/DEFAULT/<basename>``), for ``dms check``."""


def resolve(names: Iterable[str]) -> list[Plugin]:
    """Expand ``names`` with dependencies and adapters; return them in load order.

    Raises ``KeyError`` for an unknown plugin name.
    """
    seen: dict[str, Plugin] = {}

    def add(name: str) -> None:
        if name in seen:
            return
        plug = PLUGINS[name]
        seen[name] = plug
        for dep in plug.requires:
            add(dep)
        for ad in plug.adapters:
            add(ad)

    for n in names:
        if n not in PLUGINS or PLUGINS[n].adapter:
            raise KeyError(f"unknown plugin {n!r} (known: {sorted(user_names())})")
        add(n)
    return sorted(seen.values(), key=lambda p: (p.order, p.name))


def user_names() -> list[str]:
    """Plugin names a mission spec may list (adapters are implicit)."""
    return [n for n, p in PLUGINS.items() if not p.adapter]


def split_files(names: Iterable[str]) -> tuple[list[str], list[str]]:
    """(files loaded before dms_config.lua, adapter files loaded after dms.lua), repo-relative."""
    plugs = resolve(names)
    return [p.file for p in plugs if not p.adapter], [p.file for p in plugs if p.adapter]


def dms_lua_insert_index(resource_paths: Iterable[str]) -> int:
    """Where to insert dms_config.lua + dms.lua in a resource list that has no dms.lua.

    Right after the last non-adapter plugin (or an existing dms_config.lua / dms_test.lua),
    so plugins stay before DMS and adapters after it (see the module docstring); 0 if none.
    """
    idx = 0
    for i, path in enumerate(resource_paths):
        name = Path(path).name
        plug = BY_BASENAME.get(name)
        if (plug is not None and not plug.adapter) or name in ("dms_config.lua", "dms_test.lua"):
            idx = i + 1
    return idx


def file_sha256(data: bytes) -> str:
    """sha256 of a plugin file with line endings normalised to LF (git stores them as LF)."""
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


__all__ = [
    "BY_BASENAME",
    "PLUGINS",
    "Plugin",
    "dms_lua_insert_index",
    "file_sha256",
    "resolve",
    "split_files",
    "user_names",
]
