--[[
  HAVOC CLAIM PARTS — F3X / raidRolePlay ownership bypass
  =======================================================
  WHY: the F3X server-side sync handler silently REFUSES every
  SyncMove/SyncResize/SyncPaint/... on parts whose RRPartOwner tag
  belongs to another player. On your screen the operation "works"
  (client-side), but the server never applies it (it never
  replicates; the part can appear to snap back later). That is what
  looks like "the tool breaks on another player's part" — only NEW
  parts (which are yours) keep working.

  THE HOLE: the escalation remote that assigns ownership tags has
  NO validation:
      EscalateEvent:FireServer(Modules.PartOwnership, {parts})
  re-tags ANY parts to YOUR name, server-side, silently.
  After claiming, the server treats the parts as yours and every
  normal F3X operation sticks.

  USAGE (tool UI flow):
    1. Select the target parts with the F3X tool (selection works)
    2. HAVOC_CLAIM.sel()          -- claim whatever is selected
    3. move/resize/paint as usual -- the server now accepts it

  API:
    HAVOC_CLAIM.sel()             claim everything selected
    HAVOC_CLAIM.parts({p1, p2})   claim specific instances
    HAVOC_CLAIM.near(radius)      claim every foreign-tagged part in radius
    HAVOC_CLAIM.auto(true/false)  auto-claim on every new selection
    HAVOC_CLAIM.status()          counters

  NOTES:
    * claiming RETAGS the part (the original owner silently loses it)
    * untagged parts need no claim — the server allows everyone
    * only foreign-TAGGED parts are touched (no tag spam)
    * re-run after every rejoin (autoexec loads it in F3X games)
]]

local genv = (type(getgenv) == "function" and getgenv()) or _G
if genv.HAVOC_CLAIM and genv.HAVOC_CLAIM.active then
  print("[claim] already loaded")
  return genv.HAVOC_CLAIM
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local rp = RS:FindFirstChild("raidRoleplay") or RS:FindFirstChild("raidRolePlay")
local ev = rp and rp:FindFirstChild("Events") and rp.Events:FindFirstChild("EscalateEvent")
local poMod = rp and rp:FindFirstChild("Modules") and rp.Modules:FindFirstChild("PartOwnership")
if not (ev and poMod) then
  warn("[claim] raidRolePlay PartOwnership escalation not found (wrong game?)")
  return
end

local BATCH = 50
local api = { active = true, claimed = 0, batches = 0, auto = false }
genv.HAVOC_CLAIM = api

local function fireClaim(list)
  if #list == 0 then return 0 end
  local ok, err = pcall(function()
    ev:FireServer(poMod, list)
  end)
  if not ok then
    warn("[claim] fire failed: " .. tostring(err))
    return 0
  end
  api.batches = api.batches + 1
  return #list
end

-- claim only foreign-tagged parts (untagged = already free, ours = skip)
local function claimFiltered(parts)
  local want = {}
  for _, p in ipairs(parts) do
    if typeof(p) == "Instance" and p:IsA("BasePart") and p:IsDescendantOf(game.Workspace) then
      local tag = p:FindFirstChild("RRPartOwner")
      if tag and tag:IsA("StringValue") and tag.Value ~= lp.Name then
        want[#want + 1] = p
      end
    end
  end
  local total = 0
  for i = 1, #want, BATCH do
    local chunk = {}
    for j = i, math.min(i + BATCH - 1, #want) do
      chunk[#chunk + 1] = want[j]
    end
    total = total + fireClaim(chunk)
  end
  api.claimed = api.claimed + total
  return total, #want
end

function api.parts(list)
  return claimFiltered(list or {})
end

local function toolSelection()
  local btf = game.Workspace:FindFirstChild(lp.Name)
  btf = btf and btf:FindFirstChild("Building Tools")
  local core = btf and btf:FindFirstChild("Core")
  local selMod = core and core:FindFirstChild("Selection")
  if not selMod then return nil end
  local ok, sel = pcall(require, selMod)
  if ok and type(sel) == "table" then return sel end
  return nil
end

function api.sel()
  local sel = toolSelection()
  if not sel then return 0, 0 end
  local parts = {}
  for _, p in pairs(sel.Parts or {}) do parts[#parts + 1] = p end
  return claimFiltered(parts)
end

function api.near(radius)
  radius = tonumber(radius) or 150
  local ref = lp.Character and lp.Character:GetPivot().Position or Vector3.zero
  local out = {}
  for _, o in ipairs(game.Workspace:GetDescendants()) do
    if o:IsA("BasePart") then
      local tag = o:FindFirstChild("RRPartOwner")
      if tag and tag:IsA("StringValue") and tag.Value ~= lp.Name then
        local ok, pos = pcall(function() return o.Position end)
        if ok and (pos - ref).Magnitude <= radius then
          out[#out + 1] = o
          if #out >= 400 then break end
        end
      end
    end
  end
  return claimFiltered(out)
end

local autoConn
function api.auto(on)
  api.auto = on and true or false
  if autoConn then autoConn:Disconnect() autoConn = nil end
  if not api.auto then return false end
  local sel = toolSelection()
  if not sel then api.auto = false return false end
  autoConn = sel.Changed:Connect(function()
    local parts = {}
    for _, p in pairs(sel.Parts or {}) do parts[#parts + 1] = p end
    claimFiltered(parts)
  end)
  return true
end

function api.status()
  return { claimed = api.claimed, batches = api.batches, auto = api.auto }
end

print("[claim] HAVOC_CLAIM armed - select parts then HAVOC_CLAIM.sel() | .near(r) | .auto(true)")
return api
