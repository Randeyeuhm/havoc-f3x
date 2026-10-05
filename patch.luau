--[[
  ============================================================
  HAVOC F3X PATCH - one file for every F3X + raidRolePlay game
  ============================================================
  Standalone patch, separate from the bridge. Loads the full F3X kit:

    1. raidroleplay_bypass.luau
         strips the client-side clamp modules (size/mesh caps, part-count
         rate limiter, clone/anchor bombs, locked parts, ownership guards)
         and keeps logs/sets/teams
    2. claim_parts.luau
         HAVOC_CLAIM - ownership claiming + auto-claim on select/edit +
         Locked=false unlock loop + resurrection watcher (all self-arms)
    3. tool_fixer.luau
         wraps the framework sync dispatcher so MESH/TEXTURE tools create
         their needed child instances on demand (works on any part, no
         "+ Add" needed) and mirror the create to the server; also turns
         the locked-part sync gate off

  Use:
      loadstring(readfile("havoc_db/f3x_patch.luau"))()
  (autoexec loads this automatically, PlaceId-gated to F3X games)

  Status after load:
      getgenv().HAVOC_RP_BYPASS   - strip result
      getgenv().HAVOC_CLAIM       - claim tool (auto/watch/loop armed)
      getgenv().HAVOC_F3X_FIX     - tool fixer (patched/hits/created/last)
]]

-- 1) raidRolePlay clamp strip
local okStrip = pcall(function()
  return loadstring(readfile("havoc_db/raidroleplay_bypass.luau"))()
end)

-- 2) ownership claim + unlock kit
local okClaim = pcall(function()
  return loadstring(readfile("havoc_db/claim_parts.luau"))()
end)

-- 3) child-instance tool fixer (mesh/texture auto-create + locked gate off)
local okFix = pcall(function()
  return loadstring(readfile("havoc_db/f3x_toolfix.luau"))()
end)

print("[f3x_patch] loaded (strip=" .. tostring(okStrip) .. " claim=" .. tostring(okClaim) .. " toolfix=" .. tostring(okFix) .. ")")

return { strip = okStrip, claim = okClaim, toolfix = okFix }
