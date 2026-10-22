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
