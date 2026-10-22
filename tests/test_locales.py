"""Every text the addon shows (L["..."]) has a translation in each locale block
of Locales.lua with the same placeholders, and no translation is left over.

Usage: python -m pytest tests
"""
import re
from pathlib import Path

import pytest
from lupa import lua51

SRC = Path(__file__).resolve().parent.parent / "src"
LOCALES = ["deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]


def used_keys():
    keys = set()
    for path in SRC.glob("*.lua"):
        if path.name != "Locales.lua":
            text = path.read_text(encoding="utf-8")
            keys |= set(re.findall(r'L\["([^"]*)"\]', text)) | set(re.findall(r"L\['([^']*)'\]", text))
    return keys


def translations(locale):
    lua = lua51.LuaRuntime()
    lua.execute('GetLocale = function() return "%s" end' % locale)
    ns = lua.table()
    lua.eval('function(src, ns) assert(loadstring(src))("RaidnightHelper", ns) end')(
        (SRC / "Locales.lua").read_text(encoding="utf-8"), ns)
    return {key: ns.L[key] for key in ns.L.keys()}


def placeholders(text):
    return [p for p in re.findall(r"%(?:%|d|s)", text) if p != "%%"]


@pytest.mark.parametrize("locale", LOCALES)
def test_locale(locale):
    have, used = translations(locale), used_keys()
    assert sorted(used - set(have)) == [], "not translated"
    assert sorted(set(have) - used) == [], "translated but not used"
    wrong = [key for key, text in have.items() if placeholders(key) != placeholders(text)]
    assert wrong == [], "placeholders differ"
