-- The group grid in the window.

T("ui: grid shows locks and group numbers, a click locks, undo button", function()
  W.visible = true
  W.Setup({ "A:2:MAGE:DAMAGER", "B:1:PRIEST:HEALER", "X:3:ROGUE:DAMAGER" })
  local f = W.ns.CreateUI()
  W.ns.SetLayout("Group 1: A, B\nGroup 2: Gone")
  W.ns.RefreshGrid()
  -- Slots are buttons with .member set by ShowName.
  local byMember = {}
  for _, fr in ipairs(W.frames) do
    if fr.member then byMember[fr.member] = fr end
  end
  ok(byMember.A and byMember.B and byMember.X, "slots for A, B and X")
  eq(byMember.A.where.text_, "2", "A shows group 2")
  eq(byMember.B.where.text_, "", "B in place, no number")
  eq(byMember.X.where.text_, "", "pool shows no number")
  eq(byMember.X.locked, true, "X not on list: locked")
  eq(byMember.A.locked, false, "A on list: unlocked")
  eq(byMember.X.lock.shown, true, "lock shown for X")
  -- Click X's lock.
  byMember.X.lock.scripts.OnClick(byMember.X.lock)
  eq(W.ns.IsLocked("X", false, true), false, "click unlocked X")
  byMember.X.lock.scripts.OnEnter(byMember.X.lock)
  -- Undo button starts disabled.
  local undo
  for _, fr in ipairs(W.frames) do
    if fr.scripts.OnClick == W.ns.Undo then undo = fr end
  end
  ok(undo, "undo button")
  eq(undo.enabled, false, "undo disabled")
  W.ns.Auto()
  ok(W.RunUntil(W.Idle, 120), "auto ended")
  eq(undo.enabled, true, "undo enabled after auto")
  W.ns.Undo()
  eq(undo.enabled, false, "undo used")
  eq(W.ns.GetDB().text, "Group 1: A, B\nGroup 2: Gone", "layout back")
end)

-- Ashlyn is in the raid; Corvain and Dúnmir are on the list but not in it.
local function RemoveSetup()
  W.visible = true
  W.Setup({ "Ashlyn:1:MAGE:DAMAGER" })
  W.ns.CreateUI()
  W.ns.SetLayout("Group 1: Ashlyn, Corvain\nGroup 2: Dúnmir")
end

-- The slot in group g that shows name.
local function Slot(name, g)
  for _, fr in ipairs(W.frames) do
    if fr.name == name and fr.group == g then return fr end
  end
end

local function DragOut(slot)
  slot.scripts.OnDragStart(slot)
  W.mouseOver = nil
  slot.scripts.OnDragStop(slot)
end

T("ui: right-click on a name not in the raid opens a menu that removes it", function()
  RemoveSetup()
  local slot = Slot("Corvain", 1)
  slot.scripts.OnClick(slot, "RightButton")
  ok(W.menu, "menu")
  eq(W.menu.title, "Corvain", "title")
  eq(#W.menu.buttons, 1, "one option")
  eq(W.menu.buttons[1].text, "Remove from list", "option")
  W.menu.buttons[1].fn()
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 2: Dúnmir", "removed")
end)

T("ui: a raid member gets no remove menu", function()
  RemoveSetup()
  local slot = Slot("Ashlyn", 1)
  slot.scripts.OnClick(slot, "RightButton")
  eq(W.menu, nil, "no menu")
end)

T("ui: remove does nothing once the player has joined the raid", function()
  RemoveSetup()
  local slot = Slot("Corvain", 1)
  slot.scripts.OnClick(slot, "RightButton")
  W.Setup({ "Ashlyn:1:MAGE:DAMAGER", "Corvain:3:MAGE:DAMAGER" })
  W.menu.buttons[1].fn()
  eq(W.ns.GetDB().text, "Group 1: Ashlyn, Corvain\nGroup 2: Dúnmir", "kept")
end)

T("ui: a name not in the raid dropped outside the window comes off the list", function()
  RemoveSetup()
  DragOut(Slot("Dúnmir", 2))
  eq(W.ns.GetDB().text, "Group 1: Ashlyn, Corvain", "removed")
end)

T("ui: a raid member dropped outside the window stays on the list", function()
  RemoveSetup()
  DragOut(Slot("Ashlyn", 1))
  eq(W.ns.GetDB().text, "Group 1: Ashlyn, Corvain\nGroup 2: Dúnmir", "kept")
  eq(W.moves, 0, "nobody moved")
end)

T("ui: a name dropped inside the window, off the slots, stays", function()
  RemoveSetup()
  local slot = Slot("Dúnmir", 2)
  slot.scripts.OnDragStart(slot)
  W.mouseOver = W.ns.frame
  slot.scripts.OnDragStop(slot)
  eq(W.ns.GetDB().text, "Group 1: Ashlyn, Corvain\nGroup 2: Dúnmir", "kept")
end)

-- The "Not on list" column.
local function Pool()
  for _, fr in ipairs(W.frames) do
    if fr.slots and fr.slots[1] and fr.slots[1].group == nil then return fr end
  end
end

local function Drag(slot, to)
  slot.scripts.OnDragStart(slot)
  W.mouseOver = to
  slot.scripts.OnDragStop(slot)
end

T("ui: a name not in the raid dropped on Not on list waits there, grey", function()
  RemoveSetup()
  Drag(Slot("Corvain", 1), Pool())
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 2: Dúnmir\nNot on list: Corvain", "layout")
  local slot = Slot("Corvain", nil)
  ok(slot, "shown in Not on list")
  eq(slot.member, nil, "grey")
end)

-- The slot at index i of group g, empty or not.
local function SlotAt(g, i)
  for _, fr in ipairs(W.frames) do
    if fr.group == g and fr.index == i and fr.lock then return fr end
  end
end

T("ui: moving names not in the raid moves nobody in the raid", function()
  RemoveSetup()
  W.lead = false -- a raid move would put "must be raid leader" in the status
  W.ns.SetStatus("before")
  Drag(Slot("Corvain", 1), SlotAt(3, 1))
  Drag(Slot("Dúnmir", 2), Slot("Corvain", 3))
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 2: Corvain\nGroup 3: Dúnmir", "layout")
  eq(W.ns.lastStatus, "before", "no raid move tried")
  eq(W.moves, 0, "nobody moved")
end)

T("ui: a waiting name dragged into a group leaves Not on list", function()
  RemoveSetup()
  Drag(Slot("Corvain", 1), Pool())
  Drag(Slot("Corvain", nil), SlotAt(3, 1))
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 2: Dúnmir\nGroup 3: Corvain", "layout")
end)

T("ui: a waiting name dropped on a grey name trades places with it", function()
  RemoveSetup()
  Drag(Slot("Corvain", 1), Pool())
  Drag(Slot("Corvain", nil), Slot("Dúnmir", 2))
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 2: Corvain\nNot on list: Dúnmir", "layout")
end)

T("ui: a raid member dropped on Not on list just comes off the list", function()
  RemoveSetup()
  Drag(Slot("Ashlyn", 1), Pool())
  eq(W.ns.GetDB().text, "Group 1: Corvain\nGroup 2: Dúnmir", "layout")
  local slot = Slot("Ashlyn", nil)
  ok(slot and slot.member, "Ashlyn in Not on list as a raid member")
end)

T("ui: a waiting name comes off for good by right-click or a drag out", function()
  RemoveSetup()
  Drag(Slot("Corvain", 1), Pool())
  Drag(Slot("Dúnmir", 2), Pool())
  local slot = Slot("Corvain", nil)
  slot.scripts.OnClick(slot, "RightButton")
  eq(W.menu.buttons[1].text, "Remove from list", "menu")
  W.menu.buttons[1].fn()
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nNot on list: Dúnmir", "removed by menu")
  DragOut(Slot("Dúnmir", nil))
  eq(W.ns.GetDB().text, "Group 1: Ashlyn", "removed by drag out")
end)

T("ui: a waiting name that joins the raid shows once, as a raid member", function()
  RemoveSetup()
  Drag(Slot("Corvain", 1), Pool())
  W.Setup({ "Ashlyn:1:MAGE:DAMAGER", "Corvain:4:MAGE:DAMAGER" })
  local shown = {}
  for _, fr in ipairs(W.frames) do
    if fr.lock and fr.group == nil and fr.name == "Corvain" then shown[#shown + 1] = fr end
  end
  eq(#shown, 1, "shown once")
  ok(shown[1].member, "as a raid member")
  shown[1].scripts.OnClick(shown[1], "RightButton")
  eq(W.menu, nil, "no remove menu")
  eq(W.ns.GetDB().text, "Group 1: Ashlyn\nGroup 2: Dúnmir\nNot on list: Corvain", "still waiting in the layout")
end)

T("ui: names show the raid frames' role icons, melee and ranged alike", function()
  W.visible = true
  W.Setup({ "Brannoc:1:WARRIOR:TANK", "Elowyn:1:PRIEST:HEALER", "Fenwick:1:ROGUE:DAMAGER", "Isolde:1:MAGE:DAMAGER" })
  W.ns.CreateUI()
  W.ns.SetLayout("Group 1: Brannoc, Elowyn, Fenwick, Isolde, Torvald")
  eq(Slot("Brannoc", 1).icon.atlas_, "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "tank")
  eq(Slot("Elowyn", 1).icon.atlas_, "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "healer")
  eq(Slot("Fenwick", 1).icon.atlas_, "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "melee")
  eq(Slot("Isolde", 1).icon.atlas_, "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "ranged")
  eq(Slot("Torvald", 1).icon.shown, false, "no icon while not in the raid")
end)
