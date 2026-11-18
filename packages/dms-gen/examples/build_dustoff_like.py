"""Build a Dustoff-like Syria mission for manual DCS testing.

Usage:
    uv run python packages/dms-gen/examples/build_dustoff_like.py [out.miz]
"""

from __future__ import annotations

import datetime as dt
import sys
import tempfile
from pathlib import Path

from dms_gen.builder import GroundWaypoint, MissionBuilder, UnitSpec

DEFAULT_OUT = Path(
    r"C:\Users\mook\AppData\Local\Temp\claude\C--coding-claude-projects-claude-test-DMS"
    r"\8d082774-cfce-4930-8670-d823956b8b69\scratchpad\gen-out\dustoff-like.miz"
)

DMS_LUA = 'env.info("[DMS] dummy dms.lua loaded")\nDMS = DMS or {}\n'
DMS_CONFIG_LUA = (
    'DMS_CONFIG = { version = 1, seed = 4242, debug = true, missionId = "dustoff-like" }\n'
    'env.info("[DMS] dummy dms_config.lua loaded")\n'
)
# Minimal bytes with an Ogg capture pattern; not playable audio, only for packaging tests.
DUMMY_OGG = b"OggS" + b"\x00" * 60


def write_assets(folder: Path) -> dict[str, Path]:
    folder.mkdir(parents=True, exist_ok=True)
    files = {
        "dms": folder / "dms.lua",
        "config": folder / "dms_config.lua",
        "sound": folder / "convoy_contact.ogg",
    }
    files["dms"].write_text(DMS_LUA, encoding="utf-8")
    files["config"].write_text(DMS_CONFIG_LUA, encoding="utf-8")
    files["sound"].write_bytes(DUMMY_OGG)
    return files


def build(out: Path, assets: Path) -> MissionBuilder:
    files = write_assets(assets)
    b = MissionBuilder("Syria", seed=4242)
    b.set_datetime(dt.datetime(2004, 6, 12, 6, 30))
    b.set_weather("scattered", wind_dir=290, wind_speed_ms=4)
    b.set_briefing(
        sortie="Dustoff (builder test)",
        description="Escort the logistics convoy east from Ramat David through the valley.",
        blue_task="Keep the convoy alive. Expect ambushes along the road.",
        red_task="Ambush the convoy.",
    )

    b.add_player_flight(
        "blue",
        "USA",
        "AH-64D_BLK_II",
        "Ramat David",
        name="Dustoff 1",
        start="cold",
        count=2,
        callsign=("Apache", 1),
        payload="hellfire_rockets",
        frequency_mhz=127.5,
    )

    rd = b.airbase("Ramat David").position
    start = (rd.x - 3000, rd.y + 5000)
    b.add_ground_group(
        "blue",
        "USA",
        "Convoy",
        units=[
            UnitSpec("M1043 HMMWV Armament", 0, 0, 90),
            UnitSpec("M 818", 0, -25, 90),
            UnitSpec("M 818", 0, -50, 90),
            UnitSpec("M 818", 0, -75, 90),
            UnitSpec("M 818", 0, -100, 90),
            UnitSpec("M1043 HMMWV Armament", 0, -125, 90),
        ],
        position=start,
        waypoints=[
            GroundWaypoint(start[0] - 2000, start[1] + 8000, 40, True),
            GroundWaypoint(start[0] - 4000, start[1] + 16000, 40, True),
            GroundWaypoint(start[0] - 6000, start[1] + 24000, 40, True),
            GroundWaypoint(start[0] - 8000, start[1] + 30000, 40, True),
        ],
    )

    ambush = (start[0] - 5000, start[1] + 20000)
    b.add_ground_group(
        "red",
        "Insurgents",
        "Ambush North",
        units=[("BTR-80", 0, 0, 200), ("Ural-375 ZU-23", 40, 30, 200)],
        position=(ambush[0] + 1500, ambush[1]),
        hidden=True,
    )
    b.add_ground_group(
        "red",
        "Insurgents",
        "Ambush South",
        units=[("BMP-2", 0, 0, 20), ("BMP-2", 30, 30, 20), ("ZU-23 Emplacement", -30, 10, 20)],
        position=(ambush[0] - 1500, ambush[1] + 500),
        hidden=True,
        late_activation=True,
    )

    b.add_circle_zone("AMBUSH_ZONE", ambush, 2500)
    b.add_circle_zone("CONVOY_END", (start[0] - 8000, start[1] + 30000), 800)
    b.add_quad_zone(
        "VALLEY_QUAD",
        [
            (ambush[0] + 3000, ambush[1] - 4000),
            (ambush[0] + 3000, ambush[1] + 4000),
            (ambush[0] - 3000, ambush[1] + 4000),
            (ambush[0] - 3000, ambush[1] - 4000),
        ],
    )

    b.embed_lua_files([files["dms"], files["config"]])
    b.embed_sound(files["sound"])
    b.save(out)
    return b


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    with tempfile.TemporaryDirectory() as tmp:
        build(out, Path(tmp))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
