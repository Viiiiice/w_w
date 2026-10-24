#!/usr/bin/env python3
"""Bundle every .lua file in src/ into one script at dist/w_w.lua.

Each file becomes a module keyed by its path without the extension
(src/Util/Maid.lua -> "Util/Maid"), and require("Util/Maid") inside the bundle
loads it. A folder's init.lua is the folder itself
(src/Features/AnimationLogger/init.lua -> "Features/AnimationLogger").
src/init.lua is the entry point.

Usage:  python build.py           build once
        python build.py --watch   rebuild whenever a file in src/ changes
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "dist" / "w_w.lua"
ENTRY = "init"

HEADER = """-- w_w - bundled build, do not edit by hand.
-- Source lives in src/; rebuild with: python build.py
local __modules, __cache = {}, {}
local function require(name)
\tlocal cached = __cache[name]
\tif cached ~= nil then
\t\treturn cached
\tend
\tlocal loader = __modules[name]
\tif not loader then
\t\terror("module not found: " .. tostring(name), 2)
\tend
\tlocal result = loader()
\tif result == nil then
\t\tresult = true
\tend
\t__cache[name] = result
\treturn result
end
"""


def module_name(path: Path) -> str:
    name = path.relative_to(SRC).with_suffix("").as_posix()
    if name.endswith("/init"):
        name = name[: -len("/init")]
    return name


def build() -> None:
    files = sorted(SRC.rglob("*.lua"))
    names = [module_name(f) for f in files]
    if ENTRY not in names:
        sys.exit(f"missing entry point src/{ENTRY}.lua")

    parts = [HEADER]
    for path, name in zip(files, names):
        if name == ENTRY:
            continue
        body = path.read_text(encoding="utf-8").rstrip()
        parts.append(f'\n__modules["{name}"] = function()\n{body}\nend\n')

    entry = (SRC / f"{ENTRY}.lua").read_text(encoding="utf-8").rstrip()
    parts.append(f"\n-- entry: src/{ENTRY}.lua\ndo\n{entry}\nend\n")

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("".join(parts), encoding="utf-8")
    print(f"built {OUT.relative_to(ROOT)} from {len(files)} files")


def snapshot():
    return {p: p.stat().st_mtime for p in SRC.rglob("*.lua")}


if __name__ == "__main__":
    build()
    if "--watch" in sys.argv:
        print("watching src/ (ctrl+c to stop)")
        last = snapshot()
        while True:
            time.sleep(0.5)
            now = snapshot()
            if now != last:
                last = now
                try:
                    build()
                except Exception as exc:  # keep watching after a bad save
                    print("build failed:", exc)
