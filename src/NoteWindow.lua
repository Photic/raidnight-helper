-- NoteWindow
-- /raidnight note opens a window with the boss note in full. The note is a
-- working copy, like the layout: the note pasted or applied last, or the one
-- saved with the boss clicked last, in RaidnightHelperDB.note. Edits stay
-- in the note until Apply, which takes the note as pasting it does: its
-- groups become the layout, and it is saved under its boss and difficulty.
-- When the layout changes, the note's groups follow (see ns.RewriteNote).

local _, ns = ...
local L = ns.L

local win -- { frame, box, status }, made the first time the window opens

-- Shows the working note in the window, if it is open.
function ns.ShowNote()
  if not win or not win.frame:IsShown() then return end
  local text = ns.GetDB().note or ""
  if win.box:GetText() ~= text then win.box:SetText(text) end
end

-- Rewrites the working note's groups to the layout's, and shows it.
function ns.UpdateNote()
  local db = ns.GetDB()
  if db.note and db.note ~= "" then db.note = ns.RewriteNote(db.note, db.text) end
  ns.ShowNote()
end

-- msg in the window's status line while it is open, else in the chat.
local function Say(msg)
  if win and win.frame:IsShown() then
    win.status:SetText(msg)
  else
    ns.Print(msg)
  end
end

function ns.ApplyNote()
  local text = ns.GetDB().note or ""
  if not ns.ParseNote(text) then
    Say("|cffff5555" .. L["Not a boss note: the first line must start with EncounterID."] .. "|r")
    return
  end
  local plan = ns.Import(text)
  Say(#plan.errors > 0 and ("|cffff5555" .. table.concat(plan.errors, "\n") .. "|r") or "")
end

local function Create()
  local f = CreateFrame("Frame", "RaidnightHelperNoteFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(560, 460)
  f:SetPoint("CENTER", 40, -40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  table.insert(UISpecialFrames, "RaidnightHelperNoteFrame") -- Esc closes the window

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText(L["Boss note"])

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 16, -32)
  hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L["Paste the boss note from the website. Apply makes its groups the layout and saves it under its boss."])

  local sf = CreateFrame("ScrollFrame", "RaidnightHelperNoteScrollFrame", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -54)
  sf:SetPoint("BOTTOMRIGHT", -34, 72)

  local bg = f:CreateTexture(nil, "ARTWORK")
  bg:SetColorTexture(0, 0, 0, 0.4)
  bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)

  local box = CreateFrame("EditBox", "RaidnightHelperNoteEditBox", sf)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetMaxLetters(0)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(500)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Typing changes the working note; the layout waits for Apply.
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then ns.GetDB().note = self:GetText() end
  end)
  sf:SetScrollChild(box)
  sf:SetScript("OnSizeChanged", function(_, width) box:SetWidth(width) end)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() box:SetFocus() end)

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -10)
  status:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  status:SetHeight(24)
  status:SetJustifyH("LEFT")
  status:SetJustifyV("TOP")

  local apply = ns.MakeButton(f, L["Apply"], 90)
  apply:SetPoint("BOTTOMRIGHT", -12, 12)
  apply:SetScript("OnClick", function()
    box:ClearFocus()
    ns.ApplyNote()
  end)

  f:SetScript("OnShow", function()
    status:SetText("")
    ns.ShowNote()
  end)

  win = { frame = f, box = box, status = status }
end

function ns.ToggleNote()
  if not win then Create() end
  if win.frame:IsShown() then win.frame:Hide() else win.frame:Show() end
end
