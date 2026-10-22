-- Raidnight Helper
-- The window, group sorting and the slash commands. Paste a group layout
-- from the website and the raid sorts itself automatically.
--
-- Input can be plain text or the same text base64-encoded with the prefix
-- "RS1:" (UTF-8). The text format is:
--
--   Group 1: Brannoc, Elowyn, Fenwick, Isolde, Torvald
--   Group 2: Ashlyn, Corvain, Dúnmir, Ravéna, Thessaly
--   ...
--
-- Names can also go one per line under a "Group N" line, and "Gruppe", "G1",
-- "1." etc. work too. Names can include the realm: "Name-Realm".
--
-- Commands (/rn works as a short form):
--   /raidnight         open/close the window
--   /raidnight apply   sort by the last pasted layout (handy in a macro)
--   /raidnight auto    balance the groups that play by role and sort (see AutoGroups.lua)
--   /raidnight balance even out the damage of the two halves (see Balance.lua)
--   /raidnight invite  invite players on the list who are not in the raid
--   /raidnight send    send the boss layouts of the raid in the dropdown to the raid (see Sync.lua)
--   /raidnight stop    stop a sort in progress
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
  print("|cff33ff99Raidnight Helper|r: " .. msg)
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

-- Folds accents (U+00C0-U+00FF) to ASCII, so "Ravena" can match "Ravéna"
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

-- The text format for groups[g] = { names }, as ParseText reads it.
function ns.FormatLayout(groups)
  local lines = {}
  for g = 1, MAX_GROUPS do
    if groups[g] and #groups[g] > 0 then
      lines[#lines + 1] = ("Group %d: %s"):format(g, table.concat(groups[g], ", "))
    end
  end
  return table.concat(lines, "\n")
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
-- Locks
---------------------------------------------------------------------------

-- Locked players never go into the groups that play (see ApplyLocks and
-- ns.PlayGroups); only a drag in the grid moves them there. Balance leaves
-- them where they are. While
-- there is a list, players who are not on
-- it start locked and the others unlocked; a click on the lock decides for
-- the rest of the raid. Auto lets go of all locks. Kept by name as in the
-- raid, and forgotten when you leave the raid: [name] = true or false.
local locks = {}

function ns.IsLocked(name, onList, hasList)
  local locked = locks[name]
  if locked == nil then return hasList and not onList end
  return locked
end

function ns.SetLocked(name, locked)
  locks[name] = locked
  ns.RefreshGrid()
  ns.SchedulePreview()
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
-- res.missing has the names on the list that are not in the raid, and
-- res.ambiguous those that match more than one player. res.held has the
-- entries of both: their slots are kept for them.
local function MatchPlan(plan, members)
  local res = { missing = {}, ambiguous = {}, held = {}, matched = 0 }
  for _, e in ipairs(plan.entries) do
    local cands = Candidates(members, e, "base")
    if #cands == 0 then cands = Candidates(members, e, "fold") end
    if #cands == 1 then
      cands[1].entry = e
      cands[1].desired = e.group
      res.matched = res.matched + 1
    elseif #cands == 0 then
      table.insert(res.missing, e.name)
      table.insert(res.held, e)
    else
      table.insert(res.ambiguous, e.name)
      table.insert(res.held, e)
    end
  end
  return res
end

-- Locked players never go into the groups that play. One who stands in
-- their own group stays there; one who is to go to a later group is sorted
-- like anyone else. The others count as not on the list, so they stay where
-- they are, or leave the groups that play for a later one when their slot is
-- needed (see NextMove). The players a drag moves (moves, names as on the
-- list) are not held by a lock.
local function ApplyLocks(members, plan, moves)
  local hasList = plan.count > 0
  local play = ns.PlayGroups()
  for _, m in ipairs(members) do
    local dragged = moves and m.entry and moves[m.entry.name]
    if not dragged and ns.IsLocked(m.name, m.entry ~= nil, hasList) then
      m.locked = true
      if m.desired and m.desired <= play.count and m.desired ~= m.group then m.desired = nil end
    end
  end
end

-- Before the layout takes in players who are not on the list, their locks
-- are set by name, so they stay locked once they are on it.
local function KeepLocks(members)
  for _, m in ipairs(members) do
    if m.locked and locks[m.name] == nil then locks[m.name] = true end
  end
end

-- For the group grid: the names on the list that are in the raid
-- ({ [name] = info }) and the raid members who are not on the list
-- ({ info, ... }). info is { name, group, class, role, locked }: the group
-- they are in now, UnitClass's file name ("" when unknown), the role from
-- Roles.lua and whether they are locked. Both are empty outside a raid.
function ns.MatchRaid(plan)
  local found, extras = {}, {}
  if not IsInRaid() then return found, extras end
  local members = ReadRoster()
  MatchPlan(plan, members)
  local hasList = plan.count > 0
  for _, m in ipairs(members) do
    local unit = "raid" .. m.index
    local _, class = UnitClass(unit)
    local info = {
      name = m.name, group = m.group, class = class or "", role = ns.UnitRole(unit),
      locked = ns.IsLocked(m.name, m.entry ~= nil, hasList),
    }
    if m.entry then
      found[m.entry.name] = info
    else
      extras[#extras + 1] = info
    end
  end
  return found, extras
end

-- Adds the players on the list who are not in the raid, and the names that
-- match more than one player, to groups ({ [group] = { names } }): each to
-- their own group, or when that is full, to the first group with room.
local function AddMissing(groups, res)
  local function Room(g) return #(groups[g] or {}) < GROUP_SIZE end
  local function Put(g, name)
    groups[g] = groups[g] or {}
    table.insert(groups[g], name)
  end
  local displaced = {}
  for _, e in ipairs(res.held) do
    if Room(e.group) then Put(e.group, e.name) else displaced[#displaced + 1] = e.name end
  end
  for _, name in ipairs(displaced) do
    for g = 1, MAX_GROUPS do
      if Room(g) then Put(g, name) break end
    end
  end
end

-- Gives players who are not on the list a group in the open slots of the
-- groups that play, by role and class (see AutoGroups.lua). Players on the
-- list keep their groups, and slots of list players who are not in the raid,
-- or whose name matches more than one player, are held for them. Among
-- players of the same role, those already in the groups that play get a slot
-- first; anyone without a slot is left for the free groups. Locked players
-- get none. Returns { [name] = group }.
local function PlaceExtras(members, res)
  local play = ns.PlayGroups()
  local fixed, extras, far = {}, {}, {}
  for _, e in ipairs(res.held) do
    if e.group <= play.count then fixed[#fixed + 1] = { group = e.group } end
  end
  for _, m in ipairs(members) do
    local role = ns.UnitRole("raid" .. m.index)
    local _, class = UnitClass("raid" .. m.index)
    if m.desired then
      if m.desired <= play.count then fixed[#fixed + 1] = { group = m.desired, role = role, class = class } end
    elseif not m.locked then
      local list = m.group <= play.count and extras or far
      list[#list + 1] = { name = m.name, role = role, class = class }
    end
  end
  for _, p in ipairs(far) do extras[#extras + 1] = p end

  ns.BalanceGroups(fixed, extras, play)
  local targets = {}
  for _, p in ipairs(extras) do targets[p.name] = p.target end
  return targets
end

local function ApplyTargets(members, targets)
  for _, m in ipairs(members) do
    if not m.desired and targets[m.name] then m.desired = targets[m.name] end
  end
end

-- Locked players never go into the groups that play (play.count).
local function CanGo(p, g, play)
  return not (p.locked and g <= play.count)
end

-- Finds the next move. Each move puts at least one player on the list in
-- their final group, or makes room for one (players already in place are
-- never moved again), so it ends. Two players who are to go to each other's
-- group swap first, as one move places both. only, when set, limits the
-- players to place to those names (as on the list). Players the game would
-- not move (.skipped) stay where they are.
local function NextMove(plan, members, counts, moveExtras, only)
  local play = ns.PlayGroups()
  local wrong = {}
  for _, m in ipairs(members) do
    if m.desired and m.group ~= m.desired and not m.skipped
      and (not only or (m.entry and only[m.entry.name])) then
      wrong[#wrong + 1] = m
    end
  end

  -- A group after the ones that play with room for a locked player: their
  -- own group on the list, else a group the list doesn't use, else any.
  local function Bench(p)
    local own = p.desired
    if own and own > play.count and (counts[own] or 0) < GROUP_SIZE then return own end
    for pass = 1, 2 do
      for g = play.count + 1, MAX_GROUPS do
        if (counts[g] or 0) < GROUP_SIZE and (pass == 2 or not plan.used[g]) then return g end
      end
    end
  end

  -- 1. Two players who are to go to each other's group swap places.
  for _, m in ipairs(wrong) do
    for _, o in ipairs(members) do
      if o.group == m.desired and o.desired == m.group and not o.skipped then
        return "swap", m, o
      end
    end
  end

  -- 2. A player whose group has room moves there.
  for _, m in ipairs(wrong) do
    if (counts[m.desired] or 0) < GROUP_SIZE then return "set", m, m.desired end
  end

  -- 3. A player whose group is full swaps with someone there who is not to
  -- stay. A locked player there who can't take the mover's place in the
  -- groups that play leaves for a later group first.
  for _, m in ipairs(wrong) do
    local locked
    for _, o in ipairs(members) do
      if o.group == m.desired and o.desired ~= m.desired and not o.skipped then
        if CanGo(o, m.group, play) then return "swap", m, o end
        locked = locked or o
      end
    end
    local bench = locked and Bench(locked)
    if bench then return "set", locked, bench end
  end

  -- 4. Players who are not on the list leave the groups it uses.
  if moveExtras then
    for _, m in ipairs(members) do
      if not m.desired and not m.skipped and plan.used[m.group] then
        for g = 1, MAX_GROUPS do
          if not plan.used[g] and (counts[g] or 0) < GROUP_SIZE and CanGo(m, g, play) then
            return "set", m, g
          end
        end
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

-- Once nothing more can be moved: the players the game would not move, and
-- the locked players in a group that someone on the list still waits for.
local function AppendStuck(lines, members)
  local rejected, waiting, inWay = {}, {}, {}
  for _, m in ipairs(members) do
    if m.skipped and m.group ~= m.desired then
      rejected[#rejected + 1] = m.name
    elseif m.desired and m.group ~= m.desired then
      waiting[m.desired] = true
    end
  end
  for _, m in ipairs(members) do
    if m.locked and waiting[m.group] and m.desired ~= m.group then inWay[#inWay + 1] = m.name end
  end
  if #rejected > 0 then
    lines[#lines + 1] = "|cffffd100" .. L["Rejected by the game:"] .. "|r " .. table.concat(rejected, ", ")
  end
  if #inWay > 0 then
    lines[#lines + 1] = "|cffffd100" .. L["Locked players in the way:"] .. "|r " .. table.concat(inWay, ", ")
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

local runner = { active = false, timeoutToken = 0, eventToken = 0, id = 0 }

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
    ApplyLocks(members, plan)
    local moveExtras = GetDB().moveExtras
    if moveExtras then ApplyTargets(members, PlaceExtras(members, res)) end
    local wrong = CountWrong(members)
    local canMove = NextMove(plan, members, counts, moveExtras) ~= nil
    if wrong == 0 and not canMove then
      lines[#lines + 1] = "|cff55ff55" .. L["The raid matches the layout."] .. "|r"
    else
      if wrong > 0 then
        lines[#lines + 1] = L["%d player(s) in the wrong group."]:format(wrong)
      else
        lines[#lines + 1] = L["Players not on the list are in the planned groups."]
      end
      local ok, err = CanArrange()
      if not ok then lines[#lines + 1] = "|cffff5555" .. err .. "|r" end
      if not canMove then AppendStuck(lines, members) end
    end
    AppendMissing(lines, res)
  end

  for _, w in ipairs(plan.warnings) do lines[#lines + 1] = "|cffaaaaaa" .. w .. "|r" end
  return table.concat(lines, "\n")
end

local previewToken = 0

function ns.UpdatePreview()
  if runner.active or ns.IsCheckingSpecs() or not ns.frame or not ns.frame:IsShown() then return end
  ns.SetStatus(ns.BuildPreview(GetDB().text))
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
    if not runner.quiet then
      for line in msg:gmatch("[^\n]+") do Print(line) end
    end
  end
end

local function Summary(plan, res, members)
  local lines = {}
  local wrong = CountWrong(members)
  if wrong == 0 then
    -- Locked players kept out of their group in the groups that play are not
    -- in the right one.
    local right = res.matched
    for _, m in ipairs(members) do
      if m.locked and m.entry and m.group ~= m.entry.group then right = right - 1 end
    end
    lines[1] = "|cff55ff55" .. L["Done!"] .. "|r " .. L["%d of %d players are in the right group."]:format(right, plan.count)
  else
    lines[1] = "|cffff5555" .. L["%d player(s) could not be moved."]:format(wrong) .. "|r"
  end
  AppendStuck(lines, members)
  AppendMissing(lines, res)
  return table.concat(lines, "\n")
end

-- Replaces the layout text, without a preview replacing the status line.
local function SetLayoutText(text)
  GetDB().text = text
  ns.RefreshGrid()
  previewToken = previewToken + 1
end

-- Replaces the layout text and previews it.
function ns.SetLayout(text)
  GetDB().text = text
  ns.RefreshGrid()
  ns.SchedulePreview()
end

-- What Undo brings back: the layout and the locks from before Auto, Balance
-- or filling open slots last replaced the layout, and with auto-save on, the
-- selected boss's saved layout from then.
local undo, undoButton

local function UpdateUndo()
  if undoButton then undoButton:SetEnabled(undo ~= nil) end
end

local function Remember()
  undo = { text = GetDB().text, locks = {} }
  for name, locked in pairs(locks) do undo.locks[name] = locked end
  if GetDB().autoSave then undo.boss, undo.layout = ns.SelectedBossLayout() end
  UpdateUndo()
end

-- The raid stays as it is until Sort raid.
function ns.Undo()
  if not undo then return end
  if runner.active then Stop() end
  local u = undo
  undo = nil
  wipe(locks)
  for name, locked in pairs(u.locks) do locks[name] = locked end
  if u.boss then ns.RestoreBossLayout(u.boss, u.layout) end
  ns.SetLayout(u.text)
  UpdateUndo()
end

-- After Auto or Balance, or when players who are not on the list got a group, the layout
-- takes the raid as it now is, and with auto-save on, the selected boss
-- keeps it. Players on the list who are not in the raid, or whose name
-- matches more than one player, stay on it, and locked players stay locked.
local function KeepResult(res, members)
  local groups = ns.RaidGroups()
  if not groups then return end
  AddMissing(groups, res)
  local text = ns.FormatLayout(groups)
  if text == "" then return end
  if not runner.auto and text ~= GetDB().text then Remember() end
  KeepLocks(members)
  SetLayoutText(text)
  if GetDB().autoSave then ns.SaveToSelectedBoss(text) end
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

-- Matches the layout to the raid members, then the names moved from the grid
-- that are no longer on it, and applies the locks.
local function MatchRunner(members)
  local res = MatchPlan(runner.plan, members)
  local onList, off = {}, {}
  for _, e in ipairs(runner.plan.entries) do onList[e.name] = true end
  for name, g in pairs(runner.moves) do
    if not onList[name] then
      off[g] = off[g] or {}
      table.insert(off[g], name)
    end
  end
  if next(off) then MatchPlan(ns.ParseText(ns.FormatLayout(off)), members) end
  ApplyLocks(members, runner.plan, runner.moves)
  return res
end

-- Takes on moves from the grid ({ [name] = group }, names as on the list).
-- The players moved are not held by their lock, and in a sort for the grid
-- they are the only ones placed.
local function AddMoves(moves)
  for name, g in pairs(moves) do
    runner.moves[name] = g
    if runner.only then runner.only[name] = true end
  end
end

-- One step: wait for the previous move to land, then find the next one.
-- There is never more than one move in flight at a time.
function ns.Step(fromTimeout)
  if not runner.active or runner.checking then return end

  local ok, err = CanArrange()
  if not ok then return Stop("|cffff5555" .. err .. "|r") end

  -- A dead player is out of combat while the raid still fights the boss.
  if InCombatLockdown() or IsEncounterInProgress() then
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
      runner.skipped[p.name] = true -- stays put; the sort goes on with the rest
    else
      return ArmTimeout() -- other raid changes; keep waiting
    end
  end

  local members, counts = ReadRoster()
  local res = MatchRunner(members)
  if runner.targets then ApplyTargets(members, runner.targets) end
  for _, m in ipairs(members) do m.skipped = runner.skipped[m.name] end
  local op, a, b = NextMove(runner.plan, members, counts, runner.moveExtras, runner.only)
  if not op then
    if (runner.auto or runner.placed) and CountWrong(members) == 0 then KeepResult(res, members) end
    if runner.quiet then
      Stop()
      return ns.SchedulePreview()
    end
    return Stop(Summary(runner.plan, res, members))
  end

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

-- auto is true when the layout came from Auto or Balance. moves is set for a move from
-- the grid ({ [name] = group }, names as on the list): only those players
-- are placed, and nothing goes to chat.
function ns.Apply(text, auto, moves)
  if runner.active then Stop() end
  local quiet = moves ~= nil

  local plan = ns.ParseInput(text)
  if plan.empty then
    ns.SetStatus(L["Paste a layout first."])
    Print(L["No layout – paste one in /raidnight first."])
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
    if not quiet then Print(err) end
    return false
  end

  runner.id = runner.id + 1
  local id = runner.id
  runner.active = true
  runner.plan = plan
  runner.auto = auto
  runner.quiet = quiet
  runner.moveExtras = GetDB().moveExtras and not quiet
  runner.moves, runner.only = {}, quiet and {} or nil
  AddMoves(moves or {})
  runner.targets, runner.placed = nil, false
  runner.steps, runner.failures, runner.pending = 0, 0, nil
  runner.skipped = {}
  runner.waitingCombat = false

  -- Players who are not on the list are placed by role, so specs come first.
  -- Auto has just checked them.
  local function Start()
    if not runner.active or runner.id ~= id then return end
    runner.checking = false
    if runner.moveExtras then
      local members = ReadRoster()
      local res = MatchRunner(members)
      runner.targets = PlaceExtras(members, res)
      runner.placed = next(runner.targets) ~= nil
    end
    ns.SetStatus(L["Sorting raid …"])
    ns.Step()
  end
  runner.checking = true
  if runner.moveExtras and not auto then ns.CheckSpecs(Start) else Start() end
  return true
end

function ns.StopSorting()
  if runner.active then Stop(L["Sorting stopped."]) end
end

-- Moves players in the raid for the grid: { [name] = group }, names as on the
-- list, locked or not. The layout has the moves already. Where a group is
-- full, someone in it who is not in their planned group swaps places,
-- preferring a player who is to go where the mover came from. A sort in
-- progress takes the moves on, so moves made one after another wait for each
-- other. Outside a raid it does nothing.
function ns.MoveInRaid(moves)
  if not IsInRaid() or next(moves) == nil then return end
  if runner.active then
    runner.plan = ns.ParseInput(GetDB().text)
    AddMoves(moves)
    return
  end
  ns.Apply(GetDB().text, false, moves)
end

-- Balances the groups that play by role with players from the whole raid
-- (see AutoGroups.lua), makes the result the layout and sorts the raid by it.
-- Auto lets go of all locks.
function ns.Auto()
  if runner.active then Stop() end
  local ok, err = CanArrange()
  if ok and InCombatLockdown() then ok, err = false, L["Auto can't run in combat."] end
  if not ok then
    ns.SetStatus("|cffff5555" .. err .. "|r")
    Print(err)
    return
  end
  ns.CheckSpecs(function()
    local members = ReadRoster()
    local res = MatchPlan(ns.ParseInput(GetDB().text), members)
    local groups, guessed = ns.AutoLayout(members)
    -- Players on the list who are not in the raid stay on it.
    AddMissing(groups, res)
    local text = ns.FormatLayout(groups)
    Remember()
    wipe(locks)
    SetLayoutText(text)
    if #guessed > 0 then
      Print(L["Spec guessed from class: %s"]:format(table.concat(guessed, ", ")))
    end
    ns.Apply(text, true)
  end)
end

local function Percent(share) return math.floor(share * 100 + 0.5) end

-- The groups of half h of the groups that play, as text: "1+2" or "4+5+6".
local function HalfName(play, h)
  local list = {}
  for g = 1, play.count do
    if play.half[g] == h then list[#list + 1] = g end
  end
  return table.concat(list, "+")
end

-- Evens out the damage of the two halves of the groups that play by the last
-- boss pull, or the newest fight in the damage meter, swapping damage
-- dealers (see Balance.lua), makes the result the layout and sorts the raid
-- by it. Each half's goal follows its share of the players. Damage dealers
-- whose damage is not known count as an average one and stay where they
-- are, like locked players.
function ns.Balance()
  if runner.active then Stop() end
  local ok, err = CanArrange()
  if ok and InCombatLockdown() then ok, err = false, L["Balance can't run in combat."] end
  local damage, fight
  if ok then damage, fight = ns.FightDamage() end
  if not damage then
    err = err or fight
    ns.SetStatus("|cffff5555" .. err .. "|r")
    Print(err)
    return
  end
  ns.CheckSpecs(function()
    local plan = ns.ParseInput(GetDB().text)
    local members, counts = ReadRoster()
    local res = MatchPlan(plan, members)
    ApplyLocks(members, plan)
    local play = ns.PlayGroups()
    local size = { 0, 0 }
    for g = 1, play.count do size[play.half[g]] = size[play.half[g]] + (counts[g] or 0) end
    local share = size[1] + size[2] > 0 and size[1] / (size[1] + size[2]) or 0.5
    local players, unknown, known, sum = {}, {}, 0, 0
    for _, m in ipairs(members) do
      local unit = "raid" .. m.index
      local role = ns.UnitRole(unit)
      if m.group <= play.count and (role == "MELEE" or role == "RANGED") then
        local _, class = UnitClass(unit)
        local guid = UnitGUID(unit)
        local amount = (guid and not issecret(guid) and damage[guid]) or damage[m.name]
        players[#players + 1] = {
          name = m.name, group = m.group, role = role, class = class or "",
          damage = amount, movable = amount ~= nil and not m.locked,
        }
        if amount then
          known, sum = known + 1, sum + amount
        else
          unknown[#unknown + 1] = m.name
        end
      end
    end
    for _, p in ipairs(players) do
      if not p.damage then p.damage = known > 0 and sum / known or 0 end
    end

    local swaps, before, after, even = ns.BalanceDamage(players, play.half, share)
    if not swaps then
      ns.SetStatus("|cffff5555" .. L["The damage meter has no damage from this fight."] .. "|r")
      Print(L["The damage meter has no damage from this fight."])
      return
    end
    local first, second = HalfName(play, 1), HalfName(play, 2)
    Print(L["%s: groups %s did %d%% of the damage, groups %s %d%%."]:format(fight, first, Percent(before[1]), second, Percent(before[2])))
    if size[1] ~= size[2] then
      Print(L["Groups %s have %d players and groups %s %d, so the goal is %d%% and %d%%."]:format(
        first, size[1], second, size[2], Percent(share), 100 - Percent(share)))
    end
    if #unknown > 0 then Print(L["No damage known for %s: counted as average."]:format(table.concat(unknown, ", "))) end
    if #swaps == 0 then
      local msg = even and L["Groups %s and %s are already even."]:format(first, second) or L["No swap of damage dealers makes the halves more even."]
      ns.SetStatus(msg)
      Print(msg)
      return
    end

    local groups = ns.RaidGroups()
    if not groups then return end
    local function Replace(g, from, to)
      for i, name in ipairs(groups[g]) do
        if name == from then groups[g][i] = to end
      end
    end
    for _, pair in ipairs(swaps) do
      local p, q = pair[1], pair[2]
      Replace(p.group, p.name, q.name)
      Replace(q.group, q.name, p.name)
      Print(L["%s and %s trade places."]:format(p.name, q.name))
    end
    Print(L["After: groups %s %d%%, groups %s %d%%."]:format(first, Percent(after[1]), second, Percent(after[2])))
    -- Players on the list who are not in the raid stay on it.
    AddMissing(groups, res)
    local text = ns.FormatLayout(groups)
    Remember()
    KeepLocks(members)
    SetLayoutText(text)
    ns.Apply(text, true)
  end)
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

-- Makes text or a code from the website the layout. The grid writes the
-- layout as plain text, so it is stored that way from the start.
local function Import(raw)
  local plan = ns.ParseInput(raw)
  if plan.empty then return end
  if #plan.errors > 0 then
    ns.SetStatus("|cffff5555" .. table.concat(plan.errors, "\n") .. "|r")
    return
  end
  for _, w in ipairs(plan.warnings) do Print(w) end
  ns.SetLayout(ns.FormatLayout(plan.groups))
end

function ns.CreateUI()
  if ns.frame then return ns.frame end

  local f = CreateFrame("Frame", "RaidnightHelperFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetHeight(500) -- the width follows the grid, below
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  table.insert(UISpecialFrames, "RaidnightHelperFrame") -- Esc closes the window

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("Raidnight Helper")

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 16, -126)
  hint:SetText(L["Paste the layout from the website (Ctrl+V):"])

  -- The paste field shows one line. Its edit box is multi-line, so a pasted
  -- text keeps its lines; the scroll frame clips the rest.
  local sf = CreateFrame("ScrollFrame", "RaidnightHelperScrollFrame", f)
  sf:SetPoint("TOPLEFT", 16, -144)
  sf:SetPoint("TOPRIGHT", -16, -144)
  sf:SetHeight(16)

  local bg = f:CreateTexture(nil, "ARTWORK")
  bg:SetColorTexture(0, 0, 0, 0.4)
  bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)

  local eb = CreateFrame("EditBox", "RaidnightHelperEditBox", sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(530)
  eb:SetHeight(16)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- A paste can come in as several text changes, so the field is read a frame
  -- later, when all of it is there, and emptied again.
  local pasteToken = 0
  eb:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    pasteToken = pasteToken + 1
    local token = pasteToken
    C_Timer.After(0, function()
      if token ~= pasteToken then return end
      local text = self:GetText()
      self:SetText("")
      Import(text)
    end)
  end)
  sf:SetScrollChild(eb)
  sf:SetScript("OnSizeChanged", function(_, width) eb:SetWidth(width) end)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

  local grid = ns.CreateGrid(f)
  grid:SetPoint("TOPLEFT", 16, -172)
  f:SetWidth(grid:GetWidth() + 32)

  local cb = CreateFrame("CheckButton", "RaidnightHelperExtrasCheck", f, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", -6, -6)
  cb:SetChecked(GetDB().moveExtras)
  cb:SetScript("OnClick", function(self)
    GetDB().moveExtras = self:GetChecked() and true or false
    ns.SchedulePreview()
  end)
  local cbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbLabel:SetText(L["Fill open slots with players not on the list (by role)"])

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
    ns.Apply(GetDB().text)
  end)

  local invite = MakeButton(f, L["Invite missing"], 140)
  invite:SetPoint("RIGHT", apply, "LEFT", -6, 0)
  invite:SetScript("OnClick", function() ns.InviteMissing(GetDB().text) end)

  local auto = MakeButton(f, L["Auto"], 70)
  auto:SetPoint("RIGHT", invite, "LEFT", -6, 0)
  auto:SetScript("OnClick", function()
    eb:ClearFocus()
    ns.Auto()
  end)

  local balance = MakeButton(f, L["Balance"], 70)
  balance:SetPoint("RIGHT", auto, "LEFT", -6, 0)
  balance:SetScript("OnClick", function()
    eb:ClearFocus()
    ns.Balance()
  end)

  local clear = MakeButton(f, L["Clear"], 70)
  clear:SetPoint("BOTTOMLEFT", 12, 12)
  clear:SetScript("OnClick", function()
    ns.SetLayout("")
    eb:SetFocus()
  end)

  undoButton = MakeButton(f, L["Undo"], 70)
  undoButton:SetPoint("LEFT", clear, "RIGHT", 6, 0)
  undoButton:SetScript("OnClick", ns.Undo)
  UpdateUndo()

  -- The window widens when the buttons need more room, as in longer translations.
  local row = clear:GetWidth() + undoButton:GetWidth() + balance:GetWidth() + auto:GetWidth()
    + invite:GetWidth() + apply:GetWidth() + 4 * 6 + 2 * 12 + 12
  f:SetWidth(math.max(f:GetWidth(), row))

  f:SetScript("OnShow", function()
    ns.UpdatePreview()
    if GetDB().text == "" then eb:SetFocus() end
  end)
  ns.CreateBossBar(f) -- after OnShow is set, since the bar hooks it

  ns.frame, ns.statusText = f, status
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
      RaidnightHelperDB = RaidnightHelperDB or {}
      for k, v in pairs(DEFAULTS) do
        if RaidnightHelperDB[k] == nil then RaidnightHelperDB[k] = v end
      end
      DB = RaidnightHelperDB
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if not IsInRaid() then wipe(locks) end -- locks last for one raid
    ns.RefreshGrid()
    if runner.active then
      runner.eventToken = runner.eventToken + 1
      local token = runner.eventToken
      C_Timer.After(STEP_DELAY, function()
        if runner.active and runner.eventToken == token then ns.Step(false) end
      end)
    else
      ns.SchedulePreview()
    end
  elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
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
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, ...) ns.OnEvent(event, ...) end)

SLASH_RAIDNIGHT1 = "/raidnight"
SLASH_RAIDNIGHT2 = "/rn"
SlashCmdList.RAIDNIGHT = function(msg)
  msg = Trim((msg or ""):lower())
  if msg == "apply" or msg == "sort" then
    ns.Apply(GetDB().text)
  elseif msg == "auto" then
    ns.Auto()
  elseif msg == "balance" then
    ns.Balance()
  elseif msg == "invite" then
    ns.InviteMissing(GetDB().text)
  elseif msg == "send" then
    ns.SendLayouts()
  elseif msg == "stop" then
    ns.StopSorting()
  else
    ns.Toggle()
  end
end
