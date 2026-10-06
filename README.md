# Havoc F3X

Toolkit for **F3X Building Tools** games running the **raidRolePlay** framework
(reference target: place `7797017666`, F3X v3.1.0). Split out of
[`havoc-hub`](https://github.com/Randeyeuhm/havoc-hub) — full commit history preserved.

## The wall this kit exists for

The game runs F3X behind a server-side ownership gate:

- every sync (`SyncMove` / `SyncResize` / `SyncMesh` / ...) is **silently refused**
  unless the part's `RRPartOwner` tag matches the calling player — no error, no
  log, the edit just never replicates
- the ownership escalation remote is **unvalidated**:
  `EscalateEvent:FireServer(Modules.PartOwnership, {parts})`
  retags any part to you, server-side, silently

So: claim a part → every tool works on it. This kit automates that end to end.

## Components

| file | what it does |
|---|---|
| `claim_parts.luau` | **HAVOC_CLAIM v1.8.0** — claim exploit + auto-claim on select/edit (tags the part the moment you click it) + resurrection watcher (re-arms hooks after every respawn — the tool is re-cloned on death) + `Locked=false` unlock loop |
| `tool_fixer.luau` | **v1.0.0** — wraps the framework sync dispatcher (`SyncModule.PerformAction`): Mesh/Texture tools get their missing child instance created on demand and mirrored to the server so it replicates. Locked-part sync gate off. Diagnostics: `HavocFixHits` / `HavocFixCreated` / `HavocFixMirrored` / `HavocFixLast` attributes on the tool |
| `raidroleplay_bypass.luau` | strips the raidRolePlay clamp modules from the F3X `callmods` arrays (size/mesh caps, part-rate limiter, clone/anchor bombs, locked-part clamp, ownership edit-guard, explorer hider). Keeps logs / sets / shift-T |
| `patch.luau` | bundle — loads the three above in order (this is what autoexec runs) |
| `clamp_bypass.luau` | legacy first-gen strip (superseded by `raidroleplay_bypass.luau`; kept for reference / old sessions) |

## Install (executor side)

Copy the files into the executor workspace under these names:

```
havoc_db/claim_parts.luau
havoc_db/f3x_toolfix.luau          <- tool_fixer.luau
havoc_db/raidroleplay_bypass.luau
havoc_db/f3x_patch.luau            <- patch.luau
```

`havoc-hub`'s autoexec loads `havoc_db/f3x_patch.luau` automatically in F3X places
(PlaceId-gated). Manual run:

```lua
loadstring(readfile("havoc_db/f3x_patch.luau"))()
```

## API / status handles

```lua
getgenv().HAVOC_CLAIM     -- .sel() .parts(list) .near(r) .players(name) .world(r)
                          -- .unlock() .unlockloop() .auto() .watch() .status()
getgenv().HAVOC_RP_BYPASS -- strip result; restore via HAVOC_CLAMP_RESTORE()
getgenv().HAVOC_F3X_FIX   -- { patched, hits, created, mirrored, last }
```

## Notes

- never mass-run `world()` / `unlock()` in a live session — that is a lot of
  server traffic at once; if a session gets poisoned, a rejoin fixes it
- claiming retags the part — the original owner silently loses it, use with intent
- with the fixer loaded the Mesh tool works on **any** part: select → pick Mesh
  Type / paste a Mesh ID — no "+ Add Meshes" button needed
