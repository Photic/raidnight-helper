-- BossLayouts
-- A row of boss icons at the top of the Raidnight Helper window. Each boss keeps one
-- layout per difficulty: Save stores the current layout under the selected boss, and clicking
-- a boss loads its layout back into the grid. A pull selects that boss, and
-- with auto-save on, it also stores the raid's actual groups under it. Send
-- shares the raid's layouts with the rest of the raid (see Sync.lua).
--
-- Each difficulty (Normal, Heroic, Mythic) has layouts of its own. Radio
-- buttons next to the dropdown pick the difficulty the row shows; the icons,
-- Save, Delete and Send work on that one. Opening the window inside a raid,
-- or a pull, picks the raid's difficulty.
--
-- Bosses come from the Encounter Journal, so the row follows the current tier
-- without hardcoded names. Layouts are keyed by difficulty and journal
-- encounter ID, which is the same in every client language, and live in
-- RaidnightHelperDB.layouts:
--
--   [difficulty][journalEncounterID] = { text = "Group 1: ...", saved = <time()>, pull = true|nil,
--                                        note = <boss note>|nil }
--
-- difficulty is "normal", "heroic" or "mythic", and RaidnightHelperDB.difficulty
-- is the one the row shows. Layouts saved before there were difficulties
-- are Mythic ones. A layout keeps the boss note it came from (see
-- NoteWindow.lua), and whatever changes the layout's groups rewrites the
-- note's groups to match.
--
-- RaidnightHelperDB.lastBoss = { raid = journalInstanceID, boss = journalEncounterID }
-- remembers the boss pulled last, so it is selected again after a reload.

local _, ns = ...
local L = ns.L

local ICON_WIDTH   = 64   -- journal boss portraits are twice as wide as tall
local ICON_GAP     = 6
local DEFAULT_ICON = "Interface\\EncounterJournal\\UI-EJ-BOSS-Default"

-- The difficulties with layouts, in the order of the radio buttons, with the
-- game's names for them and the difficulty IDs the game gives raids.
local DIFFICULTIES     = { "normal", "heroic", "mythic" }
local DIFFICULTY_NAMES = { normal = PLAYER_DIFFICULTY1, heroic = PLAYER_DIFFICULTY2, mythic = PLAYER_DIFFICULTY6 }
local DIFFICULTY_IDS   = { [14] = "normal", [15] = "heroic", [16] = "mythic" }

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

local bar = { raids = {}, bosses = {}, buttons = {}, radios = {} }

-- The game's name for difficulty ("normal", "heroic" or "mythic"), or nil
-- for anything else.
function ns.DifficultyName(difficulty)
  return DIFFICULTY_NAMES[difficulty]
end

-- The difficulty the row shows.
local function Difficulty()
  return ns.GetDB().difficulty
end

-- The saved layouts for difficulty, or for the one the row shows.
local function Layouts(difficulty)
  local db = ns.GetDB()
  if not db.layouts then
    -- Layouts saved before there were difficulties are Mythic ones.
    db.layouts = { mythic = db.bosses }
    db.bosses = nil
  end
  difficulty = difficulty or Difficulty()
  db.layouts[difficulty] = db.layouts[difficulty] or {}
  return db.layouts[difficulty]
end

-- A boss's name with a difficulty, the one the row shows if not given:
-- "Vexmora (Heroic)".
local function BossLabel(boss, difficulty)
  return ("%s (%s)"):format(boss.name, DIFFICULTY_NAMES[difficulty or Difficulty()])
end

local function SelectedBoss()
  for _, boss in ipairs(bar.bosses) do
    if boss.id == bar.selected then return boss end
  end
end

---------------------------------------------------------------------------
-- Encounter Journal
---------------------------------------------------------------------------

-- Raids in the newest journal tier that has any. Raids without bosses are
-- skipped; the journal lists the tier's world bosses as one such raid.
local function LoadRaids()
  local raids = {}
  local previous = EJ_GetCurrentTier()
  for tier = EJ_GetNumTiers(), 1, -1 do
    EJ_SelectTier(tier)
    local i = 1
    while true do
      local id, name = EJ_GetInstanceByIndex(i, true)
      if not id then break end
      if EJ_GetEncounterInfoByIndex(1, id) then
        raids[#raids + 1] = { id = id, name = name }
      end
      i = i + 1
    end
    if #raids > 0 then break end
  end
  if previous then EJ_SelectTier(previous) end -- leave the Encounter Journal as it was
  return raids
end

-- id is the journal encounter ID; encounter is the ID ENCOUNTER_START reports.
local function LoadBosses(instanceID)
  local bosses = {}
  local i = 1
  while true do
    local name, _, journalID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(i, instanceID)
    if not name then break end
    local _, _, _, _, icon = EJ_GetCreatureInfo(1, journalID)
    bosses[#bosses + 1] = { id = journalID, encounter = encounterID, name = name, icon = icon }
    i = i + 1
  end
  return bosses
end

-- Journal ID of the instance the player is in, if any.
local function CurrentInstance()
  local map = C_Map.GetBestMapForUnit("player")
  local id = map and EJ_GetInstanceForMap(map)
  if id and id ~= 0 then return id end
end

-- The difficulty of the raid the player is in: nil outside a raid, and in
-- Raid Finder and other difficulties without layouts.
local function InstanceDifficulty()
  local _, kind, difficultyID = GetInstanceInfo()
  if kind == "raid" and not issecret(difficultyID) then return DIFFICULTY_IDS[difficultyID] end
end

-- The current tier's boss, and its raid, for an ENCOUNTER_START encounter ID.
local function BossForEncounter(encounterID)
  if #bar.raids == 0 then bar.raids = LoadRaids() end
  for _, raid in ipairs(bar.raids) do
    for _, boss in ipairs(LoadBosses(raid.id)) do
      if boss.encounter == encounterID then return boss, raid end
    end
  end
end

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------

local function UpdateButtons()
  local layouts = Layouts()
  for i, b in ipairs(bar.buttons) do
    local boss = bar.bosses[i]
    b.boss = boss
    if boss then
      local saved = layouts[boss.id] ~= nil
      b.icon:SetTexture(boss.icon or DEFAULT_ICON)
      b.icon:SetDesaturated(not saved) -- faded = nothing saved yet
      b.icon:SetAlpha(saved and 1 or 0.5)
      b.border:SetShown(boss.id == bar.selected)
    end
    b:SetShown(boss ~= nil)
  end
  for difficulty, radio in pairs(bar.radios) do radio:SetChecked(difficulty == Difficulty()) end
  bar.save:SetEnabled(bar.selected ~= nil)
  bar.delete:SetEnabled(bar.selected ~= nil and layouts[bar.selected] ~= nil)
end

-- Loads a saved layout into the grid, and its note, or none, as the working
-- note.
local function Load(layout)
  ns.GetDB().note = layout.note
  ns.SetLayout(layout.text)
end

local function OnBossClick(self)
  bar.selected = self.boss.id
  local layout = Layouts()[self.boss.id]
  if layout then Load(layout) end
  UpdateButtons()
end

local function OnBossEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:SetText(BossLabel(self.boss))
  local layout = Layouts()[self.boss.id]
  if layout then
    local when = date("%Y-%m-%d %H:%M", layout.saved)
    GameTooltip:AddLine((layout.pull and L["Saved at pull: %s"] or L["Saved: %s"]):format(when), 1, 1, 1)
  else
    GameTooltip:AddLine(L["Nothing saved yet."], 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

local function GetButton(i)
  if bar.buttons[i] then return bar.buttons[i] end
  local b = CreateFrame("Button", nil, bar.row)
  -- The gold border shows around the dark background; portraits are see-through.
  b.border = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.border:SetColorTexture(1, 0.82, 0)
  b.border:SetPoint("TOPLEFT", -2, 2)
  b.border:SetPoint("BOTTOMRIGHT", 2, -2)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.05, 0.05, 0.05)
  bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnClick", OnBossClick)
  b:SetScript("OnEnter", OnBossEnter)
  b:SetScript("OnLeave", GameTooltip_Hide)
  bar.buttons[i] = b
  return b
end

-- Shrinks the icons when a raid has too many bosses for one row.
local function LayoutButtons()
  local n = #bar.bosses
  local w = ICON_WIDTH
  if n > 0 then
    w = math.min(w, math.floor((bar.row:GetWidth() + ICON_GAP) / n) - ICON_GAP)
  end
  for i = 1, n do
    local b = GetButton(i)
    b:SetSize(w, w / 2)
    b:ClearAllPoints()
    b:SetPoint("LEFT", (i - 1) * (w + ICON_GAP), 0)
  end
end

local function SelectRaid(id)
  if bar.raid ~= id then
    bar.raid = id
    bar.bosses = LoadBosses(id)
    bar.selected = nil
  end
  LayoutButtons()
  UpdateButtons()
  bar.dropdown:GenerateMenu()
end

local function HasRaid(id)
  for _, raid in ipairs(bar.raids) do
    if raid.id == id then return true end
  end
  return false
end

-- The raid the dropdown opens on: the raid the player is in, else the raid
-- shown last, else the raid of the boss pulled last, else the first.
local function TargetRaid()
  if #bar.raids == 0 then bar.raids = LoadRaids() end
  local last = ns.GetDB().lastBoss
  local here = CurrentInstance()
  return (HasRaid(here) and here) or bar.raid
    or (last and HasRaid(last.raid) and last.raid) or (bar.raids[1] and bar.raids[1].id)
end

-- Shows the raid TargetRaid picks, at the difficulty of the raid the player
-- is in, if any. The boss pulled last is selected after a new pull, or when
-- no boss is selected yet.
local function Refresh()
  ns.GetDB().difficulty = InstanceDifficulty() or Difficulty()
  local last = ns.GetDB().lastBoss
  local target = TargetRaid()
  if not target then
    -- Right after login or a reload the Encounter Journal can come back
    -- empty, so it is asked again shortly while the window is open.
    C_Timer.After(1, function()
      if #bar.raids == 0 and bar.row:IsVisible() then Refresh() end
    end)
    return UpdateButtons()
  end
  SelectRaid(target)
  if last and last.raid == target and (bar.pulled or not bar.selected) then
    bar.selected = last.boss
    UpdateButtons()
  end
  bar.pulled = false
end

local function SaveSelected()
  local boss = SelectedBoss()
  if not boss then return end
  local text = ns.GetDB().text
  local plan = ns.ParseInput(text)
  if plan.empty then
    ns.SetStatus(L["Paste a layout first."])
    return
  end
  if #plan.errors > 0 then
    ns.SetStatus("|cffff5555" .. table.concat(plan.errors, "\n") .. "|r")
    return
  end
  ns.SaveToSelectedBoss(text)
end

-- Stores text under the boss selected in the bar, at the difficulty the row
-- shows, with the working note when it is that boss's. Returns true when
-- saved.
function ns.SaveToSelectedBoss(text)
  local boss = SelectedBoss()
  if not boss then return false end
  local note = ns.GetDB().note
  local parsed = note and ns.ParseNote(note)
  if not (parsed and parsed.encounter == boss.encounter) then note = nil end
  Layouts()[boss.id] = { text = text, saved = time(), note = note }
  UpdateButtons()
  ns.Print(L["Saved layout for %s."]:format(BossLabel(boss)))
  return true
end

-- The selected boss's journal ID, the difficulty the row shows and the
-- boss's saved layout for it (nil when it has none), so Undo can put the
-- layout back.
function ns.SelectedBossLayout()
  local boss = SelectedBoss()
  if boss then return boss.id, Difficulty(), Layouts()[boss.id] end
end

-- Puts back a boss's saved layout from ns.SelectedBossLayout; nil removes it.
function ns.RestoreBossLayout(id, difficulty, layout)
  Layouts(difficulty)[id] = layout
  if bar.row then UpdateButtons() end
end

-- The raid in the dropdown, as { id, name }: the one shown while the window
-- is open, else the one it opens on.
function ns.SelectedRaid()
  local id = (bar.row and bar.row:IsVisible() and bar.raid) or TargetRaid()
  for _, raid in ipairs(bar.raids) do
    if raid.id == id then return raid end
  end
end

-- The difficulty the row shows, and the game's name for it.
function ns.SelectedDifficulty()
  return Difficulty(), DIFFICULTY_NAMES[Difficulty()]
end

-- Shows the layouts for difficulty, and loads the selected boss's layout
-- for it, as a click on the boss does.
function ns.SelectDifficulty(difficulty)
  ns.GetDB().difficulty = difficulty
  local boss = SelectedBoss()
  local layout = boss and Layouts()[boss.id]
  if layout then Load(layout) end
  if bar.row then UpdateButtons() end
end

-- Selects the boss with an ENCOUNTER_START encounter ID, in its raid, and
-- difficulty when given. Returns false when the boss is not in the tier.
function ns.SelectEncounter(encounterID, difficulty)
  local boss, raid = BossForEncounter(encounterID)
  if not boss then return false end
  if difficulty then ns.GetDB().difficulty = difficulty end
  SelectRaid(raid.id)
  bar.selected = boss.id
  UpdateButtons()
  return true
end

-- Every boss of a raid as { [journalID] = layout text, or false when nothing
-- is saved }, for a difficulty.
function ns.RaidLayouts(raidID, difficulty)
  local layouts = {}
  for _, boss in ipairs(LoadBosses(raidID)) do
    local layout = Layouts(difficulty)[boss.id]
    layouts[boss.id] = layout and layout.text or false
  end
  return layouts
end

-- Stores layouts in the shape ns.RaidLayouts gives them, for difficulty or
-- the one the row shows; false removes a boss's layout. A boss's note
-- stays, with its groups rewritten to the new layout.
function ns.SetBossLayouts(layouts, difficulty)
  local stored = Layouts(difficulty)
  for id, text in pairs(layouts) do
    local note = stored[id] and stored[id].note
    stored[id] = text and { text = text, saved = time(), note = note and ns.RewriteNote(note, text) } or nil
  end
  if bar.row then UpdateButtons() end
end

-- data is { boss, difficulty }: the difficulty is kept, as the row can show
-- another by the time the popup is answered.
StaticPopupDialogs.RAIDNIGHT_DELETE_LAYOUT = {
  text = L["Delete the saved layout for %s?"],
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, data)
    Layouts(data.difficulty)[data.boss.id] = nil
    UpdateButtons()
    ns.Print(L["Deleted layout for %s."]:format(BossLabel(data.boss, data.difficulty)))
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function DeleteSelected()
  local boss = SelectedBoss()
  if boss then
    StaticPopup_Show("RAIDNIGHT_DELETE_LAYOUT", BossLabel(boss), nil, { boss = boss, difficulty = Difficulty() })
  end
end

function ns.CreateBossBar(f)

  local dropdown = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("TOPLEFT", 14, -30)
  dropdown:SetWidth(200)
  dropdown:SetupMenu(function(_, root)
    for _, raid in ipairs(bar.raids) do
      root:CreateRadio(raid.name, function() return raid.id == bar.raid end, function() SelectRaid(raid.id) end)
    end
  end)

  local delete = ns.MakeButton(f, L["Delete"], 80)
  delete:SetPoint("TOPRIGHT", -12, -30)
  delete:SetScript("OnClick", DeleteSelected)

  local save = ns.MakeButton(f, L["Save"], 80)
  save:SetPoint("RIGHT", delete, "LEFT", -6, 0)
  save:SetScript("OnClick", SaveSelected)

  local send = ns.MakeButton(f, L["Send"], 80)
  send:SetPoint("RIGHT", save, "LEFT", -6, 0)
  send:SetScript("OnClick", function() ns.SendLayouts() end)
  send:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["Send"])
    GameTooltip:AddLine(L["Send this raid's boss layouts for the selected difficulty to the raid. Everyone with Raidnight Helper gets yours in place of their own."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  send:SetScript("OnLeave", GameTooltip_Hide)

  -- The difficulties go between the dropdown and Send. A click on a name
  -- picks it too. The window widens when the names need more room.
  local width = 14 + dropdown:GetWidth() + 12 + send:GetWidth() + save:GetWidth() + delete:GetWidth() + 2 * 6 + 12
  local previous
  for _, difficulty in ipairs(DIFFICULTIES) do
    local radio = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
    radio:SetSize(16, 16)
    if previous then
      radio:SetPoint("LEFT", previous, "RIGHT", 10, 0)
    else
      radio:SetPoint("LEFT", dropdown, "RIGHT", 12, 0)
    end
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", radio, "RIGHT", 3, 0)
    label:SetText(DIFFICULTY_NAMES[difficulty])
    radio:SetHitRectInsets(0, -(3 + label:GetStringWidth()), 0, 0)
    radio:SetScript("OnClick", function() ns.SelectDifficulty(difficulty) end)
    bar.radios[difficulty] = radio
    previous = label
    width = width + 16 + 3 + label:GetStringWidth() + 10
  end
  f:SetWidth(math.max(f:GetWidth(), width))

  local row = CreateFrame("Frame", nil, f)
  row:SetPoint("TOPLEFT", 16, -62)
  row:SetPoint("TOPRIGHT", -16, -62)
  row:SetHeight(ICON_WIDTH / 2)

  local auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  auto:SetSize(24, 24)
  auto:SetPoint("TOPLEFT", 10, -98)
  auto:SetChecked(ns.GetDB().autoSave)
  auto:SetScript("OnClick", function(self)
    ns.GetDB().autoSave = self:GetChecked() and true or false
  end)
  local autoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  autoLabel:SetPoint("LEFT", auto, "RIGHT", 2, 0)
  autoLabel:SetText(L["Save the raid's groups to the boss on pull"])

  bar.dropdown, bar.save, bar.delete, bar.row = dropdown, save, delete, row
  f:HookScript("OnShow", Refresh)
end

---------------------------------------------------------------------------
-- Auto-save on pull
---------------------------------------------------------------------------

local lastGroups -- the raid's groups from the last time the roster could be read

-- The raid's groups as { [group] = { names } }, or nil if any of the roster
-- can't be read.
function ns.RaidGroups()
  local groups = {}
  for i = 1, GetNumGroupMembers() or 0 do
    local name, _, subgroup = GetRaidRosterInfo(i)
    if not name or not subgroup or issecret(name) or issecret(subgroup) then return end
    groups[subgroup] = groups[subgroup] or {}
    table.insert(groups[subgroup], name)
  end
  return groups
end

-- The raid's groups as layout text, or nil if any of the roster can't be read.
function ns.ReadGroups()
  local groups = ns.RaidGroups()
  if not groups then return end
  local text = ns.FormatLayout(groups)
  if text ~= "" then return text end
end

-- The boss pulled last, and the raid's difficulty, become the selected ones,
-- now if the window is open, else when it opens. With auto-save on, the pull
-- also stores the raid's groups under that boss and difficulty. Groups can't
-- change in combat, so the last out-of-combat read stands in when the roster
-- is secret at the pull.
local function OnEncounterStart(encounterID)
  if not IsInRaid() or issecret(encounterID) then return end
  local boss, raid = BossForEncounter(encounterID)
  if not boss then return end

  local difficulty = InstanceDifficulty()
  ns.GetDB().lastBoss = { raid = raid.id, boss = boss.id }
  if difficulty then ns.GetDB().difficulty = difficulty end
  bar.pulled = true
  if bar.row and bar.row:IsVisible() then Refresh() end

  if not ns.GetDB().autoSave or not difficulty then return end
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return end -- Raid Finder groups are random
  local text = ns.ReadGroups() or lastGroups
  if not text then return end
  local old = Layouts(difficulty)[boss.id]
  local note = old and old.note and ns.RewriteNote(old.note, text)
  Layouts(difficulty)[boss.id] = { text = text, saved = time(), pull = true, note = note }
  if bar.row then UpdateButtons() end
  ns.Print(L["Saved the raid's groups for %s."]:format(BossLabel(boss, difficulty)))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "ENCOUNTER_START" then
    OnEncounterStart(...)
  elseif not IsInRaid() then
    lastGroups = nil
  elseif not InCombatLockdown() then
    lastGroups = ns.ReadGroups() or lastGroups
  end
end)
