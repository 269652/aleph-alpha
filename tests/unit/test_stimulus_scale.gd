extends GutTest

## Everything a creature senses is ranked on ONE scale.
##
## `BehaviorKernel._weight` has two branches: a stimulus carrying `strength`
## is weighted by that raw number, and one without it by
## `Affinity.proximity(distance_in_PIXELS)` = 1/(1+px). Nothing normalised
## between them -- and exactly one producer in the whole game supplied a
## strength on a different curve: `_scan_smoke_stimuli` reported
## `Olfaction.dilution(distance_in_TILES)`, a 0..1 falloff over twenty
## tiles.
##
## Measured consequence, before this file existed: a player standing TWO
## TILES away scores 1/(1+32) = 0.0303, and a campfire ten tiles away scores
## dilution(10) = 0.330 -- the fire wins by **10.9x**, and the crossover is
## at 17.75 tiles. Since the fear wiring is the first rung of the mammal
## ladder and smoke's valence is negative, an aggressive predator two tiles
## from the player resolved that wiring on SMOKE and returned "flee".
##
## So **a lit campfire was a twenty-tile no-predator zone** -- four times
## SENSE_RADIUS, twice CAUTION_RADIUS -- and a player who lit one at their
## camp was untouchable inside 320 px. That is the danger gradient this
## whole overhaul exists to build, switched off by the first fire.

const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")
const Affinity = preload("res://src/gameplay/affinity.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const TILE := float(TerrainRenderer.TILE_SIZE)

## Every gate open, so a test about ranking is not accidentally about gating.
const ALL_OPEN := {"fear": 1.0, "thirst": 1.0, "hunger": 1.0, "courtship": 1.0}


const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")


## A world with exactly one campfire in it, at `_fire`.
class OneFireWorld:
	extends RefCounted
	var fire := Vector2.ZERO

	func campfires_near(_from: Vector2, _range_tiles: float) -> Array:
		return [fire]


## The REAL stimulus the real producer reports for a fire `tiles` away --
## not this file's restatement of it, which is the whole point: a test that
## re-derives the formula it is checking proves nothing.
func _smoke_at(tiles: float) -> Dictionary:
	var world := OneFireWorld.new()
	world.fire = Vector2(tiles * TILE, 0.0)
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new("wolf")
	marker.wander_seed = 5
	marker.position = Vector2.ZERO
	marker.home = Vector2.ZERO
	add_child_autofree(marker)
	marker.setup(world, int(TILE))
	var stimuli: Array = marker._scan_smoke_stimuli()
	assert_eq(stimuli.size(), 1, "precondition: the producer really reported the fire")
	return stimuli[0]


func _smoke_strength(distance_px: float, tiles: float) -> float:
	return Affinity.proximity(distance_px) * Olfaction.dilution(tiles)


func _player_at(tiles: float) -> Dictionary:
	return {"position": Vector2(tiles * TILE, 0.0), "features": {Ethogram.PLAYER: 1.0}}


func _fearful() -> Dictionary:
	return {
		"sensitivity": {Ethogram.PLAYER: 1.0, Ethogram.SMOKE: 1.0},
		"valence": {Ethogram.PLAYER: -1.0, Ethogram.SMOKE: -1.0},
	}


func _fear_wiring() -> Array:
	return [{"gate": "fear", "channels": [Ethogram.PLAYER, Ethogram.SMOKE], "avoid": "flee"}]


# -- the scale ------------------------------------------------------------

## The headline number. A person two tiles away is the most important thing
## in the world; a fire ten tiles away is not.
func test_a_person_two_tiles_away_outranks_a_fire_ten_tiles_away():
	var stimuli := [_player_at(2.0), _smoke_at(10.0)]
	var decision := BehaviorKernel.decide(
		_fear_wiring(), _fearful(), ALL_OPEN, Vector2.ZERO, stimuli
	)
	assert_eq(
		float(decision["stimulus"]["features"].get(Ethogram.PLAYER, 0.0)), 1.0,
		"the fire outranked the person standing next to the animal"
	)


## And at the same distance a thing you can SEE beats a thing you can only
## smell -- which is the whole statement the two branches of `_weight` were
## quietly denying.
func test_at_equal_range_a_person_outranks_a_smell():
	for tiles in [1.0, 3.0, 6.0, 12.0]:
		var stimuli := [_player_at(tiles), _smoke_at(tiles)]
		var decision := BehaviorKernel.decide(
			_fear_wiring(), _fearful(), ALL_OPEN, Vector2.ZERO, stimuli
		)
		assert_eq(
			float(decision["stimulus"]["features"].get(Ethogram.PLAYER, 0.0)), 1.0,
			"a smell outranked a person at %s tiles" % tiles
		)


## Smoke still matters: with nothing else around, a fire is what a creature
## keeps away from. Fixing the scale must not delete the smell.
func test_a_fire_is_still_what_a_creature_avoids_when_nothing_else_is_near():
	var decision := BehaviorKernel.decide(
		_fear_wiring(), _fearful(), ALL_OPEN, Vector2.ZERO, [_smoke_at(5.0)]
	)
	assert_eq(decision["intent"], "flee")


## The real producer, checked NUMERICALLY rather than by reading its source.
## A source test that only asserts the body mentions `Affinity.proximity(`
## would pass for `Affinity.proximity(0.0)` and pin nothing at all.
func test_the_markers_own_smoke_strength_is_on_the_shared_scale():
	for tiles in [1.0, 5.0, 10.0]:
		var stimulus: Dictionary = _smoke_at(tiles)
		assert_almost_eq(
			float(stimulus["strength"]),
			Affinity.proximity(tiles * TILE) * Olfaction.dilution(tiles),
			0.000001,
			"a smell must be the shared proximity ranking, attenuated by its own law"
		)


## And it really is BOTH: drop either factor and the numbers move.
func test_the_smell_is_neither_pure_proximity_nor_pure_dilution():
	var stimulus: Dictionary = _smoke_at(5.0)
	var strength := float(stimulus["strength"])
	assert_lt(strength, Affinity.proximity(5.0 * TILE), "the dilution law still attenuates it")
	assert_lt(strength, Olfaction.dilution(5.0), "and it is ranked by distance like everything else")


## The boldness floor is stated in pixel-proximity units
## (`Ethogram.BOLDEST_FEAR_FLOOR` is `proximity(one tile)`), so a strength
## on any other curve walks straight through it. Before the fix, the boldest
## individual in the game -- for whom a person had to be inside ONE TILE to
## register at all -- still fled a campfire sixteen tiles off.
func test_the_boldest_animal_is_not_frightened_by_a_distant_fire():
	var floor_value := Ethogram.BOLDEST_FEAR_FLOOR
	assert_almost_eq(floor_value, Affinity.proximity(TILE), 0.000001)
	assert_lt(
		float(_smoke_at(10.0)["strength"]), floor_value,
		"a fire ten tiles off must not clear the floor a person one tile off barely does"
	)


## The other side of that, decided on purpose rather than discovered later:
## once smoke shares the scale, the boldest animal in the game treats a fire
## exactly as it treats a person -- it takes notice inside about a tile and
## ignores it further out. That is the floor doing precisely what it was
## built to do; before the fix, smoke was the one thing that walked straight
## past it.
##
## It is NOT fireproof: a fire it is practically standing in weighs 1.0 at
## zero distance and clears the floor comfortably out to roughly 14 px.
func test_the_boldest_animal_still_leaves_a_fire_it_is_standing_in():
	assert_gt(
		float(_smoke_at(0.0)["strength"]), Ethogram.BOLDEST_FEAR_FLOOR,
		"nothing bold enough to stand in a fire should be in this game"
	)
	assert_gt(float(_smoke_at(0.5)["strength"]), Ethogram.BOLDEST_FEAR_FLOOR)


# -- and the gameplay claim, end to end -----------------------------------

## The test that would have caught this in the first place, stated as a
## player would: a wolf two tiles from you, with a campfire in sight, comes
## for you. It used to flee -- so a lit fire made you untouchable.
##
## Driven through the marker's own decision context and its own behaviour
## object, so it is the REAL mammal wiring, the real receptors and the real
## smoke producer rather than a hand-built ladder.
func test_a_wolf_does_not_flee_a_player_because_a_campfire_is_lit():
	var world := OneFireWorld.new()
	world.fire = Vector2(10.0 * TILE, 0.0)
	var wolf := CreatureMarker.new()
	wolf.info = CreatureInfo.new("wolf")
	wolf.wander_seed = 5
	wolf.position = Vector2.ZERO
	wolf.home = Vector2.ZERO
	add_child_autofree(wolf)
	wolf.setup(world, int(TILE))

	var player_at := Vector2(2.0 * TILE, 0.0)
	wolf._cached_stimuli = [
		{"position": player_at, "features": {Ethogram.PLAYER: 1.0}},
	]
	wolf._cached_stimuli.append_array(wolf._scan_smoke_stimuli())
	var decision: Dictionary = CreatureBehavior.new().decide(wolf._decision_context(null))
	assert_eq(
		String(decision["intent"]), "attack",
		"a lit campfire must not turn a healthy wolf two tiles away into scenery"
	)
