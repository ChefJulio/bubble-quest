local ADDON_NAME, ns = ...

-- Hides Blizzard's objective tracker (spec: hide it, never modify it).
--
-- A one-time Hide() doesn't stick: Blizzard's container calls Show() whenever a module has content
-- (Blizzard_ObjectiveTrackerContainer.lua:117-127). Reparenting and alpha are undone by the
-- managed-frame system and Edit Mode, and there is no setting or CVar. So, like Questie on
-- Forever: Hide(), plus an OnShow post-hook that hides it again. The hook runs after Blizzard's
-- own OnShow and changes nothing of Blizzard's; never call the tracker's Update() or layout
-- methods (Questie notes that taints it on Forever).
--
-- Side effect: quest auto-complete popups and the scenario UI live in this frame and hide with it.

local Tracker = {
  hooked = false,
}
ns.BlizzardTracker = Tracker

function Tracker:ShouldHide()
  return ns.DB.profile ~= nil and ns.DB.profile.blizzardTracker.hide
end

local function apply()
  local frame = ObjectiveTrackerFrame
  if Tracker:ShouldHide() then
    if not Tracker.hooked then
      frame:HookScript("OnShow", function()
        if Tracker:ShouldHide() then
          Tracker:Apply()
        end
      end)
      Tracker.hooked = true
    end
    frame:Hide()
  else
    frame:Show()
  end
end

function Tracker:Apply()
  local frame = ObjectiveTrackerFrame
  if not frame then
    return
  end
  -- The frame is normally not protected on Forever, but if it is, Show/Hide are blocked in combat.
  if InCombatLockdown() and frame:IsProtected() then
    ns.Combat:Run("blizzard-tracker", apply)
  else
    apply()
  end
end

---@return table state for /qm tracker
function Tracker:State()
  local frame = ObjectiveTrackerFrame
  return {
    exists = frame ~= nil,
    shown = frame ~= nil and frame:IsShown(),
    protected = frame ~= nil and frame:IsProtected(),
    hooked = self.hooked,
    setting = self:ShouldHide() and "hide" or "show",
  }
end

-- The tracker's modules are set up after PLAYER_ENTERING_WORLD; apply on every load screen.
ns.Events:On("PLAYER_ENTERING_WORLD", function()
  Tracker:Apply()
end)

ns.Bus:On("ProfileChanged", function()
  Tracker:Apply()
end)
