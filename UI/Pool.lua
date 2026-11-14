local ADDON_NAME, ns = ...

-- Reuses frames instead of creating new ones on every rebuild (frames can never be destroyed in
-- WoW, only hidden). Our own rather than Blizzard's CreateFramePool, which on Forever is an alias
-- for CreateSecureFramePool (Blizzard_SharedXMLBase/Pools.lua:857).

local Pool = {}
Pool.__index = Pool

---@param create fun(): table makes a new object (a frame or anything with Show/Hide/ClearAllPoints)
---@param reset (fun(obj: table))? clears an object's state when it's released
function ns.CreatePool(create, reset)
  return setmetatable({ create = create, reset = reset, free = {}, active = {} }, Pool)
end

function Pool:Acquire()
  local obj = table.remove(self.free) or self.create()
  self.active[obj] = true
  obj:Show()
  return obj
end

function Pool:Release(obj)
  if not self.active[obj] then
    return
  end
  self.active[obj] = nil
  if self.reset then
    self.reset(obj)
  end
  obj:Hide()
  obj:ClearAllPoints()
  self.free[#self.free + 1] = obj
end

function Pool:ReleaseAll()
  for obj in pairs(self.active) do
    self:Release(obj)
  end
end
