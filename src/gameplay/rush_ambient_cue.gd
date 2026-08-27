extends RefCounted

## "Rush (the band) -- ambient nod" (docs/concept/easter_eggs.md): a
## specific, out-of-the-way location that plays a short ambient mood cue on
## approach. Pinned at a quiet stretch of Canadian Shield wilderness near
## Temagami, Ontario -- real, remote, and a private wink at the band's own
## home country, never named anywhere in-game (pillar 4, "homage over
## reproduction"; also never quotes/samples/covers an actual riff, which
## the doc itself calls out as real copyright territory this project
## shouldn't cross even in homage).
##
## Reuses GeoCoordinates' reverse lookup + radius exactly like
## EasterEggSightings/EasterEggCreatures (see those modules' own doc
## comments for the shared rationale) -- but unlike every chance_per_check-
## gated cameo in this project family, LOCATION ALONE is the whole trigger
## here: the doc says the cue plays "on approach", not "sometimes, rarely,
## on approach", so there is no rarity roll at all -- is_in_range is the
## entire check. The caller (scenes/world.gd) is responsible for firing
## this only once per approach (a simple once-per-session flag, same
## low-risk "no de-duplication guard" scope call EasterEggCreatures' own
## doc comment already makes for its own cameos) rather than replaying it
## every check while the player lingers nearby.
##
## AUDIO SCOPE NOTE: no real composed audio exists in this environment (no
## audio-generation tool was available to this stage) -- CAMEO_MESSAGE below
## is real, original, playable-today flavor text (an on-screen line, the
## exact same "brief banner" shape as EasterEggSightings), but the doc's
## actual ask -- "a short ORIGINAL ambient instrumental cue" -- is a real
## composed piece of music this stage cannot produce. scenes/world.gd's
## wiring leaves an explicit TODO where a real AudioStreamPlayer2D + composed
## .ogg cue would be attached once one exists; see docs/progress.md for the
## same scope note, matching how this project's convention already treats
## "no real art asset for X" (e.g. IllustratedAnimalSprite's own gaps).

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

## A quiet stretch of Canadian Shield wilderness -- real, obscure, "out of
## the way" per the doc's own words. Chosen only for its remoteness; no
## in-game text ever names the country or the association.
const LATITUDE := 47.06
const LONGITUDE := -79.79
## Deliberately small (a pinned-to-a-point cameo, matching the "small
## radius" every other real-coordinate trigger in this doc uses -- see
## EasterEggSightings' own doc comment), not a first-pass placeholder
## needing a rarity-style property test: there is no rarity dimension here
## to tune, only "how close counts as approach", pinned as a plain, small
## constant.
const RADIUS_KM := 3.0

const CAMEO_MESSAGE := "A strange, layered hum drifts from somewhere just out of sight -- oddly rhythmic, as if built from one too many notes to count. By the time you place it, it has already faded."

var _geo := GeoCoordinates.new()


## The tile this cue's location corresponds to on a world_width x
## world_height grid.
func tile(world_width: int, world_height: int) -> Vector2i:
	return _geo.tile_for_coordinate(LATITUDE, LONGITUDE, world_width, world_height)


## True if (tile_x, tile_y) is within RADIUS_KM of the cue's location --
## the entire trigger condition; no roll, unlike every chance_per_check-
## gated cameo elsewhere in this project.
func is_in_range(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return _geo.tile_is_within_radius(
		tile_x, tile_y, LATITUDE, LONGITUDE, RADIUS_KM, world_width, world_height
	)


## The flavor line to show/play when the player approaches.
func cameo_message() -> String:
	return CAMEO_MESSAGE
