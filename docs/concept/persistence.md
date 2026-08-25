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
   - **…but the player must be told what new costs, and it must be
     recoverable.** New Game is the only irreversible action in the game.
     There is one save slot, so starting one destroys the other — the whole
     accumulated world, not just a character. Two consequences are part of
     the spec, not polish: the player is asked before anything is destroyed
     (and only when there is actually something to lose), and everything the
     wipe removes is copied to `<path>.bak` first. One generation,
     overwritten by the next New Game — enough to undo a mis-click, not an
     archive. It roughly doubles the world's on-disk size while the backup
     sits there, which is a cheap price for an undo.
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

### Confirming a destructive New Game

The destructive click is **Begin**, at the end of the character creator — not
the root screen's "New Game", which only navigates. **Host Game (LAN)** routes
through the same creator and the same Begin button, so it is exactly as
destructive; a confirmation on the root screen's New Game button alone would
miss it entirely.

- `MainMenu._begin_pressed` is the only path to `start_requested`. When
  `_player_save.has_save(save_path)` it shows a confirmation screen instead of
  emitting — the *same* predicate that decides whether the root screen offers
  Load Game, so "is there anything to lose" is answered in exactly one place.
  A first-ever game never sees a warning about a save that does not exist.
- The confirmation is a fourth screen in `MainMenu`'s existing
  `_root_screen`/`_create_screen`/`_join_screen` state machine (a plain
  `Control`, like every other overlay in this codebase — `SettingsOverlay`,
  `LicenseGateOverlay`, `LoadingOverlay` — not a `ConfirmationDialog`). `_show`
  and `_ready` read one shared `_screens()` list, so a screen can never be
  added to the tree but forgotten by the hide loop. "Keep my save" is the
  primary button and comes first; "Overwrite and start" emits.
- It names what is actually destroyed — the character *and* the world they
  lived in — rather than asking "are you sure?".

**The seam with `World`:** no new signal and no change to
`start_requested`'s signature. Its *meaning* is now stricter —
`start_requested` means "the player has confirmed a destructive new game" —
so `World._on_menu_start_requested` keeps wiping unconditionally. World never
confirms anything; by the time the signal arrives the loading overlay is
already going up.

`World`:
- **New Game** (`_on_menu_start_requested`, existing path): before spawning,
  first **backs up** everything it is about to destroy (`_backup_persisted_
  world` → `WorldReset.backup_directory`/`backup_file` over
  `World.backed_up_directories()`/`backed_up_files()`), then
  wipes `PlayerSave` and every `EarthChunkManager` persistence directory
  (`MODIFICATIONS_DIR`/`PLANTED_TREES_DIR`/`FISH_POPULATION_DIR` — read as
  already-public constants, not modified), plus the emergence stores (event,
  memory, household, contract, market, institution, world-boss) and the world
  clock, via a `World`-local helper, so the
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

## Loading screens

New Game/Host, Load Game, and Join all pay a real cost before the player can
actually move: generating and painting every chunk in a freshly-centered
`LOAD_RADIUS` (trees/stones/grass/crops/decomposers/flowers/scrub/lichen for
each) — measured at **~39-90s+ for a full radius** in this dev sandbox (real
timing instrumentation against a real running instance, not estimated).

This used to be one single fully-synchronous `EarthChunkManager.update()`
call with no `await` anywhere in its chain (`update` → `_load_chunk` →
`TerrainRenderer.paint`/`TreeRenderer.spawn_trees`/...), so the engine could
never present a frame during it — even an honest indeterminate spinner froze
on whatever glyph it was on for the entire real duration, and the game read
as hung despite the loading screen (reported: "the loading screen doesn't
show actual progress and still looks like it's hanging"). The fix was
restructuring the load itself, not just the screen over it:
`EarthChunkManager.update_with_progress(player_tile, on_progress)` is a
chunked variant that computes the exact chunk set up front
(`pending_load_chunks`, cheap — no generation, just the same
`chunks_in_radius`/`is_chunk_loaded` check `update()`'s own loop already
made), then loads one chunk at a time, calling `on_progress(loaded, total)`
and `await`ing one `process_frame` after each. That single `await` is what
lets the engine actually paint a frame between chunks — both the spinner's
own animation and a REAL determinate percentage are visible for the first
time, where neither was reachable before without exactly this restructuring
(previously deferred as "out of scope for a loading screen alone").
`update()` itself is still fully synchronous — every other caller
(continuous per-frame gameplay in `World._process`/`_server_process`, and
the whole pre-existing `update()` test suite) keeps using it unchanged;
`update_with_progress` is purely additive.

### Steady-state streaming

The same argument applies *during* play, not only at the cold load. `World`
calls `update()` **every frame**, and stepping across one chunk boundary
makes a whole `LOAD_RADIUS` column pending at once — five chunks generated,
terrain/water/hillshade/roof/snow painted, and fully populated inside that
single frame. That is the periodic stall while walking.

The fix here cannot be an `await`: `_client_process` must stay a plain
synchronous function (the constraint `world.gd`'s own comment above
`_run_initial_client_chunk_load` already records). So `update()` instead
takes an **optional per-call budget**,
`EarthChunkManager.max_chunk_loads_per_update` — the same "bounded work per
call" shape `FORAGE_DROPS_PER_TICK`/`SPREAD_ATTEMPTS_PER_TICK` already use:

- **Default `0` means unbudgeted**, i.e. exactly what `update()` has always
  done, in exactly the row-major order it always did. Nothing about the
  cold load or any existing caller changes.
- **When budgeted**, the pending set is loaded **nearest first** (ties
  broken on row-major position, so the order stays deterministic). Ordering
  is not cosmetic: `chunks_in_radius` is row-major, so a merely capped scan
  would spend the budget on the far top-left corner of the radius while the
  ground the player is walking onto stayed unloaded.
- **The budget value is derived, not picked.**
  `EarthChunkManager.chunks_per_update_for(tiles_per_second,
  frames_per_second)` computes the smallest budget that still keeps the
  streaming edge ahead: a diagonal boundary crossing makes at worst
  `2 * (2 * LOAD_RADIUS + 1) - 1` = 9 chunks pending, and the nearest tile
  of that ring is `LOAD_RADIUS * CHUNK_SIZE` = 64 tiles away, of which
  `CHUNK_BUDGET_SAFETY_FACTOR` spends only half. At the player's real base
  pace (`Player.BASE_SPEED` 80 world units/s over `TerrainRenderer.TILE_SIZE`
  16 = 5 tiles/s) at 30 fps that is **1**. A player fast enough to cross the
  whole lead inside one frame gets the entire pending set back — the budget
  degrades to today's behaviour rather than to a hole in the ground.

Budgeting changes *when* and *in what order* chunks load, never *which*: a
budgeted manager driven to completion ends holding exactly the chunks an
unbudgeted one does, and eviction is deliberately outside the budget so a
slow loader cannot grow the live set.

`World` is what makes the budget real in the running game — the manager's
own default is `0`, so until someone opts in the whole mechanism is dormant.
`World._apply_streaming_budget(manager)`, called from `_ready()` immediately
after the manager is constructed, hands it
`chunks_per_update_for(STREAMING_BUDGET_TILES_PER_SECOND,
STREAMING_BUDGET_FRAMES_PER_SECOND)`. Both inputs are real measurements
rather than dials: the pace is the *fastest* the player can actually travel
(`Taming.MOUNTED_SPEED` over `TerrainRenderer.TILE_SIZE`, not the walking
pace), and the frame rate is the *worst* the playtest measured — 6 FPS, the
floor of the 6-8 FPS dip at a chunk boundary this exists to remove, not the
20-26 FPS of smooth walking. Assuming the dip is the conservative direction:
fewer frames per second means fewer `update()` calls to spread the pending
chunks over, so the derivation must allow *more* chunks per call, and the
budget can never itself be why a chunk arrives late. Neither constant is a
knife edge — the derivation returns **1** across the whole 6-144 FPS band at
both the walking and the mounted pace, which is what makes this a derived
value rather than a tuned one. The cold load is untouched: it goes through
`update_with_progress`' coroutine, which has its own per-frame yield.

`World._show_loading_overlay(text)` shows `LoadingOverlay` (a small,
purpose-built `Control` — dim full-screen backdrop, centered status label,
spinner glyph) and awaits **two** `process_frame` signals before returning,
so the overlay is genuinely painted on screen before the caller starts its
long call (one await frame is not reliably enough — Godot can defer a
freshly-added Control's first draw one frame further; confirmed by
capturing a real rendered screenshot mid-freeze, not assumed from the
`await` alone). `LoadingOverlay.set_progress(loaded, total)` is the new
piece: it appends a real `"(N / M chunks)"` suffix onto the status line,
called as the `on_progress` callback (`World._on_chunk_load_progress`) every
`update_with_progress` call site shares. Wired into all three entry points:

- `_on_menu_start_requested` (New Game/Host): "Preparing a new world..." →
  `_spawn_local_singleplayer` → `_compute_dry_land_spawn_tile`, which now
  calls `update_with_progress` instead of `update`.
- `_on_menu_load_requested` (Load Game): "Loading your world..." →
  `_spawn_local_singleplayer_from_save`, same swap.
- `_on_menu_join_requested` (Join): "Connecting to host..." — a joining
  client still has no single call site to wrap the way the other two wrap
  their spawn functions, since its local player only exists once the
  server's own spawn has replicated in and its first real chunk load
  happens later, inside the per-frame `_client_process` tick. Shown
  immediately on click regardless, so the connection handshake and the
  later load aren't a blank/frozen-looking screen either. `_client_process`
  now runs that first load via a separate one-shot async task
  (`_run_initial_client_chunk_load`, fire-and-forget so `_client_process`
  itself stays a plain synchronous per-frame function and every per-frame
  UI update below it keeps running rather than also suspending across
  frames) instead of a single synchronous `update()` call, guarded by
  `_initial_client_chunk_load_task_running`/`_done` so it only ever runs
  once and never races the plain per-frame `update()` calls before/after it.

Hidden once the relevant path's own load actually finishes: New Game/Load
Game hide it from `_run_initial_client_chunk_load`'s own completion (their
local player only reaches `_client_process` after their heavy
`update_with_progress` call already finished, so this "second pass" finds
zero chunks pending and completes instantly — the same "second, now-cheap
call" shape as before, just through the chunked entry point uniformly); Join
hides it from that same completion point the first time it actually
represents real, multi-frame chunk loading. Still gated on
`_loading_overlay.visible` (a no-op once already hidden), the same single
hide point as before.

Progress is now a REAL, determinate **"N / M chunks"** count, not a
fabricated percentage and not just an indeterminate spinner glyph anymore
(that was this section's earlier design, before the reported "still looks
like it's hanging" follow-up made it clear an honest-but-frozen spinner
wasn't actually solving the perceived-hang problem). The chunk set is known
and bounded up front (`pending_load_chunks`), so a real total was always
computable — what was missing was `update()`'s own loop ever yielding, which
`update_with_progress` now does. `update()` itself is unchanged and every
one of the ~127 test files that depends on it completing in one synchronous
call keeps working exactly as before; only the three loading-screen entry
points (plus Join's `_client_process` tick) now go through the chunked
variant.

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
- ✅ `WorldReset` (`src/world/world_reset.gd`) backs up **and** wipes a
  persistence directory or file (`backup_directory`/`backup_file`/
  `wipe_directory`, one `.bak` generation — `BACKUP_SUFFIX`), tested
  (`test_world_reset.gd`, including the exact New Game sequence: back up,
  wipe, and the copy is still there); wired into
  `World._wipe_persisted_world` (player save + all three `EarthChunkManager`
  persistence dirs + the seven emergence stores + the world clock) for both
  New Game and Host Game.
- ✅ The backup list itself — `World.backed_up_directories()`/
  `backed_up_files()`, each path read from the persistence class that owns it
  rather than restated — tested (`test_world_backup_paths.gd`), including a
  drift pin that counts the wipe calls in `_wipe_persisted_world`'s own
  source, so a store added to the wipe without a matching backup entry fails
  a test instead of silently shipping as un-undoable data loss.
- ✅ The overwrite confirmation (`MainMenu._begin_pressed` +
  `_overwrite_confirm_screen`), tested (`test_main_menu.gd`): Begin does not
  emit `start_requested` while a save exists, confirming emits, "Keep my
  save" returns to the creator, Host Game is confirmed too, and the new
  screen is hidden by `_show` like every other. Previously Begin destroyed
  everything on one click with no prompt at all.
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
- ✅ Loading screen (`LoadingOverlay`, `src/ui/loading_spinner.gd`) covering
  New Game/Host, Load Game, and Join's real world-setup stall, now with REAL
  chunk-by-chunk progress (see Loading screens above) —
  `EarthChunkManager.pending_load_chunks`/`update_with_progress` are pure
  chunk-manager methods, tested (`test_earth_chunk_manager.gd`: total-matches-
  chunks-in-radius, same chunks loaded as `update()`, progress calls run
  0→total exactly once per chunk, eviction still happens); `LoadingSpinner.
  frame_for_elapsed` is pure and tested (`test_loading_spinner.gd`);
  `LoadingOverlay.set_progress`/its `World` wiring
  (`_on_chunk_load_progress`/`_run_initial_client_chunk_load`) are untested
  Node-composition glue, the same established boundary as the rest of
  `World`/its overlay classes (`MainMenu`/`SettingsOverlay`) — `world.gd`
  itself has no dedicated unit test (confirmed to still compile and its own
  existing pure-helper tests, `test_world_persistence.gd`, still pass after
  this change). The original spinner-only design was verified against a real
  running instance (real screenshots, both mid-freeze and post-spawn, for New
  Game and Load Game — see `docs/progress.md`); this progress-reporting
  follow-up was NOT re-verified the same way (no live-GUI-automation harness
  available in the session that built it), so the `World`-level wiring is
  reasoned from the code and the passing chunk-manager tests, not
  screenshot-confirmed — the same honestly-scoped gap this doc's own Join
  entry already had.
- 🚧 The pre-menu terrain-atlas bake (`TerrainRenderer.build_tile_set`,
  triggered unconditionally in `World._ready()` via `EarthChunkManager`'s
  constructor, before the main menu itself is even shown) is a real,
  separate stall on the same order of magnitude when its on-disk cache is
  stale or missing (measured ~62s in this dev sandbox on this session's own
  `ATLAS_VERSION` bump) — NOT covered by the New Game/Load Game/Join loading
  screens above, since it happens before any of those entry points exist to
  wrap. Left alone deliberately: fixing it would mean restructuring when/how
  `World` constructs its `EarthChunkManager`, materially bigger than a
  loading screen over an existing synchronous call. A stale cache is a
  one-time cost per `ATLAS_VERSION` bump, self-heals (writes a fresh cache)
  on that first paid run, and every run after is fast (~3s, cache hit).
- 🚧 **Restoring** from a `.bak` is manual: the copies sit next to the
  originals in `user://` and recovery today means renaming them back by hand
  (drop the `.bak`, with the game closed). The backup closes the "gone
  forever" hole; an in-game "restore the world I just overwrote" affordance
  is not built. That is the honest gap, and the obvious next step — the
  paths are already enumerated by `World.backed_up_files()`/
  `backed_up_directories()`, so a restore is the same loop run the other way.
- ⬜ Multiple save slots, cloud sync, or any cross-device concern — out of
  scope; single local save file only.
