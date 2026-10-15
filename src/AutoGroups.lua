-- AutoGroups
-- Balances groups 1-4 by role. Groups 1+2 and 3+4 form two halves, and each
-- half gets the same share of tanks, healers, melee and ranged, as close as
-- the raid allows. Within a half, the two groups are balanced the same way.
-- Groups 5-8 are left alone, so a bench stays a bench.
--
-- 20 players with 2 tanks, 4 healers, 7 melee and 7 ranged come out as:
--
--   Group 1: T H M R R     Group 3: T H M M R
--   Group 2: H M M R R     Group 4: H M M R R

local _, ns = ...

local AUTO_GROUPS = 4
local GROUP_SIZE  = 5
local HALF        = { 1, 1, 2, 2 }  -- the half each of groups 1-4 belongs to
local PER_HALF    = { TANK = 1, HEALER = 2 }

ns.AUTO_GROUPS = AUTO_GROUPS

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

-- Gives each player ({ role = r }) a .target in groups 1-4, around the fixed
-- players already there ({ group = g, role = r }). When there are more players
-- than free slots, the order below decides who gets one; players earlier in
-- the list go first within the same role. Players who don't fit get no target.
function ns.BalanceGroups(fixed, players)
  local size, inGroup, inHalf = {}, {}, { {}, {} }
  for g = 1, AUTO_GROUPS do size[g], inGroup[g] = 0, {} end

  local function Count(h, role) return inHalf[h][role] or 0 end

  local function Add(g, role)
    size[g] = size[g] + 1
    inGroup[g][role] = (inGroup[g][role] or 0) + 1
    inHalf[HALF[g]][role] = Count(HALF[g], role) + 1
  end
  for _, p in ipairs(fixed) do Add(p.group, p.role) end

  local tried = {}
  local function Place(p)
    tried[p] = true
    local best, bestScore
    for g = 1, AUTO_GROUPS do
      if size[g] < GROUP_SIZE then
        -- Fewest of this role in the half, then in the group, then the emptiest group.
        local score = Count(HALF[g], p.role) * 100 + (inGroup[g][p.role] or 0) * 10 + size[g]
        if not best or score < bestScore then best, bestScore = g, score end
      end
    end
    if best then
      p.target = best
      Add(best, p.role)
    end
  end

  local function NextOf(role)
    for _, p in ipairs(players) do
      if p.role == role and not tried[p] then return p end
    end
  end

  -- 1. Tanks and healers a half is missing: 1 tank and 2 healers each.
  for _, role in ipairs({ "TANK", "HEALER" }) do
    local p = NextOf(role)
    while p and (Count(1, role) < PER_HALF[role] or Count(2, role) < PER_HALF[role]) do
      Place(p)
      p = NextOf(role)
    end
  end

  -- 2. Damage, taking melee or ranged by whichever there is fewer of so far.
  while true do
    local melee, ranged = NextOf("MELEE"), NextOf("RANGED")
    if not (melee or ranged) then break end
    local fewerMelee = Count(1, "MELEE") + Count(2, "MELEE") <= Count(1, "RANGED") + Count(2, "RANGED")
    if melee and ranged then
      Place(fewerMelee and melee or ranged)
    else
      Place(melee or ranged)
    end
  end

  -- 3. Any further tanks and healers.
  for _, role in ipairs({ "TANK", "HEALER" }) do
    local p = NextOf(role)
    while p do
      Place(p)
      p = NextOf(role)
    end
  end
end

-- A layout for the whole raid: groups 1-4 balanced, groups 5-8 as they are.
-- Also returns the names whose role was guessed from the class.
function ns.AutoLayout()
  local players, groups, guessed = {}, {}, {}
  for i = 1, GetNumGroupMembers() or 0 do
    local name, _, subgroup = GetRaidRosterInfo(i)
    if name and subgroup and not issecret(name) and not issecret(subgroup) then
      if subgroup <= AUTO_GROUPS then
        local role, guess = ns.UnitRole("raid" .. i)
        players[#players + 1] = { name = name, role = role }
        if guess then guessed[#guessed + 1] = name end
      else
        groups[subgroup] = groups[subgroup] or {}
        table.insert(groups[subgroup], name)
      end
    end
  end

  ns.BalanceGroups({}, players)
  for _, p in ipairs(players) do
    groups[p.target] = groups[p.target] or {}
    table.insert(groups[p.target], p.name)
  end
  return ns.FormatLayout(groups), guessed
end
