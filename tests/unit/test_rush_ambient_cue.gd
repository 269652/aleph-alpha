extends GutTest

## RushAmbientCue (docs/concept/easter_eggs.md's Rush ambient nod): a
## specific, out-of-the-way real-world location that plays a short ambient
## mood cue "on approach." Reuses GeoCoordinates' reverse lookup + radius
## exactly like EasterEggSightings/EasterEggCreatures/EasterEggCreatures
## (see those modules' own doc comments for the shared rationale), but
## unlike every chance_per_check-gated cameo elsewhere in this project,
## LOCATION alone is the whole trigger here -- no rarity roll -- matching
## the doc's own "plays... on approach" wording (not "sometimes, rarely, on
## approach").

const RushAmbientCue = preload("res://src/gameplay/rush_ambient_cue.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var cue: RushAmbientCue
var world_width: int
var world_height: int


func before_each():
	cue = RushAmbientCue.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_is_in_range_true_at_the_cues_own_tile():
	var tile := cue.tile(world_width, world_height)
	assert_true(cue.is_in_range(tile.x, tile.y, world_width, world_height))


func test_is_in_range_false_far_from_the_cue():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	assert_false(cue.is_in_range(far_tile.x, far_tile.y, world_width, world_height))


func test_cameo_message_is_a_real_nonempty_line():
	assert_true(cue.cameo_message().length() > 0)


## Pillar 4 -- description/mood only, never the band's own name (the doc:
## "never an actual cover or sampled riff"; this project also never names
## real bands/works in-game text).
func test_cameo_message_never_names_the_band():
	var message: String = cue.cameo_message().to_lower()
	assert_false(message.contains("rush"))
