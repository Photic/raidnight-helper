-- Minimal WoW API stubs plus a simulated raid server, for running the
-- addon's sorting logic outside the game.
W = { now = 0, timers = {}, seq = 0, frames = {}, roster = {}, moves = 0,
      rejected = {}, printed = {}, log = {}, MOVE_DELAY = 0.2 }
local realprint = print
W.out = realprint

function GetTime() return W.now end
C_Timer = { After = function(d, fn)
  W.seq = W.seq + 1
  table.insert(W.timers, { t = W.now + d, fn = fn, seq = W.seq })
end }

-- Runs timers in time order until cond() is true or limit seconds pass.
function W.RunUntil(cond, limit)
  local stop = W.now + (limit or 600)
  while not (cond and cond()) do
    local best, bi
    for i, t in ipairs(W.timers) do
      if not best or t.t < best.t or (t.t == best.t and t.seq < best.seq) then best, bi = t, i end
    end
    if not best or best.t > stop then return false end
    table.remove(W.timers, bi)
    if best.t > W.now then W.now = best.t end
    best.fn()
  end
  return true
end

local NewFrame
local FrameMT = { __index = function(_, k)
  if type(k) ~= "string" or not k:find("^%u") then return nil end -- fields, not API methods
  if k:find("^Create") then
    return function(self) return NewFrame(self) end
  end
  if k == "IsVisible" or k == "IsShown" then return function() return W.visible end end
  return function() end
end }
function NewFrame(parent)
  local f = setmetatable({ events = {}, scripts = {}, parent = parent }, FrameMT)
  f.RegisterEvent = function(self, e) self.events[e] = true end
  f.SetScript = function(self, s, fn) self.scripts[s] = fn end
  f.HookScript = function(self, s, fn) self.scripts[s] = fn end
  f.GetParent = function(self) return self.parent end
  f.SetText = function(self, t) self.text_ = t end
  f.GetText = function(self) return self.text_ end
  f.SetEnabled = function(self, e) self.enabled = e end
  f.SetShown = function(self, s) self.shown = s end
  f.GetTextWidth = function() return 40 end
  f.GetWidth = function() return 100 end
  table.insert(W.frames, f)
  return f
end
function CreateFrame(kind, name, parent)
  return NewFrame(parent)
end
function W.Fire(event, ...)
  for _, f in ipairs(W.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

function W.Unit(unit)
  local i = unit and unit:match("^raid(%d+)$")
  return i and W.roster[tonumber(i)]
end
function IsInRaid() return #W.roster > 0 end
function GetNumGroupMembers() return #W.roster end
function GetRaidRosterInfo(i)
  local p = W.roster[i]
  if p then return p.name, 0, p.group end
end
-- The instance the player is in: W.instance = { kind = "raid", maxPlayers = 20 },
-- or nil outside one. W.InRaid(maxPlayers) enters a raid instance.
function GetInstanceInfo()
  local i = W.instance
  if not i then return "World", "none", 0, "", 0 end
  return "Raid", i.kind, 16, "Mythic", i.maxPlayers
end
function W.InRaid(maxPlayers) W.instance = { kind = "raid", maxPlayers = maxPlayers } end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return true end
function InCombatLockdown() return W.inCombat == true end
function IsEncounterInProgress() return false end

-- The damage meter: one session per fight, damage by player name. Sessions
-- live outside the UI, so they survive W.Reload.
Enum = { DamageMeterType = { DamageDone = 0 } }
W.sessions = {}
C_DamageMeter = {
  GetAvailableCombatSessions = function()
    local list = {}
    for id, s in pairs(W.sessions) do
      list[#list + 1] = { sessionID = id, name = s.name, durationSeconds = s.duration }
    end
    return list
  end,
  GetCombatSessionFromID = function(id)
    local s = W.sessions[id]
    if not s then return nil end
    local sources = {}
    for name, amount in pairs(s.damage) do
      sources[#sources + 1] = { name = name, sourceGUID = "guid-" .. name, classFilename = "MAGE", totalAmount = amount }
    end
    return { combatSources = sources }
  end,
}
-- A fight in the damage meter; damage = { [name] = amount }.
function W.Fight(damage, name)
  local id = 0
  for k in pairs(W.sessions) do if k > id then id = k end end
  W.sessions[id + 1] = { damage = damage, name = name or "", duration = 60 + id }
end
-- A boss pull that ends out of combat.
function W.Pull(damage)
  W.Fight(damage, "Boss")
  W.Fire("ENCOUNTER_END", 3000, "Boss", 16, 20, 1)
end
-- /reload: the UI and its state start over; saved variables, the raid and
-- the damage meter stay.
function W.Reload()
  W.frames, W.timers = {}, {}
  W.Load(W.dir)
end
function UnitClass(unit) local p = W.Unit(unit); if p then return p.class, p.class end end
function UnitGroupRolesAssigned(unit) local p = W.Unit(unit); return p and p.role or "NONE" end
function UnitIsUnit() return false end
function UnitGUID(unit) local p = W.Unit(unit); return p and ("guid-" .. p.name) end
function UnitIsConnected() return true end
function CanInspect() return false end
function NotifyInspect() end
function GetSpecializationInfoByID() return nil end
function GetSpecialization() return nil end
function GetSpecializationInfo() return nil end
function UnitTokenFromGUID() return nil end
function UnitInRaid() return nil end
function GetInspectSpecialization() return 0 end
function GetLocale() return "enUS" end
function GetNormalizedRealmName() return "Home" end
function GetRealmName() return "Home" end
function IsInGroup() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function time() return os.time() end
date = os.date
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  table.insert(W.printed, table.concat(parts, " "))
end
RAID_CLASS_COLORS = {}
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
GameTooltip = NewFrame()
YES, NO = "Yes", "No"
LE_PARTY_CATEGORY_INSTANCE = 2

-- The server: a move lands after MOVE_DELAY, unless the group is full by then
-- or the player is marked as rejected.
local function Count(g)
  local n = 0
  for _, p in ipairs(W.roster) do if p.group == g then n = n + 1 end end
  return n
end
W.Count = Count
function SetRaidSubgroup(i, g)
  W.moves = W.moves + 1
  local p = W.roster[i]
  table.insert(W.log, ("set %s %d->%d"):format(p.name, p.group, g))
  C_Timer.After(W.MOVE_DELAY, function()
    if W.rejected[p.name] or Count(g) >= 5 then return end
    p.group = g
    W.Fire("GROUP_ROSTER_UPDATE")
  end)
end
function SwapRaidSubgroup(i, j)
  W.moves = W.moves + 1
  local a, b = W.roster[i], W.roster[j]
  table.insert(W.log, ("swap %s(%d) %s(%d)"):format(a.name, a.group, b.name, b.group))
  C_Timer.After(W.MOVE_DELAY, function()
    if W.rejected[a.name] or W.rejected[b.name] then return end
    a.group, b.group = b.group, a.group
    W.Fire("GROUP_ROSTER_UPDATE")
  end)
end

-- Loads the addon from dir, in the order of its .toc file.
function W.Load(dir)
  W.dir = dir
  W.ns = {}
  for line in io.lines(dir .. "/RaidnightHelper.toc") do
    local file = line:match("^([%w_]+%.lua)")
    if file then
      local f = assert(loadfile(dir .. "/" .. file))
      f("RaidnightHelper", W.ns)
    end
  end
  W.Fire("ADDON_LOADED", "RaidnightHelper")
  return W.ns
end

-- players: { "Name:group:CLASS:ROLE", ... }
function W.Setup(players)
  W.roster = {}
  for _, s in ipairs(players) do
    local name, g, class, role = s:match("^([^:]+):(%d+):(%u+):(%u+)$")
    assert(name, s)
    table.insert(W.roster, { name = name, group = tonumber(g), class = class, role = role })
  end
  W.Fire("GROUP_ROSTER_UPDATE")
end

function W.GroupOf(name)
  for _, p in ipairs(W.roster) do if p.name == name then return p.group end end
end

function W.Idle() return not W.ns.IsRunning() end

-- Sorts by text and waits for the sort to end.
function W.Sort(text)
  W.ns.SetLayout(text)
  W.ns.Apply(text)
  return W.RunUntil(W.Idle, 900)
end
