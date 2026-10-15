-- RaidSort
-- Paste a group layout from the website and the raid sorts itself automatically.
--
-- Input can be plain text or the same text base64-encoded with the prefix
-- "RS1:" (UTF-8). The text format is:
--
--   Group 1: Adelie, Goatjugs, Hoolyhayat, Kitchlol, Meilian
--   Group 2: Gothmog, Hadier, Májestíc, Pepì, Sectorclear
--   ...
--
-- Names can also go one per line under a "Group N" line, and "Gruppe", "G1",
-- "1." etc. work too. Names can include the realm: "Name-Realm".
--
-- Commands:
--   /raidsort          open/close the window
--   /raidsort apply    sort by the last pasted layout (handy in a macro)
--   /raidsort invite   invite players on the list who are not in the raid
--   /raidsort stop     stop a sort in progress
--
-- Player-facing text goes through L (see Locales.lua).

local ADDON_NAME, ns = ...
ns = ns or {}
local L = ns.L

local MAX_GROUPS   = 8
local GROUP_SIZE   = 5
local PREFIX       = "RS1:"
local STEP_TIMEOUT = 1.0   -- seconds between checks for whether a move has landed
local MAX_WAITS    = 5     -- checks without change before a move counts as rejected
local MAX_FAILURES = 3     -- rejected moves in a row → give up
local STEP_DELAY   = 0.1   -- short pause after a roster update before the next move
local MAX_STEPS    = 150   -- safety stop

local DEFAULTS = { text = "", moveExtras = true, autoSave = true }
local DB

local function GetDB() return DB or DEFAULTS end
ns.GetDB = GetDB

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

local function Print(msg)
  print("|cff33ff99RaidSort|r: " .. msg)
end
ns.Print = Print

local function Trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------------------
-- Base64
---------------------------------------------------------------------------

local B64_INDEX = {}
do
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do B64_INDEX[alphabet:byte(i)] = i - 1 end
  B64_INDEX[("-"):byte()] = 62 -- URL-safe variant
  B64_INDEX[("_"):byte()] = 63
end

-- Returns the decoded string, or nil if the input is not valid base64.
function ns.DecodeBase64(s)
  s = s:gsub("%s", "")
  s = s:gsub("=+$", "")
  if s == "" or s:find("[^%w%+/%-_]") or #s % 4 == 1 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local a, b, c, d = s:byte(i, i + 3)
    a, b = B64_INDEX[a], B64_INDEX[b]
    c = c and B64_INDEX[c]
    d = d and B64_INDEX[d]
    local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    out[#out + 1] = string.char(math.floor(v / 65536) % 256)
    if c then out[#out + 1] = string.char(math.floor(v / 256) % 256) end
    if d then out[#out + 1] = string.char(v % 256) end
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- Folds accents (U+00C0-U+00FF) to ASCII, so "Majestic" can match "Májestíc"
-- when the website wrote the name without accents.
local FOLD = {}
do
  local map = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTsaaaaaaaceeeeiiiidnooooo/ouuuuyty"
  for i = 0, 63 do FOLD["\195" .. string.char(128 + i)] = map:sub(i + 1, i + 1) end
end

local function Fold(s)
  s = s:gsub("\204[\128-\191]", "")  -- combining accents (U+0300-U+033F)
  s = s:gsub("\205[\128-\175]", "")  -- combining accents (U+0340-U+036F)
  s = s:gsub("\195[\128-\191]", FOLD)
  return s:lower()
end

local function SplitName(name)
  local base, realm = name:match("^(.-)%-(.+)$")
  if not base or base == "" then return name, nil end
  return base, realm
end

local function RealmKey(realm)
  if not realm then return nil end
  return (realm:gsub("[%s'%-]", ""):lower())
end

local function HomeRealm()
  local fn = GetNormalizedRealmName or GetRealmName
  local realm = fn and fn()
  if realm and not issecret(realm) and realm ~= "" then return RealmKey(realm) end
end

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------

local function NewPlan()
  return { groups = {}, entries = {}, used = {}, errors = {}, warnings = {}, count = 0 }
end

local function NormalizeText(text)
  text = text:gsub("\r\n?", "\n")
  text = text:gsub("\194\160", " ")               -- non-breaking space
  text = text:gsub("\226\128[\139-\141]", "")     -- zero-width characters
  text = text:gsub("\239\187\191", "")            -- BOM
  return text
end

local function SplitNames(s, out)
  for token in s:gmatch("[^,;\t]+") do
    token = Trim(token)
    if token ~= "" then
      if token:find("-", 1, true) then
        out[#out + 1] = token  -- "Name-Realm": the realm may contain spaces
      else
        for part in token:gmatch("%S+") do out[#out + 1] = part end
      end
    end
  end
end

local function AddEntry(plan, seen, group, name)
  local base, realm = SplitName(name)
  local key = base:lower() .. "-" .. (RealmKey(realm) or "")
  if seen[key] then
    table.insert(plan.errors, L["%s is in both group %d and %d."]:format(name, seen[key], group))
    return
  end
  seen[key] = group
  plan.groups[group] = plan.groups[group] or {}
  table.insert(plan.groups[group], name)
  table.insert(plan.entries, {
    name = name, group = group, base = base:lower(), fold = Fold(base), realm = RealmKey(realm),
  })
  plan.used[group] = true
  plan.count = plan.count + 1
end

function ns.ParseText(text)
  local plan = NewPlan()
  local seen = {}
  local current, ignored = nil, 0

  for line in NormalizeText(text):gmatch("[^\n]+") do
    line = Trim(line)
    local _, num, rest = line:match("^([%a%s%.#]*)(%d+)%s*[:%.%)%-]?%s*(.*)$")
    if num then
      num = tonumber(num)
      if num >= 1 and num <= MAX_GROUPS then
        current = num
      else
        current = nil
        table.insert(plan.errors, L["Invalid group number %d (must be 1-%d)."]:format(num, MAX_GROUPS))
      end
      line = rest
    end
    if line ~= "" then
      if current then
        local names = {}
        SplitNames(line, names)
        for _, name in ipairs(names) do AddEntry(plan, seen, current, name) end
      elseif not num then
        ignored = ignored + 1
      end
    end
  end

  for g = 1, MAX_GROUPS do
    local list = plan.groups[g]
    if list and #list > GROUP_SIZE then
      table.insert(plan.errors, L["Group %d has %d players (max %d)."]:format(g, #list, GROUP_SIZE))
    end
  end
  if ignored > 0 then
    table.insert(plan.warnings, L["%d line(s) without a group number were ignored."]:format(ignored))
  end
  if plan.count == 0 and #plan.errors == 0 then
    table.insert(plan.errors, L['No groups found. Expected format: "Group 1: Name, Name, ..."'])
  end
  return plan
end

-- Accepts "RS1:<base64>", bare base64 or plain text.
function ns.ParseInput(raw)
  local s = Trim(raw or "")
  if s == "" then
    local plan = NewPlan()
    plan.empty = true
    return plan
  end

  if s:sub(1, #PREFIX):upper() == PREFIX then
    local decoded = ns.DecodeBase64(s:sub(#PREFIX + 1))
    if not decoded then
      local plan = NewPlan()
      plan.source = "base64"
      table.insert(plan.errors, L["The code could not be decoded. Was all of it copied?"])
      return plan
    end
    local plan = ns.ParseText(decoded)
    plan.source = "base64"
    return plan
  end

  if not s:find("[%s:,;]") then
    local decoded = ns.DecodeBase64(s)
    if decoded then
      local plan = ns.ParseText(decoded)
      if plan.count > 0 then
        plan.source = "base64"
        return plan
      end
    end
  end

  local plan = ns.ParseText(s)
  plan.source = "text"
  return plan
end

---------------------------------------------------------------------------
-- Raid
---------------------------------------------------------------------------

local function ReadRoster()
  local members, counts = {}, {}
  for g = 1, MAX_GROUPS do counts[g] = 0 end
  local home = HomeRealm()
  for i = 1, GetNumGroupMembers() or 0 do
    local name, _, subgroup = GetRaidRosterInfo(i)
    if subgroup and not issecret(subgroup) then
      counts[subgroup] = (counts[subgroup] or 0) + 1
      if name and not issecret(name) then
        local base, realm = SplitName(name)
        table.insert(members, {
          index = i, name = name, group = subgroup,
          base = base:lower(), fold = Fold(base),
          realm = RealmKey(realm) or home, home = (realm == nil),
        })
      end
    end
  end
  return members, counts
end

local function Pick(cands, entry)
  local out = {}
  if entry.realm then
    for _, m in ipairs(cands) do
      if m.realm == entry.realm or (m.home and not m.realm) then out[#out + 1] = m end
    end
    return out
  end
  if #cands > 1 then
    for _, m in ipairs(cands) do
      if m.home then out[#out + 1] = m end
    end
    if #out == 1 then return out end
  end
  return cands
end

local function Candidates(members, entry, field)
  local cands = {}
  for _, m in ipairs(members) do
    if not m.entry and m[field] == entry[field] then cands[#cands + 1] = m end
  end
  return Pick(cands, entry)
end

-- Matches the list to the raid members. Sets m.desired on those it finds.
local function MatchPlan(plan, members)
  local res = { missing = {}, ambiguous = {}, matched = 0 }
  for _, e in ipairs(plan.entries) do
    local cands = Candidates(members, e, "base")
    if #cands == 0 then cands = Candidates(members, e, "fold") end
    if #cands == 1 then
      cands[1].entry = e
      cands[1].desired = e.group
      res.matched = res.matched + 1
    elseif #cands == 0 then
      table.insert(res.missing, e.name)
    else
      table.insert(res.ambiguous, e.name)
    end
  end
  return res
end

-- Finds the next move. Each move puts at least one player on the list in
-- their final group (players already in place are never moved again), so it ends.
local function NextMove(plan, members, counts, moveExtras)
  for _, m in ipairs(members) do
    local target = m.desired
    if target and m.group ~= target then
      if (counts[target] or 0) < GROUP_SIZE then
        return "set", m, target
      end
      local partner
      for _, o in ipairs(members) do
        if o.group == target and o.desired ~= target then
          if o.desired == m.group then partner = o break end
          partner = partner or o
        end
      end
      if partner then return "swap", m, partner end
    end
  end

  if moveExtras then
    for _, m in ipairs(members) do
      if not m.desired and plan.used[m.group] then
        for g = 1, MAX_GROUPS do
          if not plan.used[g] and (counts[g] or 0) < GROUP_SIZE then
            return "set", m, g
          end
        end
        break -- no free group; the rest stay put
      end
    end
  end
end

local function CountWrong(members)
  local wrong = 0
  for _, m in ipairs(members) do
    if m.desired and m.group ~= m.desired then wrong = wrong + 1 end
  end
  return wrong
end

local function AppendMissing(lines, res)
  if #res.missing > 0 then
    lines[#lines + 1] = "|cffffd100" .. L["Not in raid:"] .. "|r " .. table.concat(res.missing, ", ")
  end
  if #res.ambiguous > 0 then
    lines[#lines + 1] = "|cffffd100" .. L["Multiple players share this name (use Name-Realm):"] .. "|r " .. table.concat(res.ambiguous, ", ")
  end
end

local function CanArrange()
  if not IsInRaid() then return false, L["You are not in a raid."] end
  if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
    return false, L["You must be raid leader or assistant to move players."]
  end
  return true
end

---------------------------------------------------------------------------
-- Status and preview
---------------------------------------------------------------------------

function ns.SetStatus(text)
  ns.lastStatus = text
  if ns.statusText then ns.statusText:SetText(text) end
end

local runner = { active = false, timeoutToken = 0, eventToken = 0 }

function ns.IsRunning() return runner.active end

function ns.BuildPreview(text)
  local plan = ns.ParseInput(text)
  if plan.empty then
    return L["Paste the layout from the website and press Sort raid."]
  end
  if #plan.errors > 0 then
    return "|cffff5555" .. table.concat(plan.errors, "\n") .. "|r"
  end

  local groups = 0
  for g = 1, MAX_GROUPS do
    if plan.used[g] then groups = groups + 1 end
  end
  local lines = {
    L["%s: %d players in %d groups."]:format(plan.source == "base64" and L["Code"] or L["Text"], plan.count, groups),
  }

  if not IsInRaid() then
    lines[#lines + 1] = L["You are not in a raid."]
  elseif InCombatLockdown() then
    lines[#lines + 1] = L["In combat – the raid is checked once combat ends."]
  else
    local members, counts = ReadRoster()
    local res = MatchPlan(plan, members)
    if not NextMove(plan, members, counts, GetDB().moveExtras) then
      lines[#lines + 1] = "|cff55ff55" .. L["The raid matches the layout."] .. "|r"
    else
      local wrong = CountWrong(members)
      if wrong > 0 then
        lines[#lines + 1] = L["%d player(s) in the wrong group."]:format(wrong)
      else
        lines[#lines + 1] = L["Players not on the list are in the planned groups."]
      end
      local ok, err = CanArrange()
      if not ok then lines[#lines + 1] = "|cffff5555" .. err .. "|r" end
    end
    AppendMissing(lines, res)
  end

  for _, w in ipairs(plan.warnings) do lines[#lines + 1] = "|cffaaaaaa" .. w .. "|r" end
  return table.concat(lines, "\n")
end

local previewToken = 0

function ns.UpdatePreview()
  if runner.active or not ns.frame or not ns.frame:IsShown() then return end
  ns.SetStatus(ns.BuildPreview(ns.editBox:GetText()))
end

function ns.SchedulePreview()
  previewToken = previewToken + 1
  local token = previewToken
  C_Timer.After(0.2, function()
    if token == previewToken then ns.UpdatePreview() end
  end)
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------

local function Stop(msg)
  runner.active = false
  runner.pending = nil
  runner.timeoutToken = runner.timeoutToken + 1
  runner.eventToken = runner.eventToken + 1
  if msg then
    ns.SetStatus(msg)
    for line in msg:gmatch("[^\n]+") do Print(line) end
  end
end

local function Summary(plan, res, members)
  local lines = {}
  local wrong = CountWrong(members)
  if wrong == 0 then
    lines[1] = "|cff55ff55" .. L["Done!"] .. "|r " .. L["%d of %d players are in the right group."]:format(res.matched, plan.count)
  else
    lines[1] = "|cffff5555" .. L["%d player(s) could not be moved."]:format(wrong) .. "|r"
  end
  AppendMissing(lines, res)
  return table.concat(lines, "\n")
end

local function ArmTimeout()
  runner.timeoutToken = runner.timeoutToken + 1
  local token = runner.timeoutToken
  C_Timer.After(STEP_TIMEOUT, function()
    if runner.active and runner.timeoutToken == token then ns.Step(true) end
  end)
end

-- Has the last move landed? (The player is no longer in the group they were
-- in when we sent it – or has left the raid.)
local function MoveLanded(p)
  for i = 1, GetNumGroupMembers() or 0 do
    local name, _, subgroup = GetRaidRosterInfo(i)
    if name and not issecret(name) and name == p.name then
      return subgroup ~= p.from
    end
  end
  return true
end

-- One step: wait for the previous move to land, then find the next one.
-- There is never more than one move in flight at a time.
function ns.Step(fromTimeout)
  if not runner.active then return end

  local ok, err = CanArrange()
  if not ok then return Stop("|cffff5555" .. err .. "|r") end

  if InCombatLockdown() then
    if not runner.waitingCombat then
      runner.waitingCombat = true
      ns.SetStatus(L["In combat – sorting continues once combat ends."])
    end
    return
  end
  if runner.waitingCombat then
    runner.waitingCombat = false
    ns.SetStatus(L["Sorting raid …"])
  end

  local p = runner.pending
  if p then
    if MoveLanded(p) then
      runner.pending = nil
      runner.failures = 0
    elseif fromTimeout then
      p.waits = p.waits + 1
      if p.waits < MAX_WAITS then return ArmTimeout() end
      runner.pending = nil
      runner.failures = runner.failures + 1
      if runner.failures >= MAX_FAILURES then
        return Stop("|cffff5555" .. L["Could not move %s – the game rejected the move."]:format(p.name) .. "|r")
      end
    else
      return ArmTimeout() -- other raid changes; keep waiting
    end
  end

  local members, counts = ReadRoster()
  local res = MatchPlan(runner.plan, members)
  local op, a, b = NextMove(runner.plan, members, counts, runner.moveExtras)
  if not op then return Stop(Summary(runner.plan, res, members)) end

  runner.steps = runner.steps + 1
  if runner.steps > MAX_STEPS then
    return Stop("|cffff5555" .. L["Stopped after too many moves – check the raid manually."] .. "|r")
  end

  if op == "set" then
    SetRaidSubgroup(a.index, b)
  else
    SwapRaidSubgroup(a.index, b.index)
  end
  runner.pending = { name = a.name, from = a.group, waits = 0 }
  ArmTimeout()
end

function ns.Apply(text)
  if runner.active then Stop() end

  local plan = ns.ParseInput(text)
  if plan.empty then
    ns.SetStatus(L["Paste a layout first."])
    Print(L["No layout – paste one in /raidsort first."])
    return false
  end
  if #plan.errors > 0 then
    ns.SetStatus("|cffff5555" .. table.concat(plan.errors, "\n") .. "|r")
    Print(plan.errors[1])
    return false
  end
  local ok, err = CanArrange()
  if not ok then
    ns.SetStatus("|cffff5555" .. err .. "|r")
    Print(err)
    return false
  end

  runner.active = true
  runner.plan = plan
  runner.moveExtras = GetDB().moveExtras
  runner.steps, runner.failures, runner.pending = 0, 0, nil
  runner.waitingCombat = false
  ns.SetStatus(L["Sorting raid …"])
  ns.Step()
  return true
end

function ns.StopSorting()
  if runner.active then Stop(L["Sorting stopped."]) end
end

function ns.InviteMissing(text)
  local plan = ns.ParseInput(text)
  if plan.empty or #plan.errors > 0 then
    Print(L["Paste a valid layout first."])
    return
  end
  if not IsInRaid() then
    Print(L["Convert the group to a raid before inviting."])
    return
  end
  local members = ReadRoster()
  local res = MatchPlan(plan, members)
  if #res.missing == 0 then
    Print(L["Everyone on the list is already in the raid."])
    return
  end
  local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  for i, name in ipairs(res.missing) do
    C_Timer.After((i - 1) * 0.2, function() invite(name) end)
  end
  Print(L["Inviting %d: %s"]:format(#res.missing, table.concat(res.missing, ", ")))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function MakeButton(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetText(text)
  b:SetWidth(math.max(width, b:GetTextWidth() + 24)) -- room for longer translations
  return b
end
ns.MakeButton = MakeButton

function ns.CreateUI()
  if ns.frame then return ns.frame end

  local f = CreateFrame("Frame", "RaidSortFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(440, 474)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  table.insert(UISpecialFrames, "RaidSortFrame") -- Esc closes the window

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("RaidSort")

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 16, -126)
  hint:SetText(L["Paste the layout from the website (Ctrl+V):"])

  local sf = CreateFrame("ScrollFrame", "RaidSortScrollFrame", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -144)
  sf:SetPoint("BOTTOMRIGHT", -36, 118)

  local bg = f:CreateTexture(nil, "ARTWORK")
  bg:SetColorTexture(0, 0, 0, 0.4)
  bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)

  local eb = CreateFrame("EditBox", "RaidSortEditBox", sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(380)
  eb:SetHeight(200)
  eb:SetText(GetDB().text or "")
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self)
    GetDB().text = self:GetText()
    ns.SchedulePreview()
  end)
  sf:SetScrollChild(eb)
  sf:SetScript("OnSizeChanged", function(_, width) eb:SetWidth(width) end)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

  local cb = CreateFrame("CheckButton", "RaidSortExtrasCheck", f, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", -6, -8)
  cb:SetChecked(GetDB().moveExtras)
  cb:SetScript("OnClick", function(self)
    GetDB().moveExtras = self:GetChecked() and true or false
    ns.SchedulePreview()
  end)
  local cbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbLabel:SetText(L["Move players who are not on the list to the free groups"])

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 6, -4)
  status:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  status:SetHeight(46)
  status:SetJustifyH("LEFT")
  status:SetJustifyV("TOP")

  local apply = MakeButton(f, L["Sort raid"], 120)
  apply:SetPoint("BOTTOMRIGHT", -12, 12)
  apply:SetScript("OnClick", function()
    eb:ClearFocus()
    ns.Apply(eb:GetText())
  end)

  local invite = MakeButton(f, L["Invite missing"], 140)
  invite:SetPoint("RIGHT", apply, "LEFT", -6, 0)
  invite:SetScript("OnClick", function() ns.InviteMissing(eb:GetText()) end)

  local clear = MakeButton(f, L["Clear"], 70)
  clear:SetPoint("BOTTOMLEFT", 12, 12)
  clear:SetScript("OnClick", function()
    eb:SetText("")
    eb:SetFocus()
  end)

  f:SetScript("OnShow", function()
    ns.UpdatePreview()
    if eb:GetText() == "" then eb:SetFocus() end
  end)
  ns.CreateBossBar(f, eb) -- after OnShow is set, since the bar hooks it

  ns.frame, ns.editBox, ns.statusText = f, eb, status
  if ns.lastStatus then status:SetText(ns.lastStatus) end
  return f
end

function ns.Toggle()
  local f = ns.CreateUI()
  if f:IsShown() then f:Hide() else f:Show() end
end

---------------------------------------------------------------------------
-- Events and commands
---------------------------------------------------------------------------

function ns.OnEvent(event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON_NAME then
      RaidSortDB = RaidSortDB or {}
      for k, v in pairs(DEFAULTS) do
        if RaidSortDB[k] == nil then RaidSortDB[k] = v end
      end
      DB = RaidSortDB
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if runner.active then
      runner.eventToken = runner.eventToken + 1
      local token = runner.eventToken
      C_Timer.After(STEP_DELAY, function()
        if runner.active and runner.eventToken == token then ns.Step(false) end
      end)
    else
      ns.SchedulePreview()
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if runner.active and runner.waitingCombat then
      ns.Step()
    else
      ns.SchedulePreview()
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns.SchedulePreview()
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, ...) ns.OnEvent(event, ...) end)

SLASH_RAIDSORT1 = "/raidsort"
SLASH_RAIDSORT2 = "/rsort"
SlashCmdList.RAIDSORT = function(msg)
  msg = Trim((msg or ""):lower())
  if msg == "apply" or msg == "sort" then
    ns.Apply(GetDB().text)
  elseif msg == "invite" then
    ns.InviteMissing(GetDB().text)
  elseif msg == "stop" then
    ns.StopSorting()
  else
    ns.Toggle()
  end
end
