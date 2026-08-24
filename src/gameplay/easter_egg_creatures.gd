extends RefCounted

## Pure decision logic for docs/concept/easter_eggs.md's real, spawnable
## coordinate-triggered creature cameos assigned to this stage: Squallmaw
## (Bermuda Triangle), Coilnecca (Loch Ness), and Champ (Lake Champlain).
##
## Unlike EasterEggSightings (Mothman/Jersey Devil/Roswell/Area 51 -- brief
## flavor-text-only glimpses with zero mechanical presence and no
## persistent sighting object), these three are real, spawnable species --
## see CreatureInfo/AnimalAnatomy/ProceduralAnimalSprite's squallmaw/
## coilnecca/champ entries. A hit here names WHICH species the caller
## should actually spawn into the world (scenes/world.gd, via
## CreatureRenderer.spawn_single, the exact same API the debug /spawn
## command and every other on-demand spawn already use), not a line of
## text -- so the "message" this module returns is the species id itself.
##
## Same reverse-geo-lookup + radius + per-check-roll shape as
## EasterEggSightings, reusing GeoCoordinates identically -- see that
## module's own doc comment for the shared design rationale (chance_per_
## check is a per-CHECK probability, not a per-second one; radius_km is
## deliberately small, a pinned-to-a-point cameo, not a regional effect).
##
## Scope note (docs/progress.md has the full writeup): this ties Squallmaw/
## Coilnecca/Champ into a REAL, live, real-time coordinate check + spawn --
## not into EarthChunkManager's deterministic per-chunk population
## promotion, which is a fundamentally different spawn mechanism (a fixed
## population computed once at chunk generation, keyed by biome, not a
## rare live event) and out of scope for a coordinate-pinned cameo. Once
## spawned, each is an ordinary CreatureMarker like anything else -- no
## despawn timer, no special persistence -- so "fight, flee, be tamed"
## (Squallmaw's own doc line) is true by construction, the same way every
## other spawned creature already works.

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

## id -> {latitude, longitude, radius_km, chance_per_check}. id is also the
## exact CreatureInfo/AnimalAnatomy species id spawn_single should use.
##
## chance_per_check values are first-pass placeholders (same "no real
## playtesting data yet" situation as EasterEggSightings' own SIGHTINGS
## table), pinned as named constants and exercised by relative property
## tests in test_easter_egg_creatures.gd (Squallmaw is tuned far rarer than
## every other coordinate-triggered cameo in the project -- the doc's own
## "wildly lower rate than even the rarest ordinary predator" -- rather
## than eyeballed inline). radius_km is deliberately small for the two lake
## cameos (a specific lake); Squallmaw's is wider since the Bermuda
## Triangle coordinate sits in open ocean with no landmark to pin against,
## not because it's meant to be easier to find -- the rarity comes entirely
## from chance_per_check.
const SIGHTINGS := {
	"squallmaw": {
		"latitude": 25.5,
		"longitude": -71.0,
		"radius_km": 30.0,
		"chance_per_check": 0.0004,
	},
	"coilnecca": {
		"latitude": 57.3,
		"longitude": -4.4,
		"radius_km": 6.0,
		"chance_per_check": 0.006,
	},
	"champ": {
		"latitude": 44.5,
		"longitude": -73.3,
		"radius_km": 6.0,
		"chance_per_check": 0.006,
	},
}

var _geo := GeoCoordinates.new()


## Every registered creature id -- also its real CreatureInfo/AnimalAnatomy
## species id (see test_every_registered_id_is_a_real_spawnable_species).
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
## unknown id rather than an error -- an unrecognized creature is simply
## never in range.
func is_in_range(id: String, tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	if not SIGHTINGS.has(id):
		return false
	var def: Dictionary = SIGHTINGS[id]
	return _geo.tile_is_within_radius(
		tile_x, tile_y, def.latitude, def.longitude, def.radius_km, world_width, world_height
	)


## One check of creature `id` against a tile+roll: `id` itself (the species
## to spawn) if the tile is in range AND `roll` (a caller-supplied [0, 1)
## draw -- pass randf() in real play, a fixed value in tests) clears the
## creature's own chance_per_check; "" otherwise, including for an unknown
## id.
func check_one(
	id: String, tile_x: int, tile_y: int, world_width: int, world_height: int, roll: float
) -> String:
	if not SIGHTINGS.has(id):
		return ""
	if not is_in_range(id, tile_x, tile_y, world_width, world_height):
		return ""
	var def: Dictionary = SIGHTINGS[id]
	if roll >= float(def.chance_per_check):
		return ""
	return id
