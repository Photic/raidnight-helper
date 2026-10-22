-- Named lists in the text format ("Left: ..."), and Swap halves.

-- prefix1, prefix2, ... prefixN
local function Names(prefix, n)
  local names = {}
  for i = 1, n do names[i] = prefix .. i end
  return names
end

-- Everyone in the lists joins the raid, in groups by join order.
local function Join(...)
  local players = {}
  for _, names in ipairs({ ... }) do
    for _, name in ipairs(names) do
      players[#players + 1] = ("%s:%d:MAGE:DAMAGER"):format(name, math.floor(#players / 5) + 1)
    end
  end
  W.Setup(players)
end

-- The names in group g of a layout text, or "" when it is empty.
local function Group(text, g)
  return table.concat(W.ns.ParseInput(text).groups[g] or {}, " ")
end

-- The layout as the window stores it: "Group N:" text.
local function Layout(text)
  return W.ns.FormatLayout(W.ns.ParseInput(text).groups)
end

local function Printed(line)
  for _, p in ipairs(W.printed) do
    if p:find(line, 1, true) then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Named lists
---------------------------------------------------------------------------

T("named lists fill groups of five in order", function()
  local text = "Left: " .. table.concat(Names("L", 14), " ") .. "\nRight: " .. table.concat(Names("R", 14), " ")
  local plan = W.ns.ParseInput(text)
  eq(#plan.errors, 0, "errors")
  eq(#plan.warnings, 0, "warnings")
  eq(plan.count, 28, "count")
  eq(Group(text, 1), "L1 L2 L3 L4 L5", "group 1")
  eq(Group(text, 2), "L6 L7 L8 L9 L10", "group 2")
  eq(Group(text, 3), "L11 L12 L13 L14", "group 3")
  eq(Group(text, 4), "R1 R2 R3 R4 R5", "group 4")
  eq(Group(text, 6), "R11 R12 R13 R14", "group 6")
  eq(Group(text, 7), "", "group 7")
end)

T("named lists: names below the label, commas, a third list", function()
  local text = "Left side:\nBrannoc\nElowyn, Fenwick\nRight side: Isolde Torvald\nBench: Ashlyn"
  local plan = W.ns.ParseInput(text)
  eq(#plan.errors, 0, "errors")
  eq(Group(text, 1), "Brannoc Elowyn Fenwick", "group 1")
  eq(Group(text, 2), "Isolde Torvald", "group 2")
  eq(Group(text, 3), "Ashlyn", "group 3")
end)

T("a named list starts after the last group used", function()
  local text = "Group 2: Corvain\nLeft: Dúnmir Ravéna\nGroup 5: Thessaly\nRight: Brannoc"
  local plan = W.ns.ParseInput(text)
  eq(#plan.errors, 0, "errors")
  eq(Group(text, 1), "", "group 1")
  eq(Group(text, 2), "Corvain", "group 2")
  eq(Group(text, 3), "Dúnmir Ravéna", "group 3")
  eq(Group(text, 5), "Thessaly", "group 5")
  eq(Group(text, 6), "Brannoc", "group 6")
end)

T("named lists past group 8 are an error", function()
  -- Left takes groups 1-6 and Right 7-8, with no room for R11.
  local plan = W.ns.ParseInput("Left: " .. table.concat(Names("L", 30), " ") .. "\nRight: " .. table.concat(Names("R", 11), " "))
  eq(plan.errors[1], "The lists have more players than groups 1-8 can hold.", "error")
  eq(#plan.errors, 1, "one error")
end)

T("a name in two lists is an error", function()
  local plan = W.ns.ParseInput("Left: Elowyn Fenwick\nRight: Fenwick")
  eq(plan.errors[1], "Fenwick is in both group 1 and 2.", "error")
end)

T("a list split by spaces: each word is a name, Name-Realm too", function()
  local text = "Left: Brannoc Elowyn-Silvermoon Fenwick\nRight: Isolde-ArgentDawn Torvald"
  local plan = W.ns.ParseInput(text)
  eq(#plan.errors, 0, "errors")
  eq(Group(text, 1), "Brannoc Elowyn-Silvermoon Fenwick", "group 1")
  eq(Group(text, 2), "Isolde-ArgentDawn Torvald", "group 2")
  eq(plan.count, 5, "count")
end)

T("a list split by commas keeps a realm with a space", function()
  local plan = W.ns.ParseInput("Group 1: Brannoc-Argent Dawn, Elowyn")
  eq(table.concat(plan.groups[1], "|"), "Brannoc-Argent Dawn|Elowyn", "group 1")
end)

T("a label with a number is a group number", function()
  local text = "Team 2: Isolde Torvald"
  eq(#W.ns.ParseInput(text).errors, 0, "errors")
  eq(Group(text, 1), "", "group 1")
  eq(Group(text, 2), "Isolde Torvald", "group 2")
end)

T("ui: pasted named lists are stored as groups", function()
  W.visible = true
  W.ns.CreateUI()
  local eb
  for _, fr in ipairs(W.frames) do
    if fr.scripts.OnTextChanged then eb = fr end
  end
  ok(eb, "paste field")
  eb.text_ = "Left: Ashlyn Corvain\nRight: Dúnmir"
  eb.scripts.OnTextChanged(eb, true)
  ok(W.RunUntil(function() return W.ns.GetDB().text ~= "" end, 5), "pasted")
  eq(W.ns.GetDB().text, "Group 1: Ashlyn, Corvain\nGroup 2: Dúnmir", "layout")
end)

---------------------------------------------------------------------------
-- Not on list
---------------------------------------------------------------------------

T("a Not on list line keeps names outside the groups", function()
  local text = "Group 1: Ashlyn\nNot on list: Corvain, Dúnmir"
  local plan = W.ns.ParseInput(text)
  eq(#plan.errors, 0, "errors")
  eq(plan.count, 1, "count")
  eq(table.concat(plan.parked, " "), "Corvain Dúnmir", "parked")
  eq(W.ns.FormatLayout(plan.groups, plan.parked), text, "formats back")
end)

T("a name in a group and in Not on list stays in the group", function()
  local plan = W.ns.ParseInput("Group 1: Corvain\nNot on list: corvain, Dúnmir, Dunmir")
  eq(table.concat(plan.parked, " "), "Dúnmir", "parked")
  eq(W.ns.FormatLayout({ { "Ravéna" } }, { "Ravena-Silvermoon", "Thessaly" }), "Group 1: Ravéna\nNot on list: Thessaly",
    "a name without a realm matches any realm")
end)

T("a layout of only names in Not on list is a layout", function()
  local plan = W.ns.ParseInput("Not on list: Corvain")
  eq(#plan.errors, 0, "errors")
  eq(plan.count, 0, "count")
  eq(plan.parked[1], "Corvain", "parked")
end)

T("Not on list is not a named list, and a label after it is", function()
  local text = "Not on list: Ashlyn\nLeft: Brannoc Elowyn"
  local plan = W.ns.ParseInput(text)
  eq(Group(text, 1), "Brannoc Elowyn", "group 1")
  eq(table.concat(plan.parked, " "), "Ashlyn", "parked")
end)

T("Auto and Swap halves keep the names in Not on list", function()
  Join({ "Ashlyn", "Brannoc" })
  W.ns.SetLayout("Group 1: Ashlyn\nGroup 3: Brannoc\nNot on list: Corvain")
  W.ns.SwapHalves()
  eq(W.ns.GetDB().text, "Group 1: Brannoc\nGroup 3: Ashlyn\nNot on list: Corvain", "swap")
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 120), "auto ended")
  ok(W.ns.GetDB().text:find("\nNot on list: Corvain$"), "auto: " .. W.ns.GetDB().text)
end)

---------------------------------------------------------------------------
-- Swap halves
---------------------------------------------------------------------------

T("swap trades groups 1-3 with 4-6 in a raid of 30", function()
  local left, right, bench = Names("L", 14), Names("R", 14), Names("B", 2)
  Join(left, right, bench)
  W.ns.SetLayout(Layout("Left: " .. table.concat(left, " ") .. "\nRight: " .. table.concat(right, " ")
    .. "\nBench: " .. table.concat(bench, " ")))
  W.ns.SwapHalves()
  local text = W.ns.GetDB().text
  eq(Group(text, 1), "R1 R2 R3 R4 R5", "group 1")
  eq(Group(text, 3), "R11 R12 R13 R14", "group 3")
  eq(Group(text, 4), "L1 L2 L3 L4 L5", "group 4")
  eq(Group(text, 6), "L11 L12 L13 L14", "group 6")
  eq(Group(text, 7), "B1 B2", "bench stays")
  eq(W.moves, 0, "nobody moved in the raid")
  ok(not W.ns.IsRunning(), "no sort")
  ok(Printed("Groups 1+2+3 and 4+5+6 traded places."), "chat line")
end)

T("swap twice brings the layout back", function()
  local left, right = Names("L", 14), Names("R", 14)
  Join(left, right)
  local before = Layout("Left: " .. table.concat(left, " ") .. "\nRight: " .. table.concat(right, " "))
  W.ns.SetLayout(before)
  W.ns.SwapHalves()
  ok(W.ns.GetDB().text ~= before, "swapped")
  W.ns.SwapHalves()
  eq(W.ns.GetDB().text, before, "back")
end)

T("swap in Mythic trades 1+2 with 3+4, and 5 stays", function()
  W.InRaid(20)
  local left, right, bench = Names("L", 10), Names("R", 10), Names("B", 4)
  Join(left, right, bench)
  W.ns.SetLayout(Layout("Left: " .. table.concat(left, " ") .. "\nRight: " .. table.concat(right, " ")
    .. "\nBench: " .. table.concat(bench, " ")))
  W.ns.SwapHalves()
  local text = W.ns.GetDB().text
  eq(Group(text, 1), "R1 R2 R3 R4 R5", "group 1")
  eq(Group(text, 2), "R6 R7 R8 R9 R10", "group 2")
  eq(Group(text, 3), "L1 L2 L3 L4 L5", "group 3")
  eq(Group(text, 4), "L6 L7 L8 L9 L10", "group 4")
  eq(Group(text, 5), "B1 B2 B3 B4", "bench stays")
  ok(Printed("Groups 1+2 and 3+4 traded places."), "chat line")
end)

T("swap in Mythic flex leaves group 3, which has no partner", function()
  W.InRaid(25)
  local left, right = Names("L", 15), Names("R", 10)
  Join(left, right)
  W.ns.SetLayout(Layout("Left: " .. table.concat(left, " ") .. "\nRight: " .. table.concat(right, " ")))
  W.ns.SwapHalves()
  local text = W.ns.GetDB().text
  eq(Group(text, 1), "R1 R2 R3 R4 R5", "group 1")
  eq(Group(text, 2), "R6 R7 R8 R9 R10", "group 2")
  eq(Group(text, 3), "L11 L12 L13 L14 L15", "group 3 stays")
  eq(Group(text, 4), "L1 L2 L3 L4 L5", "group 4")
  eq(Group(text, 5), "L6 L7 L8 L9 L10", "group 5")
  ok(Printed("Groups 1+2 and 4+5 traded places."), "chat line")
end)

T("swap while the raid forms keeps the sides, and missing players move with theirs", function()
  -- 15 in the raid would make the halves 1+2 and 3+4; the list of 28 makes them 1-3 and 4-6.
  local left, right = Names("L", 14), Names("R", 14)
  Join(Names("L", 10), Names("R", 5))
  W.ns.SetLayout(Layout("Left: " .. table.concat(left, " ") .. "\nRight: " .. table.concat(right, " ")))
  W.ns.SwapHalves()
  local text = W.ns.GetDB().text
  eq(Group(text, 1), "R1 R2 R3 R4 R5", "group 1")
  eq(Group(text, 3), "R11 R12 R13 R14", "group 3 holds R11-R14, not in the raid yet")
  eq(Group(text, 4), "L1 L2 L3 L4 L5", "group 4")
  eq(Group(text, 6), "L11 L12 L13 L14", "group 6")
  eq(W.moves, 0, "nobody moved in the raid")
end)

T("swap outside a raid uses the size of the list", function()
  W.Setup({})
  local left, right = Names("L", 14), Names("R", 14)
  W.ns.SetLayout(Layout("Left: " .. table.concat(left, " ") .. "\nRight: " .. table.concat(right, " ")))
  W.ns.SwapHalves()
  local text = W.ns.GetDB().text
  eq(Group(text, 1), "R1 R2 R3 R4 R5", "group 1")
  eq(Group(text, 4), "L1 L2 L3 L4 L5", "group 4")
  ok(Printed("Groups 1+2+3 and 4+5+6 traded places."), "chat line")
end)

T("play groups count the raid as at least as big as the list", function()
  Join(Names("P", 15))
  eq(W.ns.PlayGroups().count, 4, "raid of 15")
  eq(W.ns.PlayGroups(28).count, 6, "list of 28")
  eq(W.ns.PlayGroups(10).count, 4, "a smaller list changes nothing")
  W.InRaid(20)
  eq(W.ns.PlayGroups(28).count, 4, "Mythic still lets in 20")
end)

T("swap without a layout asks for one", function()
  Join(Names("P", 10))
  W.ns.SwapHalves()
  eq(W.ns.GetDB().text, "", "still empty")
  ok(Printed("Paste a valid layout first."), "chat line")
end)

T("swap stops a sort in progress", function()
  local text = Scrambled(20)
  W.ns.SetLayout(text)
  W.ns.Apply(text)
  W.RunUntil(function() return W.moves >= 2 end, 30)
  ok(W.ns.IsRunning(), "sorting")
  W.ns.SwapHalves()
  ok(not W.ns.IsRunning(), "stopped")
  ok(W.ns.GetDB().text ~= text, "swapped")
end)

T("ui: /rn swap and the Swap halves button swap the halves", function()
  W.visible = true
  Join({ "Ashlyn", "Corvain" })
  W.ns.CreateUI()
  W.ns.SetLayout("Group 1: Ashlyn\nGroup 3: Corvain")
  SlashCmdList.RAIDNIGHT("swap")
  eq(W.ns.GetDB().text, "Group 1: Corvain\nGroup 3: Ashlyn", "slash command")
  local button
  for _, fr in ipairs(W.frames) do
    if fr.text_ == "Swap halves" and fr.scripts.OnClick then button = fr end
  end
  ok(button, "Swap halves button")
  button.scripts.OnClick(button)
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 3: Corvain", "button")
end)
