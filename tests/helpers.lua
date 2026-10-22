-- Helpers for the *_spec.lua files. Each test runs in a fresh Lua state with
-- the addon loaded (see test_addon.py). W.ns is the addon namespace.
TESTS, ORDER = {}, {}
function T(name, fn) TESTS[name] = fn; ORDER[#ORDER + 1] = name end

function eq(a, b, msg)
  if a ~= b then error(("%s: expected %s, got %s"):format(msg or "", tostring(b), tostring(a)), 2) end
end
function ok(c, msg) if not c then error(msg or "assertion failed", 2) end end

CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "WARLOCK", "DEATHKNIGHT", "PALADIN", "MONK", "EVOKER" }

-- n players; 20 players, roles: 2 tanks, 4 healers, 14 dps.
function Scrambled(n)
  local players, names = {}, {}
  for i = 1, n do
    local role = i <= 2 and "TANK" or i <= 6 and "HEALER" or "DAMAGER"
    names[i] = "P" .. i
    -- Raid groups by join order, the layout by number: everyone is off.
    players[i] = ("P%d:%d:%s:%s"):format(i, math.floor((i - 1) / 5) + 1, CLASSES[i % #CLASSES + 1], role)
  end
  W.Setup(players)
  -- Layout: rotate everyone by 2 groups.
  local groups = {}
  for i = 1, n do
    local g = (math.floor((i - 1) / 5) + 2) % math.ceil(n / 5) + 1
    groups[g] = groups[g] or {}
    table.insert(groups[g], names[i])
  end
  return W.ns.FormatLayout(groups), names
end

-- Is everyone on the layout in their group? Else false and the first who is not.
function Matches(text)
  local plan = W.ns.ParseInput(text)
  for _, e in ipairs(plan.entries) do
    if W.GroupOf(e.name) ~= e.group then return false, e.name end
  end
  return true
end
