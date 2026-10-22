-- Sort raid, drags in the grid, locks and filling open slots.

T("perfect swap first", function()
  W.Setup({ "A:1:MAGE:DAMAGER", "B:1:MAGE:DAMAGER", "C:1:MAGE:DAMAGER", "D:1:MAGE:DAMAGER",
            "E:2:MAGE:DAMAGER", "F:2:MAGE:DAMAGER", "G:2:MAGE:DAMAGER", "H:2:MAGE:DAMAGER" })
  ok(W.Sort("Group 1: E, B, C, D\nGroup 2: A, F, G, H"), "sort ended")
  eq(W.GroupOf("A"), 2, "A"); eq(W.GroupOf("E"), 1, "E")
  eq(W.moves, 1, "moves")
end)

local function DragSetup(unlockX)
  W.Setup({ "A:2:MAGE:DAMAGER", "E:1:MAGE:DAMAGER", "B:2:MAGE:DAMAGER", "K1:1:MAGE:DAMAGER",
            "C:2:MAGE:DAMAGER", "K2:1:MAGE:DAMAGER", "D:2:MAGE:DAMAGER", "K3:1:MAGE:DAMAGER",
            "X:2:MAGE:DAMAGER" })
  W.ns.SetLayout("Group 1: E, K1, K2, K3\nGroup 2: A, B, C, D")
  if unlockX ~= nil then W.ns.SetLocked("X", not unlockX) end
  -- Drag E to the empty slot in group 2.
  W.ns.SetLayout("Group 1: K1, K2, K3\nGroup 2: A, B, C, D, E")
  W.ns.MoveInRaid({ E = 2 })
  ok(W.RunUntil(W.Idle, 60), "drag ended")
end

T("drag swaps with the player not on the list (unlocked)", function()
  DragSetup(true)
  eq(W.GroupOf("E"), 2, "E")
  eq(W.GroupOf("X"), 1, "X")
  for _, n in ipairs({ "A", "B", "C", "D" }) do eq(W.GroupOf(n), 2, n) end
end)

T("drag moves a locked player out to 5-8 first", function()
  DragSetup(nil) -- X is not on the list, so locked
  eq(W.GroupOf("E"), 2, "E")
  ok(W.GroupOf("X") >= 5, "X in 5-8, got " .. W.GroupOf("X"))
  for _, n in ipairs({ "A", "B", "C", "D" }) do eq(W.GroupOf(n), 2, n) end
end)

T("drag during a sort joins it", function()
  local text = Scrambled(20)
  W.ns.SetLayout(text)
  W.ns.Apply(text)
  W.RunUntil(function() return W.moves >= 3 end, 30)
  ok(W.ns.IsRunning(), "still sorting")
  -- Swap the first names of group 1 and group 2 in the layout, like a drag.
  local groups = W.ns.ParseInput(text).groups
  local a, b = groups[1][1], groups[2][1]
  groups[1][1], groups[2][1] = b, a
  local text2 = W.ns.FormatLayout(groups)
  W.ns.SetLayout(text2)
  W.ns.MoveInRaid({ [a] = 2, [b] = 1 })
  ok(W.RunUntil(W.Idle, 300), "ended")
  local good, who = Matches(text2)
  ok(good, "raid matches layout after drag; off: " .. tostring(who))
  ok(W.ns.lastStatus:find("Done!"), "summary: " .. tostring(W.ns.lastStatus))
end)

T("two quick drags both land", function()
  local text = Scrambled(20)
  ok(W.Sort(text), "sorted")
  local groups = W.ns.ParseInput(text).groups
  -- Drag 1: swap groups[1][1] and groups[2][1]. Drag 2 at once: swap groups[1][2] and groups[3][1].
  local a, b = groups[1][1], groups[2][1]
  groups[1][1], groups[2][1] = b, a
  W.ns.SetLayout(W.ns.FormatLayout(groups))
  W.ns.MoveInRaid({ [a] = 2, [b] = 1 })
  local c, d = groups[1][2], groups[3][1]
  groups[1][2], groups[3][1] = d, c
  local text3 = W.ns.FormatLayout(groups)
  W.ns.SetLayout(text3)
  W.ns.MoveInRaid({ [c] = 3, [d] = 1 })
  ok(W.RunUntil(W.Idle, 120), "ended")
  local good, who = Matches(text3)
  ok(good, "raid matches; off: " .. tostring(who))
end)

T("a rejected player is skipped and named", function()
  local text = Scrambled(20)
  W.rejected.P7 = true
  ok(W.Sort(text), "sort ended")
  local status = W.ns.lastStatus
  ok(status:find("Rejected by the game:|r P7", 1, true), "status: " .. status)
  local plan = W.ns.ParseInput(text)
  local off = {}
  for _, e in ipairs(plan.entries) do
    if W.GroupOf(e.name) ~= e.group then off[#off + 1] = e.name end
  end
  -- P7 stays; at most the one who was to swap with P7 is off too.
  ok(#off <= 2, "off: " .. table.concat(off, ","))
end)

T("locked helper in a needed slot moves to 5-8", function()
  local players = {}
  for i = 1, 20 do
    players[i] = ("P%d:%d:%s:%s"):format(i, math.floor((i - 1) / 5) + 1, CLASSES[i % #CLASSES + 1], "DAMAGER")
  end
  -- P13 sits in group 5; Helper in group 3 instead.
  players[13] = "P13:5:MAGE:DAMAGER"
  players[21] = "Helper:3:PRIEST:HEALER"
  W.Setup(players)
  local groups = {}
  for i = 1, 20 do
    local g = math.floor((i - 1) / 5) + 1
    groups[g] = groups[g] or {}
    table.insert(groups[g], "P" .. i)
  end
  local text = W.ns.FormatLayout(groups)
  ok(W.Sort(text), "ended")
  eq(W.GroupOf("P13"), 3, "P13")
  ok(W.GroupOf("Helper") >= 5, "Helper benched, got " .. W.GroupOf("Helper"))
  ok(W.ns.lastStatus:find("Done!"), W.ns.lastStatus)
end)

T("locked players are never put in 1-4 by fill", function()
  -- List uses groups 1-2 only; Z (not on list) is locked by default.
  W.Setup({ "A:1:MAGE:DAMAGER", "B:1:MAGE:DAMAGER", "Z:6:PRIEST:HEALER", "Y:6:MAGE:DAMAGER" })
  W.ns.SetLocked("Y", false)
  ok(W.Sort("Group 1: A\nGroup 2: B"), "ended")
  eq(W.GroupOf("Z"), 6, "Z stays")
  ok(W.GroupOf("Y") <= 4, "Y unlocked, filled in, got " .. W.GroupOf("Y"))
end)

T("no list: nobody locked", function()
  W.Setup({ "A:1:MAGE:DAMAGER" })
  eq(W.ns.IsLocked("A", false, false), false, "no list")
  eq(W.ns.IsLocked("A", false, true), true, "not on list")
  eq(W.ns.IsLocked("A", true, true), false, "on list")
end)

T("a name that matches two players keeps its slot", function()
  W.InRaid(20)
  local players = {}
  for i = 1, 18 do players[i] = ("P%d:%d:MAGE:DAMAGER"):format(i, math.floor((i - 1) / 5) + 1) end
  players[19] = "Foo-Aaa:6:MAGE:DAMAGER"
  players[20] = "Foo-Bbb:6:MAGE:DAMAGER"
  players[21] = "Z:7:PRIEST:HEALER"
  players[22] = "Y:7:PRIEST:HEALER"
  W.Setup(players)
  W.ns.SetLocked("Z", false)
  W.ns.SetLocked("Y", false)
  local groups = { {}, {}, {}, {} }
  for i = 1, 18 do table.insert(groups[math.floor((i - 1) / 5) + 1], "P" .. i) end
  table.insert(groups[4], "Foo") -- group 4: P16, P17, P18, Foo and one open slot
  ok(W.Sort(W.ns.FormatLayout(groups)), "ended")
  local n = (W.GroupOf("Z") == 4 and 1 or 0) + (W.GroupOf("Y") == 4 and 1 or 0)
  eq(n, 1, "one of Z and Y fills the open slot, Foo's is held")
  local plan = W.ns.ParseInput(W.ns.GetDB().text)
  local foo
  for _, e in ipairs(plan.entries) do if e.name == "Foo" then foo = e.group end end
  eq(foo, 4, "Foo still on the list in group 4")
end)
