-- BossLayouts
-- A row of boss icons at the top of the Raidnight Helper window. Each boss keeps one
-- layout: Save stores the current layout under the selected boss, and clicking
-- a boss loads its layout back into the grid. A pull selects that boss, and
-- with auto-save on, it also stores the raid's actual groups under it.
--
-- Bosses come from the Encounter Journal, so the row follows the current tier
-- without hardcoded names. Layouts are keyed by journal encounter ID, which is
-- the same in every client language, and live in RaidnightHelperDB.bosses:
--
--   [journalEncounterID] = { text = "Group 1: ...", saved = <time()>, pull = true|nil }
--
-- RaidnightHelperDB.lastBoss = { raid = journalInstanceID, boss = journalEncounterID }
-- remembers the boss pulled last, so it is selected again after a reload.

local _, ns = ...
local L = ns.L

local ICON_WIDTH   = 64   -- journal boss portraits are twice as wide as tall
local ICON_GAP     = 6
local DEFAULT_ICON = "Interface\\EncounterJournal\\UI-EJ-BOSS-Default"

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

local bar = { raids = {}, bosses = {}, buttons = {} }

local function Layouts()
  local db = ns.GetDB()
  db.bosses = db.bosses or {}
  return db.bosses
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
  bar.save:SetEnabled(bar.selected ~= nil)
  bar.delete:SetEnabled(bar.selected ~= nil and layouts[bar.selected] ~= nil)
end

local function OnBossClick(self)
  bar.selected = self.boss.id
  local layout = Layouts()[self.boss.id]
  if layout then ns.SetLayout(layout.text) end
  UpdateButtons()
end

local function OnBossEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:SetText(self.boss.name)
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

-- Shows the raid the player is in, else the raid shown last, else the raid of
-- the boss pulled last, else the first. The boss pulled last is selected
-- after a new pull, or when no boss is selected yet.
local function Refresh()
  if #bar.raids == 0 then bar.raids = LoadRaids() end
  local last = ns.GetDB().lastBoss
  local here = CurrentInstance()
  local target = (HasRaid(here) and here) or bar.raid
    or (last and HasRaid(last.raid) and last.raid) or (bar.raids[1] and bar.raids[1].id)
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

-- Stores text under the boss selected in the bar. Returns true when saved.
function ns.SaveToSelectedBoss(text)
  local boss = SelectedBoss()
  if not boss then return false end
  Layouts()[boss.id] = { text = text, saved = time() }
  UpdateButtons()
  ns.Print(L["Saved layout for %s."]:format(boss.name))
  return true
end

StaticPopupDialogs.RAIDNIGHT_DELETE_LAYOUT = {
  text = L["Delete the saved layout for %s?"],
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, boss)
    Layouts()[boss.id] = nil
    UpdateButtons()
    ns.Print(L["Deleted layout for %s."]:format(boss.name))
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function DeleteSelected()
  local boss = SelectedBoss()
  if boss then StaticPopup_Show("RAIDNIGHT_DELETE_LAYOUT", boss.name, nil, boss) end
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

-- The current tier's boss, and its raid, for an ENCOUNTER_START encounter ID.
local function BossForEncounter(encounterID)
  if #bar.raids == 0 then bar.raids = LoadRaids() end
  for _, raid in ipairs(bar.raids) do
    for _, boss in ipairs(LoadBosses(raid.id)) do
      if boss.encounter == encounterID then return boss, raid end
    end
  end
end

-- The boss pulled last becomes the selected one, now if the window is open,
-- else when it opens. With auto-save on, the pull also stores the raid's
-- groups under that boss. Groups can't change in combat, so the last
-- out-of-combat read stands in when the roster is secret at the pull.
local function OnEncounterStart(encounterID)
  if not IsInRaid() or issecret(encounterID) then return end
  local boss, raid = BossForEncounter(encounterID)
  if not boss then return end

  ns.GetDB().lastBoss = { raid = raid.id, boss = boss.id }
  bar.pulled = true
  if bar.row and bar.row:IsVisible() then Refresh() end

  if not ns.GetDB().autoSave then return end
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return end -- Raid Finder groups are random
  local text = ns.ReadGroups() or lastGroups
  if not text then return end
  Layouts()[boss.id] = { text = text, saved = time(), pull = true }
  if bar.row then UpdateButtons() end
  ns.Print(L["Saved the raid's groups for %s."]:format(boss.name))
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
