-- AutoGroups
-- Balances groups 1-4 by role. Groups 1+2 and 3+4 form two halves, and each
-- half gets the same share of tanks, healers, melee and ranged, as close as
-- the raid allows. Within a half, the two groups are balanced the same way.
-- Damage dealers of the same class are split between the halves as well, as
-- far as the melee and ranged balance allows: 2 Hunters means 1 per half.
-- Who gets a slot in groups 1-4 is picked from the whole raid (see
-- ns.AutoLayout); everyone else waits in groups 5-8. Auto then moves as few
-- players as it can: only the half matters, not the group within it.
--
-- 20 players with 2 tanks, 4 healers, 7 melee and 7 ranged come out as:
--
--   Group 1: T H M R R     Group 3: T H M M R
--   Group 2: H M M R R     Group 4: H M M R R

local _, ns = ...

local AUTO_GROUPS = 4
local MAX_GROUPS  = 8
local GROUP_SIZE  = 5
local HALF        = { 1, 1, 2, 2 }  -- the half each of groups 1-4 belongs to
local PER_HALF    = { TANK = 1, HEALER = 2 }
local DAMAGE      = { MELEE = true, RANGED = true }

ns.AUTO_GROUPS = AUTO_GROUPS

-- Gives each player ({ role = r, class = c }) a .target in groups 1-4, around
-- the fixed players already there ({ group = g, role = r, class = c }). A
-- fixed player without a role holds the slot for someone who is not in the
-- raid. When there are more players than free slots, the order below decides
-- who gets one; players earlier in the list go first within the same role.
-- Players who don't fit get no target.
function ns.BalanceGroups(fixed, players)
  local size, inGroup, inHalf = {}, {}, { {}, {} }
  for g = 1, AUTO_GROUPS do size[g], inGroup[g] = 0, {} end

  local function Count(h, role) return inHalf[h][role] or 0 end

  local function Add(g, role)
    size[g] = size[g] + 1
    inGroup[g][role] = (inGroup[g][role] or 0) + 1
    inHalf[HALF[g]][role] = Count(HALF[g], role) + 1
  end
  for _, p in ipairs(fixed) do
    if p.role then Add(p.group, p.role) else size[p.group] = size[p.group] + 1 end
  end

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

  -- Is a half short of the role, with room to take one more?
  local function Missing(role)
    for g = 1, AUTO_GROUPS do
      if size[g] < GROUP_SIZE and Count(HALF[g], role) < PER_HALF[role] then return true end
    end
    return false
  end

  -- 1. Tanks and healers a half is missing: 1 tank and 2 healers each.
  for _, role in ipairs({ "TANK", "HEALER" }) do
    local p = NextOf(role)
    while p and Missing(role) do
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

  -- 4. Damage dealers of the same class, split between the halves: two of the
  -- same role in opposite halves swap groups while that evens out the classes.
  -- Each group keeps its roles, so steps 1-3 stand. Fixed players count, but
  -- stay where they are.
  local classInHalf = { {}, {} }
  local function ClassCount(h, class) return classInHalf[h][class] or 0 end
  local function AddClass(h, class, n) classInHalf[h][class] = ClassCount(h, class) + n end
  local function Counts(p) return p.class and DAMAGE[p.role] end
  for _, p in ipairs(fixed) do
    if Counts(p) then AddClass(HALF[p.group], p.class, 1) end
  end
  for _, p in ipairs(players) do
    if p.target and Counts(p) then AddClass(HALF[p.target], p.class, 1) end
  end

  -- Swaps the first pair where p's class has 2 or more extra in p's half and
  -- q's class has more in q's half. Returns true when it swapped.
  local function Swap()
    for _, p in ipairs(players) do
      for _, q in ipairs(players) do
        if p.target and q.target and Counts(p) and Counts(q) and p.role == q.role then
          local hp, hq = HALF[p.target], HALF[q.target]
          if ClassCount(hp, p.class) - ClassCount(hq, p.class) >= 2
            and ClassCount(hq, q.class) > ClassCount(hp, q.class) then
            p.target, q.target = q.target, p.target
            AddClass(hp, p.class, -1)
            AddClass(hq, p.class, 1)
            AddClass(hq, q.class, -1)
            AddClass(hp, q.class, 1)
            return true
          end
        end
      end
    end
  end
  -- Each swap makes the classes more even, so this ends.
  while Swap() do end
end

-- Moves as few players as it can, for the players BalanceGroups gave a
-- .target, from the .group they are in now. Only the half counts, so two
-- players in opposite halves trade halves, or one moves over to the smaller
-- half, when that saves a move and leaves no role, and no class of damage
-- dealers, less evenly split between the halves. Within their half, players
-- keep their own group, and the others fill the free slots. Sets .target.
local function KeepInPlace(players)
  local half, size, count = {}, { 0, 0 }, {}
  local function Keys(p)
    if DAMAGE[p.role] and p.class then return { p.role, "class:" .. p.class } end
    return { p.role }
  end
  local function Add(p, n)
    local h = half[p]
    size[h] = size[h] + n
    for _, key in ipairs(Keys(p)) do
      count[key] = count[key] or { 0, 0 }
      count[key][h] = count[key][h] + n
    end
  end
  local function Flip(p)
    Add(p, -1)
    half[p] = 3 - half[p]
    Add(p, 1)
  end
  for _, p in ipairs(players) do
    half[p] = HALF[p.target]
    Add(p, 1)
  end

  local function Stays(p, h) return p.group <= AUTO_GROUPS and HALF[p.group] == h end
  -- Moves saved when the players in list go over to the other half.
  local function Saved(list)
    local n = 0
    for _, p in ipairs(list) do
      if Stays(p, 3 - half[p]) then n = n + 1 end
      if Stays(p, half[p]) then n = n - 1 end
    end
    return n
  end
  -- Sends the players in list over to the other half, unless that leaves a
  -- role, a class or the half sizes less even, or a half over 10.
  local function TryFlip(list)
    local before = {}
    for _, p in ipairs(list) do
      for _, key in ipairs(Keys(p)) do before[key] = math.abs(count[key][1] - count[key][2]) end
    end
    local sizes = math.abs(size[1] - size[2])
    for _, p in ipairs(list) do Flip(p) end
    local even = math.abs(size[1] - size[2]) <= sizes
      and size[1] <= 2 * GROUP_SIZE and size[2] <= 2 * GROUP_SIZE
    for key, n in pairs(before) do
      if math.abs(count[key][1] - count[key][2]) > n then even = false end
    end
    if not even then
      for _, p in ipairs(list) do Flip(p) end
    end
    return even
  end

  -- Each flip saves a move, so this ends.
  local better = true
  while better do
    better = false
    for _, p in ipairs(players) do
      for _, q in ipairs(players) do
        if half[p] ~= half[q] and Saved({ p, q }) > 0 and TryFlip({ p, q }) then better = true end
      end
      if Saved({ p }) > 0 and TryFlip({ p }) then better = true end
    end
  end

  local inGroup, coming = { 0, 0, 0, 0 }, {}
  for _, p in ipairs(players) do
    if Stays(p, half[p]) then
      p.target = p.group
      inGroup[p.group] = inGroup[p.group] + 1
    else
      coming[#coming + 1] = p
    end
  end
  for _, p in ipairs(coming) do
    local best
    for g = 1, AUTO_GROUPS do
      if HALF[g] == half[p] and inGroup[g] < GROUP_SIZE and (not best or inGroup[g] < inGroup[best]) then
        best = g
      end
    end
    p.target = best
    inGroup[best] = inGroup[best] + 1
  end
end

-- A layout for the whole raid as { [group] = { names } }, from the raid
-- members ({ index, name, group, desired }, desired being the group the list
-- puts them in). Groups 1-4 take the players the list puts there, and the
-- slots left go to the others by role, those in groups 1-4 now first; then
-- everyone in groups 1-4 is balanced together, moving as few players as it
-- can (see KeepInPlace). Players the list puts in
-- groups 5-8 stay out. Everyone without a slot waits in groups 5-8: in the
-- group they are in when it is one of those, else in their group on the list
-- or the first group with room. Also returns the names in groups 1-4 whose
-- role was guessed from the class.
function ns.AutoLayout(members)
  local groups = {}
  local function Room(g) return #(groups[g] or {}) < GROUP_SIZE end
  local function Put(g, name)
    groups[g] = groups[g] or {}
    table.insert(groups[g], name)
  end

  local listed, others, later, bench = {}, {}, {}, {}
  for _, m in ipairs(members) do
    local role, guess = ns.UnitRole("raid" .. m.index)
    local _, class = UnitClass("raid" .. m.index)
    local p = { name = m.name, group = m.group, desired = m.desired, role = role, class = class, guess = guess }
    if m.desired and m.desired <= AUTO_GROUPS then
      listed[#listed + 1] = p
    elseif m.desired then
      bench[#bench + 1] = p
    elseif m.group <= AUTO_GROUPS then
      others[#others + 1] = p
    else
      later[#later + 1] = p
    end
  end
  for _, p in ipairs(later) do others[#others + 1] = p end

  -- Who plays: the list's players, balanced on their own, and then as many
  -- of the others as there is room for, picked by role around them.
  ns.BalanceGroups({}, listed)
  local fixed = {}
  for _, p in ipairs(listed) do
    if p.target then fixed[#fixed + 1] = { group = p.target, role = p.role, class = p.class } end
  end
  ns.BalanceGroups(fixed, others)
  local playing = {}
  for _, list in ipairs({ listed, others }) do
    for _, p in ipairs(list) do
      if p.target then playing[#playing + 1] = p else bench[#bench + 1] = p end
      p.target = nil
    end
  end

  -- Then everyone who plays is balanced together, moving as few as it can.
  ns.BalanceGroups({}, playing)
  local placed, guessed = {}, {}
  for _, p in ipairs(playing) do
    if p.target then placed[#placed + 1] = p else bench[#bench + 1] = p end
  end
  KeepInPlace(placed)
  for _, p in ipairs(placed) do
    Put(p.target, p.name)
    if p.guess then guessed[#guessed + 1] = p.name end
  end

  local function FirstRoom(from)
    for g = from, MAX_GROUPS do
      if Room(g) then return g end
    end
  end
  local moving = {}
  for _, p in ipairs(bench) do
    if p.group > AUTO_GROUPS then Put(p.group, p.name) else moving[#moving + 1] = p end
  end
  for _, p in ipairs(moving) do
    local g = p.desired
    if not (g and g > AUTO_GROUPS and Room(g)) then g = FirstRoom(AUTO_GROUPS + 1) or FirstRoom(1) end
    if g then Put(g, p.name) end
  end
  return groups, guessed
end
