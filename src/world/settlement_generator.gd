extends RefCounted

## Procedural village placement (docs/concept/npc.md: "Similar to minecraft
## there should be procedural generated NPC populations; villages and so").
## Sparse and deterministic per chunk -- same "regenerates identically on
## revisit" philosophy as TreeRenderer/CreatureRenderer -- gated to habitable
## biomes, with a small fixed roster of NpcIdentity villagers and
## non-overlapping house anchor positions arranged around 3 shared landmarks
## every settlement always has (well/stall/gate), so an NpcPlanner schedule
## referencing any of those tags always resolves to a real place.
##
## `house_positions` are ANCHOR points, one per villager -- VillageRenderer
## is what turns each anchor into a real multi-tile HouseBlueprint structure
## (walls, floor, door, roof, actually stamped into the chunk), centred
## roughly on the anchor. This module only decides WHERE that anchor sits,
## not what gets built there.

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

## Fixed villager count per settlement -- small and constant for now rather
## than population-simulated (see docs/concept/npc.md's lifecycle/aging,
## still unstarted).
const POPULATION := 5

## Roughly 1-in-this-many habitable chunks hosts a settlement -- sparse, so
## villages read as discoverable landmarks rather than carpeting the map.
const SETTLEMENT_CHANCE_DENOMINATOR := 30

## Villages need dry, walkable, open land -- never afloat, on a cliff
## face, or (docs/concept/building.md: "houses / buildings... not in the
## forest") standing in the forest itself, where the sheer density of real
## trees would leave a village perpetually fighting to find any footprint
## the NPCs haven't already had to fell first (see EarthChunkManager.
## is_buildable_terrain_at/VillageRenderer._find_dry_origin for the SAME
## rule applied per-tile to individual scattered trees in an otherwise
## habitable biome).
const _UNINHABITABLE_BIOMES := {"ocean": true, "mountain": true, "forest": true}

## Houses ring the village center at roughly this radius -- wide enough that
## each house's real footprint (see VillageRenderer._HOUSE_FOOTPRINT, 5x4
## tiles) sits apart as a settlement rather than a huddle of overlapping
## structures. Each house also gets a small seeded radius/angle jitter so the
## ring reads as grown, not compass-drawn.
const _HOUSE_RING_RADIUS_TILES := 9
const _HOUSE_RADIUS_JITTER_TILES := 1.5
const _HOUSE_ANGLE_JITTER := 0.22

## The 3 shared landmarks (well, stall, gate) are placed by VillageLayout.
## skeleton -- on the plaza and at the street's entrance -- see
## generate_settlement below.


## Deterministic per chunk_coord: whether this chunk hosts a settlement.
## dominant_biome gates habitability -- ocean/mountain chunks never do,
## regardless of the roll (see BiomeClassifier.dominant_biome for how a
## chunk's single dominant biome is derived).
func has_settlement_at(chunk_coord: Vector2i, dominant_biome: String) -> bool:
	if _UNINHABITABLE_BIOMES.has(dominant_biome):
		return false
	var roll := absi(hash("%d_%d_settlement" % [chunk_coord.x, chunk_coord.y])) % SETTLEMENT_CHANCE_DENOMINATOR
	return roll == 0


## Builds this chunk's settlement: POPULATION villagers (deterministic
## NpcIdentity per index), one house anchor position each arranged in a ring
## around the chunk's center, and the 3 shared landmark positions. Callers
## should only call this after confirming has_settlement_at.
func generate_settlement(
	chunk_coord: Vector2i, chunk_origin_tiles: Vector2i, chunk_size: int, tile_size: int
) -> Dictionary:
	# The well, stall and gate stand where the village's own street plan
	# puts them -- on the plaza, at the street's entrance (see
	# VillageLayout.skeleton) -- so the props and the paving agree, rather
	# than at fixed offsets from the chunk centre that ignore the street.
	var skeleton := VillageLayout.skeleton(chunk_size, VillageLayout.seed_for(chunk_coord))
	var landmarks := {}
	for landmark in skeleton["landmarks"]:
		var cell: Vector2i = chunk_origin_tiles + skeleton["landmarks"][landmark]
		landmarks[landmark] = Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
	# The fallback ring (a villager whose plot fits nowhere keeps it, see
	# VillageRenderer) is centred on the square's own well, so it still
	# reads as "around the village square".
	var center_pos: Vector2 = landmarks["well"]

	var house_positions: Array[Vector2] = []
	var npcs: Array[NpcIdentity] = []
	for i in POPULATION:
		var seed_value := hash("%d_%d_villager_%d" % [chunk_coord.x, chunk_coord.y, i])
		npcs.append(NpcIdentity.new(seed_value))
		house_positions.append(_house_position(chunk_coord, center_pos, tile_size, i))

	return {"house_positions": house_positions, "landmarks": landmarks, "npcs": npcs}


## A ring position with a small deterministic per-house radius/angle jitter
## (seeded per chunk+index) so the layout reads organic while staying exactly
## reproducible on revisit.
func _house_position(chunk_coord: Vector2i, center_pos: Vector2, tile_size: int, index: int) -> Vector2:
	var base_angle := float(index) / float(POPULATION) * TAU
	var angle := base_angle + (_unit_float(chunk_coord, index, "angle") - 0.5) * 2.0 * _HOUSE_ANGLE_JITTER
	var radius_tiles := _HOUSE_RING_RADIUS_TILES + (_unit_float(chunk_coord, index, "radius") - 0.5) * 2.0 * _HOUSE_RADIUS_JITTER_TILES
	return center_pos + Vector2(cos(angle), sin(angle)) * radius_tiles * tile_size


func _unit_float(chunk_coord: Vector2i, index: int, salt: String) -> float:
	return float(absi(hash("%d_%d_house_%d_%s" % [chunk_coord.x, chunk_coord.y, index, salt])) % 10000) / 10000.0
