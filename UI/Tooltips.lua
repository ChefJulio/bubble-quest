local ADDON_NAME, ns = ...

-- Every tooltip BubbleQuest shows takes its tooltip here (review: holding Ctrl hides all of ours, to
-- see the map or minimap under them). While Ctrl is held none of ours show, and pressing it hides the
-- ones up. Letting go brings back the one under the cursor: tooltips that follow the cursor (maps)
-- show again by themselves; ones shown on enter pass `reshow`.

local Tooltips = {
  taken = {},      -- [tooltip] = owner it was last taken for
  waiting = nil,   -- { owner, reshow }: what to show again when Ctrl is released
}
ns.Tooltips = Tooltips

---@return boolean
function Tooltips:Suppressed()
  return IsControlKeyDown()
end

---Owns and anchors `tooltip` (GameTooltip by default) for one of our frames, or returns nil while Ctrl
---is held: then the caller shows nothing.
---@param owner table our frame
---@param anchor string an ANCHOR_* point
---@param reshow fun()? shows it again (for tooltips shown on enter)
---@param tooltip table? a GameTooltip
---@return table?
function Tooltips:Take(owner, anchor, reshow, tooltip)
  tooltip = tooltip or GameTooltip
  self.waiting = reshow and { owner = owner, reshow = reshow } or nil
  if self:Suppressed() then
    return nil
  end
  tooltip:SetOwner(owner, anchor)
  self.taken[tooltip] = owner
  return tooltip
end

ns.Events:On("MODIFIER_STATE_CHANGED", function(key, down)
  if key ~= "LCTRL" and key ~= "RCTRL" then
    return
  end
  if down == 1 then
    for tooltip, owner in pairs(Tooltips.taken) do
      if tooltip:IsShown() and tooltip:GetOwner() == owner then
        tooltip:Hide()
      end
    end
  elseif not IsControlKeyDown() then  -- both released
    local waiting = Tooltips.waiting
    if waiting and waiting.owner:IsVisible() and waiting.owner:IsMouseOver() then
      waiting.reshow()
    end
  end
end)
