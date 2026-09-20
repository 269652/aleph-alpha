extends RefCounted

## Turns what this world actually measures -- real slope, biome, ocean
## distance -- into the inputs CaveSiting needs (see
## docs/concept/underground.md).
##
## Pure translation, deliberately kept out of EarthChunkManager so it can
## be tested against known readings rather than against whatever terrain
## happens to generate. Nothing here decides anything about caves; it only
## restates the world's own measurements in the units Palmer's model asks
## for.

const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const CaveRecharge = preload("res://src/world/cave_recharge.gd")
const Lithology = preload("res://src/world/lithology.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## The slope at which terrain counts as fully orogenic. Reuses the world's
## own mountain threshold rather than inventing a second steepness
## constant -- the same "no unexplained coincidence" discipline
## biome_classifier.gd itself follows.
const OROGEN_SLOPE_DEG := BiomeClassifier.SLOPE_MOUNTAIN_THRESHOLD_DEG

## Restated from CaveRecharge so the biome table below can be read against
## the threshold it actually has to clear.
const FLOODWATER_SEASONALITY_REFERENCE := CaveRecharge.FLOODWATER_SEASONALITY_THRESHOLD

## Precipitation seasonality by biome -- how strong a wet/dry contrast the
## climate has, which is what turns ordinary sinkhole recharge into
## episodic floodwater injection. Grounded in real precipitation regimes:
##
## - grassland (savanna/steppe) is the classic strong wet/dry contrast,
##   and the strongest here.
## - desert rainfall is sparse but genuinely episodic -- real desert storms
##   deliver a year's water in hours, which is floodwater recharge exactly.
## - mountain and tundra both run on a real snowmelt pulse: one large,
##   concentrated annual recharge event.
## - forest is temperate and moderate.
## - rainforest (tropical wet) is the steadiest climate there is.
## - ocean has no cave under it to recharge.
const SEASONALITY_BY_BIOME := {
	"grassland": 0.75,
	"desert": 0.60,
	"mountain": 0.55,
	"tundra": 0.50,
	"forest": 0.35,
	"rainforest": 0.20,
	"ocean": 0.0,
}

## Seasonality for a biome this world does not know. Deliberately steady
## rather than extreme: an unknown climate should fall back to ordinary
## sinkhole recharge, not conjure floodwater mazes.
const DEFAULT_SEASONALITY := 0.30

## How much of the planet sits over rising sulfidic or thermal fluids.
##
## PLACEHOLDER, and flagged as one rather than presented as a measurement:
## this world has no tectonics or heat-flow field to read, so hypogenic
## settings are rolled per province at a share that keeps them the real
## minority they are among cave systems. When a real heat-flow signal
## exists this function should read it instead, and the roll should go.
const HYPOGENIC_PROVINCE_SHARE := 0.08

## What an ocean scan that found nothing should report. Far enough inland
## that CaveRecharge's mixing zone cannot possibly apply -- an unfound
## coast must read as inland, or every inland cave would come out a
## coastal sponge.
const NO_COAST_FOUND_KM := 100000.0


## Real slope in degrees, as [0,1] relief.
func relief_from_slope_degrees(slope_degrees: float) -> float:
	if OROGEN_SLOPE_DEG <= 0.0:
		return 0.0
	return clampf(slope_degrees / OROGEN_SLOPE_DEG, 0.0, 1.0)


## Precipitation seasonality for a biome, as [0,1].
func seasonality_for_biome(biome: String) -> float:
	return SEASONALITY_BY_BIOME.get(biome, DEFAULT_SEASONALITY)


## How close rising sulfidic/thermal fluids are, as [0,1]. See
## HYPOGENIC_PROVINCE_SHARE -- this is a placeholder for a real heat-flow
## reading, not a measurement.
func hydrothermal_proximity_at(global_x: int, global_y: int) -> float:
	var province_x := int(floor(float(global_x) / float(Lithology.PROVINCE_TILES)))
	var province_y := int(floor(float(global_y) / float(Lithology.PROVINCE_TILES)))
	var roll := PixelNoise.unit(hash("cave_hypogenic_province"), province_x, province_y)
	return 1.0 if roll < HYPOGENIC_PROVINCE_SHARE else 0.0


## A scanned ocean distance in tiles, as real kilometres.
##
## Converted on the MAP scale (~1km/tile, EarthChunkGenerator's own), not
## the play scale CaveNetwork builds passages at (~1.426m/tile). Biomes
## and oceans are map-scale facts; using the play scale here would put
## CaveRecharge's entire 10km mixing zone inside a single tile.
func coast_distance_km(ocean_distance_tiles: float) -> float:
	if not is_finite(ocean_distance_tiles):
		return NO_COAST_FOUND_KM
	return ocean_distance_tiles * Lithology.KM_PER_TILE
