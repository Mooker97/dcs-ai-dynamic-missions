"""PostToolUse hook: Lua 5.1 syntax check for edited files under lua/.

Reads the hook JSON from stdin. If the edited file is a .lua file under lua/src, lua/spec or
lua/mocks, compiles it with Lua 5.1 (lupa.lua51, else luac5.1/luac) and exits 2 with the error
so Claude sees it. Any missing tool or unexpected input exits 0 (never blocks unrelated work).
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

CHECKED_DIRS = ("lua/src/", "lua/spec/", "lua/mocks/")


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        file_path = payload.get("tool_input", {}).get("file_path") or ""
    except Exception:
        return 0
    norm = file_path.replace("\\", "/")
    if not norm.endswith(".lua") or not any(d in norm for d in CHECKED_DIRS):
        return 0
    path = Path(file_path)
    if not path.is_file():
        return 0
    source = path.read_text(encoding="utf-8", errors="replace")

    error: str | None = None
    try:
        import lupa.lua51 as lua51  # type: ignore[import-not-found]

        runtime = lua51.LuaRuntime()
        result = runtime.eval("loadstring")(source, "@" + path.name)
        if isinstance(result, tuple) and result[0] is None:
            error = str(result[1])
    except ImportError:
        luac = shutil.which("luac5.1") or shutil.which("luac")
        if luac is None:
            return 0
        proc = subprocess.run([luac, "-p", str(path)], capture_output=True, text=True)
        if proc.returncode != 0:
            error = (proc.stderr or proc.stdout).strip()

    if error:
        print(f"Lua 5.1 syntax error (DCS uses Lua 5.1: no goto, no //): {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
