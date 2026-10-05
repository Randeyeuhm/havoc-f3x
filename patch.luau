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
         Locked=false unlock loop (everything self-arms)

  Use:
      loadstring(readfile("havoc_db/f3x_patch.luau"))()
  (autoexec loads this automatically, PlaceId-gated to F3X games)

  Status after load:
      getgenv().HAVOC_RP_BYPASS   - strip result
      getgenv().HAVOC_CLAIM       - claim tool (auto/watch/loop armed)
]]

-- 1) raidRolePlay clamp strip
local okStrip = pcall(function()
  return loadstring(readfile("havoc_db/raidroleplay_bypass.luau"))()
end)

-- 2) ownership claim + unlock kit
local okClaim = pcall(function()
  return loadstring(readfile("havoc_db/claim_parts.luau"))()
end)

print("[f3x_patch] loaded (strip=" .. tostring(okStrip) .. " claim=" .. tostring(okClaim) .. ")")

return { strip = okStrip, claim = okClaim }
