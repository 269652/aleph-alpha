extends RefCounted

## What rock the bedrock actually is, at province scale (see
## docs/concept/underground.md "Lithology: caves need the right rock").
##
## This is the first control on the whole underground: a solutional cave
## system can only exist where the rock DISSOLVES, so lithology decides
## which regions of the planet can have caves under them at all -- the
## same role BiomeClassifier plays for what grows on top.
##
## Deterministic per PROVINCE, not per tile: real lithological provinces
## are regional (tens of km), and a cave system chopped up by per-tile
## noise would not be a cave system. Same coordinate-hash idiom
## StonePlacement/OrePlacement/Strata already use, re-keyed to a
## province-sized cell.
##
## Also the honest answer to stone.md's open "stone type varying by biome"
## item: the real control is lithology, not biome -- limestone country is
## limestone country whether forest or grassland grows on top of it.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const ROCK_LIMESTONE := "limestone"
const ROCK_DOLOMITE := "dolomite"
const ROCK_GYPSUM := "gypsum"
const ROCK_BASALT := "basalt"
const ROCK_SANDSTONE := "sandstone"
const ROCK_SHALE := "shale"
const ROCK_GRANITE := "granite"
const ROCK_GNEISS := "gneiss"

const ROCK_TYPES: Array[String] = [
	ROCK_LIMESTONE, ROCK_DOLOMITE, ROCK_GYPSUM, ROCK_BASALT,
	ROCK_SANDSTONE, ROCK_SHALE, ROCK_GRANITE, ROCK_GNEISS,
]

## Soluble in carbonic acid -- the rocks real karst forms in.
const CARBONATES: Array[String] = [ROCK_LIMESTONE, ROCK_DOLOMITE]

## Soluble without needing CO2 at all, and far faster -- real gypsum karst
## (Ukraine's Optymistychna is the world's longest gypsum cave).
const EVAPORITES: Array[String] = [ROCK_GYPSUM]

## Basement rock, exposed by real orogeny.
const CRYSTALLINE: Array[String] = [ROCK_GRANITE, ROCK_GNEISS]

## Clastic sedimentary cover, the bulk of a low-relief platform.
const CLASTIC: Array[String] = [ROCK_SANDSTONE, ROCK_SHALE]

## One degree of latitude is ~111km; EarthChunkGenerator.TILES_PER_DEGREE
## is 111.0, so a tile is ~1km. Restated here rather than preloaded so a
## tiny pure classifier does not pull in the whole world-gen pipeline (and
## cannot form a cycle once the cave stack calls back into it); the
## agreement is pinned by test_km_per_tile_agrees_with_the_world_generator_scale.
const KM_PER_DEGREE := 111.0
const KM_PER_TILE := 1.0

## How wide a lithological province is. Real mappable formation outcrops
## are regional rather than local; 40km is squarely in that "tens of km"
## band and is what keeps a cave system inside one rock type.
const PROVINCE_KM := 40.0
const PROVINCE_TILES := int(PROVINCE_KM / KM_PER_TILE)

## Carbonate rocks crop out over 15.2% of the global ice-free continental
## surface -- Goldscheider et al. (2020), World Karst Aquifer Map,
## Hydrogeology Journal. This is the single measured number the whole
## underground's availability rests on.
const GLOBAL_CARBONATE_SHARE := 0.152
const LIMESTONE_SHARE := 0.120
const DOLOMITE_SHARE := 0.032  # LIMESTONE_SHARE + DOLOMITE_SHARE == GLOBAL_CARBONATE_SHARE

## Evaporite outcrop is a small but real fraction of continental surface.
const EVAPORITE_SHARE := 0.013

## Volcanic provinces (real flood basalts -- Deccan, Columbia River,
## Siberian Traps) occur at every relief, so this share does not move with
## it either.
const BASALT_SHARE := 0.070

## Everything left over is split between clastic cover and crystalline
## basement BY RELIEF, which is the one thing relief actually controls
## here.
const RELIEF_VARIABLE_SHARE := 1.0 - (GLOBAL_CARBONATE_SHARE + EVAPORITE_SHARE + BASALT_SHARE)

## Real cratonic platforms are buried under sedimentary cover; real
## orogenic belts expose basement. Relief moves the split between those
## two ends and nothing else.
const LOWLAND_CRYSTALLINE_FRACTION := 0.15
const OROGEN_CRYSTALLINE_FRACTION := 0.65

## Shale is the most abundant sedimentary rock on Earth, so it takes the
## larger half of the clastic share.
const SHALE_FRACTION_OF_CLASTIC := 0.60
const GNEISS_FRACTION_OF_CRYSTALLINE := 0.50

## How much of the soluble rock on this planet lies under permeable but
## insoluble cover rather than being exposed at the surface.
##
## This is the one control that decides between Palmer's branchwork and
## his network maze: bare karst concentrates its own rain into point
## recharge through its epikarst, while carbonate buried under permeable
## cover takes genuinely diffuse recharge. "Outcrop" means exposed, so
## exposed karst is the commoner case -- which is also why branchwork
## dominates Palmer's survey.
##
## The least-anchored constant in this stack, and flagged as such rather
## than dressed up: the exposed/covered split of global karst is not a
## figure this project has a single measured source for the way it has
## Goldscheider's 15.2% for carbonate outcrop itself. It is set to land
## the resulting pattern mix near Palmer's own surveyed ~57% branchwork
## within CaveSiting's documented sweep, which is a real measurement but
## one reached through assumptions that sweep names out loud.
const PERMEABLE_COVER_SHARE := 0.32


## Relative dissolution rate, limestone = 1.0. Gypsum's equilibrium
## solubility (~2.4 g/L) is about an order of magnitude above CO2-charged
## limestone (~0.25 g/L); dolomite dissolves about an order of magnitude
## more SLOWLY than calcite, which is why real dolomite terrains have
## smaller, less-integrated cave systems than limestone ones rather than
## no caves at all. Everything else is exactly zero: no solutional cave
## forms in rock that does not dissolve.
const SOLUBILITY := {
	ROCK_GYPSUM: 10.0,
	ROCK_LIMESTONE: 1.0,
	ROCK_DOLOMITE: 0.1,
	ROCK_SANDSTONE: 0.0,
	ROCK_SHALE: 0.0,
	ROCK_GRANITE: 0.0,
	ROCK_GNEISS: 0.0,
	ROCK_BASALT: 0.0,
}


## Which rock the bedrock is at this global tile. `relief` is a [0,1]
## roughness/ruggedness reading (0 = flat platform, 1 = high orogenic
## belt) -- the same real slope field terrain_relief.md already derives.
func rock_at(global_x: int, global_y: int, relief: float) -> String:
	var province_x := _province_index(global_x)
	var province_y := _province_index(global_y)
	var roll := PixelNoise.unit(hash("lithology_province"), province_x, province_y)
	# Relief-INDEPENDENT bands come first on purpose: that is what makes
	# the carbonate share exactly the measured global figure at every
	# relief (real alpine karst is widespread -- carbonate outcrop is not
	# a lowland-only phenomenon), while relief redistributes only the
	# clastic/crystalline remainder behind them.
	if roll < LIMESTONE_SHARE:
		return ROCK_LIMESTONE
	roll -= LIMESTONE_SHARE
	if roll < DOLOMITE_SHARE:
		return ROCK_DOLOMITE
	roll -= DOLOMITE_SHARE
	if roll < EVAPORITE_SHARE:
		return ROCK_GYPSUM
	roll -= EVAPORITE_SHARE
	if roll < BASALT_SHARE:
		return ROCK_BASALT
	roll -= BASALT_SHARE

	var crystalline_fraction := lerpf(
		LOWLAND_CRYSTALLINE_FRACTION, OROGEN_CRYSTALLINE_FRACTION, clampf(relief, 0.0, 1.0)
	)
	var crystalline_share := RELIEF_VARIABLE_SHARE * crystalline_fraction
	var clastic_share := RELIEF_VARIABLE_SHARE - crystalline_share
	if roll < clastic_share:
		var shale_share := clastic_share * SHALE_FRACTION_OF_CLASTIC
		return ROCK_SHALE if roll < shale_share else ROCK_SANDSTONE
	roll -= clastic_share
	var gneiss_share := crystalline_share * GNEISS_FRACTION_OF_CRYSTALLINE
	return ROCK_GNEISS if roll < gneiss_share else ROCK_GRANITE


## Relative dissolution rate for this rock, limestone = 1.0, and exactly
## 0.0 for anything that does not dissolve (including an unknown rock).
func solubility_of(rock: String) -> float:
	return SOLUBILITY.get(rock, 0.0)


## Whether this province's soluble rock lies under permeable insoluble
## cover. Province-scale and deterministic like rock_at, but rolled
## independently of it: cover is a separate depositional history from the
## bedrock's own, so it must not correlate with which rock it sits on.
func has_permeable_cover_at(global_x: int, global_y: int) -> bool:
	var province_x := _province_index(global_x)
	var province_y := _province_index(global_y)
	var roll := PixelNoise.unit(hash("lithology_cover"), province_x, province_y)
	return roll < PERMEABLE_COVER_SHARE


func _province_index(tile: int) -> int:
	return int(floor(float(tile) / float(PROVINCE_TILES)))
