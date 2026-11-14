local ADDON_NAME, ns = ...

-- Work that must not happen in combat (protected frames, quest-log header changes) goes through
-- Combat:Run. Out of combat it runs immediately; in combat it waits for PLAYER_REGEN_ENABLED.
-- Queued work is keyed: a second request with the same key replaces the first, so only the latest
-- state is applied when combat ends.

local Combat = {
  queue = {},  -- [key] = fn
  order = {},  -- keys in first-queued order
}
ns.Combat = Combat

---@param key string
---@param fn function
function Combat:Run(key, fn)
  if not InCombatLockdown() then
    fn()
    return
  end
  if not self.queue[key] then
    self.order[#self.order + 1] = key
  end
  self.queue[key] = fn
end

ns.Events:On("PLAYER_REGEN_ENABLED", function()
  local order, queue = Combat.order, Combat.queue
  Combat.order, Combat.queue = {}, {}
  for _, key in ipairs(order) do
    local ok, err = pcall(queue[key])
    if not ok then
      geterrorhandler()(err)
    end
  end
end)
