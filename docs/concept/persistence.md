# Persistence (New Game / Load Game)

This doc specifies how a player's session survives a restart: what "New Game"
and "Load Game" actually mean, what state is saved, when, and in what format.
Unlike the simulation docs (`ecosystem_dynamics.md`, `fishing.md`, ...), this
isn't a simulated mechanic grounded in a real-world process — it's the
meta-system that makes the rest of them mean anything across sessions. Its
"real-world grounding" is simply: closing and reopening a game should not be
punished.

## Design pillars

1. **New Game means new.** Choosing "New Game" must produce a genuinely fresh
   world and a genuinely fresh character — no leftover chunk edits, no
   leftover trees planted by a previous run, no previous save silently
   reappearing. Before this doc, the world persisted eagerly regardless of
   menu choice while the player never persisted at all, so "New Game" actually
   meant "old world, new stats" — a bug, not a feature.
2. **Load Game means exactly where you left off.** Position, class, authored
   appearance, carried items, worn gear, hotbar bindings, wallet, XP/level,
   and skill-tree allocations all round-trip losslessly. A loaded character
   should be indistinguishable from one that never stopped playing.
3. **Save what can't be regenerated, skip what can.** This mirrors
   `EarthChunkManager`'s existing philosophy (terrain is deterministically
   regenerable from its seed, so only *modifications* persist) — per-frame
   derived fields (current swim state, cached speed multipliers, transient
   minigame state) are never saved; only the authored/accumulated state that
   has no other source of truth is.
4. **One convention, reused.** The existing world-persistence code
   (`EarthChunkManager`/`ChunkSerializer`) already established a convention
   for `user://`-backed Variant persistence — `FileAccess.store_var`/
   `get_var`, a `file_exists` guard, an empty/default fallback on a missing
   file. Player persistence follows the same convention rather than
   inventing a second one (`Keybindings`' `ConfigFile` approach is a third,
   pre-existing convention for flat key/value overrides — not reused here
   since player state is nested, not flat).

## What persists

Owned and serialized by `Player.to_save_dict()` / `Player.apply_save_dict()`
(the domain knowledge of which fields matter lives on `Player`, matching how
`apply_class` already owns "how a class/appearance choice becomes a live
character"):

- `position`, `respawn_position`
- `character_class`, `appearance` (the authored `HeroAppearance` dict — a new
  `Player.appearance` field; previously the creator's choice was applied to
  the character view once and then forgotten, so it couldn't be saved)
- `health`, `max_health`, `class_attack_bonus`, `skill_attack_bonus`
- `wallet` balance
- `experience` (total XP, level, unspent points)
- `allocated_nodes`, `unlocked_keystones` (skill tree progress)
- `inventory` (item id + count per stack — reconstructed via `ItemCatalog`,
  which already exists specifically to build an `Item` from just its id)
- `equipment` (worn item id per slot, including the held weapon/tool under
  the `"weapon"` slot — `equipped_item` is always exactly `equipment`'s
  `"weapon"` entry in current code, see `Player.equip_item`, so it isn't
  saved as a separate key; restoring the `"weapon"` slot via `equip_item`
  derives it for free)
- `hotbar` (item id per slot, `""` for empty)

Explicitly NOT persisted (derived or session-transient, regenerated for free
on load): `current_mode`/`current_speed_multiplier` (recomputed every physics
step from tile/water depth), `wetness` (starts dry — a minor, deliberate
simplification), active food buffs, in-progress fishing/trade minigame state,
input-edge flags, non-authority replication proxies.

World state (chunk modifications, spread-in trees, fish population) is
unchanged by this doc — it already persists eagerly to `user://` via
`EarthChunkManager`/`ChunkSerializer` regardless of player state. This doc
only adds the missing wipe step so "New Game" actually clears it.

## Save format

`src/gameplay/player_save.gd` (`PlayerSave`, a small `RefCounted` mirroring
`ChunkSerializer`'s role — I/O mechanics only, no game-domain knowledge):

- `SAVE_PATH := "user://player_save.bin"` — one file, one save slot (no
  multi-save-slot UI exists or is planned; out of scope).
- `has_save() -> bool` — `FileAccess.file_exists(SAVE_PATH)`.
- `save(data: Dictionary) -> void` — `FileAccess.open(WRITE)` →
  `store_var(data)` → close, the same pattern as
  `ChunkSerializer.save_modifications`.
- `load_data() -> Dictionary` — `file_exists` guard, `{}` on a missing file,
  else `FileAccess.open(READ)` → `get_var()` → close.
- `wipe() -> void` — removes `SAVE_PATH` if present.

## New Game / Load Game flow

`MainMenu` grows a **Load Game** button in the root screen, shown only when
`PlayerSave.new().has_save()` — no disabled-button state; the choice simply
isn't offered when there's nothing to load. It bypasses the character creator
entirely (a load restores a character, it doesn't author one) and emits a new
`load_requested` signal straight from the root screen.

`World`:
- **New Game** (`_on_menu_start_requested`, existing path): before spawning,
  wipes `PlayerSave` and every `EarthChunkManager` persistence directory
  (`MODIFICATIONS_DIR`/`PLANTED_TREES_DIR`/`FISH_POPULATION_DIR` — read as
  already-public constants, not modified) via a `World`-local helper, so the
  freshly spawned character loads into a genuinely clean world. Safe to do
  unconditionally here because `EarthChunkManager` hasn't loaded any chunks
  yet at this point in `_ready()`'s sequencing (chunk loading is lazy, first
  triggered by spawn) — wiping the on-disk files before that first load means
  every chunk simply finds nothing to layer on top of its deterministic base.
- **Load Game** (`_on_menu_load_requested`, new path): reads the save,
  spawns a player at the saved position (chunk-loading the area around it
  the same way a fresh spawn's dry-land search does, just without the
  dry-land search since the saved position is already valid), applies the
  saved class/appearance via the existing `apply_class` (for character-view
  wiring), then immediately overwrites health/inventory/equipment/wallet/
  hotbar/skill state from the save — `apply_class` alone would leave a
  loaded character fully healed and starter-equipped, which is only correct
  for a genuinely new character.

Autosave: mirrors the world's existing "persist eagerly, not on an explicit
save action" philosophy. Triggered on the same cadence as other periodic
world upkeep already ticking in `World` (see implementation for the exact
interval — a tuned/tested constant, not eyeballed) plus once on quit, so
progress is never more than one short interval old.

## Status / mechanisms

- ✅ `Player.appearance` field + `to_save_dict()`/`apply_save_dict()`, tested
  (`test_player_persistence.gd`) via a real source-player -> saved-dict ->
  restored-player round trip, including the "restore keeps damage, doesn't
  full-heal" regression `apply_save_dict` exists to prevent.
- ✅ `PlayerSave` (`src/gameplay/player_save.gd`), tested
  (`test_player_save.gd`).
- ✅ `MainMenu` Load Game button + `load_requested` signal, save-aware root
  screen (only offered when `PlayerSave.has_save()`), tested
  (`test_main_menu.gd`).
- ✅ `WorldReset` (`src/world/world_reset.gd`) wipes a persistence directory,
  tested (`test_world_reset.gd`); wired into `World._wipe_persisted_world`
  (player save + all three `EarthChunkManager` persistence dirs) for both
  New Game and Host Game.
- ✅ `World` Load-Game spawn path (`_spawn_local_singleplayer_from_save`) and
  the New-Game wipe call — orchestration glue over the already-tested pieces
  above, in keeping with `World`'s existing untested-glue boundary (no
  `world.gd` function had a direct unit test before this doc either); the
  one genuinely pure piece it added, `_tile_for_position`, is tested
  (`test_world_persistence.gd`). Verified by manual playtest + a clean
  relaunch log rather than an automated World-level test.
- ✅ Autosave (`World.AUTOSAVE_INTERVAL`, periodic in `_client_process` +
  once on `NOTIFICATION_WM_CLOSE_REQUEST`) — same untested-glue boundary as
  the rest of `World`.
- ⬜ Multiple save slots, cloud sync, or any cross-device concern — out of
  scope; single local save file only.
