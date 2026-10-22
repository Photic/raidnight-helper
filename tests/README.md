# Tests

The addon's logic runs outside the game in Lua 5.1 (the version WoW uses), through Python's [lupa](https://pypi.org/project/lupa/). No Lua install is needed.

```
pip install -r tests/requirements.txt
python -m pytest tests
```

- `wow.lua` stubs the WoW API the addon uses, with a simulated raid server: moves land after a short delay and are refused when the group is full.
- `helpers.lua` has `T(name, fn)`, `eq`, `ok` and shared raid builders.
- `*_spec.lua` files hold the tests. Each test runs in a fresh Lua state with the addon loaded from `src/` in `.toc` order.
- `fuzz.lua` sorts, drags, runs Auto and Balance on random raids and checks the rules hold. `FUZZ_RUNS=1000 python -m pytest tests` tries more raids (default 300 per mode).

This folder is not part of the addon package (see `.pkgmeta`). GitHub Actions runs the tests on every push, and before a release is packaged.
