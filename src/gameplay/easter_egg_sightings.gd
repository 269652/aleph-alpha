extends RefCounted

## Pure decision logic for docs/concept/easter_eggs.md's real-coordinate
## "pure atmosphere" cameos assigned to this stage: Mothman (Point
## Pleasant), the Jersey Devil (NJ Pine Barrens), and the Roswell/Area 51
## crashed-saucer + "little grey" pair. Zero mechanical weight (the doc's
## design pillar 2) -- every trigger here is a single flavor-text line,
## never a stat, an item, or a fight, and there is deliberately no
## persistent "sighting" object for the player to walk up to: a sighting is
## one stateless decision from (tile, roll), not a spawned entity, so
## "never actually catchable... gone if approached" (the doc's own words
## for Mothman) is true by construction rather than something a despawn-
## on-proximity check has to enforce.
##
## Reuses GeoCoordinates' reverse lookup + radius (tile_for_coordinate/
## tile_is_within_radius) the exact same way scenes/world.gd's own
## SPAWN_LATITUDE/SPAWN_LONGITUDE -> spawn-tile computation already does --
## no new coordinate math, just a small hand-curated table of real-world
## points layered on top.
##
## Deliberately log-line-only (a transient on-screen message), not a
## spawned sprite/Node -- see this stage's task notes, which explicitly
## sanction "a text/log-line-only sighting is also a legitimate, even
## simpler interpretation" for exactly this kind of cameo. A future pass
## could promote the "crashed saucer" landmarks specifically to an actual
## visible static prop (they read as a landmark, not a glimpse) -- left as
## an open follow-up, noted in docs/progress.md.

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

## id -> {latitude, longitude, radius_km, chance_per_check, message[, night_message]}
##
## chance_per_check is a per-CHECK probability, not a per-second one -- how
## often "a check" happens is the caller's call (scenes/world.gd throttles
## this the same way it throttles the hover tooltip, so it isn't tied to
## frame rate). radius_km is deliberately small ("a small radius" per the
## doc) -- these are pinned-to-a-point cameos, not regional effects.
##
## chance_per_check values are first-pass placeholders (this project has no
## real playtesting data on Easter-egg encounter rates to calibrate
## against yet -- same situation as BossAggro.MIN_DAMAGE_FRACTION_OF_MAX_
## HEALTH/spell_cost.gd's MAG_EXP), pinned here as named constants and
## exercised by relative property tests in test_easter_egg_sightings.gd
## (landmarks trigger far more often than fleeting glimpses; the Roswell/
## Area 51 pair stays symmetric) rather than eyeballed inline.
const SIGHTINGS := {
	"mothman": {
		"latitude": 38.85,
		"longitude": -82.13,
		"radius_km": 6.0,
		"chance_per_check": 0.01,
		"message": "Something huge and winged watches you from the tree line -- two points of red light, then it's gone.",
	},
	"jersey_devil": {
		"latitude": 39.7,
		"longitude": -74.5,
		"radius_km": 6.0,
		"chance_per_check": 0.01,
		"message": "A goat-headed shape unfolds leathery wings and slips into the pines.",
		"night_message": "A goat-headed shape unfolds leathery wings and slips into the pines. Something shrieks once, close by, and the woods go silent.",
	},
	"roswell_saucer": {
		"latitude": 33.4,
		"longitude": -104.5,
		"radius_km": 4.0,
		"chance_per_check": 0.6,
		"message": "Scorched earth, and a curved sliver of hull half-buried in the dirt -- not quite like anything that flies.",
	},
	"roswell_grey": {
		"latitude": 33.4,
		"longitude": -104.5,
		"radius_km": 4.0,
		"chance_per_check": 0.008,
		"message": "A small grey figure looks you over. \"You're early,\" it says, and then it simply isn't there.",
	},
	"area51_saucer": {
		"latitude": 37.2,
		"longitude": -115.8,
		"radius_km": 4.0,
		"chance_per_check": 0.6,
		"message": "Behind a sagging fence, a dark disc sits dented in the dust, guarded by absolutely no one.",
	},
	"area51_grey": {
		"latitude": 37.2,
		"longitude": -115.8,
		"radius_km": 4.0,
		"chance_per_check": 0.008,
		"message": "The grey blinks, unbothered by the heat. \"This exhibit is closed,\" it says, and then it's gone.",
	},
}

var _geo := GeoCoordinates.new()


## Every registered sighting id.
func sighting_ids() -> Array:
	return SIGHTINGS.keys()


## The tile `id`'s real-world coordinate corresponds to on a world_width x
## world_height grid, or Vector2i.ZERO for an unknown id.
func tile_for(id: String, world_width: int, world_height: int) -> Vector2i:
	if not SIGHTINGS.has(id):
		return Vector2i.ZERO
	var def: Dictionary = SIGHTINGS[id]
	return _geo.tile_for_coordinate(def.latitude, def.longitude, world_width, world_height)


## True if (tile_x, tile_y) falls within `id`'s radius. False for an
## unknown id rather than an error -- an unrecognized sighting is simply
## never in range.
func is_in_range(id: String, tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	if not SIGHTINGS.has(id):
		return false
	var def: Dictionary = SIGHTINGS[id]
	return _geo.tile_is_within_radius(
		tile_x, tile_y, def.latitude, def.longitude, def.radius_km, world_width, world_height
	)


## One check of sighting `id` against a tile+roll: the flavor message if the
## tile is in range AND `roll` (a caller-supplied [0, 1) draw -- pass
## randf() in real play, a fixed value in tests) clears the sighting's own
## chance_per_check; "" otherwise, including for an unknown id.
func check_one(
	id: String,
	tile_x: int,
	tile_y: int,
	world_width: int,
	world_height: int,
	roll: float,
	is_night: bool = false
) -> String:
	if not SIGHTINGS.has(id):
		return ""
	if not is_in_range(id, tile_x, tile_y, world_width, world_height):
		return ""
	var def: Dictionary = SIGHTINGS[id]
	if roll >= float(def.chance_per_check):
		return ""
	if is_night and def.has("night_message"):
		return def.night_message
	return def.message
