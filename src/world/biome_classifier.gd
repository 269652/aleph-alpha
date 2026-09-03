extends RefCounted

const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

const SEA_LEVEL := 0.3
const MOUNTAIN_LEVEL := 0.85
const COLD_TEMPERATURE := 0.25
const HOT_TEMPERATURE := 0.6
const WET_MOISTURE := 0.6

## Sentinel for classify()'s optional slope_deg parameter meaning "not
## provided" -- real slope is never negative, so this is an unambiguous
## "omitted" marker. Exposed so a caller building the value up itself (see
## EarthChunkGenerator's own perf-conditional slope sampling) can pass it
## explicitly rather than re-typing the same literal.
const SLOPE_NOT_PROVIDED := -1.0

## Local slope at/beyond which bare rock is exposed regardless of ambient
## temperature/moisture -- real alpine tree-lines: even in a warm, wet
## mountain range, sufficiently steep terrain exposes scree/rock no
## vegetation-based biome can hold. Reuses TerrainPassability's own
## HARD_THRESHOLD_DEG (already real-world-grounded as the
## scrambling/technical-climbing line) rather than a second,
## independently-tuned number -- the same "one shared quantity, not
## coincidence" discipline mountain_ore_placement.gd's own slope thresholds
## already follow.
const SLOPE_MOUNTAIN_THRESHOLD_DEG := TerrainPassability.HARD_THRESHOLD_DEG

const KNOWN_BIOMES: Array[String] = [
	"ocean", "mountain", "tundra", "forest", "grassland", "rainforest", "desert"
]

## Fresh water (docs/concept/hydrology.md "Water kinds"): a lake is a
## depression the drainage bake found, filled to its spill; a river is a
## channel carrying enough routed discharge. Kept OUT of KNOWN_BIOMES on
## purpose -- every renderer atlas, corner family, and spawn table keyed on
## that list keeps working unchanged, and the renderer draws fresh water
## with ocean's art (TerrainRenderer.art_biome). Pinned by
## test_known_biomes_stay_the_land_and_ocean_vocabulary.
const FRESH_WATER_BIOMES: Array[String] = ["lake", "river"]
const WATER_BIOMES: Array[String] = ["ocean", "lake", "river"]
## Every name classify() can return.
const ALL_BIOMES: Array[String] = [
	"ocean", "mountain", "tundra", "forest", "grassland", "rainforest", "desert", "lake", "river"
]


## The one predicate every former `== "ocean"` check reads instead, so
## the water overlay, the swim model, fish, and shore logic all work on
## fresh water with no second implementation.
static func is_water(biome_name: String) -> bool:
	return WATER_BIOMES.has(biome_name)


## Drinkable-by-kind (salinity is a per-cell side field, not a biome).
static func is_fresh_water(biome_name: String) -> bool:
	return FRESH_WATER_BIOMES.has(biome_name)

## Classifies a map cell into a biome name from its elevation, temperature, and
## moisture, all normalized to [0.0, 1.0]. sea_level/mountain_level default to
## the fictional-noise-tuned constants; callers driving real elevation data
## (a different scale/meaning) pass their own calibrated thresholds.
##
## slope_deg is optional (SLOPE_NOT_PROVIDED sentinel by default, so every
## pre-existing caller/test is untouched). When a caller DOES provide a real
## slope reading, a slope at/beyond SLOPE_MOUNTAIN_THRESHOLD_DEG forces
## "mountain" even outside the normal elevation-based mountain band -- real
## alpine tree-lines, the same "steepness exposes rock" logic already
## driving this project's mountain-ore-vein placement, just read from slope
## instead of elevation. Never overrides ocean, which is checked first and
## unconditionally.
##
## water_kind is hydrology's answer for this cell ("lake"/"river" from
## HydrologyField, or "" for dry ground). It is returned ahead of every
## land check, exactly as ocean is, and only ocean outranks it: a lake
## bed is a lake whatever its temperature, moisture, or slope.
func classify(
	elevation: float,
	temperature: float,
	moisture: float,
	sea_level: float = SEA_LEVEL,
	mountain_level: float = MOUNTAIN_LEVEL,
	slope_deg: float = SLOPE_NOT_PROVIDED,
	water_kind: String = ""
) -> String:
	if elevation < sea_level:
		return "ocean"
	if water_kind != "":
		return water_kind
	if elevation >= mountain_level:
		return "mountain"
	if slope_deg >= 0.0 and slope_deg >= SLOPE_MOUNTAIN_THRESHOLD_DEG:
		return "mountain"
	if temperature < COLD_TEMPERATURE:
		return "tundra"
	if temperature < HOT_TEMPERATURE:
		return "forest" if moisture >= WET_MOISTURE else "grassland"
	return "rainforest" if moisture >= WET_MOISTURE else "desert"


## Returns normalized water depth [0.0, 1.0]: 0.0 at/above sea level, 1.0 at
## the ocean floor (elevation 0.0). Used by gameplay's wading/swimming rules.
func depth_at(elevation: float, sea_level: float = SEA_LEVEL) -> float:
	if elevation >= sea_level:
		return 0.0
	return clampf((sea_level - elevation) / sea_level, 0.0, 1.0)


## Returns water depth in real meters: 0.0 at/above sea level, up to
## max_depth_meters at the ocean floor (elevation 0.0). Unlike depth_at()'s
## normalized fraction, this is in physical units gameplay thresholds (wading
## vs. swimming) can be calibrated against regardless of how extreme the
## underlying elevation range is (e.g. real bathymetry's -8000m..+6400m).
func depth_meters_at(elevation: float, sea_level: float, max_depth_meters: float) -> float:
	return depth_at(elevation, sea_level) * max_depth_meters


## Returns the most frequent biome name in a chunk's biome array -- used by
## callers that need a single "dominant biome" identity for an otherwise
## per-cell-granular chunk (e.g. picking a biome-specific creature species
## pool in CreatureRenderer). Ties are broken toward whichever biome appears
## earlier in KNOWN_BIOMES, for determinism, the same tie-break style as
## TerrainRenderer's _is_more_dominant. An empty array has no dominant biome
## and returns "".
func dominant_biome(biome_array: PackedStringArray) -> String:
	if biome_array.is_empty():
		return ""

	var counts := {}
	for biome_name in biome_array:
		counts[biome_name] = counts.get(biome_name, 0) + 1

	var best_biome := ""
	var best_count := -1
	for candidate in counts:
		var count: int = counts[candidate]
		if _is_more_dominant_biome(candidate, count, best_biome, best_count):
			best_biome = candidate
			best_count = count
	return best_biome


func _is_more_dominant_biome(candidate: String, count: int, best_biome: String, best_count: int) -> bool:
	if best_biome == "":
		return true
	if count != best_count:
		return count > best_count
	return ALL_BIOMES.find(candidate) < ALL_BIOMES.find(best_biome)
