-- Random raids and layouts; FUZZ(mode, seed) returns true, stats or false, why.
local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "WARLOCK", "DEATHKNIGHT", "PALADIN", "MONK",
                  "EVOKER", "HUNTER", "DRUID", "SHAMAN", "DEMONHUNTER" }

-- Outside an instance, or in a raid that lets 20, 25 or 30 players in.
local function RandomInstance()
  local r = math.random(4)
  W.instance = nil
  if r > 1 then W.InRaid(({ 20, 25, 30 })[r - 1]) end
end

local function RandomRaid(nmin, nmax)
  RandomInstance()
  local n = math.random(nmin, nmax)
  local players, counts = {}, {}
  for i = 1, n do
    local g
    repeat g = math.random(1, 8) until (counts[g] or 0) < 5
    counts[g] = (counts[g] or 0) + 1
    local r = math.random()
    local role = r < 0.1 and "TANK" or r < 0.3 and "HEALER" or "DAMAGER"
    players[i] = ("P%d:%d:%s:%s"):format(i, g, CLASSES[math.random(#CLASSES)], role)
  end
  W.Setup(players)
  return n
end

-- A random layout: each player with chance pOn, mostly in groups 1-4.
local function RandomLayout(n, pOn, missing)
  local groups, count = {}, {}
  local function Add(name)
    for _ = 1, 30 do
      local g = math.random() < 0.8 and math.random(1, 4) or math.random(5, 8)
      if (count[g] or 0) < 5 then
        count[g] = (count[g] or 0) + 1
        groups[g] = groups[g] or {}
        table.insert(groups[g], name)
        return
      end
    end
  end
  for i = 1, n do if math.random() < pOn then Add("P" .. i) end end
  for i = 1, missing do Add("Missing" .. i) end
  return groups
end

local function Planned(text)
  local plan = W.ns.ParseInput(text)
  local where = {}
  for _, e in ipairs(plan.entries) do where[e.name] = e.group end
  return where, plan.count > 0
end

local function Sort(seed)
  local n = RandomRaid(8, 30)
  local groups = RandomLayout(n, 0.85, math.random(0, 2))
  for i = 1, n do
    local r = math.random()
    if r < 0.1 then W.ns.SetLocked("P" .. i, true) elseif r < 0.2 then W.ns.SetLocked("P" .. i, false) end
  end
  W.ns.GetDB().moveExtras = math.random() < 0.5
  local text = W.ns.FormatLayout(groups)
  if text == "" then return true, {} end
  local planned, hasList = Planned(text)
  local start, locked = {}, {}
  for _, p in ipairs(W.roster) do
    start[p.name] = p.group
    locked[p.name] = W.ns.IsLocked(p.name, planned[p.name] ~= nil, hasList)
  end
  if not W.Sort(text) then return false, "did not end" end
  local status = W.ns.lastStatus or ""
  local play = W.ns.PlayGroups()
  -- Locked players never go into the groups that play, so once the groups
  -- after them are full, the list can't always be met; the summary then
  -- names the locked players in the way.
  local benchFull = true
  for g = play.count + 1, 8 do
    if W.Count(g) < 5 then benchFull = false end
  end
  local blocked = benchFull and status:find("Locked players in the way:", 1, true) ~= nil
  for _, p in ipairs(W.roster) do
    local want = planned[p.name]
    if locked[p.name] then
      if p.group <= play.count and p.group ~= start[p.name] then
        return false, ("%s is locked but moved %d -> %d"):format(p.name, start[p.name], p.group)
      end
      if want and want > play.count and p.group ~= want and not blocked then
        return false, ("%s is locked, planned for %d, in %d"):format(p.name, want, p.group)
      end
    elseif want and p.group ~= want and not blocked then
      return false, ("%s planned for %d is in %d | %s"):format(p.name, want, p.group, status)
    end
  end
  if not status:find("Done!") and not blocked then return false, "no Done: " .. status end
  return true, { moves = W.moves, seconds = W.now, blocked = blocked and 1 or 0 }
end

-- Everyone on the list, no locks: how many moves a sort takes.
local function Moves(seed)
  local n = RandomRaid(10, 30)
  local groups = RandomLayout(n, 1, 0)
  local text = W.ns.FormatLayout(groups)
  local planned = Planned(text)
  if not W.Sort(text) then return false, "did not end" end
  for _, p in ipairs(W.roster) do
    if planned[p.name] and p.group ~= planned[p.name] then return false, p.name .. " off" end
  end
  return true, { moves = W.moves, seconds = W.now }
end

local function Auto(seed)
  local n = RandomRaid(10, 30)
  local groups = RandomLayout(n, math.random() < 0.3 and 0 or 0.8, math.random(0, 2))
  for i = 1, n do if math.random() < 0.15 then W.ns.SetLocked("P" .. i, math.random() < 0.5) end end
  local before = W.ns.FormatLayout(groups)
  local planned = Planned(before)
  W.ns.SetLayout(before)
  W.ns.Auto()
  if not W.RunUntil(W.Idle, 900) then return false, "did not end" end
  local text = W.ns.GetDB().text
  local plan = W.ns.ParseInput(text)
  if #plan.errors > 0 then return false, "layout errors: " .. plan.errors[1] end
  local seen = {}
  for _, e in ipairs(plan.entries) do seen[e.name] = e.group end
  local play = W.ns.PlayGroups()
  local inPlay, eligible, size = 0, 0, { 0, 0 }
  for _, p in ipairs(W.roster) do
    if not seen[p.name] then return false, p.name .. " not in layout" end
    if seen[p.name] ~= p.group then return false, p.name .. " not sorted" end
    if W.ns.IsLocked(p.name, true, true) then return false, p.name .. " still locked" end
    local want = planned[p.name]
    if p.group <= play.count then
      inPlay = inPlay + 1
      size[play.half[p.group]] = size[play.half[p.group]] + 1
    end
    if want and want > play.count then
      if p.group <= play.count then return false, p.name .. " list bench pulled in" end
    else
      eligible = eligible + 1
    end
    if want and want <= play.count and p.group > play.count then
      return false, p.name .. " on list for the groups that play left out"
    end
  end
  if inPlay ~= math.min(play.count * 5, eligible) then
    return false, ("groups 1-%d have %d, expected %d"):format(play.count, inPlay, math.min(play.count * 5, eligible))
  end
  return true, { moves = W.moves, halves = math.abs(size[1] - size[2]) }
end

-- Drags, some while moves are in flight, on top of a sort.
local function Drags(seed)
  local n = RandomRaid(10, 25)
  local groups = RandomLayout(n, 1, 0)
  local text = W.ns.FormatLayout(groups)
  W.ns.SetLayout(text)
  W.ns.Apply(text)
  for _ = 1, math.random(1, 6) do
    W.RunUntil(nil, math.random() * 0.6)
    groups = W.ns.ParseInput(W.ns.GetDB().text).groups
    local g1, g2 = math.random(1, 8), math.random(1, 8)
    local a = groups[g1] and groups[g1][math.random(math.max(#groups[g1], 1))]
    if a then
      local b = groups[g2] and groups[g2][math.random(math.max(#groups[g2], 1))]
      local moves = {}
      if b and b ~= a then
        for i, x in ipairs(groups[g1]) do if x == a then groups[g1][i] = b end end
        for i, x in ipairs(groups[g2]) do if x == b then groups[g2][i] = a end end
        moves[a], moves[b] = g2, g1
      elseif #(groups[g2] or {}) < 5 and g1 ~= g2 then
        for i, x in ipairs(groups[g1]) do if x == a then table.remove(groups[g1], i) break end end
        groups[g2] = groups[g2] or {}
        table.insert(groups[g2], a)
        moves[a] = g2
      end
      W.ns.SetLayout(W.ns.FormatLayout(groups))
      W.ns.MoveInRaid(moves)
    end
  end
  if not W.RunUntil(W.Idle, 900) then return false, "did not end" end
  local planned = Planned(W.ns.GetDB().text)
  for _, p in ipairs(W.roster) do
    if planned[p.name] and p.group ~= planned[p.name] then
      return false, ("%s planned for %d is in %d"):format(p.name, planned[p.name], p.group)
    end
  end
  return true, { moves = W.moves }
end

local MELEE_DPS  = { "WARRIOR", "ROGUE", "DEATHKNIGHT", "PALADIN", "MONK", "DEMONHUNTER" }
local RANGED_DPS = { "MAGE", "WARLOCK", "PRIEST", "EVOKER", "HUNTER" }

-- ns.BalanceDamage on random damage dealers in 4, 5 or 6 groups, checked
-- against the rules. Counts (not fails) where a brute force finds better
-- than the greedy picks.
local function BalanceUnit(seed)
  local count = math.random(4, 6)
  local groupHalf, inHalf = {}, { {}, {} }
  for g = 1, count do
    groupHalf[g] = g <= math.ceil(count / 2) and 1 or 2
    table.insert(inHalf[groupHalf[g]], g)
  end
  local players = {}
  for h = 1, 2 do
    for _ = 1, math.random(2, 8) do
      local melee = math.random() < 0.5
      local classes = melee and MELEE_DPS or RANGED_DPS
      players[#players + 1] = {
        name = "P" .. (#players + 1), group = inHalf[h][math.random(#inHalf[h])],
        role = melee and "MELEE" or "RANGED", class = classes[math.random(math.random(2, #classes))],
        damage = math.floor(200 + math.random() ^ 2 * 3000), movable = math.random() < 0.85,
      }
    end
  end
  -- Half 1's share of the players: even halves, or up to 15 to 10.
  local share = count == 5 and 0.5 + math.random() * 0.1 or 0.5
  local half = function(p) return groupHalf[p.group] end
  local sum = { 0, 0 }
  for _, p in ipairs(players) do sum[half(p)] = sum[half(p)] + p.damage end
  local total = sum[1] + sum[2]
  local goal = total * 0.05
  -- Twice what half 1 did over its share, when it did s1.
  local function Gap(s1) return 2 * (s1 - share * total) end
  local swaps, before, after, even = W.ns.BalanceDamage(players, groupHalf, share)

  -- Replay the swaps: disjoint, movable, from opposite halves, closer in the end.
  local where, used, s, cross = {}, {}, { sum[1], sum[2] }, 0
  for _, p in ipairs(players) do where[p] = half(p) end
  local diff = math.abs(Gap(s[1]))
  if diff <= goal and #swaps > 0 then return false, "swapped although even" end
  for _, pair in ipairs(swaps) do
    local p, q = pair[1], pair[2]
    if used[p] or used[q] then return false, "someone moved twice" end
    if not (p.movable and q.movable) then return false, "moved a fixed player" end
    if where[p] ~= 1 or where[q] ~= 2 then return false, "not opposite halves" end
    used[p], used[q] = true, true
    s[1], s[2] = s[1] - p.damage + q.damage, s[2] - q.damage + p.damage
    where[p], where[q] = 2, 1
    if p.role ~= q.role then cross = cross + 1 end
  end
  if #swaps > 0 and math.abs(Gap(s[1])) >= diff then return false, "the swaps did not help" end
  diff = math.abs(Gap(s[1]))
  if math.abs(after[1] * total - s[1]) > 0.01 then return false, "after share wrong" end
  if even ~= (diff <= goal) then return false, "even flag wrong" end

  -- One same-role swap that reaches the goal without splitting a class worse
  -- means exactly that kind of swap.
  local function ClassWorse(p, q)
    if p.class == q.class then return false end
    local n = {}
    for _, x in ipairs(players) do
      n[x.class] = n[x.class] or { 0, 0 }
      n[x.class][half(x)] = n[x.class][half(x)] + 1
    end
    local a, b = n[p.class], n[q.class]
    return math.abs(a[1] - 1 - a[2] - 1) > math.abs(a[1] - a[2]) or math.abs(b[2] - 1 - b[1] - 1) > math.abs(b[1] - b[2])
  end
  local d0 = math.abs(Gap(sum[1]))
  local tier1 = false
  for _, p in ipairs(players) do
    for _, q in ipairs(players) do
      if p.movable and q.movable and half(p) == 1 and half(q) == 2 and p.role == q.role and not ClassWorse(p, q)
        and math.abs(Gap(sum[1]) - 2 * (p.damage - q.damage)) <= goal and d0 > goal then
        tier1 = true
      end
    end
  end
  if tier1 and not (#swaps == 1 and swaps[1][1].role == swaps[1][2].role) then
    return false, "a single same-role swap would do, got " .. #swaps .. " swaps"
  end

  -- Brute force: up to 3 disjoint swaps, same role only and any role.
  local pairsSame, pairsAny = {}, {}
  for _, p in ipairs(players) do
    for _, q in ipairs(players) do
      if p.movable and q.movable and half(p) == 1 and half(q) == 2 then
        pairsAny[#pairsAny + 1] = { p, q }
        if p.role == q.role then pairsSame[#pairsSame + 1] = { p, q } end
      end
    end
  end
  local function Reach(list, depth, from, d, taken)
    if math.abs(d) <= goal then return true end
    if depth == 0 then return false end
    for i = from, #list do
      local p, q = list[i][1], list[i][2]
      if not taken[p] and not taken[q] then
        taken[p], taken[q] = true, true
        local r = Reach(list, depth - 1, i + 1, d - 2 * (p.damage - q.damage), taken)
        taken[p], taken[q] = nil, nil
        if r then return true end
      end
    end
    return false
  end
  local d1 = Gap(sum[1])
  local stats = { swaps = #swaps, uneven = even and 0 or 1, crossUsed = cross > 0 and 1 or 0 }
  stats.sameMissed = (cross > 0 and #pairsSame <= 60 and Reach(pairsSame, 3, 1, d1, {})) and 1 or 0
  stats.anyMissed = (not even and #pairsAny <= 80 and Reach(pairsAny, 3, 1, d1, {})) and 1 or 0
  return true, stats
end

-- The Balance button on random raids.
local function BalanceRaid(seed)
  local n = RandomRaid(10, 30)
  local damage, before, locked = {}, {}, {}
  for _, p in ipairs(W.roster) do
    if math.random() < 0.9 then damage[p.name] = math.floor(200 + math.random() ^ 2 * 3000) end
    if math.random() < 0.15 then W.ns.SetLocked(p.name, true); locked[p.name] = true end
    before[p.name] = p.group
  end
  W.Pull(damage)
  local play = W.ns.PlayGroups()
  -- Damage dealers without damage count as the average one, as in the addon.
  -- Each half's goal is its share of the players in the groups that play.
  local known, sum, size = 0, 0, { 0, 0 }
  for i, p in ipairs(W.roster) do
    local role = W.ns.UnitRole("raid" .. i)
    if p.group <= play.count then size[play.half[p.group]] = size[play.half[p.group]] + 1 end
    if p.group <= play.count and damage[p.name] and (role == "MELEE" or role == "RANGED") then
      known, sum = known + 1, sum + damage[p.name]
    end
  end
  local average = known > 0 and sum / known or 0
  local share = size[1] + size[2] > 0 and size[1] / (size[1] + size[2]) or 0.5
  -- How far half 1 is from its share of the damage.
  local function Halves()
    local h = { 0, 0 }
    for i, p in ipairs(W.roster) do
      local role = W.ns.UnitRole("raid" .. i)
      if p.group <= play.count and (role == "MELEE" or role == "RANGED") then
        h[play.half[p.group]] = h[play.half[p.group]] + (damage[p.name] or average)
      end
    end
    return math.abs(h[1] - share * (h[1] + h[2]))
  end
  local d0 = Halves()
  W.ns.Balance()
  if not W.RunUntil(W.Idle, 900) then return false, "did not end" end
  local moved = 0
  for i, p in ipairs(W.roster) do
    if p.group ~= before[p.name] then
      moved = moved + 1
      local role = W.ns.UnitRole("raid" .. i)
      if locked[p.name] then return false, p.name .. " locked but moved" end
      if not damage[p.name] then return false, p.name .. " unknown but moved" end
      if role ~= "MELEE" and role ~= "RANGED" then return false, p.name .. " is " .. role .. " and moved" end
      if before[p.name] > play.count or p.group > play.count then
        return false, p.name .. " moved from/to a group that does not play"
      end
      if play.half[before[p.name]] == play.half[p.group] then return false, p.name .. " moved within a half" end
    end
  end
  if Halves() > d0 + 1e-6 then return false, "halves less even" end -- 1e-6: rounding of the share
  return true, { moved = moved }
end

local MODES = { sort = Sort, moves = Moves, auto = Auto, drags = Drags,
                balance = BalanceUnit, balanceraid = BalanceRaid }

function FUZZ(mode, seed)
  -- Lua 5.1's first numbers after nearby seeds are nearly the same: spread
  -- the seed and warm up.
  math.randomseed((seed * 2654435761) % 2147483647)
  for _ = 1, 20 do math.random() end
  local okk, a, b = pcall(MODES[mode], seed)
  if not okk then return false, "error: " .. tostring(a) end
  if a and type(b) == "table" then b.n = #W.roster end
  return a, b
end
