-- Sync
-- Send, in the boss row, sends the boss layouts of the raid in the dropdown to
-- everyone in the raid with Raidnight Helper. Only the raid leader and
-- assistants can send, and a push replaces the receivers' layouts for that
-- raid's bosses: bosses the sender has nothing saved for are cleared.
--
-- The names repeat from boss to boss, so a push lists each player once and
-- gives each boss as one character per player: the player's place in that
-- list (A = 1st, B = 2nd, ...). "." splits the groups, in order, so an empty
-- group keeps its place:
--
--   <name>,<name>,...;<boss>:<groups>;<boss>:<groups>;...
--   Brannoc,Elowyn,Fenwick-ArgentDawn;2901:AB.C;2902:;2903:..CA
--
-- Bosses are journal encounter IDs, the same in every client language.
-- An addon message holds 255 bytes, so a push goes out in parts, each one
-- starting with the format version and its number: "1:2/3:<part>".

local _, ns = ...
local L = ns.L

local PREFIX     = "RaidnightHelper"
local VERSION    = 1
local PART_SIZE  = 240   -- bytes of a push per message; the header needs the rest
local MAX_GROUPS = 8
local INDEX      = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"

-- Midnight can return "secret values" for some unit data; we leave those alone.
local issecret = issecretvalue or function() return false end

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

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------

-- The push for layouts = { [journalID] = text or false }, as ns.RaidLayouts
-- gives them. Returns nil and a message when it can't be sent.
function ns.EncodeLayouts(layouts)
  local ids = {}
  for id in pairs(layouts) do ids[#ids + 1] = id end
  table.sort(ids)

  local names, place, bosses = {}, {}, {}
  for _, id in ipairs(ids) do
    local groups = {}
    if layouts[id] then
      local plan = ns.ParseInput(layouts[id])
      for g = 1, MAX_GROUPS do
        local chars = {}
        for _, name in ipairs(plan.groups[g] or {}) do
          if not place[name] then
            names[#names + 1] = name
            place[name] = #names
          end
          chars[#chars + 1] = INDEX:sub(place[name], place[name])
        end
        groups[g] = table.concat(chars)
      end
    end
    -- Empty groups at the end are left out.
    bosses[#bosses + 1] = id .. ":" .. (table.concat(groups, "."):gsub("%.+$", ""))
  end

  if #names > #INDEX then
    return nil, L["Too many players in the layouts to send (max %d)."]:format(#INDEX)
  end
  return table.concat(names, ",") .. ";" .. table.concat(bosses, ";")
end

-- The layouts of a push, in the shape ns.EncodeLayouts takes them, or nil if
-- the text is not a push.
function ns.DecodeLayouts(text)
  local fields = Split(text, ";")
  if #fields < 2 then return nil end
  local names = fields[1] == "" and {} or Split(fields[1], ",")

  local layouts = {}
  for i = 2, #fields do
    local id, list = fields[i]:match("^(%d+):(.*)$")
    if not id then return nil end
    local groups = {}
    if list ~= "" then
      for g, chars in ipairs(Split(list, ".")) do
        groups[g] = {}
        for c in chars:gmatch(".") do
          local name = names[INDEX:find(c, 1, true)]
          if not name then return nil end
          table.insert(groups[g], name)
        end
      end
    end
    local layout = ns.FormatLayout(groups)
    layouts[tonumber(id)] = layout ~= "" and layout
  end
  return layouts
end

-- text in pieces of at most PART_SIZE bytes. A piece never ends inside a
-- UTF-8 character, so accented names arrive whole.
local function Parts(text)
  local parts, from = {}, 1
  while from <= #text do
    local to = math.min(from + PART_SIZE - 1, #text)
    -- Bytes 128-191 continue the character before them.
    while to > from and to < #text and text:byte(to + 1) >= 128 and text:byte(to + 1) < 192 do
      to = to - 1
    end
    parts[#parts + 1] = text:sub(from, to)
    from = to + 1
  end
  return parts
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- SendAddonMessage returns an Enum.SendAddonMessageResult, where 0 is
-- success (a boolean on older clients).
local function Refused(result)
  return result == false or (type(result) == "number" and result ~= 0)
end

function ns.SendLayouts()
  if not IsInRaid() then
    ns.Print(L["You are not in a raid."])
    return
  end
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    ns.Print(L["Layouts can't be sent in Raid Finder."])
    return
  end
  if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
    ns.Print(L["Only the raid leader and assistants can send layouts."])
    return
  end
  if InCombatLockdown() then
    ns.Print(L["Layouts can't be sent in combat."])
    return
  end
  local raid = ns.SelectedRaid()
  if not raid then
    ns.Print(L["The boss list is not loaded yet. Try again in a moment."])
    return
  end

  local text, err = ns.EncodeLayouts(ns.RaidLayouts(raid.id))
  if not text then
    ns.Print(err)
    return
  end
  local parts = Parts(text)
  for i, part in ipairs(parts) do
    local msg = ("%d:%d/%d:%s"):format(VERSION, i, #parts, part)
    if Refused(C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")) then
      ns.Print(L["The game refused to send the layouts. Try again in a moment."])
      return
    end
  end
  ns.Print(L["Sent the boss layouts for %s to the raid."]:format(raid.name))
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

-- Whether name, as the roster writes it, is the raid leader or an assistant.
local function CanSend(name)
  for i = 1, GetNumGroupMembers() or 0 do
    local member, rank = GetRaidRosterInfo(i)
    if not issecret(member) and member == name then
      return not issecret(rank) and (rank or 0) > 0
    end
  end
  return false
end

-- Pushes on the way, by sender: { count = parts in all, parts = { ... } }.
local incoming = {}

local function Receive(sender, text)
  if not CanSend(sender) then return end
  local layouts = ns.DecodeLayouts(text)
  if not layouts then return end
  ns.SetBossLayouts(layouts)
  ns.Print(L["Received boss layouts from %s."]:format(sender))
end

local function OnMessage(prefix, msg, channel, sender)
  if issecret(prefix) or issecret(msg) or issecret(sender) then return end
  if prefix ~= PREFIX or channel ~= "RAID" then return end
  local name = Ambiguate(sender, "none")
  if name == UnitName("player") then return end -- our own push comes back too

  local version, i, count, part = msg:match("^(%d+):(%d+)/(%d+):(.*)$")
  if not version then return end
  version, i, count = tonumber(version), tonumber(i), tonumber(count)
  if version ~= VERSION then
    if version > VERSION and i == 1 then
      ns.Print(L["%s sent layouts from a newer version of Raidnight Helper. Update the addon to receive them."]:format(name))
    end
    return
  end

  -- A sender's parts arrive in order. One out of place, as after a reload
  -- in the middle of a push, drops the push; the sender can send it again.
  if i == 1 then incoming[name] = { count = count, parts = {} } end
  local push = incoming[name]
  if not push or push.count ~= count or #push.parts ~= i - 1 then
    incoming[name] = nil
    return
  end
  push.parts[i] = part
  if i < count then return end
  incoming[name] = nil
  Receive(name, table.concat(push.parts))
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, ...) OnMessage(...) end)
