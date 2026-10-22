-- Boss notes from the website (Notes.lua), and boss layouts per difficulty
-- (BossLayouts.lua).

-- Two raids in the journal: Big Raid with bosses 101-103 and Small Raid with 201.
local function Journal()
  local big = { id = 1, name = "Big Raid", bosses = {} }
  for i = 1, 3 do big.bosses[i] = { id = 100 + i, encounter = 3000 + i, name = "Boss " .. i } end
  local small = { id = 2, name = "Small Raid", bosses = { { id = 201, encounter = 3101, name = "Lone Boss" } } }
  W.journal = { big, small }
end

-- A note for Lone Boss on Heroic. Only its first block holds the groups.
local NOTE = table.concat({
  "EncounterID:3101;Difficulty:Heroic;Name:Lone Boss",
  "",
  "time:0;ph:1;tag:Brannoc;spellid:370537;",
  "time:120;ph:1;tag:everyone;text:POTIONS;TTS:true;countdown:3;",
  "time:150;ph:1;tag:Brannoc Elowyn;text:Stack;",
  "time:165;ph:1;tag:Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Corvain;text:Split Left;colors:0.2 0.4 1 1;DisplayType:Text;",
  "time:165;ph:1;tag:Dúnmir Ravéna Thessaly Maelis Orrik Sylwen;text:Split Right;colors:1 0.16 0.16 1;DisplayType:Text;",
  "",
  "P2 - Group Split",
  "Left: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Corvain",
  "Right: Dúnmir Ravéna Thessaly Maelis Orrik Sylwen",
  "",
  "P1 + Int -  Coil Soaks",
  "Soak first: Brannoc Dúnmir Elowyn",
  "Soak second: Fenwick Ravéna",
  "",
  "P3 - Bite Soaks",
  "Melee: Brannoc Torvald",
  "",
  "invitelist:Brannoc-ArgentDawn,Elowyn-ArgentDawn,Dúnmir-Silvermoon;",
}, "\n")

-- Left fills groups 1-2 and Right starts in the group after.
local NOTE_LAYOUT = "Group 1: Brannoc, Elowyn, Fenwick, Isolde, Torvald\nGroup 2: Ashlyn, Corvain\n"
  .. "Group 3: Dúnmir, Ravéna, Thessaly, Maelis, Orrik\nGroup 4: Sylwen"

local function Printed(text)
  for _, line in ipairs(W.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local function Layouts(difficulty)
  return W.ns.GetDB().layouts[difficulty] or {}
end

-- The window, open, with the frame named text (a button's or a label's).
local function Window()
  W.visible = true
  local f = W.ns.CreateUI()
  f.scripts.OnShow(f)
  return f
end

local function Named(text)
  for _, fr in ipairs(W.frames) do
    if fr.text_ == text then return fr end
  end
end

-- A difficulty's radio button: the frame made just before its label.
local function Radio(name)
  for i, fr in ipairs(W.frames) do
    if fr.text_ == name then return W.frames[i - 1] end
  end
end

local function Paste(text)
  local eb
  for _, fr in ipairs(W.frames) do
    if fr.scripts.OnTextChanged then eb = fr end
  end
  local before = W.ns.GetDB().text
  eb.text_ = text
  eb.scripts.OnTextChanged(eb, true)
  ok(W.RunUntil(function() return W.ns.GetDB().text ~= before end, 5), "pasted")
end

---------------------------------------------------------------------------
-- Reading notes
---------------------------------------------------------------------------

T("notes: a note gives its boss, difficulty and the groups of its first block", function()
  local note = W.ns.ParseNote(NOTE)
  eq(note.encounter, 3101, "encounter")
  eq(note.difficulty, "heroic", "difficulty")
  eq(note.name, "Lone Boss", "name")
  local plan = W.ns.ParseInput(NOTE)
  eq(#plan.errors, 0, "errors: " .. table.concat(plan.errors, "; "))
  eq(plan.note.encounter, 3101, "plan's note")
  eq(W.ns.FormatLayout(plan.groups, plan.parked), NOTE_LAYOUT, "groups")
  local crlf = W.ns.ParseInput(NOTE:gsub("\n", "\r\n"))
  eq(W.ns.FormatLayout(crlf.groups, crlf.parked), NOTE_LAYOUT, "Windows line ends")
end)

T("notes: only text starting with EncounterID is a note", function()
  eq(W.ns.ParseNote("Left: Brannoc Elowyn\nRight: Fenwick"), nil, "named lists")
  eq(W.ns.ParseNote("Group 1: Brannoc"), nil, "groups")
  eq(W.ns.ParseNote("Name:Lone Boss;EncounterID:3101"), nil, "EncounterID not first")
  eq(W.ns.ParseInput("Left: Brannoc").note, nil, "no note on a plain paste")
end)

T("notes: a difficulty without layouts is left out", function()
  eq(W.ns.ParseNote("EncounterID:3101;Difficulty:LFR").difficulty, nil, "LFR")
  eq(W.ns.ParseNote("EncounterID:3101").difficulty, nil, "none")
  eq(W.ns.ParseNote("EncounterID:3101;Difficulty:Mythic").difficulty, "mythic", "Mythic")
end)

T("notes: the header never counts as a list", function()
  local note = W.ns.ParseNote("EncounterID:3101\nLeft: Brannoc\n\nSides\nLeft: Elowyn")
  eq(note.groups, "Left: Elowyn", "the first block after the header's")
end)

T("notes: a note without lists has no groups", function()
  local plan = W.ns.ParseInput("EncounterID:3101;Difficulty:Heroic\n\ntime:0;ph:1;tag:Brannoc;spellid:1;")
  eq(plan.count, 0, "players")
  ok(#plan.errors > 0, "an error")
end)

---------------------------------------------------------------------------
-- Pasting notes
---------------------------------------------------------------------------

T("ui: a pasted note selects its boss and difficulty and is saved at once", function()
  Journal()
  W.here = 1 -- the window opens on Big Raid
  Window()
  eq(W.ns.GetDB().difficulty, "mythic", "Mythic to start with")
  Paste(NOTE)
  eq(W.ns.GetDB().text, NOTE_LAYOUT, "layout")
  eq(W.ns.SelectedRaid().name, "Small Raid", "the note's raid")
  eq(W.ns.GetDB().difficulty, "heroic", "the note's difficulty")
  ok(Radio("Heroic").checked, "Heroic checked")
  ok(not Radio("Mythic").checked, "Mythic not checked")
  eq(Layouts("heroic")[201].text, NOTE_LAYOUT, "saved under the boss on Heroic")
  eq(Layouts("mythic")[201], nil, "not on Mythic")
  ok(Printed("Saved layout for Lone Boss (Heroic)."), "told")
end)

T("ui: Undo after a pasted note brings back the layout and the boss's layout", function()
  Journal()
  W.ns.GetDB().autoSave = false -- a note is saved, and undone, all the same
  W.ns.SetBossLayouts({ [201] = "Group 1: Isolde" }, "heroic")
  Window()
  W.ns.SetLayout("Group 1: Torvald")
  Paste(NOTE)
  eq(Layouts("heroic")[201].text, NOTE_LAYOUT, "saved")
  W.ns.SelectDifficulty("mythic") -- the row shows another difficulty by then
  W.ns.Undo()
  eq(W.ns.GetDB().text, "Group 1: Torvald", "layout back")
  eq(Layouts("heroic")[201].text, "Group 1: Isolde", "boss's layout back")
  eq(Layouts("mythic")[201], nil, "Mythic untouched")

  -- A boss with nothing saved has nothing again.
  W.ns.GetDB().layouts.heroic[201] = nil
  Paste(NOTE)
  W.ns.Undo()
  eq(Layouts("heroic")[201], nil, "nothing saved again")
end)

T("ui: a note for a boss not in the tier loads the groups but saves nothing", function()
  Journal()
  Window()
  Paste(NOTE:gsub("EncounterID:3101", "EncounterID:9999"))
  eq(W.ns.GetDB().text, NOTE_LAYOUT, "groups loaded")
  eq(next(Layouts("heroic")), nil, "nothing saved")
  ok(Printed("Lone Boss is not a boss in this tier's raids."), "told")
end)

T("ui: a note without a difficulty is saved under the one the row shows", function()
  Journal()
  Window()
  Paste(NOTE:gsub(";Difficulty:Heroic", ""))
  eq(W.ns.GetDB().difficulty, "mythic", "unchanged")
  eq(Layouts("mythic")[201].text, NOTE_LAYOUT, "saved on Mythic")
end)

---------------------------------------------------------------------------
-- Difficulties
---------------------------------------------------------------------------

T("boss layouts: layouts saved before there were difficulties are Mythic", function()
  Journal()
  W.ns.GetDB().bosses = { [101] = { text = "Group 1: Brannoc", saved = 1 } }
  eq(W.ns.RaidLayouts(1, "mythic")[101], "Group 1: Brannoc", "Mythic")
  eq(W.ns.RaidLayouts(1, "heroic")[101], false, "not Heroic")
  eq(W.ns.GetDB().bosses, nil, "moved")
end)

T("ui: the difficulty buttons switch the layouts the row shows", function()
  Journal()
  W.ns.SetBossLayouts({ [101] = "Group 1: Brannoc" }, "mythic")
  W.ns.SetBossLayouts({ [101] = "Group 1: Elowyn" }, "heroic")
  W.here = 1
  Window()
  W.ns.SelectEncounter(3001)
  local heroic = Radio("Heroic")
  heroic.scripts.OnClick(heroic)
  eq(W.ns.GetDB().text, "Group 1: Elowyn", "Heroic layout loaded")
  ok(heroic.checked and not Radio("Mythic").checked and not Radio("Normal").checked, "only Heroic checked")
  local normal = Radio("Normal")
  normal.scripts.OnClick(normal)
  eq(W.ns.GetDB().text, "Group 1: Elowyn", "nothing on Normal: the layout stays")
  W.ns.SetLayout("Group 1: Fenwick")
  local save = Named("Save")
  save.scripts.OnClick(save)
  eq(Layouts("normal")[101].text, "Group 1: Fenwick", "saved on Normal")
  eq(Layouts("heroic")[101].text, "Group 1: Elowyn", "Heroic kept")
  eq(Layouts("mythic")[101].text, "Group 1: Brannoc", "Mythic kept")
end)

T("ui: Delete removes the layout of the difficulty it was asked for", function()
  Journal()
  W.ns.SetBossLayouts({ [101] = "Group 1: Brannoc" }, "mythic")
  W.ns.SetBossLayouts({ [101] = "Group 1: Elowyn" }, "heroic")
  W.here = 1
  Window()
  W.ns.SelectEncounter(3001, "heroic")
  local delete = Named("Delete")
  delete.scripts.OnClick(delete)
  eq(W.popup.text, "Boss 1 (Heroic)", "asks for Heroic")
  W.ns.SelectDifficulty("mythic") -- the row changes before the answer
  StaticPopupDialogs[W.popup.name].OnAccept(nil, W.popup.data)
  eq(Layouts("heroic")[101], nil, "Heroic deleted")
  eq(Layouts("mythic")[101].text, "Group 1: Brannoc", "Mythic kept")
end)

T("ui: the window opens on the difficulty of the raid the player is in", function()
  Journal()
  W.InRaid(30, 14)
  Window()
  eq(W.ns.GetDB().difficulty, "normal", "Normal raid")
  ok(Radio("Normal").checked, "Normal checked")
  W.instance = nil
  W.ns.SelectDifficulty("heroic")
  local f = W.ns.CreateUI()
  f.scripts.OnShow(f)
  eq(W.ns.GetDB().difficulty, "heroic", "outside a raid it stays")
end)

T("pull: auto-save stores the groups under the raid's difficulty and picks it", function()
  Journal()
  W.Setup({ "Brannoc:1:WARRIOR:TANK", "Elowyn:2:PRIEST:HEALER" })
  W.InRaid(30, 15)
  W.Fire("ENCOUNTER_START", 3002, "Boss 2", 15, 30)
  eq(Layouts("heroic")[102].text, "Group 1: Brannoc\nGroup 2: Elowyn", "saved on Heroic")
  ok(Layouts("heroic")[102].pull, "as a pull")
  eq(Layouts("mythic")[102], nil, "not on Mythic")
  eq(W.ns.GetDB().difficulty, "heroic", "Heroic picked")
  ok(Printed("Saved the raid's groups for Boss 2 (Heroic)."), "told")

  -- Raid Finder has no layouts: nothing is saved, and the difficulty stays.
  W.InRaid(25, 17)
  W.Fire("ENCOUNTER_START", 3003, "Boss 3", 17, 25)
  eq(Layouts("heroic")[103], nil, "nothing saved")
  eq(W.ns.GetDB().difficulty, "heroic", "still Heroic")
end)

T("commands: /rn normal, heroic and mythic pick the difficulty", function()
  SlashCmdList.RAIDNIGHT("heroic")
  eq(W.ns.GetDB().difficulty, "heroic", "heroic")
  SlashCmdList.RAIDNIGHT("Normal")
  eq(W.ns.GetDB().difficulty, "normal", "normal")
  SlashCmdList.RAIDNIGHT("mythic")
  eq(W.ns.GetDB().difficulty, "mythic", "mythic")
end)

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

T("sync: a push sends one difficulty and replaces only that one", function()
  Journal()
  W.Setup({ "Lead:1:WARRIOR:TANK", "Me:1:PRIEST:HEALER" })
  W.roster[1].rank = 2
  W.me = "Lead"
  W.ns.SetBossLayouts({ [101] = "Group 1: Brannoc" }, "heroic")
  W.ns.SetBossLayouts({ [101] = "Group 1: Elowyn" }, "mythic")
  SlashCmdList.RAIDNIGHT("heroic")
  SlashCmdList.RAIDNIGHT("send")
  ok(Printed("Sent the boss layouts for Big Raid (Heroic) to the raid."), "sender told")

  W.me = "Me"
  W.ns.GetDB().layouts = {
    heroic = { [101] = { text = "Group 1: Old" }, [102] = { text = "Group 1: Old" } },
    mythic = { [101] = { text = "Group 1: Mine" }, [102] = { text = "Group 1: Mine" } },
  }
  W.Deliver("Lead")
  eq(Layouts("heroic")[101].text, "Group 1: Brannoc", "Heroic replaced")
  eq(Layouts("heroic")[102], nil, "Heroic cleared where the sender has none")
  eq(Layouts("mythic")[101].text, "Group 1: Mine", "Mythic untouched")
  eq(Layouts("mythic")[102].text, "Group 1: Mine", "Mythic not cleared")
  ok(Printed("Received boss layouts (Heroic) from Lead."), "receiver told")
end)

---------------------------------------------------------------------------
-- The note follows the groups
---------------------------------------------------------------------------

-- NOTE_LAYOUT with Corvain (Left, group 2) and Sylwen (Right, group 4) traded.
local TRADED = "Group 1: Brannoc, Elowyn, Fenwick, Isolde, Torvald\nGroup 2: Ashlyn, Sylwen\n"
  .. "Group 3: Dúnmir, Ravéna, Thessaly, Maelis, Orrik\nGroup 4: Corvain"

-- The line of text that starts with start.
local function Line(text, start)
  for line in text:gmatch("[^\n]+") do
    if line:sub(1, #start) == start then return line end
  end
end

local function Tag(text, name)
  for line in text:gmatch("[^\n]+") do
    if line:find("text:" .. name .. ";", 1, true) then return line:match("tag:([^;]*)") end
  end
end

T("notes: a note rewritten to its own groups stays as it was", function()
  eq(W.ns.RewriteNote(NOTE, NOTE_LAYOUT), NOTE, "unchanged")
  -- The raid writes players from other realms with the realm; the note keeps its own spelling.
  eq(W.ns.RewriteNote(NOTE, NOTE_LAYOUT:gsub("Ravéna", "Ravena-Draenor")), NOTE, "spelling kept")
end)

T("notes: players trading sides move between the lists and the split lines", function()
  local note = W.ns.RewriteNote(NOTE, TRADED)
  eq(Line(note, "Left:"), "Left: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Sylwen", "Left")
  eq(Line(note, "Right:"), "Right: Dúnmir Ravéna Thessaly Maelis Orrik Corvain", "Right")
  eq(Tag(note, "Split Left"), "Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Sylwen", "Split Left")
  eq(Tag(note, "Split Right"), "Dúnmir Ravéna Thessaly Maelis Orrik Corvain", "Split Right")
  eq(Tag(note, "Stack"), "Brannoc Elowyn", "a line for other players stays")
  eq(Line(note, "Soak first:"), "Soak first: Brannoc Dúnmir Elowyn", "other blocks stay")
  eq(Line(note, "invitelist:"), "invitelist:Brannoc-ArgentDawn,Elowyn-ArgentDawn,Dúnmir-Silvermoon;", "invite list stays")
  local plan = W.ns.ParseInput(note)
  eq(W.ns.FormatLayout(plan.groups, plan.parked), TRADED, "read back, the groups are the same")
end)

T("notes: when the sides trade places, so do the split lines", function()
  local swapped = "Group 1: Dúnmir, Ravéna, Thessaly, Maelis, Orrik\nGroup 2: Sylwen\n"
    .. "Group 3: Brannoc, Elowyn, Fenwick, Isolde, Torvald\nGroup 4: Ashlyn, Corvain"
  local note = W.ns.RewriteNote(NOTE, swapped)
  eq(Line(note, "Left:"), "Left: Dúnmir Ravéna Thessaly Maelis Orrik Sylwen", "Left")
  eq(Tag(note, "Split Left"), "Dúnmir Ravéna Thessaly Maelis Orrik Sylwen", "Split Left")
  eq(Tag(note, "Split Right"), "Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Corvain", "Split Right")
end)

T("notes: groups no list fills and waiting names get lines of their own", function()
  local note = W.ns.RewriteNote(NOTE, NOTE_LAYOUT .. "\nGroup 7: Quillon\nNot on list: Tamsyn")
  ok(note:find("Right: Dúnmir Ravéna Thessaly Maelis Orrik Sylwen\nGroup 7: Quillon\nNot on list: Tamsyn\n\n", 1, true),
    "after the lists")
  local plan = W.ns.ParseInput(note)
  eq(plan.groups[7][1], "Quillon", "group 7 read back")
  eq(plan.parked[1], "Tamsyn", "waiting read back")
  eq(W.ns.RewriteNote(note, NOTE_LAYOUT), NOTE, "and gone again")
end)

-- A note whose only block has three lists named for positions, not sides.
local POSITIONS = table.concat({
  "EncounterID:3101;Difficulty:Mythic;Name:Lone Boss",
  "",
  "time:30;ph:1;tag:Isolde Torvald Ashlyn;text:Healers front;",
  "",
  "P3 - Positions",
  "Melee: Brannoc Elowyn Fenwick Corvain Dúnmir Ravéna",
  "Healers - Front: Isolde Torvald Ashlyn",
  "Ranged - Back: Thessaly Maelis Orrik",
}, "\n")

T("notes: lists can have any name, and three of them fill three ranges", function()
  local note = W.ns.ParseNote(POSITIONS)
  eq(note.difficulty, "mythic", "difficulty")
  local plan = W.ns.ParseInput(POSITIONS)
  eq(#plan.errors, 0, "errors: " .. table.concat(plan.errors, "; "))
  local layout = W.ns.FormatLayout(plan.groups, plan.parked)
  eq(layout, "Group 1: Brannoc, Elowyn, Fenwick, Corvain, Dúnmir\nGroup 2: Ravéna\n"
    .. "Group 3: Isolde, Torvald, Ashlyn\nGroup 4: Thessaly, Maelis, Orrik", "groups")
  eq(W.ns.RewriteNote(POSITIONS, layout), POSITIONS, "unchanged")

  -- Ashlyn (a healer, group 3) and Orrik (ranged, group 4) trade places.
  local traded = W.ns.RewriteNote(POSITIONS, (layout:gsub("Ashlyn", "X"):gsub("Orrik", "Ashlyn"):gsub("X", "Orrik")))
  eq(Line(traded, "Healers - Front:"), "Healers - Front: Isolde Torvald Orrik", "healers")
  eq(Line(traded, "Ranged - Back:"), "Ranged - Back: Thessaly Maelis Ashlyn", "ranged")
  eq(Line(traded, "Melee:"), "Melee: Brannoc Elowyn Fenwick Corvain Dúnmir Ravéna", "melee unchanged")
  eq(Tag(traded, "Healers front"), "Isolde Torvald Orrik", "the healers' line follows")
end)

T("notes: one list alone holds the whole raid", function()
  local note = "EncounterID:3101;Difficulty:Heroic\n\nRaid\n"
    .. "Everyone: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Corvain Dúnmir Ravéna Thessaly Maelis Orrik"
  local plan = W.ns.ParseInput(note)
  eq(#plan.errors, 0, "errors")
  eq(plan.count, 12, "players")
  eq(#plan.groups[3], 2, "groups 1-3")
  -- Orrik goes to the bench, group 7.
  local back = W.ns.RewriteNote(note, "Group 1: Brannoc, Elowyn, Fenwick, Isolde, Torvald\n"
    .. "Group 2: Ashlyn, Corvain, Dúnmir, Ravéna, Thessaly\nGroup 3: Maelis\nGroup 7: Orrik")
  eq(Line(back, "Everyone:"), "Everyone: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Corvain Dúnmir Ravéna Thessaly Maelis",
    "the list")
  eq(Line(back, "Group 7:"), "Group 7: Orrik", "the bench")
  eq(W.ns.ParseInput(back).groups[7][1], "Orrik", "read back")
end)

T("notes: a player's own timeline lines stay theirs when a list has one player", function()
  local note = "EncounterID:3101;Difficulty:Heroic\n\ntime:10;ph:1;tag:Brannoc;spellid:31821;\n\n"
    .. "Sides\nLeft: Brannoc\nRight: Elowyn"
  local back = W.ns.RewriteNote(note, "Group 1: Elowyn\nGroup 2: Brannoc")
  eq(Line(back, "Left:"), "Left: Elowyn", "the list changes")
  eq(Line(back, "time:10"), "time:10;ph:1;tag:Brannoc;spellid:31821;", "the cooldown stays Brannoc's")
end)

T("notes: a list split by commas keeps its commas", function()
  local note = "EncounterID:3101\n\nSides\nLeft: Brannoc, Elowyn\nRight: Fenwick"
  eq(W.ns.RewriteNote(note, "Group 1: Brannoc, Fenwick\nGroup 2: Elowyn"),
    "EncounterID:3101\n\nSides\nLeft: Brannoc, Fenwick\nRight: Elowyn", "commas")
end)

-- The note window, opened with /rn note, and its text box.
local function NoteWindow()
  SlashCmdList.RAIDNIGHT("note")
  local box
  for _, fr in ipairs(W.frames) do
    if fr.scripts.OnTextChanged then box = fr end -- the last one made: the note's
  end
  local frame = box:GetParent():GetParent()
  frame.scripts.OnShow(frame)
  return box
end

local function Type(box, text)
  box.text_ = text
  box.scripts.OnTextChanged(box, true)
end

local function Shown(text)
  for _, fr in ipairs(W.frames) do
    if type(fr.text_) == "string" and fr.text_:find(text, 1, true) then return true end
  end
  return false
end

T("ui: a change to the groups rewrites the note and the note window", function()
  Journal()
  Window()
  Paste(NOTE)
  local box = NoteWindow()
  eq(box.text_, NOTE, "the pasted note")
  W.ns.SetLayout(TRADED) -- as a drag in the grid does
  eq(Line(W.ns.GetDB().note, "Left:"), "Left: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Sylwen", "note")
  eq(box.text_, W.ns.GetDB().note, "window")
end)

T("ui: edits in the note window wait for Apply", function()
  Journal()
  Window()
  local box = NoteWindow()
  Type(box, NOTE)
  eq(W.ns.GetDB().note, NOTE, "the working note")
  eq(W.ns.GetDB().text, "", "the groups wait")
  local apply = Named("Apply")
  apply.scripts.OnClick(apply)
  eq(W.ns.GetDB().text, NOTE_LAYOUT, "applied")
  eq(Layouts("heroic")[201].note, NOTE, "saved with the boss")
  eq(W.ns.GetDB().difficulty, "heroic", "the note's difficulty")

  Type(box, "Left: Brannoc")
  apply.scripts.OnClick(apply)
  ok(Shown("Not a boss note"), "told")
  eq(W.ns.GetDB().text, NOTE_LAYOUT, "groups unchanged")
end)

T("commands: /rn note apply takes the working note", function()
  Journal()
  Window()
  W.ns.GetDB().note = NOTE
  SlashCmdList.RAIDNIGHT("note apply")
  eq(W.ns.GetDB().text, NOTE_LAYOUT, "applied")
  W.ns.GetDB().note = "Group 1: Brannoc"
  SlashCmdList.RAIDNIGHT("note apply")
  ok(Printed("Not a boss note"), "told in the chat with the window closed")
end)

T("ui: a boss loads its note, and a boss without one clears it", function()
  Journal()
  W.ns.SetBossLayouts({ [201] = NOTE_LAYOUT }, "heroic")
  W.ns.GetDB().layouts.heroic[201].note = NOTE
  W.ns.SetBossLayouts({ [101] = "Group 1: Brannoc" }, "heroic")
  W.ns.GetDB().difficulty = "heroic"
  W.here = 2
  Window()
  local function Click(id)
    for _, fr in ipairs(W.frames) do
      if fr.boss and fr.boss.id == id then return fr.scripts.OnClick(fr) end
    end
    error("no button for " .. id)
  end
  Click(201)
  eq(W.ns.GetDB().note, NOTE, "the boss's note")
  W.ns.SelectEncounter(3001)
  Click(101)
  eq(W.ns.GetDB().note, nil, "no note")
end)

T("boss layouts: Save keeps the note only with its own boss", function()
  Journal()
  Window()
  Paste(NOTE)
  W.ns.SelectEncounter(3001)
  local save = Named("Save")
  save.scripts.OnClick(save)
  eq(Layouts("heroic")[101].text, NOTE_LAYOUT, "groups saved")
  eq(Layouts("heroic")[101].note, nil, "not another boss's note")
  W.ns.SelectEncounter(3101)
  W.ns.SetLayout(TRADED)
  save.scripts.OnClick(save)
  eq(Line(Layouts("heroic")[201].note, "Left:"), "Left: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn Sylwen", "its own")
end)

T("ui: Undo brings back the note, and Clear empties it", function()
  Journal()
  Window()
  Paste(NOTE)
  -- The second note differs outside its lists too, where groups can't put it back.
  Paste((NOTE:gsub("Corvain", "Quillon"):gsub("POTIONS", "HEALTHSTONES")))
  W.ns.Undo()
  eq(W.ns.GetDB().note, NOTE, "note back")
  local clear = Named("Clear")
  clear.scripts.OnClick(clear)
  eq(W.ns.GetDB().note, nil, "cleared")
end)

T("pull: the saved note follows the pulled groups", function()
  Journal()
  W.ns.SetBossLayouts({ [201] = NOTE_LAYOUT }, "heroic")
  W.ns.GetDB().layouts.heroic[201].note = NOTE
  local players = {}
  for g, line in ipairs({ "Brannoc Elowyn Fenwick Isolde Torvald", "Ashlyn Sylwen",
                          "Dúnmir Ravéna Thessaly Maelis Orrik", "Corvain" }) do
    for name in line:gmatch("%S+") do players[#players + 1] = ("%s:%d:MAGE:DAMAGER"):format(name, g) end
  end
  W.Setup(players)
  W.InRaid(30, 15)
  W.Fire("ENCOUNTER_START", 3101, "Lone Boss", 15, 30)
  eq(Layouts("heroic")[201].text, TRADED, "groups saved")
  eq(Tag(Layouts("heroic")[201].note, "Split Right"), "Dúnmir Ravéna Thessaly Maelis Orrik Corvain", "note follows")
end)

T("sync: a received layout keeps the receiver's note, rewritten", function()
  Journal()
  W.Setup({ "Lead:1:WARRIOR:TANK", "Me:1:PRIEST:HEALER" })
  W.roster[1].rank = 2
  W.me = "Lead"
  W.here = 2 -- in Small Raid, so /rn send sends it
  W.ns.SetBossLayouts({ [201] = TRADED }, "heroic")
  SlashCmdList.RAIDNIGHT("heroic")
  SlashCmdList.RAIDNIGHT("send")
  W.me = "Me"
  W.ns.GetDB().layouts = { heroic = { [201] = { text = NOTE_LAYOUT, note = NOTE } } }
  W.Deliver("Lead")
  eq(Layouts("heroic")[201].text, TRADED, "groups replaced")
  eq(Line(Layouts("heroic")[201].note, "Right:"), "Right: Dúnmir Ravéna Thessaly Maelis Orrik Corvain", "note follows")
end)
