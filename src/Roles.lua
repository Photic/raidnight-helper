-- Roles
-- Sorts raid members into TANK, HEALER, MELEE or RANGED for Auto. Without a
-- known spec, tanks and healers come from the assigned raid role and damage
-- dealers from their class. Hunters, Shamans, Druids and Demon Hunters have
-- both melee and ranged specs, so for them the spec has to be inspected.
--
-- Specs change between bosses, so they are kept for the session only and
-- refreshed in the background out of combat and outside boss encounters
-- (a dead player is out of combat while the raid still fights the boss):
-- when a player joins, when the game reports a spec change, and when a spec
-- is more than MAX_AGE old.
-- Inspects made by other addons, or by the player, are picked up as well.

local _, ns = ...
local L = ns.L

local MAX_AGE         = 600  -- seconds before a known spec is checked again
local INSPECT_GAP     = 1.5  -- seconds between background inspects
local REQUEST_GAP     = 0.3  -- seconds between inspects while Auto or a sort waits
local INSPECT_TIMEOUT = 3    -- seconds to wait for an inspect answer
local RETRY_AFTER     = 30   -- seconds before a failed inspect is tried again
local RETRY_WAITING   = 10   -- the same while Auto or a sort waits
local IDLE_CHECK      = 60   -- seconds between looks for old specs when nothing is due

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

local MELEE_CLASSES = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, PALADIN = true, MONK = true }
-- Classes with both melee and ranged specs, and the side to guess without one.
local HYBRID_GUESS  = { HUNTER = "RANGED", SHAMAN = "RANGED", DRUID = "RANGED", DEMONHUNTER = "MELEE" }
-- Their melee damage specs: Feral, Survival, Enhancement, Havoc. Other damage specs are ranged.
local MELEE_SPECS   = { [103] = true, [255] = true, [263] = true, [577] = true }

local specs     = {}  -- [guid] = { id = specID, at = GetTime() }
local failed    = {}  -- [guid] = GetTime() of the last inspect that got no answer
local inspecting      -- guid of the inspect in flight
local request         -- { total, done } while Auto or a sort waits for specs
local pumpToken = 0

local SpecInfo = C_SpecializationInfo or {}
local GetSpecIndex = SpecInfo.GetSpecialization or GetSpecialization
local GetSpecInfo  = SpecInfo.GetSpecializationInfo or GetSpecializationInfo

local function SpecOf(unit)
  if UnitIsUnit(unit, "player") then
    local index = GetSpecIndex()
    return index and GetSpecInfo(index)
  end
  local known = specs[UnitGUID(unit)]
  return known and known.id
end

-- Returns the role, and true when it is a guess from the class.
function ns.UnitRole(unit)
  local _, class = UnitClass(unit)
  local spec = SpecOf(unit)
  local role = spec and select(5, GetSpecializationInfoByID(spec)) or UnitGroupRolesAssigned(unit)
  if role == "TANK" or role == "HEALER" then return role end
  if spec and HYBRID_GUESS[class] then
    return MELEE_SPECS[spec] and "MELEE" or "RANGED"
  end
  local guessed = role == "NONE" or HYBRID_GUESS[class] ~= nil
  return HYBRID_GUESS[class] or (MELEE_CLASSES[class] and "MELEE" or "RANGED"), guessed
end

function ns.IsCheckingSpecs() return request ~= nil end

---------------------------------------------------------------------------
-- Inspect queue
---------------------------------------------------------------------------

-- Only damage dealers of the hybrid classes, and players without a role.
local function NeedsSpec(unit)
  if UnitIsUnit(unit, "player") then return false end
  local _, class = UnitClass(unit)
  local role = UnitGroupRolesAssigned(unit)
  return role == "NONE" or (role == "DAMAGER" and HYBRID_GUESS[class] ~= nil)
end

-- Is this raid member's spec unknown or old, and can they be inspected now?
-- After a failed inspect they wait a while, shorter while a request waits.
local function Wanted(unit)
  local guid = UnitGUID(unit)
  if not guid or issecret(guid) or not NeedsSpec(unit) then return false end
  if not UnitIsConnected(unit) or not CanInspect(unit) then return false end
  local known, lastFail = specs[guid], failed[guid]
  if known and GetTime() - known.at <= MAX_AGE then return false end
  return not lastFail or GetTime() - lastFail > (request and RETRY_WAITING or RETRY_AFTER)
end

local function NextWanted()
  for i = 1, GetNumGroupMembers() or 0 do
    local unit = "raid" .. i
    if Wanted(unit) then return unit end
  end
end

local function CountWanted()
  local n = 0
  for i = 1, GetNumGroupMembers() or 0 do
    if Wanted("raid" .. i) then n = n + 1 end
  end
  return n
end

local Pump

local function Schedule(delay)
  pumpToken = pumpToken + 1
  local token = pumpToken
  C_Timer.After(delay, function()
    if token == pumpToken then Pump() end
  end)
end

local function Soon()
  Schedule(request and REQUEST_GAP or INSPECT_GAP)
end

local function FinishRequest()
  local done = request.done
  request = nil
  done()
end

-- After each inspect, answered or not: report progress, then go on.
local function Next()
  if request then
    local left = CountWanted()
    ns.SetStatus(L["Checking specs … (%d/%d)"]:format(math.max(request.total - left, 0), request.total))
  end
  Soon()
end

-- Sends the next inspect. There is never more than one in flight.
function Pump()
  if inspecting then return end
  if not IsInRaid() then
    if request then FinishRequest() end
    return
  end
  -- PLAYER_REGEN_ENABLED or ENCOUNTER_END starts it again.
  if InCombatLockdown() or IsEncounterInProgress() then return end
  if InspectFrame and InspectFrame:IsShown() then return Schedule(5) end -- the player is inspecting someone
  local unit = NextWanted()
  if not unit then
    if request then FinishRequest() end
    if not request then Schedule(IDLE_CHECK) end -- done may have started a new request
    return
  end
  local guid = UnitGUID(unit)
  inspecting = guid
  NotifyInspect(unit)
  C_Timer.After(INSPECT_TIMEOUT, function()
    if inspecting == guid then
      failed[guid] = GetTime()
      inspecting = nil
      Next()
    end
  end)
end

-- Any inspect of a raid member counts, also those sent by other addons.
local function OnInspectReady(guid)
  if not guid or issecret(guid) then return end
  local known = false
  local unit = UnitTokenFromGUID(guid)
  if unit and UnitInRaid(unit) then
    local spec = GetInspectSpecialization(unit)
    if spec and not issecret(spec) and spec > 0 then
      specs[guid] = { id = spec, at = GetTime() }
      failed[guid] = nil
      known = true
    end
  end
  if inspecting == guid then
    inspecting = nil
    if not known then failed[guid] = GetTime() end
    Next()
  end
end

-- Inspects the raid members whose spec is unknown or old, then calls done.
-- Anyone who can't be inspected is left to the class guess. A newer request
-- takes over the wait from an older one.
function ns.CheckSpecs(done)
  if request then
    request.done = done
    return
  end
  request = { done = done }
  request.total = IsInRaid() and CountWanted() or 0
  if request.total == 0 then return FinishRequest() end
  ns.SetStatus(L["Checking specs … (%d/%d)"]:format(0, request.total))
  if not inspecting then Schedule(0) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("INSPECT_READY")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "INSPECT_READY" then
    OnInspectReady(arg1)
    return
  end
  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    local guid = arg1 and UnitGUID(arg1)
    if guid and not issecret(guid) then specs[guid], failed[guid] = nil, nil end
  end
  if not inspecting then Soon() end
end)
