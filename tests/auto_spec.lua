-- Auto: who plays, the balance of the halves, and moving as few as it can.

T("step 1 does not spend open slots on tanks", function()
  local fixed = {
    { group = 1, role = "TANK" }, { group = 1, role = "HEALER" }, { group = 1, role = "MELEE" }, { group = 1, role = "MELEE" },
    { group = 2, role = "HEALER" }, { group = 2, role = "MELEE" }, { group = 2, role = "MELEE" }, { group = 2, role = "RANGED" },
  }
  for g = 3, 4 do for _ = 1, 5 do fixed[#fixed + 1] = { group = g, role = "RANGED" } end end
  local players = { { name = "T2", role = "TANK" }, { name = "T3", role = "TANK" },
                    { name = "M1", role = "MELEE" }, { name = "R1", role = "RANGED" } }
  W.ns.BalanceGroups(fixed, players, W.ns.PlayGroups())
  ok(players[3].target and players[4].target, "dps placed")
  ok(not players[1].target and not players[2].target, "tanks not placed")
end)

local function AutoRaid()
  -- 25 in the raid, in fixed 20-player Mythic. The list puts L1-L20 in
  -- groups 1-4, N1-N5 are not on it.
  W.InRaid(20)
  local players, groups = {}, {}
  local roles = { "TANK", "TANK", "HEALER", "HEALER", "HEALER", "HEALER" }
  for i = 1, 20 do
    local raidGroup = (i * 7) % 5 + 1 -- spread over groups 1-5
    players[#players + 1] = ("L%d:%d:%s:%s"):format(i, raidGroup, CLASSES[i % #CLASSES + 1], roles[i] or "DAMAGER")
    local g = math.floor((i - 1) / 5) + 1
    groups[g] = groups[g] or {}
    table.insert(groups[g], "L" .. i)
  end
  for i = 1, 5 do players[#players + 1] = ("N%d:%d:MAGE:DAMAGER"):format(i, i) end
  return players, groups
end

local function CheckAuto()
  local plan = W.ns.ParseInput(W.ns.GetDB().text)
  local seen, inGroup = {}, {}
  for _, e in ipairs(plan.entries) do
    ok(not seen[e.name], "twice: " .. e.name)
    seen[e.name] = true
    inGroup[e.group] = (inGroup[e.group] or 0) + 1
  end
  for g, n in pairs(inGroup) do ok(n <= 5, "group " .. g .. " has " .. n) end
  for _, p in ipairs(W.roster) do ok(seen[p.name], "missing from layout: " .. p.name) end
  local good, who = Matches(W.ns.GetDB().text)
  ok(good, "raid matches Auto layout; off: " .. tostring(who))
end

T("auto: list players fill groups 1-4, the rest wait", function()
  local players, groups = AutoRaid()
  W.Setup(players)
  W.ns.SetLayout(W.ns.FormatLayout(groups))
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "ended")
  CheckAuto()
  for i = 1, 20 do ok(W.GroupOf("L" .. i) <= 4, "L" .. i .. " in 1-4") end
  for i = 1, 5 do ok(W.GroupOf("N" .. i) >= 5, "N" .. i .. " in 5-8") end
  -- Each half has a tank and 2 healers.
  local half = { {}, {} }
  for _, p in ipairs(W.roster) do
    if p.group <= 4 then
      local h = p.group <= 2 and 1 or 2
      half[h][p.role] = (half[h][p.role] or 0) + 1
    end
  end
  for h = 1, 2 do eq(half[h].TANK, 1, "tanks half " .. h); eq(half[h].HEALER, 2, "healers half " .. h) end
end)

T("auto: list bench stays out, others fill in", function()
  local players, groups = AutoRaid()
  -- The list benches L19 and L20 in group 5 instead.
  groups[4] = { "L16", "L17", "L18" }
  groups[5] = { "L19", "L20" }
  W.Setup(players)
  W.ns.SetLayout(W.ns.FormatLayout(groups))
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "ended")
  CheckAuto()
  ok(W.GroupOf("L19") >= 5 and W.GroupOf("L20") >= 5, "list bench stays out")
  local n = 0
  for _, p in ipairs(W.roster) do if p.group <= 4 then n = n + 1 end end
  eq(n, 20, "groups 1-4 full")
end)

T("auto without a list pulls from 5-8 by role", function()
  W.InRaid(20)
  local players = {}
  -- 18 in groups 1-4: 2 tanks, 3 healers. Group 5: 1 healer, 3 dps.
  local roles = { "TANK", "TANK", "HEALER", "HEALER", "HEALER" }
  for i = 1, 18 do
    players[i] = ("P%d:%d:%s:%s"):format(i, (i - 1) % 4 + 1, CLASSES[i % #CLASSES + 1], roles[i] or "DAMAGER")
  end
  players[19] = "Q1:5:MAGE:DAMAGER"
  players[20] = "Q2:5:MAGE:DAMAGER"
  players[21] = "QH:5:PRIEST:HEALER"
  players[22] = "Q3:5:MAGE:DAMAGER"
  W.Setup(players)
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "ended")
  CheckAuto()
  local n = 0
  for _, p in ipairs(W.roster) do if p.group <= 4 then n = n + 1 end end
  eq(n, 20, "groups 1-4 full")
  ok(W.GroupOf("QH") <= 4, "the healer a half needs is picked")
end)

T("auto leaves a raid that is balanced per half alone", function()
  -- Each half: tank, 2 healers, 3 melee, 4 ranged, the same classes in both
  -- halves; but the groups within a half are lopsided.
  local players = {}
  for h = 1, 2 do
    local g1, g2 = h * 2 - 1, h * 2
    local add = function(s) players[#players + 1] = s end
    add(("T%d:%d:WARRIOR:TANK"):format(h, g1))
    add(("HP%d:%d:PRIEST:HEALER"):format(h, g1))
    add(("HL%d:%d:PALADIN:HEALER"):format(h, g1))
    add(("MR%d:%d:ROGUE:DAMAGER"):format(h, g1))
    add(("MD%d:%d:DEATHKNIGHT:DAMAGER"):format(h, g1))
    add(("MW%d:%d:WARRIOR:DAMAGER"):format(h, g2))
    add(("RM%d:%d:MAGE:DAMAGER"):format(h, g2))
    add(("RL%d:%d:WARLOCK:DAMAGER"):format(h, g2))
    add(("RE%d:%d:EVOKER:DAMAGER"):format(h, g2))
    add(("RP%d:%d:PRIEST:DAMAGER"):format(h, g2))
  end
  W.Setup(players)
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "ended")
  eq(W.moves, 0, "moves")
  CheckAuto()
end)

T("auto: someone in group 2 that balance puts in group 1 stays", function()
  -- Half 1 has its tank in group 2; the balance would put a tank in group 1.
  W.Setup({ "T1:2:WARRIOR:TANK", "H1:1:PRIEST:HEALER", "M1:1:ROGUE:DAMAGER", "R1:2:MAGE:DAMAGER",
            "T2:3:WARRIOR:TANK", "H2:4:PRIEST:HEALER", "M2:3:ROGUE:DAMAGER", "R2:4:MAGE:DAMAGER" })
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "ended")
  eq(W.GroupOf("T1"), 2, "T1 stays in group 2")
  eq(W.moves, 0, "moves")
end)

T("auto unlocks, undo brings layout and locks back", function()
  local players, groups = AutoRaid()
  W.Setup(players)
  local before = W.ns.FormatLayout(groups)
  W.ns.SetLayout(before)
  W.ns.SetLocked("L3", true)
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 300), "ended")
  ok(W.ns.GetDB().text ~= before, "auto changed the layout")
  eq(W.ns.IsLocked("L3", true, true), false, "auto unlocked L3")
  W.ns.Undo()
  eq(W.ns.GetDB().text, before, "undo")
  eq(W.ns.IsLocked("L3", true, true), true, "lock back")
end)
