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
    * v1.1.0: also claims UNTAGGED parts. After our rp_bypass strip, parts
      your client creates no longer get auto-tagged, and the server silently
      refuses syncs on untagged/foreign parts - so claim before/while editing.
      watch() (auto-armed) claims the parts of every edit you make.
    * re-run after every rejoin (autoexec loads it in F3X games)
]]

local genv = (type(getgenv) == "function" and getgenv()) or _G
if genv.HAVOC_CLAIM and genv.HAVOC_CLAIM.active then
  print("[claim] already loaded")
  return genv.HAVOC_CLAIM
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
-- v1.0.1: lazy LocalPlayer (executors can inject before the client joins)
local lp = Players.LocalPlayer
local function lpNow()
  if not lp then lp = Players.LocalPlayer end
  return lp
end

local rp = RS:FindFirstChild("raidRoleplay") or RS:FindFirstChild("raidRolePlay")
local ev = rp and rp:FindFirstChild("Events") and rp.Events:FindFirstChild("EscalateEvent")
local poMod = rp and rp:FindFirstChild("Modules") and rp.Modules:FindFirstChild("PartOwnership")
if not (ev and poMod) then
  warn("[claim] raidRolePlay PartOwnership escalation not found (wrong game?)")
  return
end

local BATCH = 50
local autoState = false
local watchState = false
local api = { active = true, claimed = 0, batches = 0 }
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

-- claim anything not already owned by us: foreign-tagged AND untagged parts.
-- (untagged = "ghost" parts - the server refuses syncs on them because our
-- strip removed the game's auto-tag-on-create escalation)
local function claimFiltered(parts)
  local me = lpNow()
  if not me then return 0, 0 end
  local want = {}
  for _, p in ipairs(parts) do
    if typeof(p) == "Instance" and p:IsA("BasePart") and p:IsDescendantOf(game.Workspace) then
      local tag = p:FindFirstChild("RRPartOwner")
      if not (tag and tag:IsA("StringValue") and tag.Value == me.Name) then
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

-- locate the F3X tool wherever it lives (workspace runtime folder, character,
-- or backpack). The workspace folder shares the player's name with the
-- character model, so scan for Folder type explicitly.
local function findTool()
  local me = lpNow()
  if not me then return nil end
  for _, c in ipairs(game.Workspace:GetChildren()) do
    if c:IsA("Folder") and c.Name == me.Name then
      local bt = c:FindFirstChild("Building Tools")
      if bt and bt:FindFirstChild("Core") then return bt end
    end
  end
  local ch = me.Character
  local t2 = ch and ch:FindFirstChild("Building Tools")
  if t2 and t2:FindFirstChild("Core") then return t2 end
  local bp = me:FindFirstChildOfClass("Backpack")
  local t3 = bp and bp:FindFirstChild("Building Tools")
  if t3 and t3:FindFirstChild("Core") then return t3 end
  return nil
end

local function toolSelection()
  local tool = findTool()
  local core = tool and tool:FindFirstChild("Core")
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
  local me = lpNow()
  if not me then return 0, 0 end
  local myName = me.Name
  local ref = me.Character and me.Character:GetPivot().Position or Vector3.zero
  local out = {}
  for _, o in ipairs(game.Workspace:GetDescendants()) do
    if o:IsA("BasePart") then
      local tag = o:FindFirstChild("RRPartOwner")
      if tag and tag:IsA("StringValue") and tag.Value ~= myName then
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
  autoState = on and true or false
  if autoConn then autoConn:Disconnect() autoConn = nil end
  if not autoState then return false end
  local sel = toolSelection()
  if not sel then autoState = false return false end
  autoConn = sel.Changed:Connect(function()
    local parts = {}
    for _, p in pairs(sel.Parts or {}) do parts[#parts + 1] = p end
    claimFiltered(parts)
  end)
  return true
end

local historyConn
function api.watch(on)
  watchState = (on == nil) and true or (on and true or false)
  if historyConn then historyConn:Disconnect() historyConn = nil end
  if not watchState then return false end
  local tool = findTool()
  if not tool then return false end
  local histMod = tool.Core:FindFirstChild("History")
  if not histMod then return false end
  local okC, core = pcall(require, tool.Core)
  local okH, hist = pcall(function() return require(histMod) end)
  if not (okC and okH) or type(core) ~= "table" or type(hist) ~= "table" then return false end
  historyConn = hist.Changed:Connect(function()
    pcall(function()
      local entry = hist.Stack[hist.Index]
      if entry == nil then return end
      local _, _, parts = core.historyUnpack(entry)
      if type(parts) ~= "table" then parts = entry.Parts end
      if type(parts) ~= "table" then return end
      local list = {}
      for _, v in pairs(parts) do
        if typeof(v) == "Instance" then list[#list + 1] = v end
      end
      if #list > 0 then claimFiltered(list) end
    end)
  end)
  return true
end

function api.status()
  return { claimed = api.claimed, batches = api.batches, auto = autoState, watch = watchState }
end

-- auto-arm the history WATCH: every edit re-claims its parts, so the server
-- stops silently refusing your syncs (fixes the "ghost build" problem)
task.spawn(function()
  for _ = 1, 15 do
    if api.watch(true) then
      print("[claim] edit-watch armed (auto-claims parts you touch)")
      break
    end
    task.wait(2)
  end
end)

print("[claim] HAVOC_CLAIM armed - select parts then HAVOC_CLAIM.sel() | .near(r) | .auto(true) | .watch()")
return api
