--[[
  ============================================================
  HAVOC RAIDROLEPLAY BYPASS  (generic - for every F3X game
  running the raidRolePlay clamp framework)
  ============================================================
  Removes the CLIENT-SIDE enforcement hooks of raidRolePlay.Modules
  from the F3X callmods arrays (identity-based removal: every array
  holding the exact exported function gets it pulled). Client-only
  clamps die; server-backed services (logs / sets / teams) stay.

  Default REMOVE (name match, case-insensitive):
    MaxPartAndMeshSize       size/mesh cap escalation (50^3/100^3)      -> gone
    F3XPartModificationLimit part-count rate limiter + KICK            -> gone
    AntiCloneBomb            clone-spam kick escalation                -> gone
    AntiAnchorBomb           destructive Failsafe replace + ownership  -> gone
    DisableLockedParts       "locked part" selection clamp             -> gone
    PartOwnership            undo/deselect guard on others' parts      -> gone
    RemoveF3XExplorer        force-hidden explorer button              -> restored

  Default KEEP:
    F3XLogs / LogOnJoin  (logging only - removes no clamps)
    Sets                 (saved-build service, server DataStore-backed)
    PlayerTeaming        (team menu feature)
    F3XShiftTNotDefault  (targeting mode setup; restriction is config-off)

  NOTE (server-side ownership gate):
    the SERVER still silently refuses syncs on parts whose RRPartOwner
    tag belongs to another player - this strip only disarms CLIENT
    guards, so move/resize on foreign parts will silently do nothing.
    Use tools/f3x/claim_parts.luau (HAVOC_CLAIM) to retag first.

  Overrides (set BEFORE running):
    getgenv().HAVOC_RP_EXTRA_REMOVE = {"Name", ...}  -- also strip these
    getgenv().HAVOC_RP_EXTRA_KEEP   = {"Name", ...}  -- never strip these
    getgenv().HAVOC_RP_STRIP_ALL    = true           -- strip EVERY module
      (tip: EXTRA_REMOVE = {"F3XLogs"} silences your actions in the
       server log feed while keeping everything else intact)

  Status:  getgenv().HAVOC_RP_BYPASS
  Restore: getgenv().HAVOC_CLAMP_RESTORE()   (shared store w/ clamp_bypass)
  Re-run after every rejoin.
]]

local genv = (type(getgenv) == "function" and getgenv()) or _G
local out = { removed = {}, kept = {} }

local REMOVE_DEFAULT = {
  "MaxPartAndMeshSize", "F3XPartModificationLimit", "AntiCloneBomb",
  "AntiAnchorBomb", "DisableLockedParts", "PartOwnership", "RemoveF3XExplorer",
}

local function matches(name, list)
  local ln = string.lower(name)
  for _, pat in ipairs(list) do
    if string.find(ln, string.lower(pat), 1, true) then return true end
  end
  return false
end

local okAll, err = pcall(function()
  local RS = game:GetService("ReplicatedStorage")
  local rr = RS:FindFirstChild("raidRoleplay")
  if not rr then error("raidRoleplay not found (wrong game / not loaded yet)") end
  local Modules = rr:WaitForChild("Modules", 5)
  if not Modules then error("raidRolePlay.Modules missing") end

  local extraRemove = genv.HAVOC_RP_EXTRA_REMOVE or {}
  local extraKeep = genv.HAVOC_RP_EXTRA_KEEP or {}
  local stripAll = genv.HAVOC_RP_STRIP_ALL == true

  local targets = {}
  for _, m in ipairs(Modules:GetChildren()) do
    if m:IsA("ModuleScript") and not string.find(m.Name, "Configuration", 1, true) then
      local doRemove
      if matches(m.Name, extraKeep) then
        doRemove = false
      elseif stripAll then
        doRemove = true
      elseif matches(m.Name, extraRemove) then
        doRemove = true
      elseif matches(m.Name, REMOVE_DEFAULT) then
        doRemove = true
      else
        doRemove = false
      end
      if doRemove then
        local okR, mod = pcall(require, m)
        if okR and type(mod) == "table" then
          local fns = {}
          for k, v in pairs(mod) do
            if type(v) == "function" then
              fns[#fns + 1] = { name = tostring(k), fn = v }
            end
          end
          if #fns > 0 then
            targets[#targets + 1] = { module = m.Name, fns = fns }
          end
        end
      else
        out.kept[#out.kept + 1] = m.Name
      end
    end
  end
  out.targets = #targets
  if #targets == 0 then error("no removable modules found (wrong game / already stripped?)") end

  local store = {}
  local killed = {}

  -- one removal pass over the CURRENT gc (re-fetch each pass: callmods
  -- arrays only exist after the tool's first equip - late arrays get caught)
  local function pass()
    local gc = getgc(true)
    local total = 0
    for _, t in ipairs(targets) do
      local hits = 0
      for _, f in ipairs(t.fns) do
        for _, o in ipairs(gc) do
          if type(o) == "table" then
            local len = #o
            if len > 0 and len < 50 then
              for i = 1, len do
                if rawequal(o[i], f.fn) then
                  store[#store + 1] = { arr = o, idx = i, fn = f.fn }
                  pcall(table.remove, o, i)
                  hits = hits + 1
                  total = total + 1
                  break
                end
              end
            end
          end
        end
      end
      if hits > 0 then killed[t.module] = (killed[t.module] or 0) + hits end
    end
    return total
  end

  out.firstPassRemovals = pass()

  -- idempotent shared restore store (merge, never wipe)
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

  -- finisher: keep re-scanning briefly for arrays created at first equip
  task.spawn(function()
    for _ = 1, 20 do
      local pending = false
      for _, t in ipairs(targets) do
        if not killed[t.module] then pending = true end
      end
      if not pending then break end
      task.wait(3)
      pass()
    end
  end)

  out.removed = killed
  out.storeTotal = #genv.HAVOC_CLAMP_KILL.store
end)
out.ok = okAll
out.err = okAll and nil or tostring(err)
genv.HAVOC_RP_BYPASS = out

if okAll then
  print("[rp_bypass] raidRolePlay strip applied")
  for name, n in pairs(out.removed or {}) do print("  removed " .. name .. " x" .. n) end
  if out.kept and #out.kept > 0 then print("  kept: " .. table.concat(out.kept, ", ")) end
else
  print("[rp_bypass] failed: " .. tostring(out.err))
end
return out
