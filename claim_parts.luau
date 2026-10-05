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
    * v1.3.0: .players(name) claims a player's whole character and .world(r)
      sweeps the map - EVERYTHING in the workspace is editable once claimed
      (the F3X targeting has no character filter, so selecting a player's
      body part + auto-claim = you can move/resize people)
    * v1.4.0: .world() with NO arguments = claim EVERY part in the workspace
      (whole-server sweep - retags every player's builds to you; characters
      are skipped, use .players() for bodies). Paced batches; can take a
      while on big maps. After a full sweep other players' own edits on
      those parts silently fail server-side - loud, but that is the point.
    * v1.6.0: .unlock() = classic unlockworkspace - sets Locked=false on
      EVERY part in the workspace (local write + a server-side SetLocked
      sync pass so it sticks). The v1.5 SMARTSYNC experiment is REMOVED.
    * v1.7.0: .unlockloop(true) (auto-armed) = re-checks every part every
      1 second and forces Locked=false (local + server mirror only for
      freshly locked parts; idle ticks cost nothing).
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
local watchInfo = nil
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

-- claim a player's entire character (all BaseParts) - characters carry no
-- ownership tags, so without this every sync op on them is refused server-side
function api.players(target)
  local want = {}
  local function addChar(plr)
    if not plr or not plr.Character then return end
    for _, o in ipairs(plr.Character:GetDescendants()) do
      if o:IsA("BasePart") then want[#want + 1] = o end
    end
  end
  if target == nil then
    local me = lpNow()
    for _, plr in ipairs(Players:GetPlayers()) do
      if plr ~= me then addChar(plr) end
    end
  elseif type(target) == "string" then
    addChar(Players:FindFirstChild(target))
  elseif typeof(target) == "Instance" and target:IsA("Player") then
    addChar(target)
  end
  return claimFiltered(want)
end

-- sweep the workspace: no argument = EVERY part in the workspace; a number =
-- that radius around you. Characters are skipped (use players() for bodies).
-- Paced batches + progress prints so big sweeps stay smooth.
function api.world(radius)
  local me = lpNow()
  if not me then return 0, 0 end
  local ref = nil
  if radius then
    ref = me.Character and me.Character:GetPivot().Position or Vector3.zero
  end
  local want = {}
  for _, o in ipairs(game.Workspace:GetDescendants()) do
    if o:IsA("BasePart") then
      local a = o
      local isChar = false
      while a and a ~= game.Workspace do
        if Players:GetPlayerFromCharacter(a) then isChar = true break end
        a = a.Parent
      end
      if not isChar then
        if not ref or (o.Position - ref).Magnitude <= radius then
          local tag = o:FindFirstChild("RRPartOwner")
          if not (tag and tag:IsA("StringValue") and tag.Value == me.Name) then
            want[#want + 1] = o
          end
        end
      end
    end
  end
  local total = 0
  for i = 1, #want, BATCH do
    local chunk = {}
    for j = i, math.min(i + BATCH - 1, #want) do chunk[#chunk + 1] = want[j] end
    total = total + fireClaim(chunk)
    if i > 1 and ((i - 1) % (BATCH * 20)) == 0 then
      print("[claim] sweep progress: " .. tostring(i - 1) .. "/" .. tostring(#want))
    end
    task.wait(0.08)
  end
  api.claimed = api.claimed + total
  return total, #want
end

-- ============================================================
-- v1.6.0: SMARTSYNC REMOVED. Its namecall hook could stack across reloads
-- and crash tool syncs on foreign parts, so this one-shot cleaner walks the
-- __namecall chain, strips any left-over smartsync hooks (identified by
-- their smartState/smartOld upvalues) and restores the clean chain.
-- ============================================================
pcall(function()
  local function upv(fn, i)
    local ok, name, val = pcall(debug.getupvalue, fn, i)
    if ok and name ~= nil then return name, val end
    local ok2, name2, val2 = pcall(getupvalue, fn, i)
    if ok2 and name2 ~= nil then return name2, val2 end
    local ok3, tbl = pcall(getupvalues, fn)
    if ok3 and type(tbl) == "table" then
      local n, v = nil, nil
      local idx = 0
      for k, vv in pairs(tbl) do
        idx = idx + 1
        if idx == i then n, v = k, vv break end
      end
      return n, v
    end
    return nil, nil
  end
  local mt = getrawmetatable(game)
  local fn = mt.__namecall
  local hops, changed = 0, false
  while type(fn) == "function" and hops < 6 do
    hops = hops + 1
    local ours, nextFn = false, nil
    for i = 1, 30 do
      local name, val = upv(fn, i)
      if name == nil then break end
      if name == "smartState" then ours = true end
      if name == "smartOld" and type(val) == "function" then nextFn = val end
    end
    if ours and nextFn then
      fn = nextFn
      changed = true
    else
      break
    end
  end
  if changed then
    setreadonly(mt, false)
    mt.__namecall = fn
    setreadonly(mt, true)
    genv.HAVOC_CLAIM_SMART_OLD = nil
    print("[claim] removed stale smartsync hook(s) - chain clean")
  end
end)

-- ============================================================
-- UNLOCK (classic unlockworkspace): Locked = false on EVERY part in the
-- workspace. Local pass (client view + client-side tool checks) plus a
-- server-side SetLocked sync pass (so it sticks for the server gate too).
-- Call: HAVOC_CLAIM.unlock()
-- ============================================================
function api.unlock()
  local me = lpNow()
  if not me then return 0, 0, 0 end
  local parts = {}
  for _, o in ipairs(game.Workspace:GetDescendants()) do
    if o:IsA("BasePart") then parts[#parts + 1] = o end
  end
  local localN = 0
  for _, p in ipairs(parts) do
    if pcall(function() p.Locked = false end) then localN = localN + 1 end
  end
  local serverN = 0
  local tool = findTool()
  local se = tool and tool:FindFirstChild("SyncAPI") and tool.SyncAPI:FindFirstChild("ServerEndpoint")
  if se then
    for i = 1, #parts, BATCH do
      local chunk = {}
      for j = i, math.min(i + BATCH - 1, #parts) do chunk[#chunk + 1] = parts[j] end
      if pcall(function() return se:InvokeServer("SetLocked", chunk, false) end) then
        serverN = serverN + #chunk
      end
      task.wait(0.08)
    end
  end
  return localN, serverN, #parts
end

-- ============================================================
-- UNLOCK LOOP (v1.7.0): every 1 second, force Locked=false on any part
-- that reports locked. Idle ticks are free (nothing locked -> no work,
-- no server traffic). Server mirror only for parts not fixed in last 5s.
-- ============================================================
local unlockLoopOn = false
local unlockLoopToken = 0
local unlockMirror = setmetatable({}, { __mode = "k" })

local function unlockTick()
  local me = lpNow()
  if not me then return end
  local fresh = {}
  for _, o in ipairs(game.Workspace:GetDescendants()) do
    if o:IsA("BasePart") then
      local ok, l = pcall(function() return o.Locked end)
      if ok and l then
        pcall(function() o.Locked = false end)
        local last = unlockMirror[o]
        if not last or (os.clock() - last) > 5 then
          unlockMirror[o] = os.clock()
          fresh[#fresh + 1] = o
        end
      end
    end
  end
  if #fresh == 0 then return end
  local tool = findTool()
  local se = tool and tool:FindFirstChild("SyncAPI") and tool.SyncAPI:FindFirstChild("ServerEndpoint")
  if not se then return end
  for i = 1, #fresh, 50 do
    local chunk = {}
    for j = i, math.min(i + 49, #fresh) do chunk[#chunk + 1] = fresh[j] end
    pcall(function() return se:InvokeServer("SetLocked", chunk, false) end)
    task.wait(0.05)
  end
end

function api.unlockloop(on)
  unlockLoopOn = (on == nil) and true or (on and true or false)
  unlockLoopToken = unlockLoopToken + 1
  if not unlockLoopOn then return false end
  local myToken = unlockLoopToken
  task.spawn(function()
    while unlockLoopOn and unlockLoopToken == myToken do
      pcall(unlockTick)
      task.wait(1)
    end
  end)
  return true
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

-- the tool's own Core does NOT expose historyUnpack - the raidRolePlay
-- Assets.Core module does (that is what the game's own callbacks use)
local function resolveUnpacker(tool)
  local ok1, c1 = pcall(function() return require(tool.Core) end)
  if ok1 and type(c1) == "table" and type(c1.historyUnpack) == "function" then
    return c1, "tool"
  end
  local rp = game.ReplicatedStorage:FindFirstChild("raidRoleplay") or game.ReplicatedStorage:FindFirstChild("raidRolePlay")
  local ac = rp and rp:FindFirstChild("Assets") and rp.Assets:FindFirstChild("Core")
  if ac then
    local ok2, c2 = pcall(function() return require(ac) end)
    if ok2 and type(c2) == "table" and type(c2.historyUnpack) == "function" then
      return c2, "raidroleplay"
    end
  end
  return nil
end

function api.watch(on)
  watchState = (on == nil) and true or (on and true or false)
  watchInfo = nil
  if historyConn then historyConn:Disconnect() historyConn = nil end
  if not watchState then return false end
  local tool = findTool()
  if not tool then return false end
  local core = tool:FindFirstChild("Core")
  local histMod = core and core:FindFirstChild("History")
  if not histMod then return false end
  local unpacker, src = resolveUnpacker(tool)
  if not unpacker then return false end
  local okH, hist = pcall(function() return require(histMod) end)
  if not okH or type(hist) ~= "table" or not hist.Changed then return false end
  watchInfo = "unpacker=" .. src .. " | hist=" .. histMod:GetFullName()
  historyConn = hist.Changed:Connect(function()
    pcall(function()
      local entry = hist.Stack[hist.Index]
      if entry == nil then return end
      local _, _, parts = unpacker.historyUnpack(entry)
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
  return { claimed = api.claimed, batches = api.batches, auto = autoState, watch = watchState, watchInfo = watchInfo, loop = unlockLoopOn }
end

-- v1.2.0: arm BOTH - selection-claim (tags the part the moment you click it,
-- before the edit sync) + edit-watch (re-claims after every history entry).
-- This is what makes normal building replicate again.
task.spawn(function()
  for _ = 1, 15 do
    local w = api.watch(true)
    local a = api.auto(true)
    if w and a then
      print("[claim] edit-watch + selection-claim armed")
      break
    end
    task.wait(2)
  end
end)

-- auto-arm the unlock loop: Locked=false everywhere, checked every second
task.spawn(function()
  task.wait(2)
  if api.unlockloop(true) then
    print("[claim] unlock loop armed (Locked=false every 1s)")
  end
end)

print("[claim] HAVOC_CLAIM v1.7 armed - .unlockloop() (Locked=false every 1s) | .unlock() | .sel() | .players(name)")
return api
