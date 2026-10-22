-- The groups that play: how many, their halves, and Auto, locks, filling
-- open slots and Balance with 5 and 6 groups.

-- n players, P1-Pn, in groups by join order: P1 and P2 tank, the next
-- `healers` heal, the rest are damage dealers of every class in CLASSES.
local function Raid(n, healers)
  local players = {}
  for i = 1, n do
    local role = i <= 2 and "TANK" or i <= 2 + (healers or 0) and "HEALER" or "DAMAGER"
    players[i] = ("P%d:%d:%s:%s"):format(i, math.floor((i - 1) / 5) + 1, CLASSES[i % #CLASSES + 1], role)
  end
  W.Setup(players)
end

-- Players in each half of the groups that play, and in the groups after
-- them, with each role's count per half.
local function Halves()
  local play = W.ns.PlayGroups()
  local size, out, roles = { 0, 0 }, 0, {}
  for i, p in ipairs(W.roster) do
    if p.group <= play.count then
      local h = play.half[p.group]
      local role = W.ns.UnitRole("raid" .. i)
      size[h] = size[h] + 1
      roles[role] = roles[role] or { 0, 0 }
      roles[role][h] = roles[role][h] + 1
    else
      out = out + 1
    end
  end
  return size, out, roles
end

local function Auto()
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "auto ended")
  local good, who = Matches(W.ns.GetDB().text)
  ok(good, "raid matches Auto layout; off: " .. tostring(who))
end

T("play groups: two per 10 players, no more than the instance lets in", function()
  local function Check(n, groups, halves, where)
    Raid(n)
    local play = W.ns.PlayGroups()
    eq(play.count, groups, ("%s, %d players: groups"):format(where, n))
    eq(table.concat(play.half, ""), halves, ("%s, %d players: halves"):format(where, n))
  end
  Check(0, 4, "1122", "outside")
  Check(20, 4, "1122", "outside")
  Check(21, 6, "111222", "outside")
  Check(30, 6, "111222", "outside")
  Check(36, 6, "111222", "outside")
  W.InRaid(20)
  Check(28, 4, "1122", "Mythic")
  W.InRaid(25)
  Check(20, 4, "1122", "Mythic flex")
  Check(21, 5, "11122", "Mythic flex")
  Check(30, 5, "11122", "Mythic flex")
  W.InRaid(30)
  Check(25, 6, "111222", "Heroic")
  W.InRaid(40)
  Check(35, 8, "11112222", "40-player raid")
end)

T("auto: 25 outside an instance all play in groups 1-6, halves 13 and 12", function()
  Raid(25, 5)
  Auto()
  local size, out, roles = Halves()
  eq(out, 0, "nobody waits")
  eq(math.max(size[1], size[2]), 13, "bigger half")
  eq(math.min(size[1], size[2]), 12, "smaller half")
  eq(roles.TANK[1], 1, "tank in half 1"); eq(roles.TANK[2], 1, "tank in half 2")
  ok(math.min(roles.HEALER[1], roles.HEALER[2]) == 2, "healers 3 and 2")
  for _, role in ipairs({ "MELEE", "RANGED" }) do
    ok(math.abs(roles[role][1] - roles[role][2]) <= 1, role .. " split evenly")
  end
end)

T("auto: Mythic flex with 23 plays groups 1-5, halves 13 and 10", function()
  W.InRaid(25)
  Raid(23, 5)
  Auto()
  local size, out, roles = Halves()
  eq(out, 0, "nobody waits")
  eq(size[1], 13, "groups 1-3"); eq(size[2], 10, "groups 4-5")
  eq(roles.TANK[1], 1, "tank in half 1"); eq(roles.TANK[2], 1, "tank in half 2")
  eq(roles.HEALER[1], 3, "the bigger half has the extra healer"); eq(roles.HEALER[2], 2, "healers in groups 4-5")
end)

T("auto: Mythic flex with 28 plays 25 in groups 1-5, 3 wait", function()
  W.InRaid(25)
  Raid(28, 5)
  Auto()
  local size, out = Halves()
  eq(size[1], 15, "groups 1-3"); eq(size[2], 10, "groups 4-5")
  eq(out, 3, "wait in groups 6-8")
end)

T("auto: 18 players split 9 and 9, not 10 and 8", function()
  -- Each role's odd one would tip to groups 1+2.
  W.Setup({ "T1:1:WARRIOR:TANK", "T2:2:WARRIOR:TANK", "T3:3:WARRIOR:TANK",
            "H1:1:PRIEST:HEALER", "H2:2:PRIEST:HEALER", "H3:3:PRIEST:HEALER", "H4:4:PRIEST:HEALER", "H5:4:PRIEST:HEALER",
            "M1:1:ROGUE:DAMAGER", "M2:2:ROGUE:DAMAGER", "M3:3:ROGUE:DAMAGER", "M4:4:ROGUE:DAMAGER", "M5:5:ROGUE:DAMAGER",
            "R1:5:MAGE:DAMAGER", "R2:5:MAGE:DAMAGER", "R3:6:MAGE:DAMAGER", "R4:6:MAGE:DAMAGER", "R5:6:MAGE:DAMAGER" })
  Auto()
  local size, out = Halves()
  eq(out, 0, "nobody waits")
  eq(size[1], 9, "groups 1+2"); eq(size[2], 9, "groups 3+4")
end)

T("sort: a locked player leaves groups 1-6 for 7-8 with 21 or more", function()
  local players, groups = {}, {}
  for i = 1, 21 do
    local g = math.floor((i - 1) / 5) + 1
    players[i] = ("P%d:%d:MAGE:DAMAGER"):format(i, g)
    groups[g] = groups[g] or {}
    table.insert(groups[g], "P" .. i)
  end
  -- P7 sits in group 6; Helper, not on the list, in group 2 instead. Group 6
  -- plays too, so Helper can't simply trade places with P7.
  players[7] = "P7:6:MAGE:DAMAGER"
  players[22] = "Helper:2:PRIEST:HEALER"
  W.Setup(players)
  ok(W.Sort(W.ns.FormatLayout(groups)), "ended")
  eq(W.GroupOf("P7"), 2, "P7")
  ok(W.GroupOf("Helper") >= 7, "Helper in 7-8, got " .. W.GroupOf("Helper"))
end)

T("fill: with 22 in the raid, the open slots of groups 4-6 are filled", function()
  -- The list has 14 in groups 1-3 and 4 in group 4, each half with a tank
  -- and 2 healers; X1-X4 are not on it. 22 play, so all 4 get a slot in
  -- groups 4-6, the smaller half.
  local players, groups = {}, { {}, {}, {}, {} }
  for i = 1, 18 do
    local g = i <= 14 and math.floor((i - 1) / 5) + 1 or 4
    local role = (i == 1 or i == 15) and "TANK" or (i == 2 or i == 3 or i == 16 or i == 17) and "HEALER" or "DAMAGER"
    -- In the raid by join order from group 3, so the list's players need moving.
    players[i] = ("P%d:%d:%s:%s"):format(i, math.floor((i - 1) / 5) + 3, CLASSES[i % #CLASSES + 1], role)
    table.insert(groups[g], "P" .. i)
  end
  for i = 1, 4 do players[18 + i] = ("X%d:%d:MAGE:DAMAGER"):format(i, i <= 2 and 1 or 2) end
  W.Setup(players)
  for i = 1, 4 do W.ns.SetLocked("X" .. i, false) end
  ok(W.Sort(W.ns.FormatLayout(groups)), "ended")
  for i = 1, 4 do
    local g = W.GroupOf("X" .. i)
    ok(g >= 4 and g <= 6, ("X%d in groups 4-6, got %d"):format(i, g))
  end
end)

-- Balance's chat lines, joined.
local function Said() return table.concat(W.printed, "\n") end

T("balance: with 26 players it compares groups 1+2+3 with 4+5+6", function()
  Raid(26, 4) -- groups 1-5 full, P26 in group 6
  local damage = {}
  for i = 7, 26 do damage["P" .. i] = i <= 16 and 1200 or 800 end
  W.Pull(damage)
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  ok(Said():find("Last boss pull: groups 1+2+3 did ", 1, true), Said())
  ok(Said():find("of the damage, groups 4+5+6 ", 1, true), Said())
  ok(Said():find("Groups 1+2+3 have 15 players and groups 4+5+6 11, so the goal is 58% and 42%.", 1, true), Said())
end)

T("balance: halves of the same size get no goal line", function()
  Raid(20, 4)
  W.Pull({ P7 = 1000, P8 = 1000, P17 = 1000, P18 = 1000 })
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 60), "ended")
  ok(Said():find("Last boss pull: groups 1+2 did ", 1, true), Said())
  ok(not Said():find("so the goal is", 1, true), Said())
end)

-- Mythic flex with 25: groups 1-3 have a tank, 3 healers and 11 damage
-- dealers (A1-A11), groups 4-5 a tank, 2 healers and 7 (B1-B7). The damage
-- dealers are all mages.
local function FlexRaid()
  W.InRaid(25)
  W.Setup({ "T1:1:WARRIOR:TANK", "H1:1:PRIEST:HEALER", "A1:1:MAGE:DAMAGER", "A2:1:MAGE:DAMAGER", "A3:1:MAGE:DAMAGER",
            "H2:2:PRIEST:HEALER", "A4:2:MAGE:DAMAGER", "A5:2:MAGE:DAMAGER", "A6:2:MAGE:DAMAGER", "A7:2:MAGE:DAMAGER",
            "H3:3:PRIEST:HEALER", "A8:3:MAGE:DAMAGER", "A9:3:MAGE:DAMAGER", "A10:3:MAGE:DAMAGER", "A11:3:MAGE:DAMAGER",
            "T2:4:WARRIOR:TANK", "H4:4:PRIEST:HEALER", "B1:4:MAGE:DAMAGER", "B2:4:MAGE:DAMAGER", "B3:4:MAGE:DAMAGER",
            "H5:5:PRIEST:HEALER", "B4:5:MAGE:DAMAGER", "B5:5:MAGE:DAMAGER", "B6:5:MAGE:DAMAGER", "B7:5:MAGE:DAMAGER" })
end

T("balance: Mythic flex with 15 and 10 aims for 60% and 40%", function()
  FlexRaid()
  -- 60% and 40% of the damage: even for halves of 15 and 10.
  local damage = {}
  for i = 1, 11 do damage["A" .. i] = i == 1 and 500 or 1000 end
  for i = 1, 7 do damage["B" .. i] = 1000 end
  W.Pull(damage)
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 60), "ended")
  ok(Said():find("groups 1+2+3 did 60% of the damage, groups 4+5 40%", 1, true), Said())
  ok(Said():find("Groups 1+2+3 have 15 players and groups 4+5 10, so the goal is 60% and 40%.", 1, true), Said())
  ok(Said():find("Groups 1+2+3 and 4+5 are already even.", 1, true), Said())
  eq(W.moves, 0, "moves")
end)

T("balance: Mythic flex swaps toward 60% and 40%", function()
  FlexRaid()
  -- Groups 1-3 did 55%: A1 (500) for a 1000 from groups 4-5 brings them to 58%.
  local damage = {}
  for i = 1, 11 do damage["A" .. i] = i == 1 and 500 or 1000 end
  for i = 1, 7 do damage["B" .. i] = i == 1 and 2500 or 1000 end
  W.Pull(damage)
  W.ns.Balance()
  ok(W.RunUntil(W.Idle, 120), "ended")
  ok(Said():find("groups 1+2+3 did 55%", 1, true), Said())
  ok(W.GroupOf("A1") >= 4, "A1 moved to groups 4-5, got " .. W.GroupOf("A1"))
  eq(W.moves, 1, "one swap")
  ok(Said():find("After: groups 1+2+3 58%, groups 4+5 42%.", 1, true), Said())
end)

T("grid: the lock tooltip names the groups that play", function()
  W.visible = true
  Raid(22)
  W.ns.CreateUI()
  W.ns.SetLayout("Group 1: P1")
  W.ns.RefreshGrid()
  local lines = {}
  GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
  local slot
  for _, fr in ipairs(W.frames) do
    if fr.member == "P2" then slot = fr end
  end
  ok(slot, "slot for P2")
  slot.lock.scripts.OnEnter(slot.lock)
  ok(lines[1] and lines[1]:find("groups 1-6", 1, true), tostring(lines[1]))
end)
