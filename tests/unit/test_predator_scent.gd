extends GutTest

## A predator that hunts you by nose (docs/concept/olfaction.md, "The wind
## carries it" -> the hunting side).
##
## The wind already made the PLAYER smellable, and prey already flees earlier
## when the player is upwind of it. That made the wind a tool: something the
## player manages to get closer to a deer. This is the other edge of the same
## blade -- a wolf downwind of you knows you are there long before you can see
## it, so the wind is an EXPOSURE as well as an advantage.

const PredatorScent = preload("res://src/gameplay/predator_scent.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const WindScent = preload("res://src/world/wind_scent.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")


# -- who hunts by nose -------------------------------------------------------


func test_a_wolf_hunts_by_nose():
	assert_true(PredatorScent.hunts_by_scent("wolf"))


## A grazer is not hunting anybody. It still SMELLS the player -- that is what
## makes it flee early -- but smelling and stalking are different verbs.
func test_a_grazer_does_not_hunt_by_nose():
	assert_false(PredatorScent.hunts_by_scent("horse"))


func test_something_with_no_nose_does_not_hunt_by_nose():
	assert_false(PredatorScent.hunts_by_scent("not_an_animal"))


# -- how far it reaches ------------------------------------------------------


## The mechanic is dead unless the nose beats the eyes: if a predator could
## only smell you as far as it can see you, nothing would ever change. Pinned
## against CreatureMarker.SENSE_RADIUS, the radius it acquires threats at.
func test_a_nose_reaches_further_than_an_eye():
	var sight_tiles := CreatureMarker.SENSE_RADIUS / float(TerrainRenderer.TILE_SIZE)
	assert_gt(PredatorScent.HUNT_RANGE_TILES, sight_tiles)


## ...but not so far that a predator anywhere on the map knows about you.
## Bracketed against the scent field's own maximum reach.
func test_a_nose_does_not_reach_across_the_world():
	assert_lte(PredatorScent.HUNT_RANGE_TILES, Olfaction.MAX_RANGE_TILES)



func test_a_wolf_acquires_you_inside_its_range():
	assert_true(PredatorScent.acquires("wolf", PredatorScent.HUNT_RANGE_TILES * 0.5))


func test_a_wolf_does_not_acquire_you_beyond_it():
	assert_false(PredatorScent.acquires("wolf", PredatorScent.HUNT_RANGE_TILES * 2.0))


func test_a_grazer_never_acquires_you_however_close():
	assert_false(PredatorScent.acquires("horse", 0.0))


# -- and the wind is the whole point -----------------------------------------


## The claim that makes this worth building: standing downwind of a wolf is
## safe at a distance that standing upwind of it is not. Uses the same
## WindScent.effective_distance_tiles the prey side already uses, so the two
## halves of the mechanic cannot disagree about which way the wind blows.
func test_the_same_gap_is_safe_upwind_and_deadly_downwind():
	var wind := Vector2.RIGHT
	var strength := WindScent.advection_strength(WindScent.STORM_WIND_STRENGTH)
	var tile := float(TerrainRenderer.TILE_SIZE)
	var gap := PredatorScent.HUNT_RANGE_TILES * 0.9 * tile
	var player := Vector2.ZERO
	# The wolf sits where the player's scent is carried TO.
	var downwind_wolf := player + wind * gap
	var upwind_wolf := player - wind * gap
	var downwind_tiles := WindScent.effective_distance_tiles(
		player, downwind_wolf, wind, strength, tile
	)
	var upwind_tiles := WindScent.effective_distance_tiles(player, upwind_wolf, wind, strength, tile)
	assert_true(PredatorScent.acquires("wolf", downwind_tiles), "a downwind wolf missed you")
	assert_false(PredatorScent.acquires("wolf", upwind_tiles), "an upwind wolf smelled you anyway")
