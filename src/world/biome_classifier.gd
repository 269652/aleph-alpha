extends RefCounted

const SEA_LEVEL := 0.3
const MOUNTAIN_LEVEL := 0.85
const COLD_TEMPERATURE := 0.25
const HOT_TEMPERATURE := 0.6
const WET_MOISTURE := 0.6

const KNOWN_BIOMES: Array[String] = [
	"ocean", "mountain", "tundra", "forest", "grassland", "rainforest", "desert"
]

## Classifies a map cell into a biome name from its elevation, temperature, and
## moisture, all normalized to [0.0, 1.0]. sea_level/mountain_level default to
## the fictional-noise-tuned constants; callers driving real elevation data
## (a different scale/meaning) pass their own calibrated thresholds.
func classify(
	elevation: float,
	temperature: float,
	moisture: float,
	sea_level: float = SEA_LEVEL,
	mountain_level: float = MOUNTAIN_LEVEL
) -> String:
	if elevation < sea_level:
		return "ocean"
	if elevation >= mountain_level:
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
	return KNOWN_BIOMES.find(candidate) < KNOWN_BIOMES.find(best_biome)
