extends RefCounted

## Deterministic mountain-face ore vein placement (see
## docs/concept/terrain_relief.md's "Mountain ore: steepness exposes it").
##
## A separate placement rule from StonePlacement/OrePlacement's flat-ground
## density roll -- mountain biome isn't in StonePlacement.STONE_BIOMES at
## all (no loose-stone/ore cells there today), and even if it were, the
## design explicitly wants vein probability to scale with LOCAL SLOPE, not
## a uniform per-tile chance: a steep, eroded face is more likely to expose
## a seam; a gentler slope accumulates soil/scree that buries one.
##
## Takes slope as an INPUT, not something it computes itself -- pure logic
## stays engine/data-source-free, matching terrain_passability.gd's own
## slope_deg-as-parameter convention, rather than reaching into a real
## elevation source the way terrain_relief.gd itself has to.

const OrePlacement = preload("res://src/world/ore_placement.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

## Below this slope, a mountain face is gentle enough to accumulate soil/
## scree, and a vein essentially never turns up. Reuses
## terrain_passability.gd's own SOFT_THRESHOLD_DEG rather than a separate
## number -- the same line already marking "this reads as a real slope, not
## just ground," not a coincidence.
const MIN_SLOPE_FOR_VEINS_DEG := TerrainPassability.SOFT_THRESHOLD_DEG

## The steepest slope vein chance keeps scaling up to -- beyond this, a
## face is already the sheerest realistic terrain this project models
## (roped-only, see terrain_passability.gd), so chance simply holds at its
## ceiling rather than climbing further. This reuses that exact ceiling
## deliberately: the same steepness that makes a face hard to cross is what
## makes it likely to hold ore -- one shared quantity, two consequences,
## not two numbers independently tuned to agree by luck.
const MAX_SLOPE_FOR_SCALING_DEG := TerrainPassability.HARD_THRESHOLD_WITH_ROPE_DEG

## Vein chance at MAX_SLOPE_FOR_SCALING_DEG and beyond -- real erosion
## exposes a lot on the sheerest faces, but a third of cells is still a
## landmark find, not wallpaper.
const MAX_VEIN_CHANCE := 0.35

var _ore_placement := OrePlacement.new()


## Chance [0, MAX_VEIN_CHANCE] a mountain cell at this slope holds a vein --
## zero below MIN_SLOPE_FOR_VEINS_DEG, rising linearly to the ceiling by
## MAX_SLOPE_FOR_SCALING_DEG, and held there beyond it.
func vein_chance_for_slope(slope_deg: float) -> float:
	if slope_deg <= MIN_SLOPE_FOR_VEINS_DEG:
		return 0.0
	var t := clampf(
		(slope_deg - MIN_SLOPE_FOR_VEINS_DEG) / (MAX_SLOPE_FOR_SCALING_DEG - MIN_SLOPE_FOR_VEINS_DEG),
		0.0, 1.0
	)
	return t * MAX_VEIN_CHANCE


## Whether a vein sits at this global tile, given its real local slope.
## Deterministic per position: the same (x, y, slope) always rolls the same
## answer, and different positions at the same slope roll independently --
## same coordinate-hash idiom every other placement decision in this
## project already uses (see StonePlacement.has_stone_at).
func has_vein_at(global_x: int, global_y: int, slope_deg: float) -> bool:
	var chance := vein_chance_for_slope(slope_deg)
	if chance <= 0.0:
		return false
	var roll := float(absi(hash("%d_%d_mountain_vein" % [global_x, global_y])) % 10000) / 10000.0
	return roll < chance


## Ore type/seed reuse OrePlacement's own derivation exactly rather than
## rolling a separate channel -- mountain and flat-ground ore cells are
## mutually exclusive biomes (a tile is never both), so there's no real
## collision risk to guard against, and sharing the derivation is simpler.
func ore_type_at(global_x: int, global_y: int) -> String:
	return _ore_placement.ore_type_at(global_x, global_y)


func seed_at(global_x: int, global_y: int) -> int:
	return _ore_placement.seed_at(global_x, global_y)
