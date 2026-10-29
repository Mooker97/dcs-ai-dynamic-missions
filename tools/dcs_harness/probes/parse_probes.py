"""Turn the dcs.log of a probe run into one JSON answer per DCS unknown (K1-K10).

Stdlib only, so it runs anywhere (CI included). The probe missions come from build_probes.py
and log ``[DMS.PROBE] probe=<kN> key=value ...`` lines (protocol in lua/common.lua).

Usage:
    uv run python tools/dcs_harness/probes/parse_probes.py LOG [LOG ...]
        [--probe k5] [--out answers.json] [--tacview-dir DIR]

Several logs are separate runs. Only K5 (RNG across launches) needs more than one; every other
probe reads all runs together. Without ``--probe`` every probe that logged anything is answered.

Each answer: ``{"probe", "title", "question", "status", "answer", "evidence", "notes"}``.
``status`` is one of:
    answered  - the log settles the question
    partial   - the headless half is settled; the rest needs a cockpit (see README.md)
    manual    - headless can only log a proxy; the answer needs a cockpit
    no_data   - no probe lines for it (probe not run, or the script never loaded)
    error     - the probe ran but logged an error
Exit code: 0 when every requested probe has data, 1 otherwise.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Same shape as run_mission.LINE_RE (kept separate so this file has no harness import).
LINE_RE = re.compile(
    r"^(\S+ \S+)\s+(INFO|WARNING|ERROR|ALERT|DEBUG)\s+(\S+)\s+\(([^)]*)\):\s?(.*)$"
)
PROBE_RE = re.compile(r"\[DMS\.PROBE\]\s+(.*)$")
HARNESS_RE = re.compile(r"\[DMS\.HARNESS\]\s+(\S+)\s*(.*)$")
KV_RE = re.compile(r'([A-Za-z_][\w.]*)=("(?:[^"\\]|\\.)*"|\S*)')
TS_FMT = "%Y-%m-%d %H:%M:%S.%f"

#: The --inject snippet for K7 (run_mission.py --inject). Sets a global in the mission env via
#: the hook's net.dostring_in('mission', ...) and logs that it ran.
K7_INJECT = (
    "DMS_PROBE_K7_INJECTED = true env.info('[DMS.PROBE] probe=k7 phase=inject inject_ran=1')"
)


@dataclass(frozen=True)
class ProbeInfo:
    """One probe: what it asks, which script it runs and how to run it in the harness."""

    id: str
    slug: str
    title: str
    question: str
    headless: str  # "yes" | "partial" | "manual" (can a headless run settle it?)
    minutes: float  # model minutes for run_mission.py --minutes
    accel: int  # run_mission.py --accel
    runs: int = 1  # how many harness runs the answer needs
    inject: str = ""  # run_mission.py --inject snippet, if any
    extra_lua: tuple[str, ...] = ()  # repo-relative Lua files embedded before the probe script

    @property
    def script(self) -> str:
        return f"{self.id}_{self.slug}.lua"

    @property
    def miz_name(self) -> str:
        return f"probe_{self.id}_{self.slug}.miz"


PROBES: dict[str, ProbeInfo] = {
    p.id: p
    for p in (
        ProbeInfo(
            "k1",
            "ground_routes",
            "Ground route shape",
            "Does a ground route need >= 2 points with the current position first?",
            "yes",
            minutes=3.0,
            accel=8,
        ),
        ProbeInfo(
            "k2",
            "marks",
            "getMarkPanels contents",
            "Does world.getMarkPanels() list markup shapes, and is a script mark's initiator nil?",
            "partial",
            minutes=1.0,
            accel=1,
        ),
        ProbeInfo(
            "k3",
            "radio_arity",
            "radioTransmission subtitle arguments",
            "Does trigger.action.radioTransmission accept extra subtitle/duration arguments?",
            "partial",
            minutes=1.0,
            accel=1,
        ),
        ProbeInfo(
            "k4",
            "radio_range",
            "radioTransmission range and LOS",
            "How does radioTransmission reception depend on range, power and line of sight?",
            "manual",
            minutes=1.0,
            accel=1,
        ),
        ProbeInfo(
            "k5",
            "rng",
            "RNG seed per launch",
            "Does DMS.Rng.seed() give a different seed on each launch of the same .miz?",
            "yes",
            minutes=1.0,
            accel=1,
            runs=5,
            extra_lua=("lua/src/dms/rng.lua",),
        ),
        ProbeInfo(
            "k6",
            "timers",
            "Timer scheduled at now",
            "Does a timer.scheduleFunction call for exactly timer.getTime() at mission start fire?",
            "yes",
            minutes=1.0,
            accel=1,
        ),
        ProbeInfo(
            "k7",
            "dostring_in",
            "net.dostring_in from a hook",
            "Does net.dostring_in('mission', ...) from a GameGUI hook still work?",
            "yes",
            minutes=1.0,
            accel=1,
            inject=K7_INJECT,
        ),
        ProbeInfo(
            "k8",
            "tacview",
            "Tacview in the harness write dir",
            "Does the Tacview exporter write an ACMI when DCS runs from the isolated write dir?",
            "yes",
            minutes=2.0,
            accel=1,
        ),
        ProbeInfo(
            "k9",
            "log_length",
            "Longest intact env.info line",
            "What is the longest env.info line that arrives intact in dcs.log?",
            "yes",
            minutes=1.0,
            accel=1,
        ),
        ProbeInfo(
            "k10",
            "net_players",
            "net player API in the mission env",
            "Do net.get_player_list / net.get_player_info work in the mission scripting env?",
            "yes",
            minutes=1.0,
            accel=1,
        ),
    )
}


# ------------------------------------------------------------------------------------------
# log reading
# ------------------------------------------------------------------------------------------


@dataclass
class Entry:
    """One dcs.log record (continuation lines appended to ``msg``)."""

    ts: str
    level: str
    sub: str
    msg: str


@dataclass
class ProbeLine:
    probe: str
    kv: dict[str, str]
    ts: str
    msg: str

    def get(self, key: str, default: str = "") -> str:
        return self.kv.get(key, default)


@dataclass
class Run:
    """One dcs.log."""

    path: str
    entries: list[Entry] = field(default_factory=list)
    lines: list[ProbeLine] = field(default_factory=list)

    def probe(self, pid: str) -> list[ProbeLine]:
        return [ln for ln in self.lines if ln.probe == pid]

    @property
    def harness(self) -> list[tuple[str, str]]:
        out = []
        for e in self.entries:
            if h := HARNESS_RE.search(e.msg):
                out.append((h[1], h[2]))
        return out

    @property
    def start_ts(self) -> str | None:
        return self.entries[0].ts if self.entries else None


def unquote(v: str) -> str:
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        body = v[1:-1]
        out: list[str] = []
        esc = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}
        i = 0
        while i < len(body):
            c = body[i]
            if c == "\\" and i + 1 < len(body):
                out.append(esc.get(body[i + 1], body[i + 1]))
                i += 2
                continue
            out.append(c)
            i += 1
        return "".join(out)
    return v


def parse_kv(rest: str) -> dict[str, str]:
    return {m[1]: unquote(m[2]) for m in KV_RE.finditer(rest)}


def read_entries(text: str) -> list[Entry]:
    entries: list[Entry] = []
    cur: Entry | None = None
    for raw in text.splitlines():
        m = LINE_RE.match(raw)
        if m:
            cur = Entry(m[1], m[2], m[3], m[5])
            entries.append(cur)
        elif cur is not None:
            cur.msg += "\n" + raw
    return entries


def parse_run(text: str, path: str = "<text>") -> Run:
    run = Run(path=path, entries=read_entries(text))
    for e in run.entries:
        p = PROBE_RE.search(e.msg)
        if not p:
            continue
        kv = parse_kv(p[1].split("\n", 1)[0])
        if "probe" in kv:
            run.lines.append(ProbeLine(kv["probe"], kv, e.ts, e.msg))
    return run


def _truthy(v: str) -> bool:
    return v.strip().lower() in ("true", "1", "yes")


def _num(v: str) -> float | None:
    try:
        return float(v)
    except ValueError:
        return None


def _base(pid: str) -> dict[str, Any]:
    info = PROBES[pid]
    return {
        "probe": pid,
        "title": info.title,
        "question": info.question,
        "status": "no_data",
        "answer": {},
        "evidence": [],
        "notes": [],
    }


def _errors(lines: Iterable[ProbeLine]) -> list[str]:
    return [ln.get("error") for ln in lines if ln.get("error")]


def _finish(res: dict[str, Any], lines: list[ProbeLine], status: str) -> dict[str, Any]:
    if not lines:
        res["status"] = "no_data"
        return res
    res["status"] = status
    errs = _errors(lines)
    if errs:
        res["notes"].append("probe errors: " + "; ".join(errs[:5]))
        if status == "answered":
            res["status"] = "error"
    if not any(ln.get("done") == "1" for ln in lines):
        res["notes"].append("probe never logged done=1 (run cut short?)")
    return res


# ------------------------------------------------------------------------------------------
# per-probe answers
# ------------------------------------------------------------------------------------------

MOVED_M = 50.0  # a group "moved" when it is more than this far from its start


def answer_k1(runs: list[Run]) -> dict[str, Any]:
    res = _base("k1")
    lines = [ln for r in runs for ln in r.probe("k1")]
    variants: dict[str, dict[str, Any]] = {}
    for ln in lines:
        v, phase = ln.get("variant"), ln.get("phase")
        if not v:
            continue
        d = variants.setdefault(v, {})
        if phase == "route_set":
            d["route_ok"] = _truthy(ln.get("ok", "false")) if "ok" in ln.kv else False
            d["points"] = int(_num(ln.get("points", "0")) or 0)
            if ln.get("error"):
                d["error"] = ln.get("error")
        elif phase in ("mid", "final"):
            d[f"moved_m_{phase}"] = _num(ln.get("moved_m", ""))
            d[f"has_task_{phase}"] = ln.get("has_task")
    for d in variants.values():
        moved = d.get("moved_m_final", d.get("moved_m_mid"))
        d["moves"] = moved is not None and moved > MOVED_M
    res["answer"] = {
        "variants": variants,
        "one_point_moves": variants.get("one_point", {}).get("moves"),
        "two_points_no_current_moves": variants.get("two_points_no_current", {}).get("moves"),
        "two_points_current_first_moves": variants.get("two_points_current_first", {}).get("moves"),
        "on_road_moves": variants.get("two_points_current_first_on_road", {}).get("moves"),
        "control_moves": variants.get("control_no_task", {}).get("moves"),
        "moved_threshold_m": MOVED_M,
    }
    if variants.get("control_no_task", {}).get("moves"):
        res["notes"].append("the control group moved without a task: results are suspect")
    has_final = any(ln.get("phase") == "final" for ln in lines)
    return _finish(res, lines, "answered" if has_final else "partial")


def answer_k2(runs: list[Run]) -> dict[str, Any]:
    res = _base("k2")
    lines = [ln for r in runs for ln in r.probe("k2")]
    drawn = {ln.get("kind"): _truthy(ln.get("ok")) for ln in lines if ln.get("phase") == "draw"}
    listed = {
        ln.get("kind"): _truthy(ln.get("listed")) for ln in lines if ln.get("phase") == "listed"
    }
    ours = {ln.get("id") for ln in lines if ln.get("phase") == "draw"}
    panels = [
        {k: ln.get(k) for k in ("panel_idx", "initiator", "coalition", "groupID", "text", "pos_y")}
        for ln in lines
        if ln.get("phase") == "panels" and "panel_idx" in ln.kv
    ]
    mine = [p for p in panels if p["panel_idx"] in ours]
    removed = [ln for ln in lines if ln.get("phase") == "removed"]
    res["answer"] = {
        "draw_ok": drawn,
        "listed": listed,
        "shapes_listed": all(listed.get(k) for k in ("circleToAll", "textToAll"))
        if listed
        else None,
        "lines_quads_listed": all(listed.get(k) for k in ("lineToAll", "quadToAll"))
        if listed
        else None,
        "script_initiator_nil": all(p["initiator"] == "nil" for p in mine) if mine else None,
        "panel_count": next(
            (int(_num(ln.get("count")) or 0) for ln in lines if ln.get("phase") == "panels"),
            None,
        ),
        "our_panels": mine,
        "removed_mark_still_listed": _truthy(removed[0].get("listed")) if removed else None,
        "player_marks": "manual (needs a client placing a mark)",
    }
    return _finish(res, lines, "partial")


def answer_k3(runs: list[Run]) -> dict[str, Any]:
    res = _base("k3")
    lines = [ln for r in runs for ln in r.probe("k3")]
    calls: dict[str, dict[str, Any]] = {
        ln.get("variant"): {"ok": _truthy(ln.get("ok")), "err": ln.get("err")}
        for ln in lines
        if ln.get("phase") == "call"
    }
    ev = next((ln for ln in lines if ln.get("phase") == "events"), None)

    def ok(v: str) -> bool | None:
        return calls[v]["ok"] if v in calls else None

    control = ok("bad_arg_control")
    res["answer"] = {
        "calls": calls,
        "arity7_ok": ok("arity7"),
        "arity8_ok": ok("arity8"),
        "arity9_ok": ok("arity9"),
        "arity9_swapped_ok": ok("arity9_swapped"),
        "validates_arguments": None if control is None else not control,
        "events_seen": ev.get("ids") if ev else None,
        "subtitle_displayed": "manual (cockpit check)",
    }
    if control:
        res["notes"].append(
            "the bad-argument control did not error, so 'ok' only means 'did not raise'"
        )
    return _finish(res, lines, "partial")


def answer_k4(runs: list[Run]) -> dict[str, Any]:
    res = _base("k4")
    lines = [ln for r in runs for ln in r.probe("k4")]
    tx = [
        {
            "km": _num(ln.get("km")),
            "watts": _num(ln.get("watts")),
            "mhz": ln.get("mhz"),
            "ok": _truthy(ln.get("ok")),
            "los_to_rx": ln.get("los_to_rx"),
        }
        for ln in lines
        if ln.get("phase") == "tx"
    ]
    res["answer"] = {
        "transmissions": tx,
        "all_calls_ok": all(t["ok"] for t in tx) if tx else None,
        "audible_range": "manual (cockpit A/B, see README.md K4)",
    }
    return _finish(res, lines, "manual")


def answer_k5(runs: list[Run]) -> dict[str, Any]:
    res = _base("k5")
    per_run: list[dict[str, Any]] = []
    for r in runs:
        samples = {ln.get("phase"): ln for ln in r.probe("k5") if ln.get("seed")}
        if not samples:
            continue
        # DMS seeds at the first BIRTH, so that sample is the one that matters
        s = samples.get("first_birth") or samples.get("load") or next(iter(samples.values()))
        per_run.append(
            {
                "log": r.path,
                "phase": s.get("phase"),
                "seed": s.get("seed"),
                "t": s.get("t"),
                "abs": s.get("abs"),
                "table_addr": s.get("table_addr"),
                "launch_entropy": s.get("launch_entropy"),
                "math_random": s.get("math_random"),
                "picks": s.get("picks"),
                "load_seed": samples["load"].get("seed") if "load" in samples else None,
            }
        )
    lines = [ln for r in runs for ln in r.probe("k5")]
    n = len(per_run)

    def distinct(key: str) -> bool | None:
        return len({p[key] for p in per_run}) == n if n >= 2 else None

    res["answer"] = {
        "runs": n,
        "seeds": [p["seed"] for p in per_run],
        "seeds_all_distinct": distinct("seed"),
        "picks_all_distinct": distinct("picks"),
        "time_identical_across_runs": (len({p["t"] for p in per_run}) == 1) if n >= 2 else None,
        "launch_entropy_all_distinct": distinct("launch_entropy"),
        "math_random_all_distinct": distinct("math_random"),
        "per_run": per_run,
    }
    if n < 2:
        res["notes"].append(f"need >= 2 runs (ideally {PROBES['k5'].runs}); got {n}")
    return _finish(res, lines, "answered" if n >= 2 else "partial")


def answer_k6(runs: list[Run]) -> dict[str, Any]:
    res = _base("k6")
    lines = [ln for r in runs for ln in r.probe("k6")]
    sched = {ln.get("label"): ln for ln in lines if ln.get("phase") == "scheduled"}
    fired = {ln.get("label"): ln for ln in lines if ln.get("phase") == "fired"}
    table = {
        label: {
            "scheduled_ok": _truthy(s.get("ok")),
            "for": _num(s.get("for")),
            "fired": label in fired,
            "fired_at": _num(fired[label].get("at")) if label in fired else None,
        }
        for label, s in sched.items()
    }
    res["answer"] = {
        "labels": table,
        "start_now_fires": table.get("start_now_0", {}).get("fired"),
        "start_plus_0_05_fires": table.get("start_plus_0_05", {}).get("fired"),
        "start_past_fires": table.get("start_past_1", {}).get("fired"),
        "callback_now_fires": table.get("cb_now_0", {}).get("fired"),
    }
    done = any(ln.get("done") == "1" for ln in lines)
    return _finish(res, lines, "answered" if done else "partial")


def answer_k7(runs: list[Run]) -> dict[str, Any]:
    res = _base("k7")
    lines = [ln for r in runs for ln in r.probe("k7")]
    hook: dict[str, dict[str, str]] = {}
    for r in runs:
        for kind, rest in r.harness:
            if kind != "INFO":
                continue
            name, _, tail = rest.partition(" ")
            if name in ("errorbox_disable", "inject"):
                hook[name] = parse_kv(tail)
    inject_ran = any(ln.get("phase") == "inject" for ln in lines)
    check = next((ln for ln in lines if ln.get("phase") == "check"), None)
    seen_from_mission = _truthy(check.get("injected")) if check else None
    eb = hook.get("errorbox_disable")
    inj = hook.get("inject")
    res["answer"] = {
        "hook_errorbox_disable": eb,
        "hook_inject": inj,
        "errorbox_dostring_ok": (eb.get("err") == "nil") if eb else None,
        "inject_dostring_ok": (inj.get("err") == "nil") if inj else None,
        "inject_ran_in_mission": inject_ran,
        "global_visible_to_mission_script": seen_from_mission,
        "works": bool(inject_ran or seen_from_mission),
    }
    if inj is None:
        res["notes"].append("no '[DMS.HARNESS] INFO inject' line: was --inject passed?")
    if not lines and eb is not None:
        # the hook's own dostring_in line settles the question even without the probe script
        res["status"] = "answered"
        res["notes"].append("no k7 probe lines; answered from the harness hook lines only")
        return res
    return _finish(res, lines, "answered")


TACVIEW_RE = re.compile(r"tacview", re.IGNORECASE)


def answer_k8(
    runs: list[Run], tacview_dir: Path | None = None, since: dt.datetime | None = None
) -> dict[str, Any]:
    res = _base("k8")
    lines = [ln for r in runs for ln in r.probe("k8")]
    tv_lines = [
        f"{e.ts} {e.sub}: {e.msg[:300]}"
        for r in runs
        for e in r.entries
        if TACVIEW_RE.search(e.sub) or TACVIEW_RE.search(e.msg)
    ]
    acmi: list[str] | None = None
    if tacview_dir is not None:
        if since is None:
            starts = [r.start_ts for r in runs if r.start_ts]
            since = dt.datetime.strptime(min(starts), TS_FMT) if starts else None
        acmi = []
        if tacview_dir.is_dir():
            for f in sorted(tacview_dir.rglob("*.acmi")):
                mtime = dt.datetime.fromtimestamp(f.stat().st_mtime)
                if since is None or mtime >= since:
                    acmi.append(str(f))
        else:
            res["notes"].append(f"tacview dir not found: {tacview_dir}")
    res["answer"] = {
        "tacview_log_lines": tv_lines[:20],
        "tacview_loaded": bool(tv_lines),
        "new_acmi_files": acmi,
        "acmi_written": (bool(acmi) if acmi is not None else None),
    }
    if acmi is None:
        res["notes"].append("pass --tacview-dir to check for a new .acmi file")
    return _finish(res, lines, "answered" if acmi is not None else "partial")


def k9_message(n: int) -> str:
    """The exact text k9_log_length.lua logs for length ``n`` (mirror of DMS_PROBE.k9Message)."""
    head = f"[DMS.PROBE] probe=k9 len={n} payload="
    fill = n - len(head) - 4
    body = ("0123456789" * (fill // 10 + 1))[:fill]
    return head + body + "|END"


def answer_k9(runs: list[Run]) -> dict[str, Any]:
    res = _base("k9")
    lines = [ln for r in runs for ln in r.probe("k9")]
    plan = next((ln for ln in lines if ln.get("phase") == "plan"), None)
    lengths = [int(x) for x in plan.get("lengths").split(",") if x] if plan else []
    got: dict[int, str] = {}
    for r in runs:
        for e in r.entries:
            m = re.search(r"\[DMS\.PROBE\] probe=k9 len=(\d+) ", e.msg)
            if m:
                got.setdefault(int(m[1]), e.msg[m.start() :])
    rows: list[dict[str, Any]] = []
    for n in lengths or sorted(got):
        msg = got.get(n)
        intact = msg == k9_message(n)
        rows.append(
            {
                "len": n,
                "found": msg is not None,
                "logged_len": len(msg) if msg is not None else None,
                "intact": intact,
                "split": msg is not None and "\n" in msg,
            }
        )
    intact_lens = [r["len"] for r in rows if r["intact"]]
    first_bad = next((r["len"] for r in rows if not r["intact"]), None)
    res["answer"] = {
        "max_intact_len": max(intact_lens) if intact_lens else None,
        "first_broken_len": first_bad,
        "all_intact": bool(rows) and first_bad is None,
        "lengths": rows,
    }
    if rows and first_bad is None:
        res["notes"].append("every tested length was intact: the limit is above the largest")
    return _finish(res, lines, "answered" if rows else "partial")


def answer_k10(runs: list[Run]) -> dict[str, Any]:
    res = _base("k10")
    lines = [ln for r in runs for ln in r.probe("k10")]

    def calls(name: str) -> list[ProbeLine]:
        return [ln for ln in lines if ln.get("call") == name]

    keys: dict[str, dict[int, str]] = {}
    for ln in lines:
        if "net_keys" in ln.kv:
            keys.setdefault(ln.get("phase"), {})[int(ln.get("keys_part", "1"))] = ln.get("net_keys")
    net_keys = (
        "".join(v for _, v in sorted(next(iter(keys.values())).items())).split(",") if keys else []
    )
    net_type = next((ln.get("net_type") for ln in lines if "net_type" in ln.kv), None)
    lst = calls("get_player_list")
    info = calls("get_player_info")
    last_list = lst[-1] if lst else None
    res["answer"] = {
        "net_type": net_type,
        "net_keys": [k for k in net_keys if k],
        "get_player_list_ok": _truthy(last_list.get("ok")) if last_list else None,
        "player_ids": last_list.get("ids") if last_list else None,
        "player_count": int(_num(last_list.get("count")) or -1) if last_list else None,
        "get_player_info_ok": any(_truthy(ln.get("ok")) for ln in info) if info else None,
        "player_info_keys": next(
            (ln.get("keys") for ln in reversed(info) if _truthy(ln.get("ok"))), None
        ),
        "get_player_info_attr_ok": any(
            _truthy(ln.get("ok")) for ln in calls("get_player_info_attr")
        )
        if calls("get_player_info_attr")
        else None,
        "errors": sorted({ln.get("err") for ln in lst + info if ln.get("err") not in ("", "nil")}),
    }
    return _finish(res, lines, "answered")


ANSWERS: dict[str, Callable[[list[Run]], dict[str, Any]]] = {
    "k1": answer_k1,
    "k2": answer_k2,
    "k3": answer_k3,
    "k4": answer_k4,
    "k5": answer_k5,
    "k6": answer_k6,
    "k7": answer_k7,
    "k8": answer_k8,
    "k9": answer_k9,
    "k10": answer_k10,
}


def probes_seen(runs: list[Run]) -> list[str]:
    seen = {ln.probe for r in runs for ln in r.lines}
    return [pid for pid in PROBES if pid in seen]


def answer_all(
    runs: list[Run], probes: Iterable[str] | None = None, tacview_dir: Path | None = None
) -> list[dict[str, Any]]:
    wanted = list(probes) if probes else probes_seen(runs)
    out = []
    for pid in wanted:
        if pid == "k8":
            out.append(answer_k8(runs, tacview_dir))
        else:
            out.append(ANSWERS[pid](runs))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("logs", nargs="+", type=Path, help="dcs.log file(s), one per run")
    ap.add_argument("--probe", action="append", choices=sorted(PROBES), help="repeatable")
    ap.add_argument("--out", type=Path, help="write the JSON here as well as stdout")
    ap.add_argument("--tacview-dir", type=Path, help="K8: folder Tacview writes .acmi files to")
    a = ap.parse_args(argv)
    runs = []
    for p in a.logs:
        if not p.is_file():
            print(f"log not found: {p}", file=sys.stderr)
            return 1
        runs.append(parse_run(p.read_text(encoding="utf-8", errors="replace"), str(p)))
    answers = answer_all(runs, a.probe, a.tacview_dir)
    out = json.dumps({"logs": [str(p) for p in a.logs], "answers": answers}, indent=2)
    if a.out:
        a.out.write_text(out + "\n", encoding="utf-8")
    print(out)
    if not answers:
        return 1
    return 0 if all(x["status"] != "no_data" for x in answers) else 1


if __name__ == "__main__":
    sys.exit(main())
