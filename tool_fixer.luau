--[[
  HAVOC F3X TOOL FIXER - v1.0.0
  ============================================================
  WHY: two families of F3X tools silently do NOTHING on a fresh part:

    * CHILD-INSTANCE tools: MESH ("Mesh Tool") and TEXTURE ("Texture Tool").
      Their sync actions only APPLY changes to an ALREADY-EXISTING child
      instance. Missing child => the action `continue`s the part with no
      error, and the UI hides the real options until you find the small
      "+ Add" button:
        SyncMesh    -> needs part.SpecialMesh
        SyncTexture -> needs part.Decal/Texture with the exact Face
      => "I change Mesh Type / Mesh ID and nothing happens".

    * LOCKED-PART gate: the sync layer refuses locked parts when
      Options.DisallowLocked is on. The tool is happier with it off;
      HAVOC_CLAIM keeps parts unlocked anyway.

  WHAT THIS DOES (pure client-side table patching, NO hooks):
    * wraps the framework sync dispatcher
      (ReplicatedStorage.raidRoleplay.Assets.Core.Logs.Unapply.SyncAPI.SyncModule
      :PerformAction) so when SyncMesh / SyncTexture runs, any selected
      part missing its SpecialMesh / Decal-Texture gets the child created
      first - the action then applies normally. Mesh tool works on ANY
      part, no "+ Add" needed.
    * mirrors each auto-created child to the server once
      (ServerEndpoint "CreateMeshes" / "CreateTextures") so it replicates
      to everyone and persists across rejoins.
    * force-disables Options.DisallowLocked on the sync layer.
    * live diagnostics: attributes on the equipped/backpack tool
      (HavocFixHits / HavocFixCreated / HavocFixMirrored / HavocFixLast):
      if HavocFixHits stays 0 while you use the tools, the game glue does
      not route through PerformAction (would need a different patch point).

  Order: loaded by f3x_patch AFTER raidroleplay_bypass + claim_parts.
  Framework may not be up yet -> retries until it is.
  Handle: getgenv().HAVOC_F3X_FIX  { patched, hits, created, mirrored, last }
]]

local genv = (type(getgenv) == "function" and getgenv()) or _G
if genv.HAVOC_F3X_FIX and genv.HAVOC_F3X_FIX.active then
  print("[toolfix] already loaded")
  return genv.HAVOC_F3X_FIX
end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local api = {
  active = true,
  version = "1.0.0",
  patched = false,
  hits = 0,
  created = 0,
  mirrored = 0,
  last = nil,
  err = nil,
}
genv.HAVOC_F3X_FIX = api

-- ---------------------------------------------------------------- locate
local function findSyncAPI()
  local rp = RS:FindFirstChild("raidRoleplay") or RS:FindFirstChild("raidRolePlay")
  if rp then
    local a = rp:FindFirstChild("Assets")
    local c = a and a:FindFirstChild("Core")
    local l = c and c:FindFirstChild("Logs")
    local u = l and l:FindFirstChild("Unapply")
    local s = u and u:FindFirstChild("SyncAPI")
    if s then
      local sm = s:FindFirstChild("SyncModule")
      if sm and sm:IsA("ModuleScript") then
        return s, sm, s:FindFirstChild("ServerEndpoint")
      end
    end
  end
  for _, d in ipairs(RS:GetDescendants()) do
    if d.Name == "SyncModule" and d:IsA("ModuleScript") and d.Parent and d.Parent.Name == "SyncAPI" then
      return d.Parent, d, d.Parent:FindFirstChild("ServerEndpoint")
    end
  end
  return nil
end

-- ------------------------------------------- child-instance auto-create
-- Handles both payload shapes the dispatcher sees:
--   list form:  { {Part=part, MeshType=..., ...}, ... }     (mesh tool)
--   packed form:{ [part] = { MeshType = ..., ... }, ... }   (undo path)
local function ensureChildren(action, payload)
  if type(payload) ~= "table" then return end
  local createdMesh, createdTex = {}, {}

  local function handlePart(part, entry)
    if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
    if action == "SyncMesh" then
      if not part:FindFirstChildOfClass("SpecialMesh") then
        local m = Instance.new("SpecialMesh")
        m.Name = "Mesh"
        m.Parent = part
        createdMesh[#createdMesh + 1] = part
        api.created += 1
      end
    elseif action == "SyncTexture" then
      local tt = entry.TextureType
      if tt == "Decal" or tt == "Texture" then
        local face = entry.Face
        local exists = false
        for _, ch in ipairs(part:GetChildren()) do
          if ch.ClassName == tt and (face == nil or ch.Face == face) then
            exists = true
            break
          end
        end
        if not exists then
          local inst = Instance.new(tt)
          if face ~= nil then inst.Face = face end
          inst.Parent = part
          createdTex[#createdTex + 1] = { Part = part, TextureType = tt, Face = face }
          api.created += 1
        end
      end
    end
  end

  for k, e in pairs(payload) do
    if type(e) == "table" and typeof(e.Part) == "Instance" then
      handlePart(e.Part, e)
    elseif typeof(k) == "Instance" and type(e) == "table" then
      handlePart(k, e)
    end
  end

  return createdMesh, createdTex
end

-- ------------------------------------------------------------- patching
local syncModule, serverEndpoint
function api.patch()
  if api.patched then return true end
  local _, smInst, seInst = findSyncAPI()
  if not smInst then return false end
  syncModule, serverEndpoint = smInst, seInst
  local ok, sm = pcall(require, smInst)
  if not ok or type(sm) ~= "table" or type(sm.PerformAction) ~= "function" then
    api.err = tostring(sm)
    return false
  end
  local orig = sm.PerformAction
  sm.PerformAction = function(self, action, ...)
    if type(action) == "string" then
      api.hits += 1
      api.last = action
      local args = table.pack(...)
      pcall(function()
        local createdMesh, createdTex = ensureChildren(action, args[1])
        if serverEndpoint then
          if createdMesh and #createdMesh > 0 then
            local list = {}
            for _, p in ipairs(createdMesh) do
              list[#list + 1] = { Part = p }
            end
            pcall(function()
              serverEndpoint:InvokeServer("CreateMeshes", list)
            end)
            api.mirrored += #list
          end
          if createdTex and #createdTex > 0 then
            pcall(function()
              serverEndpoint:InvokeServer("CreateTextures", createdTex)
            end)
            api.mirrored += #createdTex
          end
        end
      end)
    end
    return orig(self, action, ...)
  end
  pcall(function()
    if type(sm.Options) == "table" then
      sm.Options.DisallowLocked = false
    end
  end)
  api.patched = true
  print("[toolfix] sync dispatcher patched - mesh/texture auto-create + locked gate off")
  return true
end

task.spawn(function()
  for _ = 1, 240 do
    if api.patch() then break end
    task.wait(0.5)
  end
  while true do
    task.wait(5)
    if not api.patched then api.patch() end
  end
end)

-- ------------------------------------------------ bridge diagnostics
task.spawn(function()
  while true do
    task.wait(1)
    local lp = Players.LocalPlayer
    local tool
    if lp then
      local ch = lp.Character
      if ch then tool = ch:FindFirstChild("Building Tools") end
      if not tool then
        local bp = lp:FindFirstChildOfClass("Backpack")
        if bp then tool = bp:FindFirstChild("Building Tools") end
      end
    end
    if tool then
      pcall(function()
        tool:SetAttribute("HavocFixHits", api.hits)
        tool:SetAttribute("HavocFixCreated", api.created)
        tool:SetAttribute("HavocFixMirrored", api.mirrored)
        tool:SetAttribute("HavocFixLast", api.last or "-")
        tool:SetAttribute("HavocFixPatched", api.patched)
      end)
    end
  end
end)

print("[toolfix] HAVOC_F3X_FIX v1.0.0 armed")
return api
