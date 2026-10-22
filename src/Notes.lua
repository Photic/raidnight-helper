-- Notes
-- A boss note from the website starts with its boss and difficulty, then
-- has a timeline of reminders, blocks of lists under a title each, and the
-- invite list, with empty lines between them:
--
--   EncounterID:3001;Difficulty:Heroic;Name:Vexmora
--
--   time:0;ph:1;tag:Brannoc;spellid:370537;
--   time:120;ph:1;tag:everyone;text:POTIONS;TTS:true;countdown:3;
--
--   P2 - Group Split
--   Left: Brannoc Elowyn Fenwick Isolde Torvald Ashlyn
--   Right: Corvain Dúnmir Ravéna Thessaly
--
--   P1 - Coil Soaks
--   Soak first: Brannoc Corvain Elowyn Dúnmir Fenwick
--
--   invitelist:Brannoc-ArgentDawn,Elowyn-ArgentDawn,...;
--
-- The groups are the lists of the first block, whatever they are called and
-- however many there are; a note can also have that block only. The blocks
-- after it (soaks and the like) name the same players again, so they are
-- left out, as are the timeline and the invite list. EncounterID is the ID
-- ENCOUNTER_START reports for the boss.
--
-- The other way round, ns.RewriteNote writes changed groups back into the
-- note, so the note window (NoteWindow.lua) follows the layout.

local _, ns = ...

local MAX_GROUPS = 8
local PARKED     = "Not on list" -- the text format's line for names that wait outside the groups

local function Trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- s split at each sep (one plain character), empty pieces included.
local function Split(s, sep)
  local out, from = {}, 1
  while true do
    local at = s:find(sep, from, true)
    if not at then
      out[#out + 1] = s:sub(from)
      return out
    end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
end

-- text's lines, empty ones too.
local function Lines(text)
  return Split((text:gsub("\r\n?", "\n")), "\n")
end

-- Where the lists of the group block are in lines. The header's block, and
-- a block whose first line holds "key:value;" pairs, are part of the
-- reminders: the header, the timeline or the invite list. In the first
-- other block, the lines with a colon are the lists; its title has none.
local function GroupBlock(lines)
  local block, reminders, inBlock = {}, true, true
  for i = 2, #lines do
    local line = Trim(lines[i])
    if line == "" then
      if #block > 0 then break end
      inBlock = false
    else
      if not inBlock then
        inBlock, reminders = true, line:find(";", 1, true) ~= nil
      end
      if not reminders and line:find(":", 1, true) then block[#block + 1] = i end
    end
  end
  return block
end

-- The note in text, or nil when text is not a note:
--   { encounter = <encounter ID>, difficulty = "normal", "heroic", "mythic"
--     or nil, name = <boss name> or nil, groups = <the first block's lists> }
-- groups is in the text format ParseText reads.
function ns.ParseNote(text)
  local lines = Lines(text)
  local header = Trim(lines[1])
  local encounter = header:match("^EncounterID:%s*(%d+)")
  if not encounter then return nil end
  local difficulty = (header:match("Difficulty:%s*(%a+)") or ""):lower()
  local lists = {}
  for _, at in ipairs(GroupBlock(lines)) do lists[#lists + 1] = Trim(lines[at]) end
  return {
    encounter = tonumber(encounter),
    difficulty = ns.DifficultyName(difficulty) and difficulty or nil,
    name = header:match("Name:%s*([^;]+)"),
    groups = table.concat(lists, "\n"),
  }
end

---------------------------------------------------------------------------
-- Writing groups back
---------------------------------------------------------------------------

-- names as a set: their NameKeys, sorted.
local function Key(names)
  local keys = {}
  for i, name in ipairs(names) do keys[i] = ns.NameKey(name) end
  table.sort(keys)
  return table.concat(keys, " ")
end

local function Same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- The Key of the players a timeline line tags ("...;tag:Brannoc Elowyn;..."),
-- or nil for a line without tags.
local function TagKey(line)
  if not line:find(";", 1, true) then return nil end
  for _, field in ipairs(Split(line, ";")) do
    local tag = field:match("^%s*tag:(.*)$")
    if tag then
      local names = {}
      for name in tag:gmatch("[^%s,]+") do names[#names + 1] = name end
      return Key(names)
    end
  end
end

-- line with its tags replaced by names.
local function Retag(line, names)
  local fields = Split(line, ";")
  for i, field in ipairs(fields) do
    if field:match("^%s*tag:") then fields[i] = "tag:" .. table.concat(names, " ") end
  end
  return table.concat(fields, ";")
end

-- The note text with its group lists rewritten to the groups of layout
-- (text in the format ParseText reads). Each named list ("Left:") gets the
-- names now in the groups it filled, in group order. Players in groups no
-- list fills go on "Group N:" lines after the lists, and names that wait
-- outside the groups on a "Not on list:" line. A timeline line that tags
-- exactly the players of a list with two or more gets the list's new
-- players. Names keep the note's spelling; the rest of the note stays.
function ns.RewriteNote(text, layout)
  local lines = Lines(text)
  local block = GroupBlock(lines)
  if #block == 0 then return text end
  local blockText = {}
  for i, at in ipairs(block) do blockText[i] = Trim(lines[at]) end
  local old, new = ns.ParseText(table.concat(blockText, "\n")), ns.ParseText(layout)

  -- The note's spelling of each name, and the groups and names of each list.
  local spelling, lists = {}, {}
  local function Spell(name) return spelling[ns.NameKey(name)] or name end
  for i, list in ipairs(old.lists) do
    lists[i] = { label = list.label, at = block[list.line], groups = {}, before = {}, after = {} }
  end
  for _, e in ipairs(old.entries) do
    spelling[ns.NameKey(e.name)] = spelling[ns.NameKey(e.name)] or e.name
    if e.list then
      lists[e.list].groups[e.group] = true
      table.insert(lists[e.list].before, e.name)
    end
  end
  for _, name in ipairs(old.parked) do
    spelling[ns.NameKey(name)] = spelling[ns.NameKey(name)] or name
  end

  local extra = {}
  for g = 1, MAX_GROUPS do
    local names = {}
    for _, name in ipairs(new.groups[g] or {}) do names[#names + 1] = Spell(name) end
    local owner
    for _, list in ipairs(lists) do
      if list.groups[g] then owner = list end
    end
    if owner then
      for _, name in ipairs(names) do table.insert(owner.after, name) end
    elseif #names > 0 then
      extra[#extra + 1] = ("Group %d: %s"):format(g, table.concat(names, ", "))
    end
  end
  if #new.parked > 0 then
    local names = {}
    for _, name in ipairs(new.parked) do names[#names + 1] = Spell(name) end
    extra[#extra + 1] = ("%s: %s"):format(PARKED, table.concat(names, ", "))
  end

  -- Which timeline lines follow which list is decided on the note as it
  -- was, so lists that trade players (as Swap halves does) don't mix up.
  local retag = {}
  for _, list in ipairs(lists) do
    local before = Key(list.before)
    if #list.before >= 2 and #list.after > 0 and before ~= Key(list.after) then
      for i, line in ipairs(lines) do
        if TagKey(line) == before then retag[i] = list.after end
      end
    end
  end

  local named, inBlock, last = {}, {}, block[#block]
  for _, list in ipairs(lists) do named[list.at] = list end
  for _, at in ipairs(block) do inBlock[at] = true end
  local out = {}
  for i, line in ipairs(lines) do
    local list = named[i]
    if list then
      if Same(list.before, list.after) then
        out[#out + 1] = line
      else
        local sep = line:match(":(.*)$"):find(",", 1, true) and ", " or " "
        out[#out + 1] = ("%s: %s"):format(list.label, table.concat(list.after, sep))
      end
    elseif retag[i] then
      out[#out + 1] = Retag(line, retag[i])
    elseif not inBlock[i] then
      out[#out + 1] = line
    end
    -- The block's other lines ("Group N:", "Not on list:") are written anew.
    if i == last then
      for _, e in ipairs(extra) do out[#out + 1] = e end
    end
  end
  return table.concat(out, "\n")
end
