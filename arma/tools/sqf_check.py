"""Static checks for the DMS Arma 3 mission (no third-party tools, stdlib only).

SQF checks: bracket balance, string/comment termination, trailing commas, missing-semicolon
heuristic, `call` results used in arithmetic without parentheses, `sleep (a) + b`, local variable
hygiene (assigned or read but never declared), engine `random` outside fn_rng,
unknown BIS functions.
Mission checks: every DMS_fnc_* used is declared in CfgFunctions and has a file (and vice versa),
every DMS_cfg key read exists in fn_config, comm-menu/debriefing classes referenced exist, and
description.ext / mission.sqm parse as Arma config.

Usage: python sqf_check.py <mission_dir>   (exit 1 on errors)
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------- tokenizer

OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {v: k for k, v in OPEN.items()}
MULTI_OPS = ("==", "!=", ">=", "<=", "&&", "||", ">>")
SINGLE_OPS = set("+-*/%^=<>!#:")
MAGIC_LOCALS = {
    "_x",
    "_y",
    "_this",
    "_forEachIndex",
    "_thisEventHandler",
    "_thisScript",
    "_exception",
    "_target",
    "_caller",
    "_actionId",
    "_arguments",
    "_fnc_scriptName",
    "_fnc_scriptNameParent",
}
STATEMENT_KEYWORDS = {
    "private",
    "if",
    "while",
    "for",
    "switch",
    "waitUntil",
    "sleep",
    "diag_log",
    "params",
}
KNOWN_BIS = {
    "BIS_fnc_holdActionAdd",
    "BIS_fnc_taskCreate",
    "BIS_fnc_taskSetState",
    "BIS_fnc_taskExists",
    "BIS_fnc_taskCompleted",
    "BIS_fnc_addCommMenuItem",
    "BIS_fnc_endMission",
    "BIS_fnc_getParamValue",
    "BIS_fnc_taskPatrol",
    "BIS_fnc_removeCommMenuItem",
}
ALLOW_RANDOM_MARK = "dms-allow-random"


@dataclass
class Token:
    kind: str  # STR NUM ID OP P
    text: str
    line: int


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def extend(self, other: Report) -> None:
        self.errors.extend(other.errors)
        self.warnings.extend(other.warnings)


class SqfSyntaxError(Exception):
    pass


def tokenize(src: str, name: str = "<sqf>") -> tuple[list[Token], set[int]]:
    """Return tokens and the set of line numbers carrying the allow-random marker."""
    tokens: list[Token] = []
    marked: set[int] = set()
    i, line, n = 0, 1, len(src)
    at_line_start = True
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            at_line_start = True
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "#" and at_line_start:  # preprocessor directive (with continuations)
            while i < n and src[i] != "\n":
                if src[i] == "\\" and i + 1 < n and src[i + 1] == "\n":
                    line += 1
                    i += 1
                i += 1
            continue
        at_line_start = False
        if src.startswith("//", i):
            end = src.find("\n", i)
            end = n if end == -1 else end
            if ALLOW_RANDOM_MARK in src[i:end]:
                marked.add(line)
            i = end
            continue
        if src.startswith("/*", i):
            end = src.find("*/", i + 2)
            if end == -1:
                raise SqfSyntaxError(f"{name}:{line}: unterminated block comment")
            line += src.count("\n", i, end)
            i = end + 2
            continue
        if c in "\"'":
            start_line = line
            j = i + 1
            buf = []
            while True:
                if j >= n:
                    raise SqfSyntaxError(f"{name}:{start_line}: unterminated string")
                if src[j] == c:
                    if j + 1 < n and src[j + 1] == c:  # doubled quote = escaped quote
                        buf.append(c)
                        j += 2
                        continue
                    break
                if src[j] == "\n":
                    line += 1
                buf.append(src[j])
                j += 1
            tokens.append(Token("STR", "".join(buf), start_line))
            i = j + 1
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            m = re.match(r"0x[0-9a-fA-F]+|\d*\.?\d+(?:[eE][+-]?\d+)?", src[i:])
            assert m
            tokens.append(Token("NUM", m.group(0), line))
            i += len(m.group(0))
            continue
        if c == "$" and i + 1 < n and src[i + 1].isalnum():  # hex like $FF
            m = re.match(r"\$[0-9a-fA-F]+", src[i:])
            assert m
            tokens.append(Token("NUM", m.group(0), line))
            i += len(m.group(0))
            continue
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
            assert m
            tokens.append(Token("ID", m.group(0), line))
            i += len(m.group(0))
            continue
        two = src[i : i + 2]
        if two in MULTI_OPS:
            tokens.append(Token("OP", two, line))
            i += 2
            continue
        if c in "()[]{};,":
            tokens.append(Token("P", c, line))
            i += 1
            continue
        if c in SINGLE_OPS:
            tokens.append(Token("OP", c, line))
            i += 1
            continue
        raise SqfSyntaxError(f"{name}:{line}: unexpected character {c!r}")
    return tokens, marked


# ---------------------------------------------------------------------------- SQF checks


def _declared_locals(tokens: list[Token]) -> set[str]:
    declared = set(MAGIC_LOCALS)
    for idx, t in enumerate(tokens):
        if t.kind == "ID" and t.text == "private" and idx + 1 < len(tokens):
            nxt = tokens[idx + 1]
            if nxt.kind == "ID":
                declared.add(nxt.text)
            elif nxt.kind == "P" and nxt.text == "[":
                j = idx + 2
                while j < len(tokens) and tokens[j].text != "]":
                    if tokens[j].kind == "STR":
                        declared.add(tokens[j].text)
                    j += 1
        if (
            t.kind == "ID"
            and t.text == "for"
            and idx + 1 < len(tokens)
            and tokens[idx + 1].kind == "STR"
        ):
            declared.add(tokens[idx + 1].text)
        if (
            t.kind == "ID"
            and t.text == "params"
            and idx + 1 < len(tokens)
            and tokens[idx + 1].text == "["
        ):
            depth = 0
            j = idx + 1
            while j < len(tokens):
                tj = tokens[j]
                if tj.text == "[" and tj.kind == "P":
                    depth += 1
                elif tj.text == "]" and tj.kind == "P":
                    depth -= 1
                    if depth == 0:
                        break
                elif tj.kind == "STR" and tj.text.startswith("_"):
                    prev = tokens[j - 1]
                    # a name is the first element of its (sub)array at depth 1 or 2
                    if (depth == 1 and prev.text in "[,") or (depth == 2 and prev.text == "["):
                        declared.add(tj.text)
                j += 1
    return declared


def check_sqf(src: str, name: str = "<sqf>", allow_random: bool = False) -> Report:
    rep = Report()
    try:
        tokens, marked = tokenize(src, name)
    except SqfSyntaxError as exc:
        rep.errors.append(str(exc))
        return rep

    # bracket balance
    stack: list[Token] = []
    # stack top kind for each token index (statement context), used by the semicolon heuristic
    ctx_after: list[str] = []
    for t in tokens:
        if t.kind == "P" and t.text in OPEN:
            stack.append(t)
        elif t.kind == "P" and t.text in CLOSE:
            if not stack:
                rep.errors.append(f"{name}:{t.line}: unmatched '{t.text}'")
            elif stack[-1].text != CLOSE[t.text]:
                rep.errors.append(
                    f"{name}:{t.line}: '{t.text}' closes '{stack[-1].text}' "
                    f"opened at line {stack[-1].line}"
                )
                stack.pop()
            else:
                stack.pop()
        ctx_after.append(stack[-1].text if stack else "")
    for t in stack:
        rep.errors.append(f"{name}:{t.line}: unclosed '{t.text}'")
    if rep.errors:
        return rep

    for idx, t in enumerate(tokens):
        nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
        prev = tokens[idx - 1] if idx > 0 else None
        # trailing comma
        if (
            t.text == ","
            and t.kind == "P"
            and nxt is not None
            and nxt.kind == "P"
            and nxt.text in ")]}"
        ):
            rep.errors.append(f"{name}:{t.line}: trailing comma before '{nxt.text}'")
        # missing semicolon: a statement ends a line at statement level and a new statement starts
        if (
            nxt is not None
            and nxt.line > t.line
            and ctx_after[idx] in ("", "{")
            and (
                t.kind in ("STR", "NUM")
                or (t.kind == "ID" and t.text not in STATEMENT_KEYWORDS)
                or (t.kind == "P" and t.text in ")]}")
            )
        ):
            after = tokens[idx + 2] if idx + 2 < len(tokens) else None
            starts_stmt = (nxt.kind == "ID" and nxt.text in STATEMENT_KEYWORDS) or (
                nxt.kind == "ID" and after is not None and after.kind == "OP" and after.text == "="
            )
            if starts_stmt:
                rep.errors.append(f"{name}:{t.line}: missing ';' before line {nxt.line}")
        # `x call fnc + y` parses as `x call (fnc + y)`
        if (
            t.kind == "ID"
            and t.text == "call"
            and nxt is not None
            and nxt.kind == "ID"
            and idx + 2 < len(tokens)
            and tokens[idx + 2].kind == "OP"
            and tokens[idx + 2].text in "+-*/"
            and prev is not None
            and prev.kind != "OP"
            and prev.text not in ";{(,["
        ):
            rep.errors.append(
                f"{name}:{t.line}: '{nxt.text}' result used in arithmetic; "
                "wrap the call in parentheses"
            )
        # `sleep (a) + b` parses as `(sleep a) + b`
        if t.kind == "ID" and t.text == "sleep" and nxt is not None and nxt.text == "(":
            depth, j = 0, idx + 1
            while j < len(tokens):
                if tokens[j].text == "(":
                    depth += 1
                elif tokens[j].text == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if j + 1 < len(tokens) and tokens[j + 1].kind == "OP" and tokens[j + 1].text in "+-*/":
                rep.errors.append(
                    f"{name}:{t.line}: 'sleep (a) op b' sleeps only (a); add outer parentheses"
                )
        # determinism: engine RNG only in fn_rng (or lines marked)
        if (
            t.kind == "ID"
            and t.text in ("random", "selectRandom", "selectRandomWeighted")
            and not allow_random
            and t.line not in marked
        ):
            rep.errors.append(
                f"{name}:{t.line}: '{t.text}' bypasses the seeded RNG (use DMS_fnc_rng)"
            )
        if t.kind == "ID" and t.text.startswith("BIS_fnc_") and t.text not in KNOWN_BIS:
            rep.warnings.append(f"{name}:{t.line}: unverified BIS function {t.text}")
        if t.kind == "STR" and t.text.startswith("BIS_fnc_") and t.text not in KNOWN_BIS:
            rep.warnings.append(f"{name}:{t.line}: unverified BIS function {t.text}")

    # local variable hygiene
    declared = _declared_locals(tokens)
    seen: set[str] = set()
    for idx, t in enumerate(tokens):
        if t.kind != "ID" or not t.text.startswith("_") or t.text in declared or t.text in seen:
            continue
        nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
        if nxt is not None and nxt.kind == "OP" and nxt.text == "=":
            rep.warnings.append(
                f"{name}:{t.line}: {t.text} assigned without 'private' (leaks into caller scope)"
            )
        else:
            rep.warnings.append(f"{name}:{t.line}: {t.text} used but never declared in this file")
        seen.add(t.text)
    return rep


# ----------------------------------------- config (description.ext / mission.sqm)


class ConfigError(Exception):
    pass


def parse_config(text: str, name: str = "<cfg>") -> dict:
    """Parse Arma config syntax into nested dicts (classes -> dicts, arrays -> lists)."""
    tokens, _ = tokenize(_strip_preprocessor(text), name)
    pos = 0

    def peek(k: int = 0) -> Token | None:
        return tokens[pos + k] if pos + k < len(tokens) else None

    def expect(text_: str) -> Token:
        nonlocal pos
        t = peek()
        if t is None or t.text != text_:
            got = "EOF" if t is None else repr(t.text)
            line = tokens[-1].line if t is None else t.line
            raise ConfigError(f"{name}:{line}: expected {text_!r}, got {got}")
        pos += 1
        return t

    def parse_value() -> object:
        nonlocal pos
        t = peek()
        if t is None:
            raise ConfigError(f"{name}: unexpected EOF in value")
        if t.text == "{":
            pos += 1
            items: list[object] = []
            while peek() is not None and peek().text != "}":
                items.append(parse_value())
                if peek() is not None and peek().text == ",":
                    pos += 1
                    if peek() is not None and peek().text == "}":
                        raise ConfigError(f"{name}:{t.line}: trailing comma in array")
            expect("}")
            return items
        # scalar: string, number (maybe negative), or bare word(s) up to ; , }
        if t.kind == "STR":
            pos += 1
            return t.text
        parts = []
        while peek() is not None and peek().text not in (";", ",", "}"):
            parts.append(peek().text)
            pos += 1
        raw = "".join(parts)
        try:
            return float(raw) if any(ch in raw for ch in ".eE") else int(raw)
        except ValueError:
            return raw

    def parse_body(end: str | None) -> dict:
        nonlocal pos
        out: dict = {}
        while True:
            t = peek()
            if t is None:
                if end is None:
                    return out
                raise ConfigError(f"{name}: unexpected EOF, missing '{end}'")
            if end is not None and t.text == end:
                pos += 1
                return out
            if t.kind == "ID" and t.text == "class":
                pos += 1
                cname = peek()
                if cname is None or cname.kind != "ID":
                    raise ConfigError(f"{name}:{t.line}: class without name")
                pos += 1
                if peek() is not None and peek().text == ":":
                    pos += 2  # base class
                if peek() is not None and peek().text == ";":  # forward declaration
                    pos += 1
                    out.setdefault(cname.text, {})
                    continue
                expect("{")
                out[cname.text] = parse_body("}")
                expect(";")
                continue
            if t.kind != "ID":
                raise ConfigError(f"{name}:{t.line}: unexpected {t.text!r}")
            key = t.text
            pos += 1
            is_array = False
            if peek() is not None and peek().text == "[":
                expect("[")
                expect("]")
                is_array = True
            if peek() is not None and peek().text == "+":
                pos += 1  # +=
            expect("=")
            val = parse_value()
            if is_array and not isinstance(val, list):
                raise ConfigError(f"{name}:{t.line}: {key}[] needs an array value")
            out[key] = val
            expect(";")

    return parse_body(None)


def _strip_preprocessor(text: str) -> str:
    return "\n".join("" if ln.lstrip().startswith("#") else ln for ln in text.splitlines())


# ---------------------------------------------------------------------------- mission-level checks

CFG_GET_RE = re.compile(r"""(?:_cfg|DMS_cfg)\s+get(?:OrDefault)?\s*\[?\s*"(\w+)\"""")
FNC_RE = re.compile(r"\bDMS_fnc_(\w+)")


def config_keys(config_sqf: str) -> set[str]:
    return set(re.findall(r'^\t\["(\w+)",', config_sqf, flags=re.MULTILINE))


def cfg_functions(desc: dict) -> set[str]:
    names: set[str] = set()
    for tag_cls in desc.get("CfgFunctions", {}).values():
        for cat in tag_cls.values():
            if isinstance(cat, dict):
                names.update(k for k, v in cat.items() if isinstance(v, dict))
    return names


def check_mission(mission_dir: Path) -> Report:
    rep = Report()
    mission_dir = Path(mission_dir)
    sqf_files = sorted(mission_dir.rglob("*.sqf"))
    texts = {p: p.read_text(encoding="utf-8") for p in sqf_files}

    for p, src in texts.items():
        rel = p.relative_to(mission_dir).as_posix()
        rep.extend(check_sqf(src, rel, allow_random=p.name == "fn_rng.sqf"))

    desc_path = mission_dir / "description.ext"
    try:
        desc_text = desc_path.read_text(encoding="utf-8")
        desc = parse_config(desc_text, "description.ext")
    except (OSError, ConfigError, SqfSyntaxError) as exc:
        rep.errors.append(f"description.ext: {exc}")
        return rep

    # SQF inside comm-menu expressions
    for cls_name, cls in desc.get("CfgCommunicationMenu", {}).items():
        expr = cls.get("expression", "")
        rep.extend(check_sqf(expr, f"description.ext:CfgCommunicationMenu.{cls_name}.expression"))

    declared = cfg_functions(desc)
    used: set[str] = set()
    for src in [*texts.values(), desc_text]:
        used.update(FNC_RE.findall(src))
    fn_dir = mission_dir / "functions"
    files = {p.stem[3:] for p in fn_dir.glob("fn_*.sqf")}
    for fn in sorted(used - declared):
        rep.errors.append(f"DMS_fnc_{fn} is used but not declared in CfgFunctions")
    for fn in sorted(declared - files):
        rep.errors.append(f"DMS_fnc_{fn} is declared but functions/fn_{fn}.sqf is missing")
    for fn in sorted(files - declared):
        rep.errors.append(f"functions/fn_{fn}.sqf exists but is not declared in CfgFunctions")

    # DMS_cfg keys
    cfg_path = fn_dir / "fn_config.sqf"
    if cfg_path.exists():
        keys = config_keys(cfg_path.read_text(encoding="utf-8"))
        for p, src in texts.items():
            for key in CFG_GET_RE.findall(src):
                if key not in keys:
                    rep.errors.append(f"{p.name}: config key '{key}' not defined in fn_config.sqf")

    # comm-menu items and debriefing classes referenced from SQF
    menu = set(desc.get("CfgCommunicationMenu", {}))
    debrief = set(desc.get("CfgDebriefing", {}))
    all_sqf = "\n".join(texts.values())
    for item in set(re.findall(r'"(DMS_(?:Arty\w+|AirSupport|Extract))"', all_sqf)):
        if item not in menu:
            rep.errors.append(f"comm-menu item {item} not in CfgCommunicationMenu")
    for end in set(re.findall(r'"(DMS_(?:Win|Fail\w*|TestEnd))"', all_sqf)):
        if end not in debrief:
            rep.errors.append(f"end {end} not in CfgDebriefing")

    sqm_path = mission_dir / "mission.sqm"
    try:
        parse_config(sqm_path.read_text(encoding="utf-8"), "mission.sqm")
    except (OSError, ConfigError, SqfSyntaxError) as exc:
        rep.errors.append(f"mission.sqm: {exc}")
    return rep


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    rep = check_mission(Path(argv[1]))
    for w in rep.warnings:
        print(f"WARN  {w}")
    for e in rep.errors:
        print(f"ERROR {e}")
    print(f"{len(rep.errors)} error(s), {len(rep.warnings)} warning(s)")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
