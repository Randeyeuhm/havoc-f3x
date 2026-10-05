--[[
  ============================================================
  HAVOC F3X CLAMP BYPASS
  ============================================================
  For the F3X building game (raidRoleplay framework). Removes the two
  clamp triggers from the client-side F3X callmods arrays:

    * MaxPartAndMeshSize.f3xHistoryUpdated        (triggers the server
      size/mesh clamp escalation on Resize/MeshEdit)
    * F3XPartModificationLimit.f3xHistoryUpdated  (part-creation rate
      limiter + KICK for exceeding limits)

  Escalations go client -> server (EscalateEvent:FireServer), so removing
  the client trigger is the correct bypass; the server never hears about
  the operation. F3XLogs stays active (log only, no clamps).

  Usage:
    loadstring(readfile("havoc_db/clamp_bypass.luau"))()
    getgenv().HAVOC_CLAMP_KILL          -- status (removed refs stored)
    getgenv().HAVOC_CLAMP_RESTORE()     -- restore
  Re-run after every rejoin (fresh client = fresh arrays).
]]

local genv = (type(getgenv) == "function" and getgenv()) or _G
local out = { removed = {} }

local okAll, err = pcall(function()
  local RS = game:GetService("ReplicatedStorage")
  local rr = RS:FindFirstChild("raidRoleplay")
  if not rr then error("raidRoleplay not found (wrong game / not loaded yet)") end
  local Modules = rr:WaitForChild("Modules", 5)
  if not Modules then error("raidRoleplay.Modules missing") end
  local function tryMod(name)
    local m = Modules:FindFirstChild(name)
    if not m then return nil end
    local ok, mod = pcall(require, m)
    if ok and type(mod) == "table" then return mod end
    return nil
  end
  local targets = {}
  local m1 = tryMod("MaxPartAndMeshSize")
  if m1 and type(m1.f3xHistoryUpdated) == "function" then
    targets[#targets + 1] = { name = "MaxPartAndMeshSize", fn = m1.f3xHistoryUpdated }
  end
  local m2 = tryMod("F3XPartModificationLimit")
  if m2 and type(m2.f3xHistoryUpdated) == "function" then
    targets[#targets + 1] = { name = "F3XPartModificationLimit", fn = m2.f3xHistoryUpdated }
  end
  out.targets = #targets
  if #targets == 0 then error("clamp modules not found (already bypassed or not loaded?)") end
  local store = {}
  local killed = {}

  -- one full removal pass over the CURRENT gc (arrays are created at first
  -- tool equip - re-fetch every pass so late arrays are caught)
  local function pass()
    local gc = getgc(true)
    local n = 0
    for _, t in ipairs(targets) do
      local hits = 0
      for _, o in ipairs(gc) do
        if type(o) == "table" then
          local len = #o
          if len > 0 and len < 50 then
            for i = 1, len do
              if rawequal(o[i], t.fn) then
                store[#store + 1] = { arr = o, idx = i, fn = t.fn }
                local ok2 = pcall(table.remove, o, i)
                out.removed[#out.removed + 1] = t.name .. (ok2 and (" removed@" .. i) or " REMOVE-FAIL")
                hits = hits + 1
                n = n + 1
                break
              end
            end
          end
        end
      end
      if hits > 0 then killed[t.name] = true end
      out[t.name .. "_arrays"] = (out[t.name .. "_arrays"] or 0) + hits
    end
    return n
  end

  local first = pass()
  out.firstPass = first

  -- idempotent restore store: MERGE with any previous run (never wipe it)
  local prev = genv.HAVOC_CLAMP_KILL
  local merged = {}
  if type(prev) == "table" and type(prev.store) == "table" then
    for _, s in ipairs(prev.store) do merged[#merged + 1] = s end
  end
  for _, s in ipairs(store) do merged[#merged + 1] = s end
  genv.HAVOC_CLAMP_KILL = { store = merged, at = os.time() }
  function genv.HAVOC_CLAMP_RESTORE()
    local n = 0
    for _, s in ipairs(genv.HAVOC_CLAMP_KILL.store or {}) do
      if pcall(function() table.insert(s.arr, s.idx, s.fn) end) then n = n + 1 end
    end
    return n
  end

  -- finisher: if a target was never found (arrays don't exist until the tool
  -- is first equipped), keep re-scanning for up to ~60s
  task.spawn(function()
    for _ = 1, 20 do
      local pending = false
      for _, t in ipairs(targets) do
        if not killed[t.name] then pending = true end
      end
      if not pending then break end
      task.wait(3)
      pass()
    end
  end)
end)
out.ok = okAll
out.err = okAll and nil or tostring(err)
if type(genv.HAVOC_CLAMP_KILL) == "table" then
  out.removedTotal = #genv.HAVOC_CLAMP_KILL.store
end
return out
