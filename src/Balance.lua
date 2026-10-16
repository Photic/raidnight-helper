-- Balance
-- Evens out the damage of the two halves, groups 1+2 and 3+4, by the damage
-- each damage dealer did in the last boss pull, read from the game's damage
-- meter. Only damage dealers count, and only they move: two in opposite
-- halves trade places, so the halves keep their size, until the halves are
-- within 5% of each other. Auto's rules hold as far as they can: swaps keep
-- melee for melee and ranged for ranged, even if a class then ends up less
-- evenly split (see AutoGroups.lua), before they trade a melee for a ranged.
-- Then as few players as possible move. Locked players stay where they are,
-- and nobody moves twice.
--
-- The damage meter's numbers are secret in combat, so the session of a boss
-- pull is noted once combat is over, and Balance only runs out of combat.
-- The note is saved, so after a reload Balance still finds the boss pull
-- while the damage meter has it; else it takes the newest fight there.

local _, ns = ...
local L = ns.L

local HALF      = { 1, 1, 2, 2 }  -- the half each of groups 1-4 belongs to
local TOLERANCE = 0.05            -- halves this close count as even
local MAX_SWAPS = 4               -- 3 when both halves have more than 8 to move

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

local pulled  -- true while a boss pull's session waits for combat to end

local function Plain(value)
  if not issecret(value) then return value end
end

---------------------------------------------------------------------------
-- Damage meter
---------------------------------------------------------------------------

-- The session to read: the last boss pull's, as RaidnightHelperDB.pullSession
-- ({ id, name, duration }) noted it, while the damage meter still has that
-- session; else the newest. Returns its ID and whether it is the boss pull.
local function Session()
  local noted, newest = ns.GetDB().pullSession
  local found = false
  for _, s in ipairs(C_DamageMeter.GetAvailableCombatSessions() or {}) do
    local id = Plain(s.sessionID)
    if id then
      if not newest or id > newest then newest = id end
      if noted and noted.id == id and noted.name == Plain(s.name) and noted.duration == Plain(s.durationSeconds) then
        found = true
      end
    end
  end
  if found then return noted.id, true end
  return newest, false
end

-- The damage each player did in the fight Balance reads, by GUID and by
-- name, and which fight that is; or nil and why not.
function ns.FightDamage()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromID) then
    return nil, L["The damage meter is not available."]
  end
  local id, boss = Session()
  if not id then return nil, L["The damage meter has no fight yet."] end
  local session = C_DamageMeter.GetCombatSessionFromID(id, Enum.DamageMeterType.DamageDone)
  local damage, any = {}, false
  if session and not issecret(session) then
    for _, source in ipairs(session.combatSources or {}) do
      local amount = source.totalAmount
      if amount and not issecret(amount) then
        if source.sourceGUID and not issecret(source.sourceGUID) then
          damage[source.sourceGUID], any = amount, true
        end
        if source.name and not issecret(source.name) then
          damage[source.name], any = amount, true
        end
      end
    end
  end
  if not any then return nil, L["The damage meter has no damage from this fight."] end
  return damage, boss and L["Last boss pull"] or L["Last fight"]
end

-- The newest session is the boss pull's once combat is over.
local function NotePull()
  pulled = nil
  local newest
  for _, s in ipairs(C_DamageMeter.GetAvailableCombatSessions() or {}) do
    local id = Plain(s.sessionID)
    if id and (not newest or id > newest.sessionID) then newest = s end
  end
  if newest then
    ns.GetDB().pullSession = { id = newest.sessionID, name = Plain(newest.name), duration = Plain(newest.durationSeconds) }
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_END")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return end
  if event == "ENCOUNTER_END" then
    if not IsInRaid() then return end
    pulled = true
    if not InCombatLockdown() then NotePull() end
  elseif pulled then
    NotePull()
  end
end)

---------------------------------------------------------------------------
-- Swaps
---------------------------------------------------------------------------

-- Picks the swaps for players ({ name, group, role, class, damage, movable }),
-- the damage dealers in groups 1-4; movable is false for those who are
-- locked or whose damage is not known. It tries every set of up to
-- MAX_SWAPS swaps. Each set has a level, by how far it bends Auto's rules:
-- 1, only melee for melee and ranged for ranged, and no class less evenly
-- split than before; 2, only the same role; 3, melee for ranged too, but no
-- class less evenly split; 4, anything. Of the sets that get the halves
-- within 5%, the lowest level wins, then the fewest swaps, then the most
-- even. When none does, the set that gets them closest wins. Returns the
-- swaps as { { p, q }, ... } with p from groups 1+2, each half's share of the
-- damage before and after as { half1, half2 }, and whether the halves end up
-- even. Returns nothing when there is no damage at all.
function ns.BalanceDamage(players)
  local sum, count, side = { 0, 0 }, {}, { {}, {} }
  for _, p in ipairs(players) do
    local h = HALF[p.group]
    sum[h] = sum[h] + p.damage
    count[p.class] = count[p.class] or { 0, 0 }
    count[p.class][h] = count[p.class][h] + 1
    if p.movable then table.insert(side[h], p) end
  end
  local total = sum[1] + sum[2]
  if total <= 0 then return end
  local goal = total * TOLERANCE

  local best = { swaps = {}, diff = math.abs(sum[1] - sum[2]), level = 1, gap = sum[1] - sum[2] }
  local function Better(diff, level, n)
    local reach, bestReach = diff <= goal, best.diff <= goal
    if reach ~= bestReach then return reach end
    if not reach then
      if diff ~= best.diff then return diff < best.diff end
      return level < best.level or (level == best.level and n < #best.swaps)
    end
    if level ~= best.level then return level < best.level end
    if n ~= #best.swaps then return n < #best.swaps end
    return diff < best.diff
  end

  -- Class counts per half as the swaps so far leave them.
  local c = {}
  for class, n in pairs(count) do c[class] = { n[1], n[2] } end
  local function ClassWorse()
    for class, n in pairs(c) do
      if math.abs(n[1] - n[2]) > math.abs(count[class][1] - count[class][2]) then return true end
    end
    return false
  end
  local function Move(p, q, n)
    c[p.class][1], c[p.class][2] = c[p.class][1] - n, c[p.class][2] + n
    c[q.class][2], c[q.class][1] = c[q.class][2] - n, c[q.class][1] + n
  end

  local depth = (#side[1] > 8 and #side[2] > 8) and MAX_SWAPS - 1 or MAX_SWAPS
  local chosen, taken = {}, {}
  -- gap is groups 1+2's damage minus groups 3+4's; cross counts melee for ranged.
  local function Search(from, gap, cross)
    local n = #chosen
    if n > 0 then
      local level = (cross > 0 and 3 or 1) + (ClassWorse() and 1 or 0)
      local diff = math.abs(gap)
      if Better(diff, level, n) then
        best = { swaps = { unpack(chosen) }, diff = diff, level = level, gap = gap }
      end
    end
    if n == depth then return end
    -- More swaps can't beat sets that keep all the rules.
    if best.diff <= goal and best.level == 1 and n >= #best.swaps then return end
    for i = from, #side[1] do
      local p = side[1][i]
      for _, q in ipairs(side[2]) do
        if not taken[q] then
          taken[q] = true
          chosen[n + 1] = { p, q }
          Move(p, q, 1)
          Search(i + 1, gap - 2 * (p.damage - q.damage), cross + (p.role ~= q.role and 1 or 0))
          Move(p, q, -1)
          chosen[n + 1] = nil
          taken[q] = nil
        end
      end
    end
  end
  if best.diff > goal then Search(1, sum[1] - sum[2], 0) end

  local after1 = (total + best.gap) / 2
  return best.swaps, { sum[1] / total, sum[2] / total }, { after1 / total, 1 - after1 / total }, best.diff <= goal
end
