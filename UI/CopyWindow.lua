local ADDON_NAME, ns = ...

-- A window with selectable text, so debug output can be copied out of the game (chat text can't
-- be selected, and Forever disables /dump). Built from Blizzard's BasicFrameTemplateWithInset and
-- InputScrollFrameTemplate (a scroll frame around a multi-line EditBox). Escape closes it.

local CopyWindow = {
  frame = nil,
  text = "",
}
ns.CopyWindow = CopyWindow

local WIDTH, HEIGHT = 640, 420

local function create()
  local frame = CreateFrame("Frame", "QuestmarkerCopyWindow", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, "QuestmarkerCopyWindow")  -- Escape closes it

  local scroll = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -34)
  scroll:SetPoint("BOTTOMRIGHT", -30, 14)
  scroll.CharCount:Hide()

  local editBox = scroll.EditBox
  -- The template sizes the EditBox at creation, when the frame had no size yet.
  editBox:SetWidth(WIDTH - 46 - 18)
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetScript("OnEscapePressed", function()
    frame:Hide()
  end)
  -- Read-only: put the text back if a keystroke changes it.
  editBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(CopyWindow.text)
      self:HighlightText()
    end
  end)

  frame.editBox = editBox
  return frame
end

---Show lines of text, selected, ready for Ctrl+C.
---@param title string
---@param lines string[]
function CopyWindow:Show(title, lines)
  self.frame = self.frame or create()
  self.text = table.concat(lines, "\n")
  self.frame.TitleText:SetText(title .. "  (Ctrl+C to copy, Escape to close)")
  local editBox = self.frame.editBox
  editBox:SetText(self.text)
  self.frame:Show()
  editBox:SetFocus()
  editBox:SetCursorPosition(0)
  editBox:HighlightText()
end
