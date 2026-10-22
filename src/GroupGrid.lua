-- GroupGrid
-- The layout as groups of five in the Raidnight Helper window, groups 1-4
-- above 5-8. Names are moved with the mouse: dropped on another name, the two
-- swap places; dropped on an empty slot, the name moves there; dropped on
-- "Not on list", it comes off the list. Raid members who are not on the list
-- wait in that column and can be dragged into a group. So can names that are
-- not in the raid: dropped there, they wait in it, grey, and the layout keeps
-- them on its "Not on list:" line. A name that is not in the raid comes off
-- the list for good from its right-click menu, or when dropped outside the
-- window.
--
-- In a raid, the players dragged move in the raid too (see ns.MoveInRaid);
-- everyone else stays put until Sort raid. Names show in class colours with
-- the raid frames' role icon, and grey without one while the player is not in
-- the raid. A name in a group shows, in orange, the number of the group the
-- player is in now when that is another one. Raid members have a lock to
-- click: locked players never go into the groups that play when the raid is
-- sorted (see ns.PlayGroups), and Balance leaves them where they are (see
-- ns.IsLocked).

local _, ns = ...
local L = ns.L

local MAX_GROUPS  = 8
local GROUP_SIZE  = 5
local COLUMNS     = 4    -- groups per row
local POOL_SIZE   = 10   -- slots in the "Not on list" column
local SLOT_WIDTH  = 112
local SLOT_HEIGHT = 17
local HEADER      = 16
local GAP         = 6
local LOCK_ICON   = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"

-- The role icons of the game's raid frames (GetMicroIconForRole). Melee and
-- ranged share the damage icon, as they do there.
local ROLE_ATLASES = {
  TANK   = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
  HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
  MELEE  = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
  RANGED = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
}

-- groups[g] and pool hold the slot buttons; targets is everything a name can
-- be dropped on. A slot has .group (nil in the pool), .index and .name, and
-- for a raid member .raidGroup (the group they are in now), .member (their
-- name in the raid) and .locked.
local grid = { groups = {}, pool = {}, targets = {} }

---------------------------------------------------------------------------
-- Showing the layout
---------------------------------------------------------------------------

-- info is the raid member behind the name (see ns.MatchRaid), or nil when
-- the player is not in the raid.
local function ShowName(slot, name, info)
  slot.name = name
  slot.raidGroup = info and info.group
  slot.member = info and info.name
  slot.locked = info and info.locked
  slot.text:SetText(name or "")
  local elsewhere = info and slot.group and info.group ~= slot.group
  slot.where:SetText(elsewhere and tostring(info.group) or "")
  slot.lock:SetShown(info ~= nil)
  slot.lock.icon:SetDesaturated(not slot.locked)
  slot.lock.icon:SetAlpha(slot.locked and 1 or 0.3) -- faded = unlocked
  local atlas = info and ROLE_ATLASES[info.role]
  if atlas then slot.icon:SetAtlas(atlas) end
  slot.icon:SetShown(atlas ~= nil)
  local color = info and RAID_CLASS_COLORS[info.class]
  if color then
    slot.text:SetTextColor(color.r, color.g, color.b)
  elseif info then
    slot.text:SetTextColor(1, 1, 1)
  else
    slot.text:SetTextColor(0.5, 0.5, 0.5)
  end
end

function ns.RefreshGrid()
  if not (grid.frame and grid.frame:IsVisible()) then return end
  local plan = ns.ParseInput(ns.GetDB().text)
  local found, extras, away = ns.MatchRaid(plan)
  for g = 1, MAX_GROUPS do
    local names = plan.groups[g] or {}
    for i, slot in ipairs(grid.groups[g]) do
      ShowName(slot, names[i], names[i] and found[names[i]])
    end
  end
  -- "Not on list" shows the raid members first, then the names waiting
  -- there who are not in the raid.
  local pool = {}
  for _, p in ipairs(extras) do pool[#pool + 1] = { name = p.name, info = p } end
  for _, name in ipairs(away) do pool[#pool + 1] = { name = name } end
  for i, slot in ipairs(grid.pool) do
    if i == POOL_SIZE and #pool > POOL_SIZE then
      ShowName(slot, nil)
      slot.text:SetText(L["+%d more"]:format(#pool - POOL_SIZE + 1))
    else
      local p = pool[i]
      ShowName(slot, p and p.name, p and p.info)
    end
  end
end

---------------------------------------------------------------------------
-- Removing
---------------------------------------------------------------------------

local function IndexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
end

-- Takes a name off the list when the player is not in the raid: from its
-- group, or with group nil, from "Not on list". Raid members come off the
-- list by a drag to "Not on list". Nothing happens if the layout changed
-- since.
local function Remove(group, index, name)
  local plan = ns.ParseInput(ns.GetDB().text)
  local found, _, away = ns.MatchRaid(plan)
  if group then
    local list = plan.groups[group]
    if not (list and list[index] == name) or found[name] then return end
    table.remove(list, index)
  else
    local i = IndexOf(plan.parked, name)
    if not (i and IndexOf(away, name)) then return end
    table.remove(plan.parked, i)
  end
  ns.SetLayout(ns.FormatLayout(plan.groups, plan.parked))
end

-- A right-click on a name that is not in the raid opens a menu to remove it.
local function OnSlotClick(self, button)
  if button ~= "RightButton" or not self.name or self.member then return end
  local group, index, name = self.group, self.index, self.name
  MenuUtil.CreateContextMenu(self, function(_, root)
    root:CreateTitle(name)
    root:CreateButton(L["Remove from list"], function() Remove(group, index, name) end)
  end)
end

---------------------------------------------------------------------------
-- Dragging
---------------------------------------------------------------------------

-- Moves the dragged name ({ group, index, name, raidGroup, member }) to the
-- target, a slot or the "Not on list" column, makes the result the layout,
-- and moves the raid members whose group changed in the raid as well. A raid
-- member taken off the list stays where it is in the raid, unless a player
-- from "Not on list" takes its slot; then the two swap. A name that is not in
-- the raid waits in "Not on list" when it leaves the groups, and moves nobody.
local function Drop(from, to)
  local plan = ns.ParseInput(ns.GetDB().text)
  local groups, parked = plan.groups, plan.parked
  local function List(g)
    groups[g] = groups[g] or {}
    return groups[g]
  end
  -- Nothing happens if the layout changed under the drag.
  local function Holds(t)
    if t.group then return List(t.group)[t.index] == t.name end
    return not t.name or t.member ~= nil or IndexOf(parked, t.name) ~= nil
  end
  if not (Holds(from) and Holds(to)) then return end

  local moves = {}
  local function Move(t, g)
    if t.member then moves[t.name] = g end
  end
  local function Park(t)
    if not t.member then parked[#parked + 1] = t.name end
  end
  if from.group and to.group then
    if to.name then
      List(from.group)[from.index], List(to.group)[to.index] = to.name, from.name
      Move(to, from.group)
    else
      table.remove(List(from.group), from.index)
      table.insert(List(to.group), from.name)
    end
    Move(from, to.group)
  elseif from.group then
    table.remove(List(from.group), from.index)
    Park(from)
  elseif to.group then
    if to.name then
      List(to.group)[to.index] = from.name
      Move(to, from.raidGroup)
      Park(to)
    else
      table.insert(List(to.group), from.name)
    end
    Move(from, to.group)
  else
    return
  end
  -- A name waiting in "Not on list" that is now in a group leaves it there.
  ns.SetLayout(ns.FormatLayout(groups, parked))
  ns.MoveInRaid(moves)
end

local function OnDragStart(self)
  if not self.name then return end
  grid.drag = {
    group = self.group, index = self.index, name = self.name, raidGroup = self.raidGroup,
    member = self.member, slot = self,
  }
  grid.ghost.text:SetText(self.name)
  grid.ghost.text:SetTextColor(self.text:GetTextColor())
  grid.ghost:Show()
  self.text:SetAlpha(0.3)
end

-- Ends the drag in progress, if any, and returns it.
local function EndDrag()
  local drag = grid.drag
  grid.drag = nil
  grid.ghost:Hide()
  if drag then drag.slot.text:SetAlpha(1) end
  return drag
end

local function OnDragStop()
  local drag = EndDrag()
  if not drag then return end
  for _, target in ipairs(grid.targets) do
    if target:IsMouseOver() then
      if target ~= drag.slot then Drop(drag, target) end
      return
    end
  end
  -- Dropped outside the window: a name that is not in the raid comes off the list.
  if not drag.member and not grid.frame:GetParent():IsMouseOver() then
    Remove(drag.group, drag.index, drag.name)
  end
end

-- The name that follows the mouse while dragging.
local function CreateGhost()
  local ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetFrameStrata("TOOLTIP")
  ghost:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
  local bg = ghost:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.7)
  ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ghost.text:SetPoint("LEFT", 4, 0)
  ghost:Hide()
  ghost:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
  end)
  return ghost
end

---------------------------------------------------------------------------
-- Locks
---------------------------------------------------------------------------

local function OnLockEnter(self)
  local slot = self:GetParent()
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(slot.member or "")
  local tip = slot.locked and L["Locked: Sort raid never puts this player in groups 1-%d, and Balance never moves them. Auto unlocks everyone. Click to unlock."]
    or L["Click to lock: Sort raid will never put this player in groups 1-%d, and Balance will not move them."]
  GameTooltip:AddLine(tip:format(ns.PlayGroups().count), 1, 1, 1, true)
  GameTooltip:Show()
end

local function OnLockClick(self)
  local slot = self:GetParent()
  if not slot.member then return end
  ns.SetLocked(slot.member, not slot.locked)
  if GameTooltip:IsOwned(self) then OnLockEnter(self) end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function NewSlot(parent, group, index)
  local slot = CreateFrame("Button", nil, parent)
  slot:SetSize(SLOT_WIDTH, SLOT_HEIGHT - 1)
  slot.group, slot.index = group, index
  local bg = slot:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.4)
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetSize(SLOT_HEIGHT - 3, SLOT_HEIGHT - 3)
  slot.icon:SetPoint("LEFT", 2, 0)

  slot.lock = CreateFrame("Button", nil, slot)
  slot.lock:SetSize(SLOT_HEIGHT - 3, SLOT_HEIGHT - 3)
  slot.lock:SetPoint("RIGHT", -2, 0)
  slot.lock.icon = slot.lock:CreateTexture(nil, "ARTWORK")
  slot.lock.icon:SetAllPoints()
  slot.lock.icon:SetTexture(LOCK_ICON)
  slot.lock:SetScript("OnClick", OnLockClick)
  slot.lock:SetScript("OnEnter", OnLockEnter)
  slot.lock:SetScript("OnLeave", GameTooltip_Hide)
  slot.lock:Hide()

  slot.where = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slot.where:SetPoint("RIGHT", slot.lock, "LEFT", -2, 0)
  slot.where:SetTextColor(1, 0.5, 0)

  slot.text = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slot.text:SetPoint("LEFT", slot.icon, "RIGHT", 3, 0)
  slot.text:SetPoint("RIGHT", slot.where, "LEFT", -2, 0)
  slot.text:SetJustifyH("LEFT")
  slot.text:SetWordWrap(false)
  slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  slot:RegisterForDrag("LeftButton")
  slot:SetScript("OnDragStart", OnDragStart)
  slot:SetScript("OnDragStop", OnDragStop)
  slot:RegisterForClicks("RightButtonUp")
  slot:SetScript("OnClick", OnSlotClick)
  table.insert(grid.targets, slot)
  return slot
end

-- A heading with slots under it. group is nil for "Not on list".
local function NewColumn(parent, title, group, size)
  local col = CreateFrame("Frame", nil, parent)
  col:SetSize(SLOT_WIDTH, HEADER + size * SLOT_HEIGHT)
  local heading = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  heading:SetPoint("TOPLEFT", 2, -2)
  heading:SetText(title)
  col.slots = {}
  for i = 1, size do
    local slot = NewSlot(col, group, i)
    slot:SetPoint("TOPLEFT", 0, -HEADER - (i - 1) * SLOT_HEIGHT)
    col.slots[i] = slot
  end
  return col
end

-- Builds the grid in the window f and returns it for the window to place.
function ns.CreateGrid(f)
  local frame = CreateFrame("Frame", nil, f)
  local colWidth = SLOT_WIDTH + GAP
  local rowHeight = HEADER + GROUP_SIZE * SLOT_HEIGHT + GAP
  for g = 1, MAX_GROUPS do
    local col = NewColumn(frame, L["Group %d"]:format(g), g, GROUP_SIZE)
    local row = math.floor((g - 1) / COLUMNS)
    col:SetPoint("TOPLEFT", ((g - 1) % COLUMNS) * colWidth, -row * rowHeight)
    grid.groups[g] = col.slots
  end

  local pool = NewColumn(frame, L["Not on list"], nil, POOL_SIZE)
  pool:SetPoint("TOPLEFT", COLUMNS * colWidth + GAP, 0)
  grid.pool = pool.slots
  table.insert(grid.targets, pool) -- anywhere in the column takes a name off the list

  frame:SetSize(COLUMNS * colWidth + GAP + SLOT_WIDTH, 2 * rowHeight - GAP)
  frame:SetScript("OnShow", ns.RefreshGrid)
  frame:SetScript("OnHide", EndDrag)
  grid.ghost = CreateGhost()
  grid.frame = frame
  return frame
end
