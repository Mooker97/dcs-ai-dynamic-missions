# tools/

| Path | What |
|---|---|
| `bundle_lua.py` | `lua/src` -> `dist/dms.lua` in manifest order |
| `dcs_harness/run_mission.py` | runs one `.miz` in a real DCS, unattended, and writes a JSON report |
| `arma_harness/run_mission.py` | the same for Arma 3 dedicated servers |
| `nightly.py` + `nightly.yaml` | rebuilds and runs a list of DCS test missions one at a time (below) |
| `tests/` | parser tests for the harnesses and the nightly tests (fake subprocess, nothing launched) |

## Nightly (`tools/nightly.py`)

```bash
uv run python tools/nightly.py --dry-run          # check the gates, print the plan, run nothing
uv run python tools/nightly.py                    # tools/nightly.yaml (viper m01-m04)
uv run python tools/nightly.py --config my.yaml --min-free-gb 14 --ram-wait-sec 1800
```

The nightly holds the shared sim lock for the whole run. It then does this for each mission in
turn:

1. **Foreign process check.** It stops if `DCS.exe`, `DCS_server.exe`, `arma3.exe`,
   `arma3_x64.exe`, `arma3server(_x64).exe` or `arma3battleye.exe` is running. It never kills
   anything. A game that is running at the start refuses the whole run (exit 2). A game started
   between missions makes it skip every mission that is left.
2. **Harness lock check.** It skips the mission if a live run holds the DCS harness write-dir
   lock (see below). It waits up to `--lock-wait-sec` (default 1800) first.
3. **Rebuild.** It runs `dms build <mission> --test [--variant v] [--test-minutes m]`. This is free
   (no voice), and a non-zero exit means `build_failed`. The model minutes and accel are read from
   the build's `harness:` line.
4. **RAM gate.** It waits for `--min-free-gb` (default 12) of free physical RAM, polling every
   30 s for up to `--ram-wait-sec` (default 900). If there still isn't enough, the mission is
   `skipped` with `low_ram`. (Syria ran out of memory at 9 GB free.)
5. **Harness.** It runs `tools/dcs_harness/run_mission.py <miz> --minutes M --accel A --report ...
   --min-free-gb ... --ram-wait-sec ... --write-dir-name ...` as a subprocess, so the harness is
   never imported or edited. Exit codes map as 0 = `pass`, 1 = `fail` and 2 = `infra_error`. If
   the harness overruns its wall timeout plus slack, that is also `infra_error`.

`--dry-run` still checks the gates and records them in `preflight`, but it takes no lock and
builds or launches nothing. Every mission is `planned` and the process exits 0.

The nightly's exit codes are 0 = every mission passed (or `--dry-run`), 1 = at least one mission
didn't pass and 2 = refused (game running, sim lock held, or bad config).

### Config (`tools/nightly.yaml`, or any `.yaml`/`.json` passed with `--config`)

```yaml
min_free_gb: 12          # optional; the CLI flag wins
ram_wait_sec: 900        # optional; the CLI flag wins
write_dir_name: DCS.dms_test   # optional harness write dir
missions:
  - campaigns/viper-detachment/missions/m01-broken-umbrella   # a bare path is fine
  - mission: campaigns/viper-detachment/missions/m02-the-quarry
    variant: air          # build --variant (which start variant the AI proxy takes)
    minutes: 20           # build --test-minutes (default: derived by the build)
    accel: 8              # harness --accel (default 16)
    harness_args: ["--no-log-checks"]   # extra run_mission.py arguments
```

Paths are relative to the repo root. Unknown keys are an error. If `tools/nightly.yaml` is
missing, the built-in list (viper m01-m04) is used.

### Output

Each run writes to `<out-dir>/<YYYYMMDD-HHMMSS>/`, where `--out-dir` defaults to `~/.dms/nightly`
(or `$DMS_HOME/nightly`):

- `nightly.json`: the report (schema below). It is rewritten after every mission, so a crash
  still leaves a partial report.
- `<name>.build.log`, `<name>.harness.log`: stdout and stderr of each step.
- `<name>.harness.json`: the harness's own report (`--report`).

`<out-dir>/latest.json` is a copy of the newest `nightly.json`.

### Report schema (`dms.nightly/1`)

```jsonc
{
  "schema": "dms.nightly/1",
  "started": "2026-10-30T02:00:01+10:00",     // local time, ISO 8601 with offset
  "finished": "2026-10-30T02:41:17+10:00",
  "host": "Mooks-Rig",
  "config": "C:\\...\\tools\\nightly.yaml",    // or "<built-in>"
  "dry_run": false,
  "min_free_gb": 12.0,
  "run_dir": "C:\\Users\\...\\.dms\\nightly\\20261030-020001",
  "status": "pass",               // pass | fail | refused | planned (dry run)
  "refused_reason": null,         // "foreign_process: DCS.exe pid 123" | "sim_lock_held: pid N (path)"
  "preflight": {                  // machine state when the run started
    "foreign_processes": [],      // ["DCS.exe pid 123", ...]
    "free_ram_gb": 21.4,          // null when unknown
    "sim_lock": "C:\\Users\\...\\.dms\\locks\\sim.lock",
    "sim_lock_holder": null,      // live pid holding it, else null
    "harness_lock_holder": null   // live pid holding the DCS harness write-dir lock, else null
  },
  "missions": [
    {
      "name": "m01-broken-umbrella",          // folder name, "-<variant>" appended if set
      "mission": "campaigns/viper-detachment/missions/m01-broken-umbrella",
      "variant": null,
      "status": "pass",   // pass | fail | infra_error | build_failed | skipped | planned
      "reason": null,     // why it isn't pass: "low_ram: ...", "foreign_process: ...",
                          // "harness_lock_held: ...", "harness exit 1 verdict fail", "refused", ...
      "miz": "C:\\...\\out\\m01-broken-umbrella-test.miz",
      "minutes": 87.0,    // model minutes passed to the harness
      "accel": 16,
      "free_ram_gb": 21.0,                    // when the RAM gate passed or gave up
      "build":   {"cmd": [...], "exit_code": 0, "seconds": 14.2, "log": "...build.log"},
      "harness": {"cmd": [...], "exit_code": 0, "seconds": 731.5, "log": "...harness.log"},
                          // exit_code null = timed out; build/harness null = step not reached
      "harness_report": "...\\m01-broken-umbrella.harness.json",
      "verdict": "pass",  // the harness report's verdict
      "tests": {"PASS": 9, "SKIP": 1},        // status counts over tests + log_checks
      "script_errors": 0,
      "dms_errors": 0
    }
  ],
  "summary": {"total": 4, "pass": 3, "skipped": 1}   // total plus a count per status
}
```

When `docs/CONTRACTS.md` gets its "Tooling formats" section, this schema should move there.

## Locks

### DCS harness write-dir lock (existing; owned by `dcs_harness/run_mission.py`)

The lock file is `%USERPROFILE%\Saved Games\<write-dir-name>\dms_harness.lock`. It is created
with `O_CREAT|O_EXCL` and holds `"<pid>\n"`. One harness run gets one write dir, because two runs
would overwrite each other's hook and `kill_ours()` would kill the other run's DCS. A lock whose
pid is dead is stale, and the next run deletes it. A live holder makes the harness wait up to
`--ram-wait-sec` and then exit 2. The nightly only reads this lock: it skips the mission while a
live pid holds it and leaves a stale one for the harness to clean up.

### Shared sim lock (new convention: one heavy sim run per machine)

DCS and Arma 3 both want most of the RAM and the GPU on the user's gaming PC, so only one
headless sim run should happen at a time, whatever the engine. The convention:

- **Path:** `~/.dms/locks/sim.lock` (`$DMS_HOME/locks/sim.lock`; `--lock-dir` in the nightly).
- **Create** it atomically with `os.open(path, O_CREAT | O_EXCL | O_WRONLY)`, and never by
  checking first and writing after.
- **Content** is one JSON line:
  `{"pid": 1234, "owner": "nightly" | "dcs_harness" | "arma_harness" | "<tool>", "started": "<ISO 8601>", "host": "<hostname>"}`.
  A reader also accepts a bare `"<pid>"` first token, the same format as `dms_harness.lock`.
- **Stale:** if the pid isn't alive (`OpenProcess` + `GetExitCodeProcess` != `STILL_ACTIVE`, or
  `os.kill(pid, 0)` off Windows), or the file can't be parsed, delete it and retry the create.
- **Live holder:** wait, polling every 30 s up to the tool's wait budget, then give up with exit 2.
  Never delete a live holder's lock.
- **Release:** delete it only if it still holds your own pid, in a `finally`.
- **Nesting:** a parent that holds the lock (the nightly) runs its children (the DCS harness)
  under it. A harness that adopts this convention should skip taking the lock when an
  environment variable says the parent already holds it. The proposed name is
  `DMS_SIM_LOCK_HELD=<parent pid>`; the nightly doesn't set it yet, because neither harness reads
  it.

`nightly.py` implements this (`acquire_sim_lock`, `lock_holder`, `release_sim_lock`). The DCS
and Arma harnesses don't take it yet. Adopting it is a small change for whichever work package
owns each harness: the DCS harness takes it around `_run`, and the Arma harness takes it around
its launches. Until then, the nightly's foreign-process check stops it from starting next to a
manual Arma run, and the write-dir lock stops it from starting next to a manual DCS run.

## Scheduling the nightly (Windows Task Scheduler)

Nothing is scheduled for you. To run it at 02:00 every night, open a normal (not elevated)
terminal and run:

```bat
mkdir %USERPROFILE%\.dms\nightly
schtasks /Create /TN "DMS Nightly" /SC DAILY /ST 02:00 /RL LIMITED /F ^
  /TR "cmd /c cd /d C:\coding\claude-projects\claude-test\DMS && .venv\Scripts\python.exe tools\nightly.py >> %USERPROFILE%\.dms\nightly\task.log 2>&1"
```

Or use the GUI (`taskschd.msc`, then **Create Task**):

- **General:** "Run only when user is logged on". DCS needs your desktop session and Saved Games.
  Don't tick "Run with highest privileges".
- **Triggers:** Daily at 02:00 (or "On idle", if you'd rather).
- **Actions:** Program `C:\coding\claude-projects\claude-test\DMS\.venv\Scripts\python.exe`,
  arguments `tools\nightly.py`, start in `C:\coding\claude-projects\claude-test\DMS`.
- **Conditions:** "Wake the computer to run this task" if you want it. Untick "Start the task
  only if the computer is on AC power" on a laptop.
- **Settings:** "Stop the task if it runs longer than" 4 hours, and "Do not start a new
  instance". The sim lock guards against overlap too.

Notes:

- Use the venv's `python.exe` directly. Task Scheduler's PATH may not have `uv`, and the nightly
  runs `dms` and the harness through the same interpreter (`sys.executable`).
- Run `uv sync --all-packages` after pulling, because the task doesn't sync.
- If you're playing when the task fires, the nightly sees DCS/Arma, refuses, writes a `refused`
  report and exits 2. Nothing is killed.
- Test the task once with `--dry-run` added to the arguments, then check `~/.dms/nightly/latest.json`.
- To remove the task: `schtasks /Delete /TN "DMS Nightly" /F`.
