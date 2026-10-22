-- Balance: evening out the damage of the halves from the damage meter.

-- 2 tanks and 4 healers, then damage dealers: { "Name:group:CLASS", ... }.
local function BalanceRaid(dps)
  local players = { "T1:1:WARRIOR:TANK", "H1:1:PRIEST:HEALER", "H2:2:PALADIN:HEALER",
                    "T2:3:WARRIOR:TANK", "H3:3:PRIEST:HEALER", "H4:4:PALADIN:HEALER" }
  for _, s in ipairs(dps) do players[#players + 1] = s .. ":DAMAGER" end
  W.Setup(players)
end

local function HalfDamage(damage)
  local h = { 0, 0 }
  for i, p in ipairs(W.roster) do
    local role = W.ns.UnitRole("raid" .. i)
    if p.group <= 4 and (role == "MELEE" or role == "RANGED") then
      local k = p.group <= 2 and 1 or 2
      h[k] = h[k] + (damage[p.name] or 0)
    end
  end
  return h
end

T("balance: no fight in the meter yet", function()
  BalanceRaid({ "A:1:ROGUE" })
  W.ns.Balance()
  ok(W.ns.lastStatus:find("no fight yet"), W.ns.lastStatus)
end)

-- Uneven boss damage, then an even trash fight.
local UNEVEN = { Rog1 = 700, Mag1 = 600, War2 = 600, Mag2 = 500 }
local EVEN = { Rog1 = 500, Mag1 = 500, War2 = 500, Mag2 = 500 }

T("balance: after a reload it still finds the boss pull", function()
  BalanceRaid({ "Rog1:1:ROGUE", "Mag1:2:MAGE", "War2:3:WARRIOR", "Mag2:4:MAGE" })
  W.Pull(UNEVEN)
  W.Fight(EVEN, "Trash")
  W.Reload()
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  local said = table.concat(W.printed, "\n")
  ok(said:find("Last boss pull: groups 1+2 did 54%", 1, true), said)
  ok(W.moves > 0, "balanced by the boss pull")
end)

T("balance: without a noted boss pull it takes the newest fight", function()
  BalanceRaid({ "Rog1:1:ROGUE", "Mag1:2:MAGE", "War2:3:WARRIOR", "Mag2:4:MAGE" })
  W.Fight(EVEN, "")
  W.Fight(UNEVEN, "")
  W.Reload()
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  local said = table.concat(W.printed, "\n")
  ok(said:find("Last fight: groups 1+2 did 54%", 1, true), said)
end)

T("balance: a noted session the meter no longer has is not used", function()
  BalanceRaid({ "Rog1:1:ROGUE", "Mag1:2:MAGE", "War2:3:WARRIOR", "Mag2:4:MAGE" })
  W.Pull(UNEVEN)
  -- After a relog the meter starts over, and the IDs with it.
  W.sessions = {}
  W.Fight(EVEN, "")
  W.Reload()
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 60), "ended")
  local said = table.concat(W.printed, "\n")
  ok(said:find("Last fight: groups 1+2 did 50%", 1, true), said)
  eq(W.moves, 0, "even trash fight, nothing to do")
end)

T("balance: not in combat", function()
  BalanceRaid({ "A:1:ROGUE" })
  W.Pull({ A = 100 })
  W.inCombat = true
  W.ns.Balance()
  ok(W.ns.lastStatus:find("in combat"), W.ns.lastStatus)
end)

T("balance: one same-role swap evens the halves", function()
  BalanceRaid({ "Rog1:1:ROGUE", "DK1:2:DEATHKNIGHT", "Mag1:2:MAGE", "Loc1:2:WARLOCK",
                "War2:3:WARRIOR", "DK2:4:DEATHKNIGHT", "Mag2:4:MAGE", "Loc2:4:WARLOCK" })
  local damage = { Rog1 = 800, DK1 = 500, Mag1 = 600, Loc1 = 500, War2 = 600, DK2 = 500, Mag2 = 500, Loc2 = 500,
                   T1 = 9000, T2 = 100 } -- tank damage must not count
  W.Pull(damage)
  local before = {}
  for _, p in ipairs(W.roster) do before[p.name] = p.group end
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  local h = HalfDamage(damage)
  ok(math.abs(h[1] - h[2]) <= 0.05 * (h[1] + h[2]), ("halves %d / %d"):format(h[1], h[2]))
  local moved = 0
  for _, p in ipairs(W.roster) do
    if p.group ~= before[p.name] then moved = moved + 1 end
  end
  eq(moved, 2, "one swap")
  for _, n in ipairs({ "T1", "T2", "H1", "H2", "H3", "H4" }) do eq(W.GroupOf(n), before[n], n .. " stays") end
end)

T("balance: melee for ranged only when no same-role swap helps", function()
  BalanceRaid({ "M1:1:ROGUE", "R1:2:MAGE", "M2:3:WARRIOR", "R2:4:WARLOCK" })
  -- Same-role swaps can't even it out; a cross swap can.
  local damage = { M1 = 500, R1 = 700, M2 = 600, R2 = 400 }
  W.Pull(damage)
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  local h = HalfDamage(damage)
  ok(math.abs(h[1] - h[2]) <= 0.05 * (h[1] + h[2]), ("halves %d / %d"):format(h[1], h[2]))
end)

T("balance: locked and unknown players stay", function()
  BalanceRaid({ "Big:1:ROGUE", "S1:2:MAGE", "Who:2:WARLOCK", "S2:3:WARRIOR", "S3:4:MAGE", "S4:4:EVOKER" })
  W.ns.SetLocked("Big", true)
  local damage = { Big = 3000, S1 = 500, S2 = 500, S3 = 500, S4 = 500 }
  W.Pull(damage)
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  eq(W.GroupOf("Big"), 1, "locked stays")
  eq(W.GroupOf("Who"), 2, "unknown stays")
  local said = table.concat(W.printed, "\n")
  ok(said:find("No damage known for Who", 1, true), said)
end)

T("balance: already even does nothing", function()
  BalanceRaid({ "A:1:ROGUE", "B:3:ROGUE" })
  W.Pull({ A = 1000, B = 1010 })
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 60), "ended")
  eq(W.moves, 0, "moves")
  ok(W.ns.lastStatus:find("already even"), W.ns.lastStatus)
end)

T("balance: undo brings the layout back", function()
  BalanceRaid({ "Rog1:1:ROGUE", "Mag1:2:MAGE", "War2:3:WARRIOR", "Mag2:4:MAGE" })
  local layout = "Group 1: T1, H1, Rog1\nGroup 2: H2, Mag1\nGroup 3: T2, H3, War2\nGroup 4: H4, Mag2"
  W.ns.SetLayout(layout)
  W.Pull({ Rog1 = 700, Mag1 = 600, War2 = 600, Mag2 = 500 })
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  ok(W.moves > 0, "balance moved someone")
  ok(W.ns.GetDB().text ~= layout, "layout changed")
  W.ns.Undo()
  eq(W.ns.GetDB().text, layout, "undo")
end)
