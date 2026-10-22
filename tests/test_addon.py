"""Runs the addon's Lua tests and fuzzer under Lua 5.1 (lupa), the Lua
version WoW uses. Each test gets a fresh Lua state with the WoW stubs
(wow.lua), the test helpers (helpers.lua) and the addon from src/ loaded.

Every *_spec.lua file declares its tests with T(name, fn); each one becomes
a pytest test. fuzz.lua tries FUZZ_RUNS random raids per mode (default 300).

Usage: python -m pytest tests
"""
import os
from pathlib import Path

import pytest
from lupa import lua51

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "src"
SPECS = sorted(HERE.glob("*_spec.lua"))
FUZZ_MODES = ["sort", "moves", "auto", "drags", "balance", "balanceraid"]
FUZZ_RUNS = int(os.environ.get("FUZZ_RUNS", "300"))


def read(path):
    return path.read_text(encoding="utf-8")


def fresh(*files):
    """A Lua state with the stubs, the helpers, the addon and then files loaded."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(read(HERE / "wow.lua"))
    lua.execute(read(HERE / "helpers.lua"))
    lua.globals().W.Load(SRC.as_posix())
    for path in files:
        lua.execute(read(path))
    return lua


def spec_tests():
    params = []
    for spec in SPECS:
        order = fresh(spec).globals().ORDER
        for i in range(1, len(order) + 1):
            params.append(pytest.param(spec, order[i], id=f"{spec.stem}: {order[i]}"))
    return params


@pytest.mark.parametrize("spec, name", spec_tests())
def test_spec(spec, name):
    lua = fresh(spec)
    passed, err = lua.eval("function(n) local ok, err = pcall(TESTS[n]); return ok, tostring(err) end")(name)
    if not passed:
        log = lua.globals().W.log
        moves = "; ".join(log[i] for i in range(1, len(log) + 1))
        pytest.fail(f"{err}\nmoves: {moves[:600]}", pytrace=False)


@pytest.mark.parametrize("mode", FUZZ_MODES)
def test_fuzz(mode):
    for seed in range(1, FUZZ_RUNS + 1):
        passed, info = fresh(HERE / "fuzz.lua").globals().FUZZ(mode, seed)
        if not passed:
            pytest.fail(f"seed {seed}: {info}", pytrace=False)
