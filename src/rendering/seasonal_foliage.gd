extends RefCounted

## What the season does to LIVING GREEN -- the ground cover, the tall grass,
## a root crop's tops. IllustratedTree already gives a TREE its season (four
## canopy frames, mapped by meaning); everything underneath it wore high
## summer all year, so forcing winter produced bare trees standing on a
## bright green lawn -- the season was something that happened to the crowns
## and to nothing else. This is the same clock, read by the flat green
## instead of by the crown. See docs/concept/seasons.md.
##
## A TINT rather than four sets of art, and deliberately so: the ground cover
## is painted into a disk-cached atlas keyed by ONE version string (see
## TerrainAtlasCache / TerrainRenderer.ATLAS_VERSION), with no per-tile
## invalidation. One atlas per season would mean four full bakes of a ~5MB
## image plus a whole TileSet rebuild -- one of them landing mid-session at
## the exact moment the season turned, which is precisely the boot cost the
## cache exists to avoid. A multiplier pushed into the shader already sitting
## on the terrain layer costs one uniform write and invalidates nothing.
##
## Pure and engine-free: this says what a season multiplies green by.
## Applying it is the shader's job -- the same split SeasonTransition already
## draws between "which two seasons and how far" and "blend the art".

const SeasonTransition = preload("res://src/world/season_transition.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")


## What a GRASSLAND TILE should look like in each season -- real colours for
## a real surface, from which the multiplier below is derived. Stated this
## way round (a target picture, not a tuned gain) so the numbers are about
## something observable instead of about arithmetic (CLAUDE.md), and pinned
## by test_seasonal_foliage.gd against the properties that make each season
## that season rather than against the numbers themselves.
##
## - summer is BASE_COLORS["grassland"] itself, so summer comes out as the
##   exact identity multiplier and high summer stays pixel-for-pixel the
##   picture that already shipped.
## - spring is NEW GROWTH: lighter and brighter than mature turf, the
##   yellow-green of a first flush rather than a deeper established sward.
## - autumn is SENESCENCE: chlorophyll breaks down before the leaf dies, so
##   the carotenoids underneath show through and a meadow swings toward gold
##   while still holding real colour.
## - winter is DEAD THATCH: chlorophyll gone entirely, so the surface stops
##   being green-dominant at all and reads as a drab, desaturated tan-grey --
##   not a dimmer lawn, which is the specific thing that looked wrong.
const GRASSLAND_BY_SEASON := {
	"spring": Color(0.45, 0.82, 0.28),
	"summer": Color(0.36, 0.74, 0.22),
	"autumn": Color(0.54, 0.60, 0.23),
	"winter": Color(0.45, 0.43, 0.33),
}

## What an unrecognised season falls back to. Summer, for exactly
## IllustratedTree's own fallback reason: unexpectedly green is a lawn,
## unexpectedly brown reads as dead ground.
const FALLBACK_SEASON := "summer"

## How hard a pixel's own greenness gates the tint.
##
## MEASURED against the real biome palette, not eyeballed (CLAUDE.md): at 3.0
## every green biome in ProceduralTerrainSprite.BASE_COLORS scores >= 0.85
## (grassland 1.0, forest 1.0, rainforest 0.90 -- the least green of the
## three, which is what actually sets this number) while every non-green one
## scores exactly 0.0 (ocean, desert, mountain and tundra all have a green
## channel at or below their own max(red, blue)). Pinned by
## test_greenness_gain_covers_every_green_biome_and_no_other.
const GREENNESS_GAIN := 3.0

## Guards the componentwise divide below against a zero channel in a future
## palette edit -- a season is a multiplier, and an infinite one is a white
## hole where the meadow was.
const _MIN_CHANNEL := 0.0001

## The multiplier a season applies to a green pixel: this season's grassland
## target divided, channel by channel, by summer's. Derived rather than
## authored, so summer is the identity by construction and every other
## season is exactly "what it takes to turn the shipped grass into that
## season's grass".
static var TINT_BY_SEASON: Dictionary = _build_tints()


static func _build_tints() -> Dictionary:
	var base: Color = GRASSLAND_BY_SEASON[FALLBACK_SEASON]
	var tints := {}
	for season in GRASSLAND_BY_SEASON:
		var target: Color = GRASSLAND_BY_SEASON[season]
		tints[season] = Color(
			target.r / maxf(base.r, _MIN_CHANNEL),
			target.g / maxf(base.g, _MIN_CHANNEL),
			target.b / maxf(base.b, _MIN_CHANNEL)
		)
	return tints


## How green a colour is, 0 (not green at all) to 1 (fully takes the season).
## Green ABOVE its own red and blue, so a blue ocean, tan sand and grey rock
## are untouched by a wash that is only ever about chlorophyll. The GLSL in
## GroundTint/IllustratedGrassPatch is this same expression with
## GREENNESS_GAIN interpolated in, so the two languages cannot drift.
static func greenness_of(color: Color) -> float:
	return clampf((color.g - maxf(color.r, color.b)) * GREENNESS_GAIN, 0.0, 1.0)


## One named season's multiplier, falling back rather than crashing on a name
## no season table knows.
static func tint_for_season(season: String) -> Color:
	return TINT_BY_SEASON.get(season, TINT_BY_SEASON[FALLBACK_SEASON])


## The season's tint at this point in the year, blended across a season turn
## by the SAME SeasonTransition state the tree canopies turn on -- so the
## lawn and the crown above it can never disagree about what month it is.
static func tint_at(year_fraction: float) -> Color:
	var state := SeasonTransition.state_at(year_fraction)
	return tint_for_season(state.from).lerp(tint_for_season(state.to), state.progress)


## Convenience for callers holding the raw world clock (see
## EarthChunkManager.world_age_seconds) rather than a year fraction.
static func tint_for_world_age(elapsed_seconds: float) -> Color:
	return tint_at(SeasonCycle.new().year_fraction(elapsed_seconds))
