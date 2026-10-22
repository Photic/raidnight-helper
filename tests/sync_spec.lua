-- Sending boss layouts to the raid (Sync.lua).

local NAMES = { "Brannoc", "Elowyn", "Fenwick-ArgentDawn", "Isolde", "Torvald", "Ashlyn",
  "Corvain", "Dúnmir", "Ravéna", "Thessaly", "Maelis-TwistingNether", "Orrik", "Sylwen",
  "Kaelthos", "Vorrigan", "Lysandre-Silvermoon", "Tamsyn", "Grimbald", "Neriah", "Quillon",
  "Bastienne", "Halvard-Draenor", "Éowynne", "Pellimore" }

-- Two raids in the journal: Big Raid with bosses 101-109 and Small Raid with 201.
local function Journal()
  local big = { id = 1, name = "Big Raid", bosses = {} }
  for i = 1, 9 do big.bosses[i] = { id = 100 + i, encounter = 3000 + i, name = "Boss " .. i } end
  local small = { id = 2, name = "Small Raid", bosses = { { id = 201, encounter = 3101, name = "Lone Boss" } } }
  W.journal = { big, small }
end

-- Lead leads the raid; Me and Pug are members.
local function Raid()
  W.Setup({ "Lead:1:WARRIOR:TANK", "Me:1:PRIEST:HEALER", "Pug:2:MAGE:DAMAGER" })
  W.roster[1].rank = 2
end

-- A layout of size players (20 if not given) from names (NAMES if not
-- given), starting at the from-th.
local function Layout(from, names, size)
  names = names or NAMES
  local groups = {}
  for i = 0, (size or 20) - 1 do
    local g = math.floor(i / 5) + 1
    groups[g] = groups[g] or {}
    table.insert(groups[g], names[(from + i - 1) % #names + 1])
  end
  return W.ns.FormatLayout(groups)
end

local function Printed(text)
  for _, line in ipairs(W.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

-- The push in the messages sent, put back together.
local function Push()
  local parts = {}
  for _, m in ipairs(W.sent) do parts[#parts + 1] = m.text:match("^%d+:%d+/%d+:(.*)$") end
  return table.concat(parts)
end

-- Lead sends layouts; then the test goes on as Me, with saved layouts mine.
local function LeadSends(layouts, mine)
  W.me = "Lead"
  W.ns.SetBossLayouts(layouts)
  W.ns.SendLayouts()
  W.me = "Me"
  W.ns.GetDB().bosses = mine or {}
end

T("sync: layouts come through the encoding as they were", function()
  local layouts = {
    [101] = "Group 1: Brannoc, Dúnmir-ArgentDawn\nGroup 3: Ravéna", -- group 2 empty
    [102] = false,
    [103] = Layout(1),
    [104] = "Group 8: Torvald",
    [105] = "Group 2: Isolde\nNot on list: Ashlyn, Fenwick-ArgentDawn",
    [106] = "Not on list: Corvain",
  }
  local back = W.ns.DecodeLayouts(W.ns.EncodeLayouts(layouts))
  local n = 0
  for id, text in pairs(back) do
    eq(text, layouts[id], "boss " .. id)
    n = n + 1
  end
  eq(n, 6, "bosses")
  eq(W.ns.DecodeLayouts("not a push"), nil, "not a push")
  eq(W.ns.DecodeLayouts("Brannoc;101:AB"), nil, "index past the names")
end)

T("sync: a push replaces the raid's layouts and leaves other raids alone", function()
  Journal()
  Raid()
  LeadSends({ [101] = Layout(1), [105] = Layout(3) },
    { [101] = { text = "Group 1: Old" }, [102] = { text = "Group 1: Old" }, [201] = { text = "Group 1: Small" } })
  ok(Printed("Sent the boss layouts for Big Raid to the raid."), "sender told")
  W.Deliver("Lead-Home")
  local bosses = W.ns.GetDB().bosses
  eq(bosses[101].text, Layout(1), "101 replaced")
  eq(bosses[105].text, Layout(3), "105 added")
  eq(bosses[102], nil, "102 cleared: the sender has none")
  eq(bosses[201].text, "Group 1: Small", "the other raid stays")
  ok(Printed("Received boss layouts from Lead."), "receiver told")
end)

T("sync: all bosses of a big raid fit in 3 messages", function()
  Journal()
  Raid()
  local layouts = {}
  for i = 1, 9 do layouts[100 + i] = Layout(i * 2) end
  LeadSends(layouts)
  ok(#W.sent >= 2 and #W.sent <= 3, "messages: " .. #W.sent)
  for i, m in ipairs(W.sent) do
    eq(m.prefix, "RaidnightHelper", "prefix")
    eq(m.channel, "RAID", "channel")
    ok(m.text:find("^1:" .. i .. "/" .. #W.sent .. ":"), "header " .. m.text:sub(1, 8))
  end
  W.Deliver("Lead")
  for id, text in pairs(layouts) do eq(W.ns.GetDB().bosses[id].text, text, "boss " .. id) end
end)

T("sync: a part never ends inside a character", function()
  Journal()
  Raid()
  -- Names of an ASCII letter and 2-byte letters, so a cut after 240 bytes
  -- would fall inside one.
  local names = {}
  for i = 1, 20 do names[i] = string.char(64 + i) .. ("é"):rep(6) end
  local layouts = { [101] = Layout(1, names) }
  local byte = W.ns.EncodeLayouts(layouts):byte(241)
  ok(byte >= 128 and byte < 192, "byte 241 continues a character")
  LeadSends(layouts)
  ok(#W.sent >= 2, "more than one part")
  for _, m in ipairs(W.sent) do
    local first = m.text:match("^%d+:%d+/%d+:(.*)$"):byte(1)
    ok(not (first >= 128 and first < 192), "part starts inside a character")
  end
  W.Deliver("Lead")
  eq(W.ns.GetDB().bosses[101].text, layouts[101], "names whole")
end)

T("sync: only the raid leader and assistants are listened to", function()
  Journal()
  Raid()
  LeadSends({ [101] = Layout(1) })
  local push = W.sent
  W.Deliver("Pug")
  eq(W.ns.GetDB().bosses[101], nil, "not from a member")
  W.Deliver("Stranger")
  eq(W.ns.GetDB().bosses[101], nil, "not from someone outside the raid")
  local whispers = {}
  for i, m in ipairs(push) do whispers[i] = { prefix = m.prefix, text = m.text, channel = "WHISPER" } end
  W.Deliver("Lead", whispers)
  eq(W.ns.GetDB().bosses[101], nil, "not as a whisper")
  W.roster[3].rank = 1
  W.Deliver("Pug")
  eq(W.ns.GetDB().bosses[101].text, Layout(1), "from an assistant")
end)

T("sync: the sender's own push does not come back in", function()
  Journal()
  Raid()
  W.me = "Lead"
  W.ns.SetBossLayouts({ [101] = Layout(1) })
  W.ns.SendLayouts()
  W.ns.GetDB().bosses = {}
  W.Deliver("Lead")
  eq(W.ns.GetDB().bosses[101], nil, "own push ignored")
  ok(not Printed("Received"), "nothing received")
end)

T("sync: a push missing a part is dropped, and sending again lands", function()
  Journal()
  Raid()
  -- Short names, so the first part alone already holds whole bosses.
  local names = {}
  for i = 1, 40 do names[i] = "P" .. i end
  local layouts = {}
  for i = 1, 9 do layouts[100 + i] = Layout(i, names, 40) end
  LeadSends(layouts)
  local sent = W.sent
  eq(#sent, 3, "three parts")
  W.Deliver("Lead", { sent[2], sent[3] })
  eq(next(W.ns.GetDB().bosses), nil, "nothing without part 1")
  W.Deliver("Lead", { sent[1], sent[3] })
  eq(next(W.ns.GetDB().bosses), nil, "nothing without part 2")
  W.Deliver("Lead", sent)
  eq(W.ns.GetDB().bosses[101].text, layouts[101], "the whole push lands")
end)

T("sync: sending is refused outside a raid, in Raid Finder, without lead and in combat", function()
  Journal()
  W.ns.SetBossLayouts({ [101] = Layout(1) })
  W.ns.SendLayouts()
  ok(Printed("You are not in a raid."), "not in a raid")
  Raid()
  W.raidFinder = true
  W.ns.SendLayouts()
  ok(Printed("Layouts can't be sent in Raid Finder."), "Raid Finder")
  W.raidFinder = false
  W.lead = false
  W.ns.SendLayouts()
  ok(Printed("Only the raid leader and assistants can send layouts."), "not lead")
  W.lead = true
  W.inCombat = true
  W.ns.SendLayouts()
  ok(Printed("Layouts can't be sent in combat."), "combat")
  eq(#W.sent, 0, "nothing sent")
end)

T("sync: a message the game refuses is reported", function()
  Journal()
  Raid()
  W.sendResult = 3 -- Enum.SendAddonMessageResult.AddonMessageThrottle
  W.ns.SetBossLayouts({ [101] = Layout(1) })
  W.ns.SendLayouts()
  ok(Printed("The game refused to send the layouts."), "refusal reported")
  ok(not Printed("Sent the boss layouts"), "no claim it was sent")
end)

T("sync: more than 64 players can't be sent", function()
  Journal()
  Raid()
  local names = {}
  for i = 1, 65 do names[i] = "P" .. i end
  local layouts = {}
  for i = 1, 4 do layouts[100 + i] = Layout((i - 1) * 20 + 1, names) end
  W.ns.SetBossLayouts(layouts)
  W.ns.SendLayouts()
  ok(Printed("Too many players in the layouts to send (max 64)."), "refused")
  eq(#W.sent, 0, "nothing sent")
end)

T("sync: a push from a newer version asks to update", function()
  Raid()
  W.Deliver("Lead", { { prefix = "RaidnightHelper", text = "2:1/1:anything", channel = "RAID" } })
  ok(Printed("Lead sent layouts from a newer version of Raidnight Helper."), "update hint")
end)

T("ui: Send uses the raid shown, /rn send the raid the window opens on", function()
  Journal()
  Raid()
  W.me = "Lead"
  W.ns.GetDB().lastBoss = { raid = 2, boss = 201 }
  W.ns.SetBossLayouts({ [101] = Layout(1), [201] = Layout(2) })

  -- The window opens on the raid of the boss pulled last.
  W.visible = true
  local f = W.ns.CreateUI()
  f.scripts.OnShow(f)
  local send
  for _, fr in ipairs(W.frames) do
    if fr.text_ == "Send" then send = fr end
  end
  ok(send, "Send button")
  -- Inside Big Raid now, but the window still shows Small Raid.
  W.here = 1
  send.scripts.OnClick(send)
  ok(Printed("Sent the boss layouts for Small Raid to the raid."), "the raid shown")
  local layouts = W.ns.DecodeLayouts(Push())
  eq(layouts[201], Layout(2), "Small Raid's boss")
  eq(layouts[101], nil, "not Big Raid's")

  -- With the window closed it would open on the raid the player is in.
  W.sent = {}
  W.visible = false
  SlashCmdList.RAIDNIGHT("send")
  ok(Printed("Sent the boss layouts for Big Raid to the raid."), "the raid the player is in")
  eq(W.ns.DecodeLayouts(Push())[101], Layout(1), "Big Raid's boss")
end)
