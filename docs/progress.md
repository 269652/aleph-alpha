# Progress Tracker

This document is a living status tracker for everything defined across the 32
design docs in `docs/concept/*.md` plus `docs/roadmap.md`, cross-referenced
against what is actually implemented in the codebase today. It was generated
by extracting every distinct mechanism named or implied in those docs (481
total, catalogued below) and checking each one against the real, tested
source in `src/`, `scenes/`, and `tests/`.

**Update this file as work progresses.** When a mechanism moves from
not-started to partial or done, update its row/bullet, and when new design
docs are added, extend the relevant section. This is meant to be a complete
reference, not a curated highlight reel — it intentionally includes every
minor/open-question mechanism the source docs mention, not just headline
features.

## Status legend

- ✅ **Done** — implemented and (per project convention) covered by tests.
- 🚧 **Partial** — meaningfully started, but incomplete, superseded, or not
  wired into live gameplay yet.
- ⬜ **Not started** — no implementation exists.

---

## Roadmap phases (`docs/roadmap.md`)

The roadmap is the only source doc that already sequences work into phases,
so its own mechanisms are tracked here phase-by-phase. Nearly everything else
in the design corpus (classes, skills, magic, crafting, farming, etc.)
predates or sits outside this roadmap and is tracked in the
[Unscheduled](#unscheduled--not-yet-phased-into-the-roadmap) section below.

### Phase 0 — Foundations / tech spikes

Goal per roadmap: de-risk the unknowns before building gameplay on top of them.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Project Scaffold & Tile Rendering | ✅ Done | Godot 4.7 project set up; `scenes/world.gd`/`.tscn` is the root scene (viewport 1280x720). `src/rendering/terrain_renderer.gd` bakes procedurally-generated, seeded pixel-art tiles (`procedural_terrain_sprite.gd`) with `VARIANTS_PER_BIOME` (6) variety per biome, now **animated in real time** via `TileSetAtlasSource` tile animation (`FRAME_COUNT` 4-frame blocks, zero per-frame script cost): grass tufts sway (baked, frozen-per-blade -- real motion lives in the GPU blade field below), and each biome layers detail over its base speckle (grass tufts + flower accents, forest-floor moss, desert dune ripples, tundra stones, mountain cracks). The base water tile is now a calm static-per-frame tint/texture only -- all visible water motion (waves, shore blending, rain) moved to a dedicated **WaterFx GPU overlay** (`water_shader.gd`, a second TileMapLayer painted via `TerrainRenderer.build_water_overlay_tile_set`/`EarthChunkManager.set_water_layer`): a per-pixel "shore distance" data tile family (`procedural_shore_distance_sprite.gd`, 0 at the land edge to 1 in open water) drives a fragment shader that sums ambient wind chop, an incident+reflected standing-wave band near the coast ("waves bounce off shore"), and hash-seeded expanding raindrop ripple rings (`rain_intensity` uniform, driven continuously by `EarthChunkManager.set_rain` from the live weather model) into one interfering wave field, fading alpha smoothly with shore distance so the coastline blends instead of cutting off at a tile edge (replacing the old baked foam/dash shore tiles, whose 16px grid read as a jagged staircase). A `wind_strength` uniform (`WeatherModel.wind_strength_for`, driven the same way as `rain_intensity` via `EarthChunkManager.set_wind_strength`) paces the ambient wave's scroll rate to the live weather's severity, so the same shore idles calmly on a clear day and churns faster/choppier during a storm. Individual 1px grass blades similarly moved off the tile grid onto a per-chunk GPU `MultiMeshInstance2D` field (`grass_blade_field.gd`) clustered into natural tufts. Vegetation sprites (trees, tall-grass and scrub tufts, the GPU blade field) sway via a shared GPU vertex shader (`wind_sway.gd`, gentle two-frequency gust motion, world-position phase so gusts roll across a meadow; lichen deliberately static). Border cells still dither toward whichever differing neighbor biome dominates on each edge (`dominant_blend_for`, `BLEND_VARIANTS` 3 -- fringe needs fewer looks than base ground), and chunk seams blend through `EarthChunkGenerator.biome_at_global` exactly like interior borders. | small |
| Camera & Player Movement | ✅ Done | `scenes/player.gd` — `CharacterBody2D` with WASD movement (runtime-bound), toroidal wrap, water movement integration. | small |
| Heightmap Generation | 🚧 Partial (repurposed) | `src/world/heightmap_generator.gd` exists, tested, but no longer used for Earth — kept explicitly for generating future non-Earth planets. Earth instead uses real elevation data (`earth_elevation_source.gd`). | medium |
| Hydraulic Erosion Pass | 🚧 Partial (repurposed) | `src/world/hydraulic_erosion.gd` exists, tested, same caveat: part of the old fully-procedural pipeline, not used for Earth's real rivers/lakes. | large |
| Climate Banding | ✅ Done | `src/world/climate_model.gd` — temperature from latitude + elevation (simple lapse-rate model), applied to the real Earth world. | medium |
| Biome Classification | ✅ Done | `src/world/biome_classifier.gd` — elevation/temperature/moisture → 7 biomes (ocean/mountain/tundra/forest/grassland/rainforest/desert); has both a fictional-noise-tuned default calibration and a parameterized real-Earth calibration. | small |
| Toroidal World Wrap | ✅ Done | `src/world/world_coordinates.gd` (toroidal math) + player wrap in `scenes/player.gd`. | medium |
| Chunk Save/Load System | 🚧 Partial | `src/world/chunk.gd` + `chunk_serializer.gd` — data model and persistence built and tested, but **not wired into gameplay**: no player-driven terrain modification exists yet, so nothing is ever actually saved/loaded at runtime. | large |
| Day/Night Clock | ✅ Done (superseded design) | `src/world/solar_position.gd` drives real-time (actual system clock, not accelerated/abstract) day/night lighting via `CanvasModulate` in `scenes/world.gd`. The originally-planned abstract/accelerated clock (`world_clock.gd`, `sunlight_model.gd`) still exists, kept as a possibly-reusable utility (e.g. abstract elapsed game-days later). | trivial |
| Per-Tile Sunlight Model | ✅ Done | `solar_position.gd` computes real astronomical solar elevation from UTC time + lat/long (approximate formula, no equation-of-time correction). | small |

**Phase 0 definition of done** ("a small toroidal world generates once, looks
biome-plausible, saves/loads chunks correctly, and has a visible day/night
cycle"): mostly met, but the project deliberately diverged from the plan —
instead of a small fictional test map, it generates a real, finite Earth
(~40,000×20,000 tiles, ~111 tiles/degree, ~1km/tile) from real elevation data.
Biome plausibility and day/night are real; chunk save/load exists but is not
yet exercised by any runtime gameplay.

### Phase 1 — Living ecosystem MVP

Goal per roadmap: prove the "boars live where boars thrive" pillar. Core loop
built and wired into live gameplay (server/singleplayer-authoritative); known
gaps noted per mechanism below.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Vegetation Growth Model | 🚧 Partial | Three still-separate systems: (1) `src/world/tree_placement.gd` + `src/rendering/tree_renderer.gd` -- static, deterministic, biome-driven tree *placement* (collidable `ChoppableTree`s), unchanged; (2) `src/world/vegetation_growth_model.gd` -- a real per-cell logistic growth/die-back/neighbor-spread simulation (temperature+moisture -> effective carrying capacity -> density), driving herbivore capacity below (mountain's `CARRYING_CAPACITY_BY_BIOME` entry is now a small nonzero `0.12`, sparser than tundra's `0.2` -- previously a hard `0.0` that made mountain permanently uninhabitable, which was pointless once mountain got its own goat/mountain_lion species pool; ocean correctly stays `0.0`); (3) new **individual-tree genetics/spread** -- `TreeGenome` (deterministic per-tree DNA: fruit_yield/species_bias/spread_radius/maturity_time, with `mutate()` for inheritance), `TreeSpread` (mature trees plant a mutated-child sapling within their own spread_radius, centrally throttled like forage), and `TreeMaturity` (a sapling only forages/reproduces once its own age exceeds its genome's maturity_time) -- wired into `EarthChunkManager.step_tree_spread`, spawned/rendered via `TreeRenderer.spawn_tree_at` with a genome-tinted canopy (`ProceduralTreeSprite`), and persisted per-chunk (`Chunk.planted_trees`, `ChunkSerializer.save_planted_trees`/`load_planted_trees`) across unload/reload. None of the three are unified: the density field still doesn't spawn/despawn/resize visible trees, and individual-tree genetics is independent of the density-driven herbivore capacity. | large |
| Herbivore Population Model | ✅ Done | `src/world/herbivore_population_model.gd` (+ generic `population_model.gd`): regional/aggregate logistic growth toward a vegetation+water-access-derived capacity, with migration toward neighboring spare-capacity regions. Tested incl. drought decline/recovery (`test_ecosystem_time_lapse.gd`). | large |
| Predator Population Model | ✅ Done | `src/world/predator_population_model.gd`: same shape, capacity derived from local herbivore population (trophic-pyramid ratio). | large |
| Aggregate/Individual Promotion System | ✅ Done | `src/rendering/creature_renderer.gd` + `EarthChunkManager`: loading a chunk (i.e. player proximity, reusing the existing chunk-streaming radius) spawns individual creature nodes sized to that region's current aggregate population; unloading frees them. Each promoted creature has procedurally-generated pixel-art (`procedural_animal_sprite.gd`) and real per-individual AI (see Individual Creature AI below). Species is now **biome-gated**, realizing the "boars live where boars thrive" pillar for real: `EarthChunkManager` computes each chunk's dominant biome (`BiomeClassifier.dominant_biome`) and passes it into `spawn_creatures`, which picks from `HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME` (grassland/forest/desert/tundra/rainforest/mountain each get their own herbivore+predator pair, e.g. desert -> camel/jackal, rainforest -> tapir/jaguar) instead of one global 4-species pool; unmapped biomes (currently just ocean) fall back to the original generic pool. Not replicated to multiplayer clients yet -- a connected client sees its own locally-seeded population, not the server's evolving one (see Multiplayer's known gaps). | large |
| Individual Creature AI (flee/hunt/graze/drink) | ✅ Done | `CreatureMarker` runs a per-frame sense→decide→act loop from four tested pure modules: `creature_needs.gd` (hunger/thirst rising over time), `creature_perception.gd` (senses nearby creatures/player + scans terrain for nearest food/water), `creature_behavior.gd` (priority decision: flee/attack/hunt/seek-water/seek-food/wander), and temperament/role on `creature_info.gd`. Herbivores are calm — they flee predators and the player, graze food biomes, and drink at water; predators are aggressive — they hunt and eat herbivores when hungry, attack the player when healthy (dealing real `Player.take_damage`), and flee when weakened below half health ("weak monsters flee, strong monsters attack"). **Known gaps**: food-seeking is biome-granularity (walks toward vegetated *biomes*, not toward the Phase-1 per-cell vegetation *density* field — the two aren't wired together yet); killing/being-killed doesn't decrement the region's aggregate `EcosystemSimulation` population (it reseeds on next chunk reload); sensing is O(nearby creatures) per frame with no spatial index; no flocking/territory/reproduction-at-individual-scale. | large |
| Ecosystem Time-Lapse Test | ✅ Done | `tests/unit/test_ecosystem_time_lapse.gd`: proves natural biome clustering (rainforest sustains more herbivores/predators than desert with no hand-placed spawners) and a scripted drought visibly declining then recovering a region's population -- both halves of the roadmap's explicit definition of done. | medium |

Known simplification shared by all of the above (documented in
`ecosystem_simulation.gd`): only chunks currently loaded (i.e. within the
existing player-proximity streaming radius) are simulated at all; there is no
whole-planet background simulation, and a region's state is not persisted
across unload/reload (regenerated at fresh equilibrium on revisit, same as
terrain chunks already do). A real "catch-up pass" for unloaded regions is
the separate, larger "Variable-Fidelity Chunk Simulation" item below.

### Phase 2 — NPC AI MVP

Goal per roadmap: prove the daily-plan NPC architecture at small scale.
**Nothing in this phase has been started.**

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| NPC Data Model | ⬜ Not started | No NPCs of any kind exist. | medium |
| LLM Daily Planner | ⬜ Not started | Zero LLM API wiring exists anywhere in the codebase. | medium |
| Local Schedule Executor | ⬜ Not started | | large |
| Interrupt/Replan Handling | ⬜ Not started | | medium |
| Live Dialogue System | ⬜ Not started | | large |
| LLM Backend Abstraction | ⬜ Not started | No LLM integration whatsoever. | medium |

### Phase 3 — Core gameplay loop

Goal per roadmap: make it a game, not a simulation demo. Definition of done
is met for the two mechanisms it names explicitly (a tactical mechanic beyond
plain damage trading; a built structure surviving save/reload) — inventory,
fire/oil, and layered elevation remain unstarted.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Player Stats/Inventory/Equipment | 🚧 Partial | Real `health`/`max_health`/`take_damage()` (`health.gd`); a real **item + inventory system** (`item.gd`, `item_stack.gd`, `inventory.gd` — typed items with stacking, a fixed-slot inventory, all tested); the player starts with an **Iron Sword** (equipped weapon, drives attack damage) and an **Iron Axe** (`equipped_tool`, felling-only — see Real-Time Arena Combat), and picks up loot/forage into the inventory. The old always-visible inventory text panel is gone, replaced by a real toggleable **`InventoryWindow`** (default key I, `scenes/inventory_window.gd`) showing an icon+name+count row per stack; clicking a row **activates** it via `Player.activate_item_id()` — weapons/tools get equipped, food/potions get used, materials do nothing (`hotbar_action.gd`, tested). A real HUD now exists (`scenes/world.gd`'s `_build_hotbar_slots`/`_build_spell_bar`/`_update_player_health_bar`/`_build_survival_bar`): a player health bar, a **usable hotbar** (number keys 1–5 or a click activate the corresponding slot via `Player.activate_hotbar_slot()` — equip weapon/tool, or eat food), a placeholder spell bar, and a bottom-left survival bar (hunger/thirst/stamina meters, from `src/gameplay/survival_meters.gd`, ticking down over time and refilled by eating/drinking/resting) plus a gold-count label backed by the `Wallet` (`/gold` dev-console command). Equipping is now a **single held item**: `Player.equip_item()` points `equipped_item` at whatever weapon/tool you activate (from the hotbar or by clicking an inventory row) and draws it in hand — so switching sword↔axe↔pickaxe visibly changes what you hold, and that one item alone decides attack damage, tree-felling speed (axe fast / sword slow / bare-hands slowest, via `MaterialDamage`), and mining power (only a pickaxe mines ore). **Key bindings are configurable** in a proper **pause/settings menu** (`scenes/settings_overlay.gd`, default Escape, pauses the game while open) with **Key Bindings** and **Graphics** (fullscreen, vsync) tabs; the tested `src/gameplay/keybindings.gd` is the single source of truth for every rebindable action + default key, and both keybinding overrides and graphics prefs persist to `user://keybindings.cfg`. Default layout: **E = pick up nearby items**, **I = inventory**, **C = crafting**, **B = place earth**, Escape = menu. A press of E sweeps every ground item within `PICKUP_RADIUS` into the inventory (`Player.pickup_nearby`), alongside the existing click-to-pick-up. The hotbar is now **user-assignable via drag-and-drop** (`src/gameplay/hotbar.gd`, `src/ui/drag_slot.gd`): drag an inventory item onto a HUD hotbar slot to bind it to that number key, and drag one inventory item onto another to reorder your pack (`Inventory.swap_slots`/`move_to_end`). Previously the hotbar just mirrored the first 5 inventory stacks with no drag-and-drop anywhere in the project, so — since the player starts with exactly 5 stacks — anything crafted later could never be put on a key at all (the reported "can't drag the rod into the hotbar / can't equip it"). Empty slots still auto-fill from the inventory so pickups appear on their own, explicit assignments are never overwritten, and a slot clears when you no longer carry its item. Equipping a weapon/tool now also fills the paperdoll's "weapon" slot (`Item.equip_slot_name` slots tools there too), so the Character screen reflects what's in hand. Still missing: armor slots (the `character_view.gd` colored squares remain cosmetic placeholders), a temperature/wetness-driven survival dimension (wetness tracking exists separately, see Phase 0; not yet fed into a meter), a potion item kind (the "use" path exists but only food items are defined so far), splitting/merging stacks by drag, and multiplayer sync of the inventory (a networked client's inventory is its local proxy's, not the server's). | medium |
| Real-Time Arena Combat | 🚧 Partial | Cooldown-based AOE melee swing (`_perform_attack`, `melee_attack.gd`) whose **damage comes from the equipped weapon** (`attack_damage(weapon, unarmed)`); it damages, knocks back, and kills creatures, which then **drop loot** (`loot_table.gd` → ground items). The swing is a real pendulum-arc animation (`weapon_swing.gd` + `CharacterView.play_attack_swing`) oriented horizontal/vertical by facing and pivoting from the weapon's grip, not its sprite center. Combat is now **two-directional**: aggressive+healthy predators attack the player back, weak ones flee (see Individual Creature AI). Each creature within range now gets its own real HUD panel (`scenes/creature_panel.gd`, one `CreaturePanel` per nearby creature via `world.gd`'s `_update_creature_panels`) showing name, level, an HP bar, and a numeric "HP x/y" label — replacing both the earlier aggregate "Nearby Creatures" list panel and an even earlier world-space floating-nameplate attempt (both rejected in favor of this per-creature-panel design). `CreatureHoverBus` and the world-space hover/name-label code in `creature_marker.gd` were deleted outright as dead code once nothing consumed them. Creature variety expanded to **12 species total**: the original herbivore/boar and predator/lynx pairs, plus 8 more biome-specific species (camel/jackal for desert, reindeer/arctic_fox for tundra, tapir/jaguar for rainforest, goat/mountain_lion for mountain), each its own entry in `creature_info.gd`'s stat/diet/temperament tables (tapir notably reuses boar's silhouette but stays calm, not aggressive — temperament is independent of shape); and every creature's max health now scales with level (`CreatureInfo.LEVEL_HEALTH_SCALE`). Creatures now use species-shaped procedural pixel art (`procedural_animal_sprite.gd`, 24x16 shaded+outlined silhouettes from 4 hand-authored shape families — boar-shaped, lynx-shaped, deer-shaped, wolf-shaped, see `SPECIES_SHAPE_FAMILY` — each reused by 2-3 species in a different color, plus a small dark speckle overlay unique to jaguar, with per-individual seeded shade jitter) — replacing the old generic color-tinted blob sprites. Species selection is now **biome-gated** rather than one global pool per role (see the Promotion System row above for `HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME`); within grassland/forest specifically, a promoted predator-role individual is a lynx 1-in-4 (`PREDATOR_SPECIES_POOL`), and predators are themselves the rarest role, so lynx are genuinely uncommon there; the distinct silhouette at least makes the ones that do spawn recognizable. **Combat is now material-aware** (`material_damage.gd`): creature hits go through a flesh multiplier per weapon kind (sword 1.0x, axe 0.8x, unarmed 0.5x) and tree chopping through a wood multiplier (axe 3x — the historical 15-damage tuning — sword 0.5x, bare hands 0.25x, so anything can eventually hack a tree down but only an axe is efficient). **Blocking exists** (`block.gd`, hold Shift): incoming damage is reduced by a weapon-dependent efficiency (sword 70%, axe 40%, unarmed 20%); blocking, like attacking, costs no stamina -- per `concept/survival.md`'s "Stamina scope: movement only, not combat" decision, combat stays purely cooldown-based. **Creatures are animated** (`procedural_animal_animation.gd`): every marker plays 2-frame generated pixel-art animations per action — walking legs alternate, attacks lunge, eating/drinking dips the head, swimming bobs half-submerged in a water band — with the action driven by what the AI actually did that frame (and an on-water check forcing "swim"). The player stows their weapon while swimming (`CharacterView.set_movement_state` hides the tool slot; `Player._attack_step` refuses to swing mid-swim). **The primitive knapping-tech chain is live** (see `knapping.gd`/`smashable_stone.gd`): boulders (`StonePlacement`/`StoneRenderer`) smash on a swing, always yielding the rock itself; carrying another rock knaps off sharp shards with a tested ~60% chance; a swing over mature tall grass tears up plant fibre (`EarthChunkManager.harvest_grass_near`); felled trees now drop sticks alongside wood; and `/craft crude_blade` lashes stick + shard + 2 fibre into a first crude weapon (damage 9, between fists and iron). **Trees feed animals**: herbivore-role creatures eat dropped fruit/nut ground items when standing close (`food_consumption.gd`, wired in `World._step_herbivore_food_consumption`), closing the trees→forage→herbivore loop; tall grass and trees both keep spreading on their own (`TallGrass.advance`, `TreeSpread`). The player also carries an **axe** (`equipped_tool`, see Item.is_axe()) that fells `ChoppableTree`s in range on the same attack input, dropping wood — separate from weapon combat, gated by tool type rather than weapon damage. Remaining: no abilities beyond the one swing, no armor/mitigation, killing a creature still doesn't decrement `EcosystemSimulation`'s aggregate count, and combat isn't replicated in multiplayer (a client's swing runs server-side against server creatures, not the client's local ones — play single-player for a coherent loop). | large |
| Knockback/Hazard Interaction | ✅ Done | `Knockback.step` (smooth ease-out displacement, not a teleport) + `MeleeAttack.knockback_vector` + `CreatureMarker.apply_knockback` — every hit shoves the target away from the player, Hammerwatch-style. Satisfies the roadmap's "at least one tactical/environmental mechanic beyond plain damage trading." No hazards (fire/traps/terrain) yet, only knockback. | small |
| Player Death & Respawn | 🚧 Partial | `scenes/player.gd`: reaching 0 HP now actually does something (previously it silently did nothing) — `is_dead` freezes input/movement, the sprite dims (`DEAD_MODULATE`), and after `RESPAWN_DELAY` the player respawns at `respawn_position` with health restored. No lives cost yet (`lives_tracker.gd` exists as a tested pure-logic module — see Eras/Death sections below — but isn't wired to this flow), no graveyard/corpse-recovery, no death penalty of any kind beyond the respawn delay. | medium |
| Spreadable Fire/Oil | ⬜ Not started | | large |
| Layered Tile Elevation | ⬜ Not started | | large |
| Vegetation-Based Concealment | ⬜ Not started | Blocked on combat's one-directional-only state (nothing to hide *from* yet); Phase 1's vegetation density data it would reuse now exists (`vegetation_growth_model.gd`). | medium |
| Tile Building/Destruction System | ✅ Done | `Chunk.modifications` is now real: `EarthChunkManager.build_at_global`/`destroy_at_global` write to it, `TerrainRenderer.paint()` renders a modified cell over its generated biome tile, and `ChunkSerializer.save_modifications`/`load_modifications` persist it to `user://chunk_modifications/` across chunk unload/reload (walking away and back — this project's real equivalent of "save/reload", per the pre-existing plan noted in `EarthChunkManager.update()`'s doc comment). Player-facing, with no placeable item armed: E turns the faced tile into bare earth (`TerrainRenderer.EARTH_TILE_ID`, Terraria-style terraforming -- E intentionally replaces whatever biome tile is there, grass included), Q destroys/reverts it, on whichever tile the player is facing (`src/gameplay/tile_targeting.gd`). **Placing crafted structures is now live**: selecting a `"placeable"`-kind item (campfire/furnace, `item_catalog.gd`) from the hotbar or inventory arms it (`HotbarAction.PLACE` → `Player._arm_placeable`); the next E press places that item's id into `Chunk.modifications` instead of bare earth, consuming exactly one from inventory only on a successful placement (`Player._build_step`, tested end-to-end against a real `Player`/`EarthChunkManager` in `test_player.gd`); Q on a placed structure returns one unit to the inventory (plain earth still gives nothing back). Placed campfire/furnace render with real dedicated procedural art (`ProceduralStructureSprite`: flame-on-embers / brick-block-with-firebox, each distinct from earth and each other, tested), not the flat earth-brown fill. Cooking/smelting now gate on real world proximity to a *placed* structure (`EarthChunkManager.has_structure_near`, `Player._has_campfire`/`_has_heat_source`, `HEAT_SOURCE_RADIUS_TILES = 3`) instead of merely carrying one in inventory — closing the gap an earlier doc comment flagged ("Carried, for now — placed heat sources come later"). Known gaps: only two structure types exist (no multi-tile blueprints yet, despite `building_blueprint.gd`'s pure footprint-checking logic already supporting them), and `has_structure_near`'s chunk-neighbor scan is exact only up to a `CHUNK_SIZE`-tile radius (documented limitation, comfortably beyond any realistic proximity check). | large |
| Dev/Admin Console | 🚧 Partial | Real dev console now exists: press backtick to toggle (`world.gd`'s `_bind_console_toggle_action`), type a `/command arg1 arg2` line into `DevConsole`'s `LineEdit` (`scenes/dev_console.gd`, parsed by the pure/tested `ConsoleCommandParser`). Implemented commands: `/day` (forces daytime lighting for the rest of the session), `/spawn <herbivore\|predator> [count]` (spawns creatures near the player via `CreatureRenderer.spawn_single`), `/give <item_id> [count]` (adds an item to the player's inventory via the new `ItemCatalog`), `/craft <recipe_id>` (calls `Player.craft()` against `CraftingRecipeBook`), `/gold <amount>` (adjusts the player's `Wallet` balance), `/help`. While the console has focus, `ConsoleFocus` (new autoload) suppresses the player's raw keyboard polling so typing "wasd" doesn't also move the character. No settings-tweak commands yet, and `/spawn`/`/give`-spawned entities aren't chunk-tracked (won't get cleaned up on chunk unload, unlike the world's own creatures). | medium |

### Phase 4 — Emergent quests

Goal per roadmap: replace "kill 10 boars" with need-driven requests. **Nothing
in this phase has been started** (depends entirely on Phase 2's NPCs).

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Need-Driven Quest Templates | ⬜ Not started | | large |
| LLM Quest Flavor Text | ⬜ Not started | | medium |
| Quest Reward/Consequence Hooks | ⬜ Not started | | small |

### Phase 5+ — Post-MVP expansion

Explicitly deferred by design until Phases 0–4 are solid. **Nothing in this
phase has been started**, with one notable scale-related caveat.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Multiplayer Netcode | 🚧 Partial (unverified live) | Server-authoritative architecture built: `--server`/client bootstrap in `world.gd` (ENet) plus an in-game **main-menu Host/Join flow** (`scenes/main_menu.gd` → `World._start_server`/`_start_client_to(address)`), dynamic per-peer `Player` spawning via `MultiplayerSpawner`, RPC input-up + `MultiplayerSynchronizer` position-down in `player.gd`, client-side visual-only proxies (facing/animation inferred from replicated position deltas + local deterministic terrain lookup, no extra network traffic). Follows standard Godot high-level multiplayer patterns. LAN/direct-IP join works via the menu; internet play needs a port-forward or an external tunnel (an ngrok-style built-in relay is not implemented — it would require a hosted relay server). **Live server↔client connectivity is unverified**: a minimal bare-ENet repro (no game code at all) also hangs on this dev machine, isolating the failure to CrowdStrike Falcon (confirmed running) blocking this specific unrecognized executable's networking — not a code bug (raw TCP and UDP loopback both work fine via a trusted process in the same environment). Needs either an EDR exception from IT or testing on an unmanaged machine/network to verify live. Known scope gaps even once verified: only tracks one player's position for chunk streaming (no multi-interest-point union yet), no client-side prediction/interpolation (positions will look choppy over real latency), no interest management/culling, no persistence of connections. | huge |
| Player Economy & Society | ⬜ Not started | | huge |
| Era Progression System | 🚧 Partial | `src/gameplay/era_progression.gd`: a tested, deterministic 4-era (medieval/industrial_revolution/ai_boom/space_exploration) progress-threshold state machine (`current_era`), plus `current_era_with_boss_defeat` letting a defeated world boss push the player one era ahead of progress alone (per `concept/worldbosses.md`'s "Era-gated bosses" section). Not wired to any live progress counter or world-boss event. | huge |
| Reincarnation Mechanic | ⬜ Not started | | large |
| Multi-Planet/Galaxy System | ⬜ Not started | | huge |
| Full-Planet-Scale World | 🚧 Partial (divergent path) | The roadmap describes reaching whole-Earth scale later by "reusing the same [procedural] worldgen systems" as a scaling exercise. In practice the project reached real-Earth scale (~40,000×20,000 tiles) much earlier and via a completely different mechanism — real bundled elevation/moisture data instead of procedurally expanding the Phase-0 heightmap. The scale goal is arguably met; none of Phase 1–4's gameplay exists on top of it yet. | huge |

---

## Unscheduled — not yet phased into the roadmap

The roadmap predates almost all of these concept docs. Each subsection below
covers one `docs/concept/*.md` file's full mechanism list. Status is honest:
the large majority are ⬜ not started, since the codebase currently has no
NPCs, combat, items, crafting, magic, DNA/genetics, economy, factions,
housing, pets, world bosses, PvP, festivals, death/respawn, survival needs,
weather beyond day/night tinting, transportation, exploration mechanics,
building, farming, cooking, fishing, or flora/vegetation simulation of any
kind. Where a mechanism does overlap with the real world-simulation
foundation, that overlap is called out explicitly.

### Ecosystem Dynamics (`concept/ecosystem_dynamics.md`)

The living-ecosystem phase, grounded in real ecological mechanisms and run at
two fidelities (individual agents near the player, aggregate catch-up for
chunks away from the player). See the concept doc for the full spec.

- **Fruit phenology (growing → ripe → fallen)** (medium) — ✅ Done — `src/world/fruiting_model.gd` (tested): each tree runs a repeating bearing cycle driven by its `TreeGenome` (crop size from `fruit_yield`) and local warmth (a growing-degree-day analogue — warmer trees ripen faster). Near the player (`EarthChunkManager.step_fruiting`, within a detail radius) a tree's current **ripe crop is rendered as individual pixel dots on its canopy** (`ProceduralTreeSprite.generate_image_with_fruit`) and abscised (fallen) fruit drops as ground items animals and the player can eat.
- **Frugivory (animals eat fallen fruit)** (small) — ✅ Done — herbivores/boars consume nearby fallen fruit (`FoodConsumption`, `World._step_herbivore_food_consumption`), gaining body condition. Seed dispersal (moved seeds germinating elsewhere) is a documented ⬜ future extension.
- **Condition-gated reproduction (bioenergetics)** (medium) — ✅ Done — `src/gameplay/animal_reproduction.gd` (tested): each creature carries an `energy` value that rises on eating and decays over time; a **healthy, well-fed** creature past a **birth cooldown** spawns an offspring of the same species beside it (`CreatureMarker.can_reproduce`/`on_reproduced`, `World._step_reproduction`), capped by `MAX_LIVE_CREATURES` (individual-scale density dependence + safety bound).
- **Variable-fidelity LOD / unloaded-chunk catch-up** (large) — ✅ Done — `src/world/chunk_ecology_catchup.gd` (tested, reuses the same logistic + predator-prey models as loaded chunks): a chunk records its aggregate ecology at unload; on revisit `EarthChunkManager._apply_ecology_catchup` integrates it forward over the elapsed unloaded time and installs the caught-up herbivore/predator populations (`EcosystemSimulation.seed_populations`) instead of resetting to fresh equilibrium — so a region the player left keeps evolving (herds grow or get thinned by predators). Closes the long-standing "regenerates at equilibrium on revisit" gap.
- **Seasonal forcing of phenology** (medium) — ⬜ Not started — warmth is instantaneous temperature, not a seasonal calendar variable.
- **Animal-mediated seed dispersal** (medium) — ⬜ Not started.

### Overview (`concept/overview.md`)

- **Mechanistic Planet Simulation** (huge) — 🚧 Partial — terrain/biome layer is real and data-driven; a Phase-1-MVP-scoped slice of plant-growth/animal-ecology emergence now exists (see Plant Growth Simulation and Animal Ecology below) but it's aggregate/per-loaded-chunk only, not the full always-on planetary simulation this pillar envisions.
- **Terrain Generation** (large) — ✅ Done — via real elevation data (`earth_elevation_source.gd`, `earth_chunk_generator.gd`); the old fully-procedural generator is kept for future non-Earth planets.
- **Biome System** (medium) — ✅ Done — `biome_classifier.gd`, 7 biomes.
- **Plant Growth Simulation** (large) — 🚧 Partial — static deterministic tree placement + collision exists (`tree_placement.gd`, `tree_renderer.gd`), unchanged; a real per-cell density growth/die-back/spread simulation now also exists (`vegetation_growth_model.gd`) but isn't unified with tree placement/rendering yet -- it currently only feeds herbivore carrying capacity.
- **Animal Ecology / Population Simulation** (large) — 🚧 Partial — regional/aggregate herbivore + predator population dynamics (reproduction, drought-driven death, migration) built and wired into live gameplay (`herbivore_population_model.gd`, `predator_population_model.gd`, `ecosystem_simulation.gd`), AND individual promoted creatures now have real per-agent AI (flee/hunt/graze/drink, temperament-driven, `creature_behavior.gd` et al. — see Phase 1 table's "Individual Creature AI" row). Still missing: taming, genetics, individual reproduction, and a link between individual predation and the aggregate population counts.
- **AI-Driven NPCs** (huge) — ⬜ Not started
- **NPC Memory Log** (large) — ⬜ Not started
- **NPC Daily Planning Loop** (large) — ⬜ Not started
- **LLM Backend Integration** (medium) — ⬜ Not started
- **Need-Driven Quest System** (large) — ⬜ Not started
- **Creature Collection System** (large) — ⬜ Not started
- **Sandbox Building System** (large) — ⬜ Not started
- **Persistent World State** (medium) — ⬜ Not started
- **MMO-Scale Social Systems** (huge) — ⬜ Not started
- **Multiplayer Netcode** (huge) — 🚧 Partial (unverified live) — server-authoritative ENet architecture built (see Phase 5+ table above for detail); live connectivity blocked on this dev machine by CrowdStrike Falcon, not a code issue.
- **Shared Player Economy** (huge) — ⬜ Not started
- **Player-Driven Society** (huge) — ⬜ Not started
- **PvP Combat Rules** (large) — ⬜ Not started
- **Emergent Physics Combat** (huge) — ⬜ Not started (explicit non-goal in the doc)
- **Era Progression / Reincarnation System** (huge) — ⬜ Not started
- **Death & Carryover Mechanic** (medium) — ⬜ Not started
- **Toroidal World Map** (medium) — ✅ Done — `world_coordinates.gd`, player wrap.
- **True Spherical Globe Rendering** (huge) — ⬜ Not started (explicit non-goal)
- **Plate Tectonics Simulation** (huge) — ⬜ Not started (explicit non-goal)
- **Climate / Fluid Weather Simulation** (huge) — ⬜ Not started (explicit non-goal; only real-time day/night tint exists)
- **Multi-Planet Travel** (huge) — ⬜ Not started
- **Procedural Planet Generation** (huge) — 🚧 Partial — old procedural whole-map generator intact/tested but not wired to any "other planet" gameplay.
- **Planet Rarity System** (medium) — ⬜ Not started
- **Monetization / Platform Distribution** (small) — ⬜ Not started

### Eras (`concept/eras.md`)

- **Technological Era Progression (World Eras)** (huge) — 🚧 Partial — `src/gameplay/era_progression.gd`: a linear 4-era progress-threshold state machine (`current_era`/`era_index`/`progress_to_next_era`), tested; scoped down from the doc's full multi-planet system per its own header comment. `current_era_with_boss_defeat` adds a defeated-world-boss trigger that advances one era beyond progress alone (see World Bosses' "Emergent World-Boss Promotion" row). Nothing in live gameplay tracks progress or calls either function yet.
- **Reincarnation / Era Advancement** (large) — ⬜ Not started
- **Permadeath / Death System** (medium) — 🚧 Partial — `src/gameplay/lives_tracker.gd` (nine-lives countdown + soul-stone revival) exists as a tested pure-logic module; not wired to the live respawn flow (see Phase 3 table's Player Stats row), which currently just resets health with no lives cost.
- **Cross-Era Carryover** (medium) — ⬜ Not started
- **Era State Scope (Per-Player vs Per-Server)** (large) — ⬜ Not started

### Planets (`concept/planets.md`)

- **Multi-system / multi-galaxy structure** (huge) — ⬜ Not started
- **Earth as shared starting planet** (medium) — ✅ Done — player spawns in Berlin at real lat/long on the real-Earth world.
- **Space exploration unlock (era gate)** (medium) — ⬜ Not started
- **Spacecraft construction** (large) — ⬜ Not started
- **Interplanetary travel** (huge) — ⬜ Not started
- **Procedural planet generation** (huge) — 🚧 Partial — old generator exists, unused.
- **Planet rarity tiers** (medium) — ⬜ Not started
- **Planet discovery / rarity reveal** (medium) — ⬜ Not started
- **Planet claiming (second home base)** (large) — ⬜ Not started
- **Primitive-by-default base restriction** (medium) — ⬜ Not started
- **Space logistics / technology import** (large) — ⬜ Not started
- **Post-MVP layer gating (design note)** (trivial) — n/a — a scoping note, not a buildable mechanism.

### Classes (`concept/classes.md`)

No skills/classes/leveling/stats/XP is wired into live gameplay yet, but a first pure-logic slice now exists as tested, unwired modules:

- **Soft Class System** (small) — ✅ Done (basic) — `src/gameplay/class_archetype.gd`: 7 archetypes (Warrior/Mage/Ranger/Beastmaster/Artisan/Herbalist/Overseer) with stat-lens functions, now **wired to character creation**: the main menu's New Game class picker (`scenes/main_menu.gd`) applies the chosen archetype's lens to the player (`Player.apply_class` — max-health + attack offsets). Plus a real XP/level system (`experience_track.gd`) earning levels from kills. Full skill-web pathing and respec UI still to come (see Progression / `concept/progression.md`).
- **DNA Resonance** (medium)
- **DNA Reroll (Premium)** (medium)
- **Free Respec** (small) — 🚧 Partial — `class_archetype.gd`'s `respec()` is a free no-cost archetype swap; not exposed to the player.
- **Archetype-as-Snapshot** (trivial) — 🚧 Partial — `class_archetype.gd`'s stat lens is a pure snapshot function with no persistent per-archetype state, matching this design exactly, just not wired to a live character.
- **Starting Archetype Lens** (medium)
- **NPC Need-Driven Quests** (huge)
- **Warrior: Melee/Tank Combat** (large)
- **Mage: Spellcrafting DSL** (huge)
- **Ranger: Ranged Combat** (medium)
- **Ranger: Wilderness Tracking** (medium)
- **Ranger: Vegetation Concealment** (medium)
- **Beastmaster: Taming/Breeding** (huge)
- **Beastmaster: Pet Combat** (large)
- **Artisan: Crafting/Building** (large)
- **Artisan: Resource Specialization** (small)
- **Herbalist: Medicine/Curing** (medium)
- **Herbalist: Buff/Support** (medium)
- **Overseer: NPC DSL Hiring/Instruction** (huge)
- **Overseer: Logistics/Economy** (huge)

### Players (`concept/players.md`)

No marriage/reproduction/child-rearing system exists. All ⬜ Not started:

- **Marriage System** (medium)
- **Player Reproduction / Child Conception** (medium)
- **DNA Inheritance (Genetic Cross)** (large)
- **Inheritance Mutation Chance** (trivial)
- **Breeding-for-Traits / Eugenics Strategy Layer** (small)
- **Birth Fast-Forward** (trivial)
- **Child Life Stage** (medium)
- **Child-as-Instructable-NPC (NPC DSL Integration)** (medium)
- **Sims-Style Needs System** (medium)
- **Wants/Fears (Wish) System** (medium)
- **Gradual Trait Solidification** (medium)
- **Runaway Consequence** (medium)
- **Child Death Consequence** (small)
- **Parental Grief Debuff** (small)
- **Growing Up / Graduation to Adult NPC** (medium)

### Skills (`concept/skills.md`)

No skill/passive system is wired into live gameplay yet, but a tested pure-logic foundation now exists:

- **Archetype Passive Skill Web** (large) — 🚧 Partial — `src/gameplay/skill_tree.gd` now wired to a real spend UI (`scenes/skill_tree_window.gd`, toggle K) fed by the XP/level system (see Progression / `concept/progression.md`); still a flat node list, no web/graph layout or archetype-specific branches yet.
- **Small Stat Nodes** (small) — ✅ Done (basic) — `skill_tree.gd` nodes are allocated in the skill-tree window and applied live to player stats (`Player.allocate_skill` → max-health/attack bonuses); stamina-regen bonus is tracked but not yet fed to the meter.
- **Keystone Passives** (medium) — ✅ Done (basic) — `keystone_passive.gd` keystones are unlockable in the window once their minimum-node gate is met and points are paid (`Player.unlock_keystone`), applying their bonus live.
- **Soft Cross-Archetype Pathing Gate** (medium) — ⬜ Not started — no cross-archetype gating logic exists, only same-archetype node-count gating.
- **DNA Resonance / Class Resonance** (large)
- **Web-to-Domain Unlock Hooks** (medium)
- **Signature Node (Procedural DNA-Seeded Spell)** (huge)
- **DNA-Flavored Shared Node Variants** (large)
- **Respec System (undecided)** (small)

### Crafting (`concept/crafting.md`)

A first crafting loop is now real and wired into live gameplay, though shallow:

- **Base gather-craft-build loop** (medium) — ✅ Done (basic) — `src/gameplay/crafting_recipe_book.gd` defines recipes (inputs → output), wired into `Player.craft()`; there's now a real **crafting UI** (`scenes/crafting_window.gd`, toggle C) listing every recipe with its output icon + input requirements, greyed out when unaffordable, click to craft — plus the `/craft` console command. `Player.craft()` produces the output into the inventory (and, if the inventory is full and consuming inputs didn't free a slot, drops the crafted item at the player's feet rather than silently losing it). The gather side is real too: chop trees (wood+sticks), smash boulders (rock), knap rock-on-rock (sharp shards), harvest tall grass (fibre), and mine ore-bearing boulders with a pickaxe (ore+stone). **Smelting/metalworking** now exists (`src/gameplay/smelting.gd`, tested, see `concept/smelting.md`): ore + coal smelted at a **heat source** (a carried campfire or crafted **furnace**) → iron/copper ingots, which forge a full **iron armor set** that out-protects leather — `Player.craft` heat-gates the smelt recipes exactly like cooking. No skill-gating or placed stations yet.
- **Crafting Stations** (small) — 🚧 Partial — `src/gameplay/crafting_station.gd` (tier-gated `can_craft_at`), tested but not wired — `/craft` currently works anywhere, no station placement/proximity check.
- **Skill-gated crafting progression** (medium)
- **Blueprint DSL** (large)
- **Base Item Templates** (trivial) — ✅ Done — `item.gd`/`item_catalog.gd` (now also includes torch/campfire/cooked_meat).
- **Material Inputs** (small) — ✅ Done — `crafting_recipe_book.gd` recipes consume a dictionary of item-id→count inputs.
- **Modifier Slots** (medium)
- **Deterministic crafting resolution** (small) — ✅ Done — no RNG in `crafting_recipe_book.gd`; a craft either has enough inputs or it doesn't.
- **Material quality feed from creature rarity** (medium)
- **Dual item-sourcing tracks (crafted vs. looted)** (large) — 🚧 Partial — both tracks now exist (loot drops + `/craft`) but aren't unified under one design (no shared rarity/affix system yet).
- **Station-tier gating of blueprint complexity** (medium) — 🚧 Partial — `crafting_station.gd`'s tier check exists; not wired to `/craft`.

### Resources (`concept/resources.md`)

Gathering now has a real primitive slice (rocks/shards/fibre/sticks — see the knapping chain in Phase 3's combat row); classic vein mining is still pure-logic-only:

A first primitive-resource loop is now real and wired into live gameplay:

- **Existence-Conditioned Placement Philosophy** (large) — 🚧 Partial — boulders place deterministically only on biomes that plausibly carry them (grassland/forest, never on a tree's own cell — `stone_placement.gd`); no ore/mineral placement yet.
- **Procedural Resource Placement** (large) — 🚧 Partial — same `stone_placement.gd` slice; stones only.
- **Dynamic Resource Distribution** (large)
- **Nonrenewable Mineral Depletion** (medium) — 🚧 Partial — `src/gameplay/mining_yield.gd` (depletion-toward-zero math) still unwired; the live mining loop instead uses `src/gameplay/ore_yield.gd` (per-strike drop table) on one-shot **ore nodes** — `src/world/ore_placement.gd` marks ~30% of boulders as ore-bearing (iron/copper/coal), rendered via `src/rendering/procedural_ore_sprite.gd` and spawned by `StoneRenderer` as `MinableOre`. Mining a node consumes it (nonrenewable per node) but there's no vein-scale pool depletion yet.
- **Vein Migration & Regeneration** (large)
- **Renewable Organic Resource Growth** (medium)
- **Plant-Growth Model (world.md)** (large)
- **World-Sim Timescale** (huge)
- **Mining Action** (medium) — ✅ Done (basic) — a swing that reaches an ore node (`MinableOre`, shares the "stone" group) mines it: with a `stone_pickaxe` equipped (`Item.is_pickaxe()`, `Player._pickaxe_power`) it drops ore + stone (`OreYield`), bare-handed only stone. Craft the pickaxe from 2 stick + 3 rock.
- **Crafting Blueprint DSL Material Integration** (medium)
- **Crafting Blueprint DSL (crafting.md)** (huge)
- **DNA-Quality-to-Material-Quality Link** (large)
- **Creature DNA/Genetics System** (huge)
- **Resource Discovery / Prospecting (open design question)** (medium)
- **Surface Ore Hints & Biome Correlation** (medium)
- **Dedicated Prospecting Tools/Skills** (medium)
- **Regeneration Timescale Tuning (open design question)** (small)

### Items (`concept/items.md`)

A basic item/inventory/loot foundation now exists (typed items, stacking
inventory, loot drops, weapon damage, procedural item sprites, clickable
ground items) but none of the *rarity/affix/crafting* depth this doc
describes:

- **Rarity/Affix Tier System** (medium) — ⬜ Not started — items are fixed definitions (`item.gd`), no rolled affixes or rarity.
- **Found/Looted Gear Generation** (medium) — 🚧 Partial — creatures drop deterministic loot (`loot_table.gd`) as clickable ground items (`dropped_item.gd`); no randomized/rarity generation, and drops are materials/food/weapons, not multi-slot gear.
- **Crafted Gear (Blueprint DSL)** (large) — ⬜ Not started
- **Shared Rarity/Stat Pool Consistency** (small) — ⬜ Not started
- **Spells as Items (Spell Gems)** (large) — ⬜ Not started — no "spell"/"spell_gem" item kind exists yet, and `item.gd` has no sealed/forkable/use-only flag (`docs/concept/magic.md`'s "sealed IP" decision needs both, and neither is built).
- **Spell Gem Rarity Derivation** (medium) — 🚧 Partial — `rarity_tier.gd`'s
  `tier_from_complexity(complexity)` derives a tier straight from a numeric
  complexity/cost score (e.g. `spell_cost.gd`'s `derived_base()`), reusing the
  same tier vocabulary as `roll_tier()`'s random loot roll. Pure, tested,
  monotonic. Not yet called from anywhere that actually mints a spell gem
  (that needs the item-kind/sealed-flag work above first).
- **Spell Gem Trading Category** (small) — ⬜ Not started
- **Affix Pool Segmentation by Category** (medium) — ⬜ Not started
- **Equipment Slot / Itemization Power Balance** (large) — 🚧 Partial — a real **equipment system** now exists (`src/gameplay/equipment.gd`, tested): head/chest/legs/feet/weapon slots, `Item` carries `equip_slot` + `armor`, and worn armor reduces incoming damage (`Player.take_damage` subtracts `Equipment.total_armor()`, min 1). Wearable **leather armor** (helm/chest/legs/boots) is in the catalog with its own pixel art, and the revamped inventory screen (see UI section) is a **grid + equipment paperdoll**: click an item to wear/equip it, click a worn slot to unequip. Still missing: affix/rarity rolls, set bonuses, and full itemization balance.

Supporting systems now built (tested): `inventory.gd` (fixed-slot stacking
inventory), `item.gd`/`item_stack.gd` (typed items — "weapon"/"tool"/
"material"/"food" kinds), `loot_table.gd`, `dropped_item.gd` (clickable/
auto-pickup ground items), `procedural_item_sprite.gd` (offline pixel-art for
items, including sword/axe shapes). Trees also drop fruit/nuts as ground
forage over time — dropped centrally and throttled by
`EarthChunkManager.step_forage` via `forage_scheduler.gd` (trees themselves
run no per-frame script; an earlier per-tree approach tanked the frame rate
since thousands of trees load at once), and can be felled with the starting
axe for wood (`ChoppableTree`). Ground items despawn after a lifetime and are
capped in number; creature AI sensing is throttled/cached (`SENSE_INTERVAL`)
so per-frame cost stays low with many creatures loaded.

**Procedural pixel art** is now used consistently across every rendered
entity, all offline/deterministic/seed-based (no external image-gen
API/network/cost, same shaded-and-outlined technique everywhere):
`procedural_item_sprite.gd` (items/weapons/tools), `procedural_sprite_generator.gd`
(creatures), `procedural_character_sprite.gd` (player body/head/limbs), and
`procedural_tree_sprite.gd` (tree canopy+trunk, tinted by the tree's own
`TreeGenome.species_bias`). An **art-direction pass** (`src/rendering/pixel_palette.gd`,
tested) pushed the whole look toward a brighter, more saturated Legend-of-Zelda /
Pokémon-overworld palette with chunkier near-black outlines and a top-left
highlight (Hammerwatch readability): terrain `BASE_COLORS` are now vivid
route-style greens/blues, and the item/creature/character/tree/stone/ore
generators route their base colors + shading through the shared palette helper.
Known gaps: none of the item/creature/combat layer is replicated in multiplayer
(play single-player for a coherent loop).

### Magic (`concept/magic.md`)

The cost/atom foundation of the spellcrafting DSL has been started (pure,
tested modules); everything above the cost layer (parser, validator, runtime,
authoring UI, physics compliance) is still unbuilt. The 2026-07-15 brainstorm
extensions (atom domains beyond the physical, material-component cost,
caster self-danger, complexity-priced spell gems) now have a pure/tested
foundation too, but none of it is wired into runtime casting yet — see the
new rows below.

- **Spellcrafting DSL** (huge) — 🚧 Partial — first three of the pure
  `RefCounted` pipeline modules exist and are test-first: `spell_atom_catalog.gd`,
  `spell_cost.gd`, and `spell_parser.gd` (player text → canonical AST, pipeline +
  blocks surface syntax, with human-readable parse errors). No validator/runtime/
  UI yet; the parser is purely structural (does not check atoms against the
  catalog — that is the validator's job).
- **Primitive Effects Catalog** (large) — 🚧 Partial — `spell_atom_catalog.gd`:
  25 atoms across 10 categories and 3 tiers, each with cost-relevant data (base
  cost, magnitude/duration scaling refs). Pure lookup, tested. Beyond the
  original 15 damage/heal/control/movement/defense/summon/utility atoms, it now
  covers the brainstorm's three non-physical domains too:
  **biological** (`accelerate_growth`, `induce_mutation`, `suppress_mutation`,
  `blight`), **perceptual** (`illuminate`, `calm`, `fear`), and **spatial**
  (`teleport`, `portal`, `gravity_shift`) — vocabulary-level only, with no hook
  yet into `dna.md`'s genome/mutation systems, `creature_behavior.gd`/taming, or
  `fast_travel.gd`/waypoints. Not yet wired into any runtime.
- **Delivery Method System** (medium) — 🚧 Partial — delivery-method cost
  *multipliers* (self/touch/projectile/area) exist in `spell_cost.gd`; actual
  delivery (projectile travel, area resolution) is unbuilt.
- **Shape Modifier System** (medium) — ⬜ Not started
- **Elemental Reaction Matrix** (large) — ⬜ Not started
- **Resource Cost Formula** (medium) — 🚧 Partial — `spell_cost.gd` derives cost
  deterministically from atoms + params (magnitude, duration, burst radius) and
  delivery, with a stat-driven efficiency term that discounts what the caster
  *pays* without changing the derived power price. Property-tested. Not wired
  into gameplay (no mana pool spends it yet).
- **Diminishing Returns Curve** (small) — 🚧 Partial — superlinear magnitude
  exponent (`MAG_EXP`) plus a repeated-atom spam penalty in `spell_cost.gd`,
  both pinned by property tests so the constants are a tested function, not
  eyeballed.
- **Material-Component Cost** (medium) — 🚧 Partial — a third cost axis
  (`spell_cost.gd`'s `material_cost()`, folded into `breakdown()`): materials
  are declared per-atom under a `"materials"` params key (material_id →
  quantity), the same way magnitude/duration/radius already are, and summed
  across the whole composition. Pure and tested. Not wired to `inventory.gd`/
  `item_catalog.gd` — nothing actually deducts a fire gem or frost hide yet,
  and there's no per-atom *requirement* data (a caster can currently declare
  any material for any atom).
- **Caster Self-Danger** (small) — 🚧 Partial — `spell_cost.gd`'s
  `does_affect_caster(delivery, radius, caster_distance_from_effect)` is a
  small pure predicate: `"self"` delivery always affects the caster by design,
  any other delivery blows back only if the caster's standoff distance falls
  within the effect's own radius. Property-tested. Not wired into live combat
  resolution — nothing calls it during an actual cast yet.
- **Physical Simulation Compliance** (large) — ⬜ Not started
- **Projectile Travel & Interception** (medium)
- **Area/Summon Spatial Validity** (medium)
- **Mass-Based Push/Pull Knockback** (small)
- **Environmental Fire Spread (Ignite)** (medium)
- **Freeze-to-Walkable Terrain** (medium)
- **Shock Conduction Through Water** (medium)
- **Skill-Tree Gating (Layer 0)** (medium)
- **Spell Editor / Authoring Tool** (huge)
- **Spell Crystallization (Tradeable Spells)** (medium)
- **Master Tier: Freeform Node-Graph Authoring** (huge) — ⬜ Not started

### Economy (`concept/economy.md`)

A first real currency now exists and is wired into live gameplay; everything else in this doc remains unbuilt:

- **Regular Currency System** (medium) — 🚧 Partial — `src/gameplay/wallet.gd` (`Wallet`): a real gold balance on the player, shown in the HUD (`world.gd`'s `_wallet_label`) and adjustable via the dev console's `/gold <amount>` command, now also spendable at a village merchant (see below). Still no way to actually earn gold through play (no quest rewards, no selling anything) — a functioning ledger with a real sink now, but no faucet beyond the debug command.
- **Premium Currency System** (large) — ⬜ Not started
- **Market (NPC & Player Selling)** (large) — 🚧 Partial — `src/gameplay/shop.gd`: buying from a village merchant NPC now works (see NPC section's "Basic Merchant Shopping"), spending the real `Wallet` above. Fixed shared catalog/pricing (not per-NPC), no shop browsing UI, and no selling the player's own goods yet.
- **Crafting System (external)** (large)
- **Resource Gathering System (external)** (medium)
- **Taming/Breeding System (external)** (huge)
- **Quest/Bounty Reward System** (large)
- **NPC Hiring System (wages)** (large)
- **Player-to-Player Trading** (medium)
- **DNA Reroll Purchase** (small)
- **Extra Lives/Soul Stone Purchase** (small)
- **Cosmetics Purchase** (medium)
- **Convenience Purchases (storage/travel)** (small)
- **Premium/Regular Currency Exchange (open design question)** (large)
- **Wage/Price Balancing (open design question)** (small)

### Weather (`concept/weather.md`)

Only real-time day/night lighting is wired into live rendering; a first deterministic weather model now exists as tested pure logic but isn't wired into the game world yet:

- **Dynamic Weather System** (large) — 🚧 Partial — `src/world/weather_model.gd` (deterministic clear/cloudy/rain/storm per region+time) is now **wired with mechanical teeth**: `EarthChunkManager.current_weather` derives the player-region weather (shown in the HUD "Season · Weather"); rain/storm **slow the player** (`weather_speed_modifier` → `Player._weather_speed_multiplier`), and wet/cold weather feeds the new **body-temperature exposure** system (see Survival). Water is now the one visibly weather-reactive surface: `weather_model.wind_strength_for` (calm on clear days, most energetic in a storm) drives `WaterShader`'s `wind_strength` uniform via `EarthChunkManager.set_wind_strength`, pacing the GPU ambient wave scroll rate to match, alongside the existing rain-ripple tie-in. Still missing: visual rain/storm particles/tint over land, combat fire-dousing, and disaster events (drought/flood/wildfire).
- **Weather Exposure Debuff** (small) — ✅ Done — cold/wet weather chills the player's warmth meter; while cold, condition (fitness) degrades faster and, while freezing, movement is slowed further (`SurvivalMeters` warmth + `Player._weather_speed_multiplier`). See Survival section.
- **Seasons (calendar cycle)** (medium) — ✅ Done — `src/world/season_cycle.gd` (tested, see `concept/seasons.md`): a deterministic spring→summer→autumn→winter year with smooth warmth/growth modifiers. Wired into fruit phenology (`EarthChunkManager._warmth_at_pixel` scales `FruitingModel` warmth by season, so trees fruit fast in summer / slowly in winter) and shown in the HUD. Not yet driving vegetation/tall-grass growth rate or farming crop viability.
- **Regional Weather Variety** (medium) — 🚧 Partial — `weather_model.gd` takes a `region_seed` parameter so different regions roll independently; not wired to any real per-chunk region concept yet.
- **Disaster Events** (large)
- **Drought Carrying-Capacity Penalty** (medium)
- **Flood Terrain Reshaping** (large)
- **Wildfire Vegetation Clear & Migration Trigger** (large)
- **Player-Triggered Wildfire** (medium)
- **Weather Exposure Debuff** (small)
- **Rain Douses Fire/Oil Combat Effects** (small)
- **Fog Line-of-Sight Reduction** (small)
- **Snow/Mud Movement Slow** (small)
- **Seasonal Crop Viability** (medium)
- **Farm Disaster Risk** (medium)
- **Disaster Forecast/Warning (open question)** (small)

### World Bosses (`concept/worldbosses.md`)

No live world-boss/creature-fitness simulation exists yet, but the promotion math and the phase-generation abstraction are now real, tested, pure logic:

- **Emergent World-Boss Promotion** (large) — 🚧 Partial — `src/gameplay/world_boss_fitness.gd`'s `attempt_promotion(individual_id, species, score, trait_description, phase_generator)` turns a passing fitness-threshold check into a named boss record (`{individual_id, species, score, threshold, phases}`); the generator side is abstracted behind a `PhaseGenerator` base class plus a deterministic `FakePhaseGenerator` (canned two-threshold phase list, no real LLM call — per `concept/worldbosses.md`'s "one offline LLM call at promotion time" design and `roadmap.md`'s stubbed-LLM testing convention). Tested; not wired to any live creature population.
- **Fitness-Threshold Promotion Math** (medium) — 🚧 Partial — `src/gameplay/world_boss_fitness.gd`: deterministic fitness scoring + a per-species promotion threshold check, tested; now feeds `attempt_promotion` above, still not wired to any live creature population (no actual world-boss promotion happens in the running game).
- **Unique Naming & Identity** (small)
- **Per-World Uniqueness** (trivial)
- **World Boss Combat Encounter** (medium)
- **Best-in-Slot Loot Drop** (small)
- **High-Risk World Boss Taming** (medium)
- **Population Impact of Killing (Outlier Removal)** (small)
- **Population Impact of Taming (Outlier Retained)** (small)
- **World Boss Discovery/Signaling (open question)** (medium)
- **World Boss Special AI/Behavior (open question)** (large)

### Evolution (`concept/evolution.md`)

No DNA/genetics/evolution simulation exists. All ⬜ Not started:

- **Evolutionary Population System (DNA/Reproduction/Selection)** (large)
- **Resource-Constrained Reproduction** (medium)
- **Genetic Phenotype Generation** (medium) — 🚧 Partial — `src/world/animal_fitness.gd`'s `phenotype_for` derives a deterministic phenotype from a seed; not wired to any live creature's actual rendered appearance (creature color still comes from species, not individual DNA).
- **Attractive Phenotype Target** (large)
- **Mate-Attractiveness Scoring** (small) — 🚧 Partial — `animal_fitness.gd`'s `mate_attractiveness`, tested; no reproduction/mate-selection system consumes it.
- **Emergent Rarity from Population Dynamics** (medium)
- **Player-Facing Rarity/Shiny Payoff** (small)
- **DNA-Driven Fitness Attributes** (medium) — 🚧 Partial — `animal_fitness.gd`'s `fitness_score`, tested; not linked to the aggregate population model or individual creature promotion yet.
- **Pet Fitness Carryover** (medium)
- **World Boss Outlier Trigger** (large)
- **Aquatic DNA/Fitness Model (Fishing)** (medium)
- **Crop DNA/Fitness Model (Farming)** (medium)
- **Ecosystem Simulation (Resource Constraints)** (huge)
- **DNA/Genetics System** (large)

### Combat (`concept/combat.md`)

A first, minimal real-time combat loop now exists (see Phase 3 table above);
most of this doc's scope (classes, skills, PvP, weather/elevation effects) is
still unbuilt:

- **Core Real-Time Combat Loop** (medium) — 🚧 Partial — a cooldown-based AOE melee swing exists, real-animated (`weapon_swing.gd`), and is now two-directional (aggressive/healthy predators attack back, weak ones flee — see Phase 1's Individual Creature AI). Each creature has a health bar and a hover/on-hit info panel (name/level/stamina/mana).
- **Fast Movement** (trivial) — ✅ Done — pre-existing player movement, unrelated to combat specifically.
- **Cooldown-Based Ability System** (small) — 🚧 Partial — the one attack has a cooldown; no ability variety. A separate axe-driven tree-felling action (`equipped_tool`) exists on the same input, gated by tool type rather than a cooldown/ability slot.
- **Dodge/Dash Mechanic** (small) — 🚧 Partial — `src/gameplay/dodge.gd`: cooldown + invulnerability-window math, tested; not wired to any player input.
- **Positional/Tactical Spacing** (trivial) — ⬜ Not started
- **Co-op Multiplayer** (huge) — ⬜ Not started
- **Knockback** (small) — ✅ Done — smooth ease-out shove (`Knockback.step`), Hammerwatch-style, not a teleport. See Phase 3 table above.
- **Environmental Hazards** (medium) — ⬜ Not started
- **Knockback-into-Hazard Interaction** (small) — ⬜ Not started — no hazards exist yet to knock anything into.
- **Spreadable Environmental Effects** (large) — ⬜ Not started
- **Layered Tilemap Elevation** (medium) — ⬜ Not started
- **Height Advantage** (small) — ⬜ Not started
- **Line-of-Sight Blocking (Elevation)** (medium) — ⬜ Not started
- **Vegetation-Based Concealment** (large) — ⬜ Not started
- **Biome-Dependent Combat Variation** (medium) — ⬜ Not started
- **Weather Effects on Combat** (large) — ⬜ Not started
- **Throwables** (medium) — 🚧 Partial — `src/gameplay/throwable.gd`: trajectory/impact math, tested; no actual throwable item or player action exists.
- **Weight-Based Physics Interactions** (medium) — 🚧 Partial — `throwable.gd`'s `impact_knockback` covers one slice (mass-scaled knockback on impact); no broader weight/physics system.
- **Stat System** (medium) — 🚧 Partial — player health only; no broader stats.
- **Skill System** (large) — ⬜ Not started
- **Class System** (large) — ⬜ Not started
- **Equipment/Item System** (large) — ⬜ Not started
- **PvP** (medium) — ⬜ Not started
- **PvE** (small) — ✅ Done — player-vs-creature combat exists, however minimal.

### Materials (`concept/materials.md`)

A design-direction doc (2026-07-15 brainstorm) proposing that item stats and
combat outcomes *emerge* from a shared material property vector + contact
geometry, replacing per-(weapon, material) authored lookup tables. A first
pure-logic slice of that model now exists (tested), independent of and not
yet wired into the live, still-lookup-table-shaped `material_damage.gd`/
`block.gd` combat path:

- **Material Property Vector** (medium) — 🚧 Partial — `src/gameplay/material_properties.gd`: a fixed "mineral track" vector (density/hardness/toughness/elasticity/sharpness_capacity/flammability/conductivity/decay_rate) for six named materials (wood/flesh/stone/iron/obsidian/fiber), tested, with unknown-material/unknown-property defaults. Only the doc's mineral track exists; the DNA-driven organic track (see dna.md/evolution.md) is unbuilt, and nothing in live gameplay reads this vector yet — `material_damage.gd`'s per-(weapon_kind, material)-string lookup table remains what `scenes/player.gd` actually calls.
- **Impact Resolution (Momentum × Geometry × Material → Outcome)** (large) — 🚧 Partial — `src/gameplay/impact_resolver.gd`'s `resolve_impact()` (tested, calibration-pinned `T_CUT`/`T_PIERCE`/`T_CRUSH`/`T_BRITTLE_TOUGHNESS`/`PIERCE_HARDNESS_CAP` thresholds — the doc's own Open Questions section flags exactly these as needing calibration tests) returns cut/dent/crush/pierce/shatter/bounce from momentum + contact geometry (edge/point/blunt) + the target material's hardness/toughness. Not wired into any live combat, tree-felling, or mining path, and doesn't yet cover the doc's shape-assembly mechanics (leverage/edge+backing/balance) that would compute momentum and geometry from an actual item.
- **Two-Track Organic vs. Mineral Materials** (large) — ⬜ Not started — no DNA-driven variable material track exists; every entry in `material_properties.gd` is a fixed mineral-style vector.
- **Shape & Assembly (Leverage, Edge+Backing, Balance)** (large) — ⬜ Not started — no part-graph/geometry-composition model exists; `impact_resolver.gd` takes momentum and contact geometry as direct inputs rather than deriving them from assembled parts.
- **Physical Interaction Verbs (Shove/Throw/Topple/Drop)** (large) — 🚧 Partial — throw exists narrowly (`throwable.gd`, see Combat section's Throwables row); shove/topple/drop-as-momentum are unmodeled, and none of the four route through `impact_resolver.gd`.
- **Reactive Surfaces (Elemental Reaction Matrix on the Floor)** (large) — ⬜ Not started — see Magic section's Elemental Reaction Matrix row.
- **Physical Honesty (Item Wear/Chip/Fracture Over Time)** (medium) — ⬜ Not started — no durability/wear state exists on any item.
- **Traversal-Tool Material Viability (Raft Buoyancy / Rope Tensile Strength)** (small) — ✅ Done (basic) — `material_properties.gd`'s `is_viable_for_tool()`, tested: density-gated for `raft`, toughness-gated (standing in for tensile strength — see the doc's transportation.md cross-reference) for `grapple_rope`. No raft/rope items or transportation.md wiring exist yet to consume it — see Transportation section.

### Housing (`concept/housing.md`)

No housing/decoration system is wired into live gameplay, but its scoring math now exists as tested pure logic:

- **Placeable Furniture/Decor Placement** (medium)
- **Coziness/Appeal Score** (medium) — 🚧 Partial — `src/gameplay/coziness_score.gd`: deterministic score from placed-decor data, tested; no actual furniture placement system to feed it real data.
- **Thematic Coherence / Set Bonus** (small) — 🚧 Partial — `coziness_score.gd`'s coherence bonus term, tested; same caveat as above.
- **NPC Home Visit Scheduling** (large)
- **NPC Opinion Formation on Homes** (medium)
- **NPC Relationship/Memory Log-and-Recall System** (huge)
- **Multiplayer Home Visiting & Rating** (huge)
- **Appeal Score Transparency Design** (small)
- **Decor-Linked Sleep Quality Bonus** (small)
- **Decor-Linked NPC Hiring Willingness** (small)

### Factions (`concept/factions.md`)

No faction/reputation system exists. All ⬜ Not started:

- **Emergent settlement reputation** (medium)
- **NPC relationship & memory system** (large)
- **Reputation aggregation function** (small) — 🚧 Partial — `src/gameplay/faction_reputation.gd`: deterministic aggregation math, tested; no actual factions/settlements/NPCs exist yet to apply it to.
- **NPC social-influence weighting** (medium)
- **Reputation-gated hiring difficulty** (small)
- **Reputation-skewed quest offers** (small)
- **Reputation-based price softening** (small)
- **Settlement reputation summary (legibility layer)** (small)
- **Settlement identity** (trivial)
- **Player-formed factions (guilds/settlements)** (huge)
- **Player-faction-to-settlement standing** (medium)
- **Cross-settlement reputation propagation (open question)** (large)

### Exploration (`concept/exploration.md`)

No exploration-specific mechanics (map/POIs/fog-of-war/waypoints) exist beyond raw walking. All ⬜ Not started:

- **History-Seeded POI System** (large)
- **Abandoned Settlements** (medium)
- **Monster Lairs** (medium)
- **Causal Procedural Weighting** (large)
- **Historical Event Logging / Discoverable Fragments** (large)
- **POI Loot Rarity Integration** (small) — 🚧 Partial — `src/gameplay/poi_loot_scaling.gd`: deterministic rarity-scaling-by-POI-tier math, tested; no actual POIs exist in the world yet to attach it to.
- **World-Scale POI Density Scaling (open question)** (small)

### Transportation (`concept/transportation.md`)

- **Toroidal, Water-Heavy World** (huge) — 🚧 Partial — the world is genuinely toroidal (`world_coordinates.gd`) and genuinely water-heavy (real Earth oceans/lakes from real elevation data), but this is the terrain substrate only, not a transportation mechanic.
- **Boats** (large) — ⬜ Not started
- **Fast Travel System** (large) — 🚧 Partial — `src/gameplay/fast_travel.gd` (cost/cooldown math + living-creature cargo restriction) + `src/gameplay/waypoint_network.gd` (unlock tracking), both tested; no player-triggered travel action, no map UI, nothing actually moves the player yet.
- **Horses (Land Mount)** (trivial) — ⬜ Not started
- **Waypoint Network (fast-travel option A)** (medium) — 🚧 Partial — see `waypoint_network.gd` above.
- **Personal Portal Item (fast-travel option B)** (medium) — ⬜ Not started
- **Fast-Travel Cost/Limitation Mechanic** (small) — 🚧 Partial — resolved per `concept/transportation.md` ("Fast travel: free for cargo, never for living stock"): `fast_travel.gd`'s cost/cooldown math is unchanged and untaxed for cargo, plus a new `can_fast_travel_with_cargo(cargo)` that allows any inanimate load but blocks the whole trip if it contains even one living creature. Tested; not yet wired to a live travel action.
- **Boat/Weather Interaction (storm risk, open question)** (medium) — ⬜ Not started

### Building (`concept/building.md`)

- **Tile placement/destruction (building system)** (medium) — ✅ Done — see Phase 3 table above; one live placeable tile type, persisted across unload/reload. Rendering for two more (`campfire`, `furnace`) is ready (`TerrainRenderer`/`ProceduralStructureSprite`) but not yet wired to a live placement action.
- **House/base construction** (small) — 🚧 Partial — `src/gameplay/building_blueprint.gd`: multi-tile footprint validation (fits/overlaps), tested; the live build system (Phase 3 table) still only places single wall/earth tiles, not connected to this blueprint validator.
- **Terrain digging** (medium) — ⬜ Not started
- **Chunked world persistence** (large) — 🚧 Partial — modifications-only persistence is now wired into live gameplay (`ChunkSerializer.save_modifications`/`load_modifications` via `EarthChunkManager`); the original full-chunk `save_chunk`/`load_chunk` methods remain tested but still unused (terrain itself is deterministically regenerated, not saved).
- **Housing decoration layer** (medium) — ⬜ Not started
- **MMO-driven villages** (huge) — ⬜ Not started
- **Player-influenced economy** (huge) — ⬜ Not started
- **Player-driven society** (huge) — ⬜ Not started

### Pets (`concept/pets.md`)

No pets/taming system is wired into live gameplay, but two of its core math pieces now exist as tested pure logic:

- **Taming System** (medium) — 🚧 Partial — `src/gameplay/taming_system.gd`: deterministic tame-chance/success roll, tested; no player action or creature-side state to apply it to.
- **Pet Accompaniment (Follow AI)** (medium)
- **Species-Fixed Role System** (small)
- **DNA/Fitness-Driven Performance** (large)
- **Unified Fitness Dimension (Ecosystem ↔ Taming value)** (trivial)
- **Guard Dog Behavior** (medium)
- **Combat Pet System** (large)
- **Mount System (Horses)** (large)
- **Decorative Pet Behavior (Birds)** (small)
- **Farm Animal Resource Production** (medium)
- **Beastmaster Class Archetype** (large)
- **Breeding System** (large)
- **Bonding/Loyalty Mechanic (proposed, open question)** (medium) — 🚧 Partial — `src/gameplay/pet_loyalty.gd`: loyalty accrual/decay math, tested; no actual tamed pets exist yet to carry this state.
- **Species-to-Role & Fitness-to-Metric Mapping Table (design task)** (trivial)

### Cooking (`concept/cooking.md`)

No cooking system is wired into live gameplay, but its recipe math now exists as tested pure logic:

- **Cooking System (core loop)** (medium) — 🚧 Partial — a live single-item heat transform now exists: `src/gameplay/campfire_cooking.gd` (meat→cooked_meat, fish→cooked_fish) is wired into `Player._use_food` — clicking/using a raw cookable food while carrying a **campfire** item (craftable from 8 wood) cooks it instead of eating it raw. The richer multi-ingredient `cooking_recipe_book.gd` dish system is still unwired, and the campfire is a carried "portable heat source" rather than a placed world object yet.
- **Dish Buffs** (medium) — 🚧 Partial — `cooking_recipe_book.gd` models buff type/duration/**category** data per dish (sustenance/combat/resistance), and `food_consumption.gd`'s `apply_food_buff`/`buff_in_category`/`advance_food_buffs` track a player's active food buffs as fixed per-category slots. **Now live for one trigger**: eating a rare/legendary fish catch (`FoodConsumption.FISH_BUFFS`, `Player.eat_food`/`_food_buff_step`) grants a real timed buff — extra stamina regen (sustenance) or +30% melee damage (combat), see `Player._damage_buff_multiplier`. The multi-ingredient `cooking_recipe_book.gd` dish path is still unwired — eating a cooked dish (as opposed to a raw rare fish) doesn't grant its buff in practice yet.
- **Ingredient Quality Propagation** (medium)
- **Recipe Discovery/Composition (Blueprint-DSL reuse)** (large)
- **Buff Stacking/Duration Rules (open question)** (medium) — 🚧 Partial — resolved by the 2026-07-16 brainstorm in `concept/cooking.md` ("Buff slots: fixed, and typed by category") and implemented as pure logic: `food_consumption.gd`'s `apply_food_buff` replaces same-category entries instead of stacking, `advance_food_buffs` ticks down and expires them, tested. Live and exercised by the rare-fish buff trigger above; the cooking-recipe dish path still doesn't call it.
- **Recipe/Buff-Type Space Sizing (open question)** (small)
- **Class Specialization Hook (Herbalist/Artisan)** (small)
- **Festival/Visitor Food Hook** (small)

### PvP (`concept/pvp.md`)

No PvP system exists. All ⬜ Not started:

- **Zone-Based PvP Risk Escalation** (medium)
- **Permadeath** (large)
- **Soul-Stone Life Stakes** (medium)
- **Consensual/Flagged PvP** (medium) — 🚧 Partial — `src/gameplay/duel.gd`: duel request/accept state machine + zone-flagging check (`is_pvp_allowed_in_zone`), tested; no actual PvP damage path or UI exists to use it.
- **Dueling** (small) — 🚧 Partial — same `duel.gd` module.
- **Flagged Contested Zones** (small)
- **Guild-War Declarations** (medium)
- **Full-Loot Open-World PvP** (large)
- **World Bosses** (large)
- **Top-Tier Resource Placement** (medium)
- **Resurrection by Nearby Player** (medium)
- **Biome/Danger Gradient** (large)
- **Character Power Gating** (medium)
- **World-Sim** (huge)
- **Era/Space-Travel Endgame** (huge)
- **Zone Boundary Definition (open question)** (small)

### Festivals (`concept/festivals.md`)

No festival system exists. All ⬜ Not started:

- **Emergent Festival Trigger System** (large)
- **Harvest Festival Trigger** (small) — 🚧 Partial — `src/gameplay/festival_trigger.gd`'s `harvest_festival_eligible`, tested; no actual harvest/season data feeds it live.
- **Solstice/Seasonal Festival Trigger** (small) — 🚧 Partial — `festival_trigger.gd`'s `seasonal_festival_for_day`, tested; not wired to the real solar/day clock (`solar_position.gd`).
- **Anniversary/Commemoration Festival Trigger** (medium)
- **Village History/Event Log** (medium)
- **NPC Festival Replanning** (medium)
- **Festival Schedule Entries (Stalls, Performances, Shared Meals)** (medium)
- **Player Festival Activities** (medium)
- **Festival Reputation Boost** (small)
- **Festival Trigger Threshold Calibration (open question)** (small)
- **Cross-Settlement Festivals** (large)

### DNA (`concept/dna.md`)

No DNA/genetics system exists. All ⬜ Not started:

- **DNA System (Core Generator)** (large)
- **NPC DNA Generation** (small)
- **DNA Trait Rarity Tiers** (small)
- **Class Resonance Score** (medium)
- **Free Character Reroll** (small)
- **Premium Reroll Purchase** (medium)
- **DNA Inheritance (Genetic Crossover)** (large) — 🚧 Partial — `src/gameplay/dna_crossover.gd`: generic two-parent trait crossover, tested; not species-specific and not wired to any player/pet/creature reproduction flow.
- **Inheritance Mutation Chance** (small) — 🚧 Partial — `dna_crossover.gd`'s bounded mutation nudge, tested; same wiring caveat.
- **DNA-Driven Phenotype/Body Generation** (huge)
- **Cosmetic Customization Layer** (medium)

### Death (`concept/death.md`)

A real (if simple) death/respawn loop now exists and is wired into live gameplay (see Phase 3 table's Player Death & Respawn row); the lives/permadeath/graveyard layer this doc describes on top of that is still pure-logic-only or unbuilt:

- **Nine Lives Permadeath** (medium) — 🚧 Partial — `src/gameplay/lives_tracker.gd`: countdown-of-lives + revival math, tested; the live respawn flow (`Player._respawn()`) doesn't consult it yet — dying currently costs nothing.
- **Soul Stones (Extra Life Item)** (small) — 🚧 Partial — `lives_tracker.gd`'s `add_life`, tested; no actual soul-stone item exists.
- **Premium Currency Soul Stone Purchase** (medium)
- **Rare Soul Stone Loot Drops** (small)
- **Soul Stone Boss/Quest Rewards** (small)
- **Ghost Respawn at Graveyard** (medium) — ⬜ Not started — the live respawn instead just returns the player to a fixed `respawn_position`, no graveyard concept.
- **Graveyard Network** (medium)
- **Corpse/Body Placement & Recovery** (medium) — 🚧 Partial — `src/gameplay/corpse.gd`: corpse-state/recovery-window math, tested; the live death flow doesn't drop a corpse or lose any items on death.
- **Self-Resurrection at Corpse** (small)
- **Player-Assisted Resurrection** (medium)
- **Resurrection Channeling Risk** (medium)
- **PvP Death Stakes (cross-reference)** (medium)
- **Survival Debuff Persistence on Revival (open question)** (medium)
- **Era-Reincarnation vs Lives Counter (open question)** (large)
- **Premium Currency / Economy System** (large)

### Survival (`concept/survival.md`)

Core survival meters are now real and wired into live gameplay; the sickness/wounds/debuff layer on top exists as tested pure logic but isn't wired in yet:

- **Core Survival Meters (Hunger/Thirst/Stamina/Fitness/Warmth)** (small) — 🚧 Partial — `src/gameplay/survival_meters.gd` (`SurvivalMeters`), owned by `Player`: hunger/thirst/stamina tick over time (`advance(delta)`), swimming drinks thirst down (`drink()`), eating food via the inventory window relieves hunger (`Player.eat_food`), all shown live in the HUD's bottom-left survival bar (`world.gd`'s `_build_survival_bar`). Per `concept/survival.md`'s "Stamina scope: movement only, not combat" decision, stamina no longer touches combat at all: attacking and blocking spend no stamina (the old `ATTACK_STAMINA_COST`/`Block.block_stamina_cost` coupling was removed). Stamina itself is not yet wired to anything, though -- sprinting, climbing, and swimming don't exist as stamina-consuming player actions yet (swimming is a movement mode that drains thirst but never spends stamina), so the meter currently only regenerates and never drains outside of the removed combat coupling. A **body-temperature/warmth** meter (`regulate_temperature`, see `concept/survival.md`) now closes the old temperature gap: warmth drifts toward the ambient (climate × season × weather) and is chilled by `wetness`; while cold, fitness degrades faster, and while freezing the player moves slower. Hunger/thirst rates were **retuned much slower** (pinned by a test: a minute of play no longer pushes you into hungry/thirsty), and **standing in any water (wading or swimming) drinks** from it.
- **Weather Exposure Debuffs** (medium) — 🚧 Partial — cold/wet weather is now a real debuff on warmth → fitness/movement (above). Not yet a discrete stacking entry in a unified `debuff_stack` model, and no prolonged-cold sickness trigger yet.
- **Sleep / Rest System** (small)
- **Wounds System** (medium) — 🚧 Partial — `src/gameplay/wounds.gd`: severity accrual + bandage-healing math, tested; not wired to combat or the player.
- **Debuff Stacking System** (medium) — 🚧 Partial — `src/gameplay/debuff_stack.gd`: stacking/expiry math, tested; nothing applies a debuff yet.
- **Death/Life Exclusion Rule** (small)
- **Weather Exposure Debuffs** (medium)
- **Sickness System** (large) — 🚧 Partial — `src/gameplay/sickness.gd`: a small, deliberately-scoped illness model (onset/progression), tested; not wired to gameplay, no epidemic/contagion layer.
- **Sickness Diagnosis** (medium) — 🚧 Partial — `sickness.gd`'s `diagnose()`, tested.
- **Remedy Brewing (Medicine Crafting)** (medium)
- **Crafting Blueprint System** (huge)
- **Herbalist Class** (large)
- **Herbalist Skill Nodes** (medium)
- **Preventative Treatments** (small)
- **Cooking Buffs System** (medium) — 🚧 Partial — same `food_consumption.gd` fixed-category-slot buff tracker as the Cooking section's "Dish Buffs" row above; now wired to the live eat flow for rare/legendary fish specifically (see Fishing section), the cooked-dish path from `cooking_recipe_book.gd` is still not.
- **Contagion/Epidemic System (proposed, undecided)** (huge)
- **Debuff Curve Tuning (open question)** (small)
- **Sickness Roster & Symptom Design (open question)** (small)

### NPC (`concept/npc.md`)

A first real slice of the "AI-native NPC" pillar is now live and playable --
procedurally placed villages, walking villagers running a deterministic
daily plan, and basic shopping. Still nothing LLM-driven yet: the planning
architecture is built and wired end-to-end, but behind a deterministic stand-
in, exactly like `worldbosses.md`'s `PhaseGenerator`/`FakePhaseGenerator`
split -- so a real local-LLM planner (the design brainstorm settled on
Ollama + a local model, e.g. `qwen2.5-coder:14b`, called via `HTTPRequest`,
never live during normal ticks) is a drop-in swap, not a rearchitect. No
dialogue, no instruction DSL, no memory, no lifecycle/aging, no faction/
festival wiring yet.

- **Procedural NPC Population Generation** (large) — ✅ Done (basic) — `src/world/settlement_generator.gd` places a sparse (~1-in-30 habitable chunks, never on ocean/mountain), deterministic 5-villager settlement per qualifying chunk, wired into `EarthChunkManager`'s chunk load/unload (same regenerates-identically-on-revisit philosophy as trees/creatures). `src/rendering/village_renderer.gd` spawns one house per villager plus a walking `NpcMarker`, wearing the same hero-appearance engine the player uses (`HeroAppearance`/`ProceduralCharacterSprite`), extended with 6 occupation outfit palettes. **Houses now read as real homes** (`ProceduralHouseSprite` reworked after the "tiny houselike buildings... all the same" report): 3 sizes (36x32/46x40/56x46 — every one clearly bigger than a villager, test-pinned), 4 seeded wall palettes (plaster/timber/stone/clay), 3 roof palettes (fired tile/thatch/slate), scaled doors, 1-2 windows, plank/masonry coursing, chimneys on about half; the ring layout widened to ~9 tiles with per-house seeded radius/angle jitter so the village looks grown, not compass-drawn. The shared **well/market-stall/gate landmarks are now real visible props** (`ProceduralLandmarkSprite`) anchoring a village square, instead of invisible positions NPCs walked to. Fixing the house variety also surfaced (and fixed) a real hash pathology: Godot's string hash freezes `hash(...) % count` to one bucket for counts divisible by 3 when salted strings share a short suffix — every seed was rolling the identical size and roof (see `ProceduralHouseSprite._index`; `NpcIdentity._index` had the same latent bug for its 24-entry name pool). Still single-sprite houses, not multi-tile `BuildingBlueprint` footprints -- a deliberate Phase 1 simplification.
- **NPC Identity System** (small) — ✅ Done — `src/world/npc_identity.gd`: deterministic per-seed name (two-part syllable generator), occupation (farmer/blacksmith/merchant/guard/fisher/herbalist), personality trait, and driving need, tested. Relationships to other NPCs (also part of npc.md's Identity) are NOT modeled yet.
- **Organic Backstory Growth** (small) — ⬜ Not started
- **NPC Behaviour DSL** (huge) — ⬜ Not started
- **Daily Planning (LLM Scheduler)** (large) — 🚧 Partial — `src/world/npc_planner.gd`'s `Planner`/`FakeNpcPlanner` split (mirroring `WorldBossFitness`'s `PhaseGenerator` convention exactly): `FakeNpcPlanner` deterministically produces an occupation-keyed `{time_block, location_tag, activity}` day (work by day, home to sleep by night, a guard stays on watch through the evening instead of socializing) with zero LLM calls. The real LLM-backed planner (see intro above) isn't built yet.
- **Local FSM/Pathfinder Plan Execution** (large) — ✅ Done (basic) — `src/rendering/npc_marker.gd`: a lightweight per-frame FSM (deliberately much lighter than `CreatureMarker`'s full sense/perceive/act AI) reads the current schedule entry for the in-game hour (`src/world/npc_schedule.gd`, paced by the same `SECONDS_PER_SIMULATED_DAY` clock as the rest of the world sim) and walks toward wherever it resolves to -- "home", a settlement's 3 shared landmarks (well/stall/gate), or a personal workspot for occupations without a dedicated building yet (field/forge/dock/garden). No real pathfinding (straight-line `move_toward`, no obstacle avoidance).
- **Interrupt System** (medium) — ⬜ Not started
- **Live Dialogue System** (large) — ⬜ Not started
- **Persistent Memory Log** (medium) — ⬜ Not started
- **Self-Determination / Role Drift** (medium) — ⬜ Not started
- **Dynamic Quest Generation** (large) — ⬜ Not started (each `NpcIdentity` already carries a `need`, but nothing turns it into a request yet)
- **Instruction DSL** (huge) — ⬜ Not started
- **Instruction Complexity Budget** (small) — ⬜ Not started
- **Hiring/Wage System** (medium) — ⬜ Not started
- **Relationship/Trust Gate for Hiring** (medium) — ⬜ Not started
- **Child-NPC Trust Exception** (small) — ⬜ Not started
- **Faction/Settlement Reputation Aggregation** (medium) — ⬜ Not started
- **Emergent Village Festivals** (large) — ⬜ Not started
- **Basic Merchant Shopping** (medium) — ✅ Done (basic) — `src/gameplay/shop.gd`: a fixed gold-priced catalog (tool/weapon/armor/food), spent from the player's existing (previously unwired) `Wallet`. `EarthChunkManager.has_merchant_near` finds a nearby villager with occupation "merchant"; `Player._shop_step` (trade key, default T) buys the first affordable catalog item, cycling through the list on repeat presses so it doesn't just rebuy the same thing. No shop UI browsing, no selling the player's own goods, no per-NPC stock/pricing -- open follow-ups.

### Fishing (`concept/fishing.md`)

- **Aquatic ecosystem population simulation** (large) — ⬜ Not started
- **Aquatic environmental factors** (medium) — ⬜ Not started
- **Hydraulic erosion water generation** (large) — 🚧 Partial — `hydraulic_erosion.gd` exists/tested but is part of the old procedural pipeline, unused for Earth (real elevation data already contains real rivers/oceans).
- **Visible, catchable fish entities** (medium) — ✅ Done (basic) — ocean cells now spawn actual `FishMarker` nodes (`src/rendering/fish_marker.gd`), not just an abstract catch roll: `FishRenderer` (mirroring `TreeRenderer`/`CreatureRenderer`'s chunk-based spawn/despawn shape) places a deterministic, capped subset of a chunk's **interior** water tiles with a fish (never a shore-adjacent cell), in one of 4 colorful hand-authored species (`ProceduralFishSprite`: goldfish, bluegill, speckled trout, patched koi). Each fish idle-swims via `CreatureWander`'s pure drift pattern (deliberately lighter than `CreatureMarker`'s full sense/perceive/act AI), keeps `CLEARANCE_PX` of open water on every side so no part of the sprite ever overlaps the beach, and **deflects along the shore instead of freezing** when its heading points at land (fixing the reported "fish all strand at the shoreline": a blocked fish used to stop dead for its whole direction interval, piling fish up motionless at the waterline). `EarthChunkManager.catch_nearest_fish` lets `Player._fishing_step`'s existing CAUGHT branch remove a real nearby fish and name its species in the catch message when one happens to be around — purely cosmetic; the actual reward stays the generic `fish` item/rarity-based count from `FishingMinigame`, deliberately not proliferating per-species items yet. No DNA/phenotype, no population sim, no bait-driven species targeting — species is just a per-tile deterministic color/pattern pick, not simulated life.
- **Aggregate + individual-agent promotion simulation (open question)** (large) — 🚧 Partial — visible fish entities exist (see above) but they're placement decoration, not a population sim like `CreatureRenderer`'s promotion-from-aggregate-population; there is no aquatic equivalent of `EcosystemSimulation` yet.
- **DNA/phenotype/sexual-selection system (aquatic)** (huge) — ⬜ Not started
- **Sexual selection / mate choice reproduction** (large) — ⬜ Not started
- **Rare-phenotype catch desirability** (small) — ⬜ Not started
- **Fishing catching minigame** (medium) — ✅ Done (basic) — a **playable fishing loop** now exists: `src/gameplay/fishing_session.gd` (tested state machine: cast → wait → bite → react → caught/missed) drives the pre-existing `fishing_minigame.gd` timing/rarity math. A craftable **fishing rod** (stick + plant fibre; player starts with one), a `fish` action (default F) that casts when next to open water and reels on the second press, a HUD prompt ("Casting…" → "! BITE — press the fish key!" → "Caught a … fish!"), and rarity-scaled fish rewards into the inventory (cooked over a campfire, eaten for hunger). A rare/legendary catch is now its own item (`rare_fish`/`legendary_fish`) that grants a real timed buff on eating (extra stamina regen / +30% melee damage) instead of the rarity vanishing after reward-quantity math — see Cooking section's "Dish Buffs". Bait depth, species/location availability, and the aquatic population sim are still ⬜.
- **Bait/lure system** (medium) — ⬜ Not started
- **Location-based fish availability** (medium) — ⬜ Not started
- **Cooking ingredient integration** (small) — ⬜ Not started
- **Crafting material integration** (small) — ⬜ Not started
- **DNA-quality-to-material-quality link** (medium) — ⬜ Not started
- **Aquatic taming (Beastmaster/Herbalist crossover, open question)** (medium) — ⬜ Not started
- **Companion fish / pond keeping** (medium) — ⬜ Not started
- **Aquatic mount** (large) — ⬜ Not started
- **Species-category/DNA-quality pet model** (small) — ⬜ Not started
- **Freshwater/saltwater ecosystem separation (open question)** (medium) — ⬜ Not started

### Flora (`concept/flora.md`)

Trees are real, individual, choppable, genetically-varied, and now spread on
their own -- see the Vegetation Growth Model row in the Phase 1 table above
for the implementation detail. Most of this doc's deeper trait-rarity/
disperser/climate scope is still unbuilt:

- **Biome-Specific Ground Cover** (medium) — 🚧 Partial — desert and tundra previously had zero ground-cover flora at all. Two new self-contained per-chunk patch sims now exist, each copying `TallGrass`'s exact architecture rather than sharing a base class (deterministic hash-seeded placement, growth-toward-maturity, throttled spread into same-biome neighbor cells, a pure `graze()`): `src/world/desert_scrub.gd` (gated to `biome == "desert"`, sparser and slower-growing than tall grass -- `SEED_CHANCE 0.04`/`GROWTH_RATE 0.005` vs. grass's `0.08`/`0.01`) and `src/world/tundra_lichen.gd` (gated to `biome == "tundra"`, sparser/slower still -- `SEED_CHANCE 0.02`/`GROWTH_RATE 0.002` -- continuing the grass > scrub > lichen flavor gradient, pinned by tests rather than eyeballed). Matching procedural sprites (`src/rendering/procedural_scrub_sprite.gd` dusty sage/olive, `src/rendering/procedural_lichen_sprite.gd` pale muted grey-green) reuse `ProceduralGrassSprite`'s blade-silhouette technique. Both are wired into `EarthChunkManager` exactly like tall grass (`step_desert_scrub`/`step_tundra_lichen`, called from `World._process` alongside `step_tall_grass`; patches instantiate/render on chunk load and free on unload). Known gap: unlike tall grass's `harvest_grass_near`/herbivore-graze wiring, nothing yet triggers `graze()` on either new type from live gameplay (no fibre-equivalent harvest action, no herbivore auto-graze) -- deliberately left as pure, tested logic only, to avoid cross-cutting a parallel in-flight task also touching `EarthChunkManager`. Mountain and ocean remain intentionally without ground cover (out of scope for this pass).
- **Vegetation Density Field** (medium) — 🚧 Partial — see `vegetation_growth_model.gd` (Phase 1 table); not yet unified with individual tree placement/spread.
- **Individual-Agent Promotion (Tree LOD)** (large) — 🚧 Partial — trees are always individual, collidable, choppable nodes (`ChoppableTree`) from the start, not promoted from an aggregate; there's no LOD demotion back to a density field.
- **Fruit/Nut DNA Trait System** (medium) — ✅ Done — `TreeGenome.fruit_yield`/`species_bias` deterministically drive whether a given tree's forage drops lean fruit or nut (`ForageScheduler.genome_for`).
- **Common/Rare/Legendary Trait Rarity Tiers** (small) — ⬜ Not started — genome traits are continuous floats, no discrete rarity tiers.
- **Species Foraging Preference Profiles** (small) — ⬜ Not started — no animal-side foraging preferences; only the tree's own species_bias exists.
- **Disperser vs. Seed-Predator Role Assignment** (small) — ⬜ Not started
- **Local Self-Seeding with Janzen-Connell Suppression** (medium) — 🚧 Partial — `TreeSpread` plants a mutated-child sapling within the parent's own `spread_radius` and enforces `MIN_TREE_SPACING` against overcrowding, but there's no distance-dependent survival penalty (true Janzen-Connell), just a hard minimum-spacing cutoff.
- **Animal-Mediated Seed Dispersal** (medium) — ⬜ Not started — spread is distance/genome-based only (`TreeSpread`), not carried by animals.
- **Plant DNA Inheritance & Mutation** (small) — ✅ Done — `TreeGenome.mutate()` (small, bounded nudges per trait, not a full reroll) drives every spread sapling's genome (`TreeSpread`).
- **Unified Wild/Farmed Plant DNA Population** (medium) — ⬜ Not started — no farming system exists yet.
- **Crop Escape / Wild Domestication Crossover** (small) — ⬜ Not started
- **Drought/Climate Tolerance Trait** (small) — ⬜ Not started — no climate-linked genome trait.
- **Climate-Driven Selective Mortality** (medium) — ⬜ Not started — trees never die of natural causes, only axe damage.
- **Mast Fruiting Events** (medium) — ⬜ Not started
- **Long-Timescale Forest Migration** (large) — 🚧 Partial — trees do genuinely creep outward via `TreeSpread` (throttled, persisted per-chunk), but there's no climate-driven directional bias, just proximity/spacing.
- **Ancient Tree Emergent Legendary Landmark** (medium) — ⬜ Not started
- **Ancient Tree Exploration/Crafting Payoff** (small) — ⬜ Not started
- **Rare Grove Discovery & Harvest Payoff** (small) — ⬜ Not started
- **Grove Overharvesting Population Consequence** (small) — ⬜ Not started — felling a tree (`ChoppableTree.take_damage`) drops wood and removes it permanently; nothing tracks grove-level depletion.

### World (`concept/world.md`)

The hub doc for the core simulated planet. Its foundational terrain/clock
mechanisms substantially overlap with Phase 0 above (tracked there too, in
more roadmap-oriented language); its ecosystem/weather/creature mechanisms
overlap with Phase 1 and the Weather/Evolution/Fishing/Farming/Flora/Building/
Exploration sections (referenced, not redefined, in world.md itself).

- **Procedural Terrain & Climate Generation** (large) — ✅ Done — via real Earth elevation data, replacing the doc's originally-described one-time heightmap+erosion approach (that approach still exists, retained for future non-Earth planets).
- **Köppen-style Climate Banding** (small) — ✅ Done — `climate_model.gd` + `biome_classifier.gd`.
- **Day/Night & Seasonal Clock** (medium) — ✅ Done — `solar_position.gd` real-time astronomical lighting (no distinct "season" gameplay variable yet, only the real solar geometry).
- **Vegetation Growth Simulation** (large) — 🚧 Partial — see Phase 1 table above (`vegetation_growth_model.gd`); not unified with visible tree rendering yet.
- **Herbivore Population Simulation** (large) — ✅ Done — see Phase 1 table above.
- **Predator Population Simulation** (large) — ✅ Done — see Phase 1 table above.
- **Emergent Creature Distribution ("boars" pillar)** (medium) — ✅ Done — `test_ecosystem_time_lapse.gd` proves biome-driven clustering with no hand-placed spawners, matching this pillar's exact framing.
- **Aggregate-to-Individual Agent Promotion (simulation LOD)** (large) — ✅ Done — see Phase 1 table above; placeholder visuals only, not replicated in multiplayer yet.
- **Torus/Globe World Topology** (medium) — ✅ Done — `world_coordinates.gd` toroidal wrap.
- **Chunk-Based World Persistence** (large) — 🚧 Partial — built and tested, not wired into live gameplay.
- **Variable-Fidelity Chunk Simulation (catch-up pass)** (large) — ⬜ Not started
- **Dynamic Weather & Disaster Events** (large) — ⬜ Not started (see Weather section)
- **Creature Genetics/Evolution System** (huge) — ⬜ Not started (see Evolution section)
- **World Boss Emergence** (medium) — ⬜ Not started (see World Bosses section)
- **Fishing/Aquatic Ecosystem Simulation** (large) — ⬜ Not started (see Fishing section)
- **Farming System** (medium) — ⬜ Not started (see Farming section)
- **Flora DNA & Seed-Dispersal Evolution** (huge) — ⬜ Not started (see Flora section)
- **Building/Construction System** (large) — ⬜ Not started (see Building section)
- **Exploration & History-Seeded Points of Interest** (large) — ⬜ Not started (see Exploration section)

### Farming (`concept/farming.md`)

No farming system is wired into live gameplay, but its plot and breeding math now exist as tested pure logic:

- **Farming loop (plant/tend/harvest)** (medium) — 🚧 Partial — `src/gameplay/farm_plot.gd`: plant/grow-over-time/harvest state machine, tested; no plantable tile exists in the live world, no player action to use it.
- **Crop DNA/phenotype system** (large)
- **Crop trait rarity tiers** (medium)
- **Selective breeding / cross-pollination** (large) — 🚧 Partial — `src/gameplay/crop_breeding.gd`: two-parent crop crossover, tested; no live crops to breed.
- **Rare crop strain collecting hook** (small) — 🚧 Partial — `crop_breeding.gd`'s `trait_rarity_score`/`is_rare_strain`, tested; same wiring caveat.
- **Crafting ingredient integration** (medium)
- **Cooking ingredient integration** (medium)
- **Farm plot as vegetation-density override** (large)
- **Tilling/watering/fertilizing (carrying-capacity boost)** (medium)
- **Shared wild/farmed genetic population** (large)
- **Cross-breeding UI / trait-math visibility (open question)** (medium)
- **Seasonal crop viability (open question)** (medium)

---

### UI / presentation

- **Unified UI theme** — ✅ Done — `src/ui/ui_theme.gd` (tested: palette, styleboxes, built `Theme` all pinned) is one dark/rounded/gold-accent theme applied to every menu and window (main menu, settings, inventory, crafting, skill tree, dev console) plus the HUD survival card. Replaces the earlier raw grey boxes.
- **Main-menu backdrop** — ✅ Done — the start-up menu now dims the whole screen behind a full-rect backdrop (`World._show_main_menu`) so the game world/HUD no longer bleed through it.
- **HUD polish** — 🚧 Partial — survival meters grouped into a themed panel card; XP bar / creature panels repositioned to stop overlapping. Meter fills are still plain rects (no rounded fills).
- **Character screen / inventory revamp** — ✅ Done (basic) — `scenes/inventory_window.gd` (toggle I) is now a PoE/Valheim/Hammerwatch-style **two-pane character screen**: a left **equipment paperdoll** (rendered head+torso preview + clickable head/chest/legs/feet/weapon slots) and a right **item-slot grid** (icon + count, hover tooltips). Click an inventory item to wear/equip or eat it; click a worn slot to unequip. **Drag-and-drop works**: drag an item onto another grid slot to reorder, or out onto a HUD hotbar slot to bind it to a number key (`src/ui/drag_slot.gd` is the shared drag-capable slot Control; `src/gameplay/hotbar.gd` holds the bindings). Shows total armor. Not yet: splitting/merging stacks by drag, or dragging directly onto a paperdoll slot to equip.
- **Character creation with pixel art** — ✅ Done (basic) — the New Game class picker (`scenes/main_menu.gd`) renders a **live pixel-art character preview** (procedural head + class-tinted torso) that updates as you select a class, alongside the stat blurb.

## Reality check

This design corpus — 32 concept docs plus a roadmap, 481 catalogued
mechanisms — describes a multi-year, full-team-scale MMORPG: procedurally
simulated planetary ecology, LLM-driven autonomous NPCs with memory and daily
planning, deep genetics/evolution shared across animals/plants/players/pets,
a player-authorable spellcrafting DSL, deterministic blueprint-based
crafting, a dual-currency economy, factions, housing, world bosses, PvP,
festivals, farming, fishing, cooking, marriage and child-rearing, permadeath
with reincarnation across technological eras, and eventual multi-planet space
travel — before multiplayer is even considered.

A solo/part-time developer has, to date, built a real, tested foundation:
a genuine real-Earth world simulation (bilinear elevation sampling, real
lat/long geodesy, real-time astronomical day/night, biome classification,
chunk streaming) plus a basic player/movement/rendering layer (toroidal
movement, water-depth-based swimming/wading/drowning, wetness tracking,
placeholder character rendering). That is Phase 0 of the roadmap, essentially
complete, plus an early, deliberate architectural pivot (real Earth data
instead of fictional procedural generation) that the roadmap didn't
anticipate.

Since that snapshot, several more passes have landed: per-creature HUD info
panels (`CreaturePanel`, one per nearby creature with name/level/HP bar +
numeric HP label) replaced both an aggregate "Nearby Creatures" list and an
earlier world-space-nameplate attempt; the always-visible inventory text
panel was replaced by a real toggleable `InventoryWindow` (key I, click a
food row to eat it); creature variety grew (boars, lynx) with level-scaled
max health; flat-color terrain tiles were replaced by procedurally-generated,
seeded pixel-art tile variants per biome, plus a directional border-blending
system between any two neighboring biomes (a border cell dithers toward
whichever biome dominates on each edge, rather than a random patchwork);
reaching 0 HP now actually kills and respawns the player instead of silently
doing nothing; and three of the 36 pure-logic mechanics built in a large
parallelized TDD sweep across all 32 concept docs are now wired into the live
game loop and HUD — **survival meters** (hunger/thirst/stamina, ticking down
and refilled by eating/drinking/resting), a **wallet/gold currency**, and a
first **crafting loop** (console-driven `/craft`). The other ~30 modules from
that same sweep (mining, farming, cooking, fishing, taming/pet loyalty,
skills/keystones, class archetypes, item rarity, world-boss fitness,
dodge/throwables, corpses/lives, wounds/debuffs/sickness, housing coziness,
faction reputation, fast-travel/waypoints, animal DNA/fitness, festivals, PvP
dueling, building blueprints, and POI loot scaling) are real and tested but
not yet connected to any live gameplay system — each is called out with a
🚧 Partial note and file path in its section above, so "partial" there
specifically means "real, tested logic sitting unused," not "half-written."

The vast majority of documented mechanisms — NPCs/AI, magic, economy,
crafting, farming, pets, world bosses, PvP, festivals, death, player-side
DNA, multiplayer, and essentially everything from Phase 2 onward — have not
been started. Phase 1 (living ecosystem MVP) and a growing slice of Phase 3
(core gameplay loop) are now built: regional herbivore/predator population
dynamics, per-cell vegetation density, proximity-based creature promotion,
real per-individual creature AI (temperament-driven flee/hunt/graze/drink,
predators eating herbivores and fighting or fleeing the player, each with a
health bar and a name/level/stamina/mana info panel), a weapon-driven melee
attack with a real swing animation and Hammerwatch-style knockback that
makes creatures drop clickable loot, a real item/inventory system with a HUD
(player health bar, hotbar, spell bar placeholder), a persistent tile
build/destroy system, and — new this pass — **individual tree genetics**:
every tree has a deterministic DNA (`TreeGenome`: fruit/nut yield, spread
radius, maturity time) that drives its forage drops and its genome-tinted
canopy art, an axe-wielding player can fell trees for wood
(`ChoppableTree`), and mature trees slowly self-seed mutated-child saplings
that grow to their own maturity before foraging/reproducing in turn, all
persisted per-chunk across unload/reload. Procedural pixel art is now
consistent across items, creatures, the player character, and trees, all
offline and deterministic. Honestly-scoped known gaps remain (no
multiplayer replication for creatures/combat/items/trees — play
single-player for a coherent loop; no whole-planet background simulation;
individual predation not yet linked to aggregate ecosystem counts;
food-seeking is biome- not density-granularity) noted per mechanism above. A
real dev/admin console now exists (backtick to toggle; `/day`, `/spawn`,
`/give`, `/craft`, `/gold`, `/help` commands — see Phase 3 table). Of the 481
mechanisms catalogued here, roughly 38 are now done and roughly 55 are
partial (up sharply from 36/24, mostly via this session's batch of unwired
pure-logic modules) — both counts are approximate rather than a full
re-audit of all 481. This is not a
criticism of the design work, which is thorough and internally consistent; it
simply means prioritization decisions (what to build next, and how much of
this scope is realistic for one person) are needed rather than assuming the
roadmap's phases — let alone the full concept-doc corpus — will be
implemented linearly or in full.
