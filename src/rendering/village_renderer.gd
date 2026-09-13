extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## Chunk-based spawn/despawn of a procedurally generated village (see
## SettlementGenerator, docs/concept/npc.md) -- real HouseBlueprint-stamped
## houses (see _stamp_house) plus walking NpcMarker villagers, wearing the
## same hero-appearance engine the player uses (HeroAppearance/
## ProceduralCharacterSprite), keyed by occupation instead of class. Same
## "one call per chunk load, deterministic, returns spawned nodes for the
## caller to free" shape as TreeRenderer/CreatureRenderer/FishRenderer --
## except houses themselves are chunk modifications, not spawned nodes (see
## spawn_village's own doc comment).

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")
const HouseDecor = preload("res://src/gameplay/house_decor.gd")

## Villagers are rendered with the player's own CharacterView (see
## _build_npc), so there are deliberately no villager-specific body size
## constants here -- the previous ones drifted out of sync with
## CharacterView and left NPCs legless.

var _settlement_generator := SettlementGenerator.new()
var _landmark_sprite := ProceduralLandmarkSprite.new()
var _character_sprite := ProceduralCharacterSprite.new()
var _appearance := HeroAppearance.new()
var _drop_shadow := DropShadow.new()
var _house_blueprint := HouseBlueprint.new()
var _construction_catchup := ConstructionCatchup.new()

## Roughly 1-in-this-many houses is stone rather than wood -- most villages
## read as a wood-built settlement, with the occasional stone house for
## visual variety, deterministic per house.
const _STONE_HOUSE_CHANCE_DENOMINATOR := 4

## How far a house's origin may be nudged off its ring-layout anchor to
## escape a water pocket (a chunk's dominant biome only gates the whole
## CHUNK, not every individual cell -- see BiomeClassifier.dominant_biome --
## so a grassland-dominant chunk can still have a pond/river cutting through
## it). Comfortably larger than one house footprint's own diagonal, so a
## small pond doesn't strand a house with nowhere to go; a house that still
## can't find dry ground within this radius is skipped rather than forced
## into the water (see _stamp_house).
const _WATER_AVOIDANCE_SEARCH_RADIUS_TILES := 6

## Draw order for an upper storey's own lit windows (see _stamp_house's
## `upper_windows`): from outside, an upper storey is only ever its facade
## band, painted one row UP on a layer that sits ABOVE the roof
## (EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX, 2), so a light for one of
## its windows has to draw above that layer or it is buried under the very
## facade it lights -- and below whoever is standing upstairs
## (EarthChunkManager.UPPER_FLOOR_OCCUPANT_Z_INDEX, 4), or it is painted
## over the player. Not read off EarthChunkManager directly: this small
## module deliberately never preloads that large, engine-bound script (see
## _construction_completion_fraction's own identical reasoning), so the
## relationship is pinned by test instead (test_village_renderer.gd).
const UPPER_WINDOW_LIGHT_Z_INDEX := 3

## How far outside the door a merchant's personal trading stand sits (see
## _build_stands_for_merchants) -- close enough to read as "this villager's
## own stand", clear of the door cell and the house's wall thickness.
const _STAND_OFFSET_TILES := 2

## Bright daylight -- spawn_village's own default for `sun_elevation_deg`
## when a caller doesn't pass one (every existing caller/test, plus tools
## that don't care about night lighting). Same "nothing pinned, sun high"
## convention CreatureMarker.DEFAULT_SUN_ELEVATION_DEG/HillshadeShader.
## DEFAULT_SUN_ELEVATION_DEG already use elsewhere in this codebase for the
## identical purpose, kept as its own constant here rather than importing
## either of those (this file has no other reason to depend on them).
const DEFAULT_SUN_ELEVATION_DEG := 45.0

## The sun elevation at/below which a house's windows light up for the
## night -- the EXACT same day/night boundary scenes/world.gd already uses
## for its own sky tint and Easter-egg sightings (its own `elevation <= 0.0`
## -- see is_night's own doc comment), not a second, independently-tuned
## threshold.
const _NIGHT_ELEVATION_THRESHOLD_DEG := 0.0

## Warm lamplight for a window at night -- deliberately warmer than
## ProceduralHouseSprite.WINDOW_GLASS_COLOR's cool daylight glass tint, so a
## village genuinely reads as "windows glowing after dark", not the same
## daytime glass merely recoloured.
const _WINDOW_LIGHT_COLOR := Color(1.0, 0.82, 0.42, 0.9)

## A lit window's glow is drawn at this fraction of a tile -- small enough to
## read as light spilling from the window pane, not a solid tile-sized block
## stamped over the whole wall cell.
const _WINDOW_LIGHT_SIZE_FRACTION := 0.5

var _window_light_texture_cache: Dictionary = {}  # tile_size (int) -> ImageTexture


## Whether it's dark enough for a house's windows to glow (see
## docs/concept/housing.md#night-lighting-ambient) -- the EXACT same
## elevation-at-or-below-zero boundary scenes/world.gd already uses to decide
## day/night for its own sky tint and Easter-egg sightings, not a second,
## re-tuned threshold, so a village's windows go dark/lit at the same real
## moment the sky itself does.
func is_night(sun_elevation_deg: float) -> bool:
	return sun_elevation_deg <= _NIGHT_ELEVATION_THRESHOLD_DEG


## Spawns this chunk's village (real stamped houses, landmark props, and NPC
## markers, the last two as children of `parent`) if SettlementGenerator
## places one here, given the chunk's dominant_biome (see BiomeClassifier.
## dominant_biome -- ocean/mountain never qualify). Returns [] on a chunk
## with no settlement.
##
## `world` is the owning EarthChunkManager (duck-typed: only
## stamp_structure_at_global is actually called), the same object every
## other renderer's spawn call already receives. A village house is not a
## decorative sprite with a painted-on door any more -- it's a real
## HouseBlueprint assembly of floor/wall/door/roof pieces stamped into the
## world exactly the way the player's own building pieces are (see
## docs/concept/building.md#one-system-two-builders), so it produces no
## Node2D of its own; only the returned door position (used for the
## villager's home_position) comes out of stamping a house. `world == null`
## (an isolated rendering test/tool that doesn't need real chunk mutation)
## skips stamping entirely rather than crashing -- same fail-open shape as
## _water_layer/_roof_layer elsewhere in this codebase -- and falls back to
## the raw anchor position so callers still get a sensible home_position.
##
## `sun_elevation_deg` is the real, live sun elevation (see solar_position.gd,
## scenes/world.gd's own day/night lighting) at the moment this chunk streams
## in -- when is_night(sun_elevation_deg) is true, every real window this
## call actually stamps gets a warm lit-window glow sprite alongside it (see
## docs/concept/housing.md#night-lighting-ambient). Defaults to bright
## daylight so every existing caller/test that doesn't care about night
## lighting keeps behaving exactly as before this parameter existed. Chunk-
## scoped like the rest of this function: a village's lit/unlit state is
## decided once here, not re-evaluated while the chunk stays loaded.
func spawn_village(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	dominant_biome: String,
	world = null,
	sun_elevation_deg: float = DEFAULT_SUN_ELEVATION_DEG
) -> Array[Node2D]:
	if not _settlement_generator.has_settlement_at(chunk_coord, dominant_biome):
		return []
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_origin_tiles, chunk_size, tile_size
	)

	# One VillageMarket per settlement, shared by every villager built below
	# (see NpcMarker.setup_economy) -- docs/concept/npc.md "Needs and the
	# local production economy": a producer's real surplus must be visible
	# to every consumer of the SAME village, not siloed per NPC. Freshly
	# created on every spawn_village call, same as the rest of this
	# settlement's state -- a chunk reload regenerates an empty market, the
	# same known "regenerates identically on revisit, no persistence"
	# simplification trees/creatures already accept (see docs/progress.md).
	var market := VillageMarket.new()

	# Tells the world this settlement exists, duck-typed exactly like
	# stamp_structure_at_global above -- world == null or lacking the method
	# is skipped rather than crashing, the same fail-open shape the rest of
	# this function already uses. EarthChunkManager owns deciding whether this
	# is genuinely a FIRST founding (a chunk reload must not re-record one).
	if world != null and world.has_method("record_settlement_founded_if_new"):
		world.record_settlement_founded_if_new(chunk_coord, settlement.npcs)

	var spawned: Array[Node2D] = []
	var house_positions: Array = settlement.house_positions
	var npcs: Array = settlement.npcs
	var door_positions: Array[Vector2] = []
	var stand_positions: Array[Vector2] = []
	var night := is_night(sun_elevation_deg)
	for i in house_positions.size():
		var house := _stamp_house(chunk_coord, i, house_positions[i], npcs[i], tile_size, world, npcs.size())
		door_positions.append(house.door)
		stand_positions.append(house.stand)
		if night:
			for window_position in house.windows:
				spawned.append(_build_window_light(window_position, tile_size, parent))
			# An upper storey's own facade windows, already reported one row
			# up where that facade is actually drawn from outside -- lit on
			# their own draw order above the upper-floor layer (see
			# UPPER_WINDOW_LIGHT_Z_INDEX).
			for window_position in house.upper_windows:
				spawned.append(_build_window_light(window_position, tile_size, parent, UPPER_WINDOW_LIGHT_Z_INDEX))
	for landmark_id in settlement.landmarks:
		spawned.append(_build_landmark(landmark_id, settlement.landmarks[landmark_id], parent))
	for i in npcs.size():
		var npc_marker := _build_npc(settlement, i, door_positions[i], tile_size, parent, world, market)
		spawned.append(npc_marker)
		# A merchant gets a second, PERSONAL trading stand at their own house,
		# on top of the one shared village-square stall -- otherwise every
		# merchant in the village routes to the same single stall, which reads
		# as one shop rather than several villagers who each trade (see
		# docs/concept/npc.md).
		if npcs[i].occupation == "merchant":
			spawned.append(_build_landmark("stall", stand_positions[i], parent))
		# Every OTHER occupation whose own work location isn't already one of
		# the settlement's 3 shared landmarks (merchant/stall and guard/gate
		# both already have something real there) gets a real prop of their
		# own at their personal workspot -- a farmer's field, a blacksmith's
		# forge, a fisher's dock, an herbalist's garden -- instead of an
		# invisible position they simply stood on empty grass at (reported
		# directly as the remaining gap after houses themselves got real
		# variety: "no per-occupation building beyond the shared landmarks
		# and a merchant's own stand").
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(npcs[i].occupation, "")
		if work_tag != "" and not settlement.landmarks.has(work_tag):
			spawned.append(_build_landmark(work_tag, npc_marker.workspot_position, parent))
	return spawned


## Stamps one villager's house as a real HouseBlueprint structure centred
## roughly on `anchor` (the old ring-layout position), and returns
## {"door": Vector2, "stand": Vector2} -- the door is what the villager
## should actually walk home to, since it's the one cell of the house
## guaranteed to be both walkable and on the structure's edge (walking to the
## raw anchor/centre would just as often land an NPC in the middle of a wall
## or floor cell); the stand is one step further out in the same direction,
## for a merchant's personal trading stand (see spawn_village). Both fall
## back to `anchor` when nothing is actually stamped (no world, an empty
## footprint, or no dry ground nearby -- see _find_dry_origin), the same
## fail-open shape as the rest of this function.
##
## `npc` (the villager's own NpcIdentity) is what makes the house THEIRS:
## HouseBlueprint.choose_blueprint_id picks a real named shape from
## `npc.occupation`'s own pool, nudged by `npc.genome`'s dominant
## personality trait (docs/concept/npc.md's "personality should be DNA
## derived") -- a farmer's hut, a merchant's bright manor, and everything
## between, instead of the one fixed 5x4 box every villager used to get.
##
## `npc_count` (the settlement's own real villager count -- see
## spawn_village) is what retires this function's own named anti-pattern
## (docs/concept/timber_construction.md's "Known anti-pattern this doc
## replaces": a house used to stamp complete, instantly and for free, the
## moment a chunk generated). See _construction_completion_fraction for the
## real, computed reasoning; in the near-certain case that reasoning finds
## the house already fully buildable (see that function's own doc comment),
## this stamps the exact same full pieces + roofs as before -- deliberately
## behavior-preserving for the common case.
##
## Two-story houses (docs/concept/housing.md): if `npc.occupation`'s own
## HouseBlueprint.choose_blueprint_id lands on a real two-story id (only
## possible for merchant/blacksmith today -- see BLUEPRINT_POOL_BY_
## OCCUPATION's own doc comment), this ALSO stamps a real upper storey
## once the ground floor itself is fully complete -- see the two-story
## branch near this function's own return.
func _stamp_house(chunk_coord: Vector2i, index: int, anchor: Vector2, npc: NpcIdentity, tile_size: int, world, npc_count: int) -> Dictionary:
	var seed_value := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, index])
	var blueprint_id := _house_blueprint.choose_blueprint_id(npc.occupation, npc.genome, seed_value)
	var footprint := _house_blueprint.footprint_for(blueprint_id)
	var anchor_tile := Vector2i(floori(anchor.x / tile_size), floori(anchor.y / tile_size))
	var raw_origin := anchor_tile - footprint / 2

	if world == null or not world.has_method("stamp_structure_at_global"):
		return {"door": anchor, "stand": anchor, "windows": [], "upper_windows": []}

	var material := (
		BuildingPiece.MATERIAL_STONE
		if PixelNoise.value(seed_value, index, 0) % _STONE_HOUSE_CHANCE_DENOMINATOR == 0
		else BuildingPiece.MATERIAL_WOOD
	)
	var pieces := _house_blueprint.build(blueprint_id, seed_value, material)
	if pieces.is_empty():
		return {"door": anchor, "stand": anchor, "windows": [], "upper_windows": []}

	var origin_tile = _find_dry_origin(raw_origin, footprint, world)
	if origin_tile == null:
		return {"door": anchor, "stand": anchor, "windows": [], "upper_windows": []}  # no dry ground nearby -- skip rather than build in water

	var roofs := _house_blueprint.build_roofs(blueprint_id, seed_value, material)

	# The door position is derived from the FULL blueprint's own door cell
	# regardless of how complete the house is -- a villager needs somewhere
	# real to walk home to even while their own house is still being built
	# (see docs/concept/timber_construction.md's NPC construction section).
	var door_local := _door_cell(pieces)
	var door_global: Vector2i = origin_tile + door_local
	var door_position := Vector2((door_global.x + 0.5) * tile_size, (door_global.y + 0.5) * tile_size)

	var facing := _door_facing_direction(door_local, pieces)
	var stand_global := door_global + facing * _STAND_OFFSET_TILES
	var stand_position := Vector2((stand_global.x + 0.5) * tile_size, (stand_global.y + 0.5) * tile_size)

	var fraction := _construction_completion_fraction(pieces, npc_count)
	var stamped_pieces := pieces
	var stamped_roofs := roofs
	if fraction < 1.0:
		stamped_pieces = _partial_pieces(pieces, fraction)
		# The roof only ever goes up once every non-roof piece is placed --
		# Worked Example C's own "walls up, no roof yet" partial-project
		# flavor (see docs/concept/timber_construction.md), made real.
		if stamped_pieces.size() < pieces.size():
			stamped_roofs = {}
	world.stamp_structure_at_global(chunk_coord, origin_tile, stamped_pieces, stamped_roofs)
	# Occupation-themed decor (docs/concept/housing.md's "Occupation-themed
	# decor" section): furnished against the SAME stamped_pieces just given
	# to stamp_structure_at_global above, never a second floor-detection
	# pass -- a partially-built house (fraction < 1.0 above) is only ever
	# furnished against the floor cells that are actually there. Duck-typed
	# exactly like record_settlement_founded_if_new above: a world stub that
	# only implements stamp_structure_at_global is skipped, not broken.
	if world.has_method("furnish_house_at_global"):
		world.furnish_house_at_global(
			chunk_coord, origin_tile, stamped_pieces, HouseDecor.furniture_set_for(npc.occupation)
		)

	# Windows are read off `stamped_pieces`, never the full `pieces` -- a
	# still-under-construction house (fraction < 1.0 above) only lights the
	# windows it has actually built so far, never one that isn't there yet.
	var window_positions := _window_positions(stamped_pieces, origin_tile, tile_size)

	# Two-story houses (docs/concept/housing.md): an NPC's own real second
	# storey, gated on the SAME "ground floor fully complete" condition the
	# roof itself already uses just above -- a house still being raised
	# gets no upper floor yet either, the same real build order a hired
	# Builder now follows too (see BuilderMarker.target_upper_pieces).
	# Duck-typed via has_method exactly like stamp_structure_at_global
	# itself already is a few lines up. Upper windows are reported as their
	# OWN list (`upper_windows`), not appended to the ground floor's: from
	# outside, an upper storey is only ever its facade band, drawn one row
	# UP over the roof's front row (docs/concept/building.md "How a house
	# reads from above", point 5), so its lights go where that band is drawn
	# and need their own draw order above the upper-floor layer -- see
	# _upper_facade_window_positions and spawn_village's night-lighting loop.
	var upper_pieces := {}
	var upper_window_positions: Array[Vector2] = []
	if (
		_house_blueprint.is_two_story(blueprint_id) and stamped_pieces.size() == pieces.size()
		and world != null and world.has_method("stamp_upper_floor_at_global")
	):
		upper_pieces = _house_blueprint.build_upper_floor(blueprint_id, seed_value, material)
		world.stamp_upper_floor_at_global(chunk_coord, origin_tile, upper_pieces)
		upper_window_positions = _upper_facade_window_positions(upper_pieces, origin_tile, tile_size)

	# Interior furniture, upper floor (docs/concept/housing.md's "Interior
	# furniture" / "Occupation-themed decor" sections) -- reported directly
	# alongside two-story houses themselves ("no room decoration... no do
	# both floors"): the SAME real, occupation-linked HouseDecor set the
	# ground floor was just furnished with above, tried again against the
	# upper floor's own real floor cells via its own real layer (see
	# furnish_upper_floor_at_global's own doc comment for why
	# furniture_modifications can't simply be reused for the upper floor
	# too). Gated on the SAME "ground floor fully complete" condition the
	# upper floor's own walls just used above -- a still-rising house gets
	# no upper furniture either. Duck-typed exactly like stamp_upper_
	# floor_at_global itself already is a few lines up.
	if (
		not upper_pieces.is_empty() and world != null
		and world.has_method("furnish_upper_floor_at_global")
	):
		world.furnish_upper_floor_at_global(
			chunk_coord, origin_tile, upper_pieces, HouseDecor.furniture_set_for(npc.occupation)
		)

	return {
		"door": door_position, "stand": stand_position,
		"windows": window_positions, "upper_windows": upper_window_positions,
	}


## How structurally complete a settlement house should be by the time a
## player actually discovers it, given `npc_count` real villagers to have
## conceivably been working on it. This is the real, computed resolution to
## this file's own named anti-pattern (see _stamp_house's own doc comment
## and docs/concept/timber_construction.md's "Known anti-pattern this doc
## replaces") -- reuses the EXACT SAME offscreen labor-catch-up calculation
## the rest of this codebase already trusts (ConstructionLabor.
## labor_hours_required_for_pieces / ConstructionCatchup.advance -- see
## docs/concept/timber_construction.md's "Unloaded / offscreen fidelity"
## section) as a bare, UN-PERSISTED calculation. This deliberately does NOT
## create a real ConstructionProject/ConstructionProjectStore entry:
## EarthChunkManager.record_settlement_founded_if_new already grants this
## exact house's property under its OWN chunk+villager-index house-id
## scheme (see that function), while ConstructionProject.property_id() uses
## a DIFFERENT scheme keyed by footprint origin (see construction_project.gd)
## -- wiring through that ledger here would produce two divergent ownership
## records for the same real house.
##
## assumed_elapsed_seconds intentionally assumes the MOST generous plausible
## age for a settlement a player is only now discovering: the same
## ConstructionCatchup.MAX_CATCHUP_DAYS cap ("logistic growth converges
## anyway") every other offscreen catch-up in this codebase already treats
## as long enough to reach a steady state -- ConstructionCatchup.
## MAX_CATCHUP_DAYS mirrors EarthChunkManager.MAX_CATCHUP_DAYS's own exact
## value and justification (see that constant's own doc comment; not
## preloaded directly here to avoid pulling this small, testable module into
## EarthChunkManager's own large, engine-dependent script) -- times
## ConstructionCatchup's own SECONDS_PER_DAY. By the time any player
## discovers a settlement, assume it has had at least as long to build as
## this game's own existing "how long was I away" cap already treats as
## enough to reach a steady state.
##
## In practice this returns >= 1.0 for essentially every real settlement
## size in today's game (SettlementGenerator.POPULATION villagers against
## any real HouseBlueprint entry -- see
## test_every_real_blueprint_reaches_full_completion_at_the_real_settlement_
## population), which is exactly what keeps this a deliberately
## behavior-preserving change for the common case: a real, live, tested
## reachable fraction < 1.0 path exists (see the oversized-piece-set tests),
## it just essentially never fires at today's typical settlement sizes.
func _construction_completion_fraction(pieces: Dictionary, npc_count: int) -> float:
	var required := ConstructionLabor.labor_hours_required_for_pieces(pieces)
	if required <= 0.0:
		return 1.0  # an empty/zero-cost blueprint has nothing to build
	var assumed_elapsed_seconds := ConstructionCatchup.MAX_CATCHUP_DAYS * ConstructionCatchup.SECONDS_PER_DAY
	var caught_up := _construction_catchup.advance(
		{"labor_hours_accumulated": 0.0, "labor_hours_required": required},
		assumed_elapsed_seconds,
		{"builder_count": float(npc_count)}
	)
	return float(caught_up.get("labor_hours_accumulated", 0.0)) / required


## The doc's own real historical build order (floor -> load-bearing walls ->
## infill doors/windows), sliced to a deterministic PREFIX sized by
## `fraction` -- Worked Example C's own "walls up, no roof yet" partial-
## project flavor, made real for the (essentially never reached at today's
## real settlement sizes -- see _construction_completion_fraction) case
## where a house's own assumed accumulated labor falls short of what it
## would take to finish. No RandomNumberGenerator anywhere -- matches this
## doc's own determinism pillar.
func _partial_pieces(pieces: Dictionary, fraction: float) -> Dictionary:
	var ordered := _construction_install_order(pieces)
	var target_count := int(floor(fraction * ordered.size()))
	var partial := {}
	for i in target_count:
		var cell: Vector2i = ordered[i]
		partial[cell] = pieces[cell]
	return partial


## Deterministic cell ordering for _partial_pieces: every FLOOR cell first (a
## house needs a foundation before anything stands on it), then every WALL
## cell (load-bearing -- see BuildingPiece.is_load_bearing; every
## CATEGORY_WALL piece in this catalog already is one, generalized past just
## the timber tier -- see building_piece.gd's own support_capacity doc
## comment), then every remaining cell (door/window infill -- an opening
## punched through a wall, not a structural member). Cells within each group
## sort by (y, x), the same deterministic top-left-to-bottom-right cell
## ordering BuildingStatics._cell_before already establishes elsewhere in
## this same piece-grid mechanism -- never raw Dictionary insertion order,
## which would depend on how HouseBlueprint.build happened to walk its own
## loops rather than on the house's own real layout.
func _construction_install_order(pieces: Dictionary) -> Array:
	var floor_cells: Array = []
	var wall_cells: Array = []
	var infill_cells: Array = []
	for cell in pieces:
		var piece_id: String = pieces[cell]
		if BuildingPiece.category_of(piece_id) == BuildingPiece.CATEGORY_FLOOR:
			floor_cells.append(cell)
		elif BuildingPiece.is_load_bearing(piece_id):
			wall_cells.append(cell)
		else:
			infill_cells.append(cell)
	var by_row_then_column := func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	floor_cells.sort_custom(by_row_then_column)
	wall_cells.sort_custom(by_row_then_column)
	infill_cells.sort_custom(by_row_then_column)
	var ordered: Array = []
	ordered.append_array(floor_cells)
	ordered.append_array(wall_cells)
	ordered.append_array(infill_cells)
	return ordered


## Which way the door opens outward: the OPPOSITE direction from wherever
## its one true FLOOR neighbour sits (see HouseBlueprint._wall_candidates --
## a valid door/window cell always has exactly one floor neighbour, so this
## is well-defined for every blueprint shape, rectangular or notched).
## Previously assumed a plain box's 4 sides directly from the door's raw
## (x, y) -- correct for every rectangular blueprint, but would have
## silently defaulted to "east" for a door landing on an L-shaped
## blueprint's own notch-exposed edge (not one of the box's outer 4 sides
## at all), pointing a merchant's personal trading stand at a wall instead
## of open ground.
func _door_facing_direction(door_local: Vector2i, pieces: Dictionary) -> Vector2i:
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for offset in offsets:
		var neighbor: Vector2i = door_local + offset
		if BuildingPiece.category_of(pieces.get(neighbor, "")) == BuildingPiece.CATEGORY_FLOOR:
			return -offset
	return Vector2i(1, 0)  # never happens for a real door cell; stays safe regardless


## `raw_origin` if its whole footprint is real, buildable ground already;
## otherwise the nearest (by squared distance, deterministic) candidate
## origin within _WATER_AVOIDANCE_SEARCH_RADIUS_TILES whose whole
## footprint qualifies; null if none does. `world` supporting neither real
## check (a caller that only cares about stamp_structure_at_global, e.g.
## an older/duck-typed test double) skips the check entirely and trusts
## raw_origin, the same fail-open shape as every other optional-capability
## check in this codebase.
##
## Named "_dry" historically (water avoidance was this search's original
## and only job); it now also avoids forest and standing trees (docs/
## concept/building.md: "houses / buildings cannot be built on river /
## water; also not in the forest... must first fell all trees to make
## space") via the real EarthChunkManager.is_buildable_terrain_at, when
## the caller provides it -- see _footprint_is_dry's own doc comment for
## the fallback this keeps for a `world` that only has biome_at_global.
func _find_dry_origin(raw_origin: Vector2i, footprint: Vector2i, world) -> Variant:
	if not _world_has_a_terrain_check(world) or _footprint_is_dry(raw_origin, footprint, world):
		return raw_origin
	var offsets: Array[Vector2i] = []
	for dy in range(-_WATER_AVOIDANCE_SEARCH_RADIUS_TILES, _WATER_AVOIDANCE_SEARCH_RADIUS_TILES + 1):
		for dx in range(-_WATER_AVOIDANCE_SEARCH_RADIUS_TILES, _WATER_AVOIDANCE_SEARCH_RADIUS_TILES + 1):
			if dx != 0 or dy != 0:
				offsets.append(Vector2i(dx, dy))
	offsets.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	for offset in offsets:
		var candidate := raw_origin + offset
		if _footprint_is_dry(candidate, footprint, world):
			return candidate
	return null


func _world_has_a_terrain_check(world) -> bool:
	return world.has_method("is_buildable_terrain_at") or world.has_method("biome_at_global")


## The real, comprehensive EarthChunkManager.is_buildable_terrain_at when
## `world` provides it (ocean, forest, river, lake, AND standing trees --
## see that function's own doc comment); otherwise the narrower, original
## ocean-only biome_at_global check, for a `world` double that predates
## it (see _world_has_a_terrain_check). Prefers the real check whenever
## it's available rather than ever running both.
func _footprint_is_dry(origin: Vector2i, footprint: Vector2i, world) -> bool:
	var use_real_check: bool = world.has_method("is_buildable_terrain_at")
	for x in footprint.x:
		for y in footprint.y:
			var cell := origin + Vector2i(x, y)
			if use_real_check:
				if not world.is_buildable_terrain_at(cell.x, cell.y):
					return false
			elif world.biome_at_global(cell.x, cell.y) == CreaturePerception.WATER_BIOME:
				return false
	return true


func _door_cell(pieces: Dictionary) -> Vector2i:
	for cell in pieces:
		if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_DOOR:
			return cell
	return Vector2i.ZERO


## World-space centre of every CATEGORY_WINDOW cell in `pieces` (a stamped
## house's own LOCAL cell -> piece_id map -- see _stamp_house's own
## `stamped_pieces`), translated by `origin_tile` into global tile space
## then into pixels -- the same local-cell -> global-tile -> pixel
## conversion _stamp_house's own door_position already uses. Pure and
## deterministic: the same house (same pieces/origin) always yields the
## same window positions, so a caller can light every real window a house
## was actually built with, and never one that isn't there.
func _window_positions(pieces: Dictionary, origin_tile: Vector2i, tile_size: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for cell in pieces:
		if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_WINDOW:
			var global_cell: Vector2i = origin_tile + cell
			positions.append(Vector2((global_cell.x + 0.5) * tile_size, (global_cell.y + 0.5) * tile_size))
	return positions


## The upper storey's twin of _window_positions, restricted to the windows
## that are actually visible from outside and placed where they are
## actually drawn: from a bird's-eye view an upper storey is only ever its
## facade band (HouseBlueprint._facade_cells' own southernmost-per-column
## rule), painted one row UP over the roof's front row -- see EarthChunk
## Manager._paint_upper_floor and docs/concept/building.md "How a house
## reads from above", point 5. Its side/back windows are under the roof from
## outside exactly like the ground floor's own, so they get no exterior
## light at all (the ground floor's are merely harmless under the roof;
## up here a light would have to draw ABOVE the roof to reach the facade
## layer, and would then glow straight through it).
func _upper_facade_window_positions(upper_pieces: Dictionary, origin_tile: Vector2i, tile_size: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var facade := _house_blueprint._facade_cells(upper_pieces)
	for cell in upper_pieces:
		if not facade.has(cell) or BuildingPiece.category_of(upper_pieces[cell]) != BuildingPiece.CATEGORY_WINDOW:
			continue
		var lit_cell: Vector2i = origin_tile + cell + Vector2i(0, -1)
		positions.append(Vector2((lit_cell.x + 0.5) * tile_size, (lit_cell.y + 0.5) * tile_size))
	return positions


## The settlement's shared well/stall/gate, a merchant's personal trading
## stand, and a farmer/blacksmith/fisher/herbalist's own workspot prop --
## previously all invisible positions NPC schedules walked to, now real,
## visible props. Tagged with its own `landmark_id` as node metadata so a
## caller (chiefly tests, since several distinct landmark kinds can now
## exist side by side in the same spawned list) can tell exactly which prop
## a given node is without resorting to comparing raw positions.
func _build_landmark(landmark_id: String, position: Vector2, parent: Node2D) -> Sprite2D:
	var landmark := Sprite2D.new()
	landmark.texture = _landmark_sprite.generate_texture(landmark_id)
	landmark.set_meta("landmark_id", landmark_id)
	# Art is authored DETAIL_MULTIPLIER times oversized for pixel detail;
	# scaling it back keeps the world footprint unchanged (see
	# docs/concept/art_resolution.md).
	landmark.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	landmark.position = position
	var size: Vector2i = ProceduralLandmarkSprite.SIZES.get(landmark_id, Vector2i(20, 20))
	landmark.add_child(_drop_shadow.make_shadow(int(size.x * 0.8), size.y * 0.5 - 1.0))
	parent.add_child(landmark)
	return landmark


## A small warm glow over one real stamped window, built only when
## is_night(sun_elevation_deg) is true for the current spawn_village call
## (see that loop) -- tagged "window_light" the same landmark_id-metadata
## way _build_landmark tags its own sprites, so a caller (chiefly tests) can
## tell a night light apart from every other spawned prop.
##
## `z_index` defaults to the ordinary entity draw order every ground-floor
## window light has always used; an upper storey's own lights pass
## UPPER_WINDOW_LIGHT_Z_INDEX (see that constant for why they need it).
func _build_window_light(position: Vector2, tile_size: int, parent: Node2D, z_index: int = 0) -> Sprite2D:
	var light := Sprite2D.new()
	light.texture = _window_light_texture(tile_size)
	light.set_meta("landmark_id", "window_light")
	light.position = position
	light.z_index = z_index
	parent.add_child(light)
	return light


## A small solid square of warm lamplight, sized off the real world tile
## size (not ProceduralHouseSprite's own unrelated authored-pixel-art scale
## -- this overlay has to line up with a REAL stamped window tile, not a
## whole decorative house sprite). Cached per tile_size, the same "generate
## once, reuse the ImageTexture" shape DropShadow._texture_for already uses
## for its own per-width shadow cache.
func _window_light_texture(tile_size: int) -> ImageTexture:
	if _window_light_texture_cache.has(tile_size):
		return _window_light_texture_cache[tile_size]
	var size := maxi(1, int(tile_size * _WINDOW_LIGHT_SIZE_FRACTION))
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(_WINDOW_LIGHT_COLOR)
	var texture := ImageTexture.create_from_image(image)
	_window_light_texture_cache[tile_size] = texture
	return texture


## Each villager gets a personal workspot south of their own house, for
## occupations whose work tag isn't one of the settlement's 3 shared
## landmarks (see NpcMarker._resolve_location, and this file's own
## WORK_LOCATION_BY_OCCUPATION-driven prop spawning in spawn_village).
## Houses now vary in size per-villager (see HouseBlueprint.BLUEPRINT_IDS),
## so unlike the original fixed 5x4 box this offset is no longer guaranteed
## to clear every possible house footprint -- fine for a decorative prop a
## couple tiles from a door, not attempted as a hard collision guarantee the
## way house placement's own water-avoidance is.
const _WORKSPOT_OFFSET_TILES := 4.0


## `home_position` is this villager's own house's DOOR position (see
## _stamp_house) -- not a house-anchor point -- so a villager standing at
## home is standing somewhere it could actually have walked to. `world` is
## forwarded into NpcMarker.setup so villagers are water-aware (swim
## animation) exactly like the player and wild creatures -- previously
## nothing passed it through, so a villager's walk cycle never left WALKING
## even while crossing water.
func _build_npc(
	settlement: Dictionary, index: int, home_position: Vector2, tile_size: int, parent: Node2D, world = null, market = null
) -> NpcMarker:
	var identity = settlement.npcs[index]

	var marker := NpcMarker.new()
	marker.identity = identity
	marker.home_position = home_position
	marker.workspot_position = home_position + Vector2(0, _WORKSPOT_OFFSET_TILES * tile_size)
	marker.landmarks = settlement.landmarks
	marker.position = home_position
	if world != null:
		marker.setup(world, tile_size)
	if market != null:
		marker.setup_economy(market)

	# Villagers use the SAME CharacterView the player does, rather than a
	# hand-assembled torso-plus-head. The old version had neither legs nor
	# arms (reported: "npcs have no legs") and carried its own size
	# constants, which had silently fallen out of sync with CharacterView's
	# and missed the art-resolution pass entirely. Sharing the view means
	# body proportions, resolution and walk animation can only ever come
	# from one place.
	# CharacterView.BODY_SIZE is the pre-shrink world size -- CharacterView
	# itself now scales down further to CharacterView.SCALE (2/3 of a tree's
	# height, see its own doc comment), so the shadow has to be sized off
	# that same scale or it renders oversized relative to the now-smaller
	# villager standing on it.
	marker.add_child(_drop_shadow.make_shadow(
		int(CharacterView.BODY_SIZE.x * 0.9 * CharacterView.SCALE),
		CharacterView.BODY_SIZE.y * 0.5 * CharacterView.SCALE - 1.0
	))
	# The marker must be in the tree BEFORE the view is dressed: CharacterView
	# reaches its part sprites through @onready refs, which stay null until
	# the node enters the tree.
	parent.add_child(marker)

	var view := CharacterViewScene.instantiate()
	marker.add_child(view)
	view.apply_appearance(_appearance.appearance_for(identity.occupation, identity.seed_value))
	marker.bind_character_view(view)
	return marker
