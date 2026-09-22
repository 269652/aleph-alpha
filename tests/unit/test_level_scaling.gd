extends GutTest

## A level is a bigger animal (docs/concept/combat.md, section of that name).
##
## A creature's `level` rolls per individual in `[1, LEVEL_RANGE]` --
## variety, since the journey rings supply the distance gradient by changing
## which species live where. "That one is bigger" is meant to be a warning.
##
## It was not one. `CreatureInfo` had `LEVEL_HEALTH_SCALE` and no
## counterpart for anything else, and `CreatureMarker.bite_damage()` read
## `info.species` and never `info.level` -- so a level-5 wolf carried
## **twice the health and the identical 6-damage bite**. A bigger animal was
## a longer chore, never a greater danger: the "spongier, not deadlier"
## failure the reference exchange exists to avoid, hiding inside the level
## roll.

const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const Dodge = preload("res://src/gameplay/dodge.gd")

var creatures_parent: Node2D
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var manager: EarthChunkManager
var renderer: CreatureRenderer


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	add_child(creatures_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	renderer = CreatureRenderer.new()


func after_each():
	creatures_parent.free()
	tile_map_layer.free()
	entities_parent.free()


## A real marker of `species`, forced to `level`. Only the frames a test
## drives itself (the two-clocks rule, see test_bite_telegraph.gd).
func _creature_at_level(species: String, level: int):
	var marker = renderer.spawn_single(
		creatures_parent, species, Vector2.ZERO, manager, TerrainRenderer.TILE_SIZE
	)
	marker.set_process(false)
	marker.info.level = level
	return marker


func _biting_species() -> Array:
	var out: Array = []
	for species in SpeciesBite.species_list():
		if SpeciesBite.bite_damage_for(species) > 0.0:
			out.append(species)
	return out


# -- the defect ------------------------------------------------------------

## The heart of it, driven through the marker the player actually fights.
func test_a_bigger_wolf_bites_harder():
	var small = _creature_at_level("wolf", 1)
	var large = _creature_at_level("wolf", CreatureInfo.LEVEL_RANGE)
	assert_gt(
		large.bite_damage(), small.bite_damage(),
		"a level-%d wolf must hit harder than a level-1 one" % CreatureInfo.LEVEL_RANGE
	)


## And by the authored amount, composed from the game's own constants rather
## than restated here.
func test_the_bite_grows_by_the_authored_scale():
	var level: int = CreatureInfo.LEVEL_RANGE
	var large = _creature_at_level("wolf", level)
	var expected: float = (
		SpeciesBite.bite_damage_for("wolf")
		* (1.0 + (level - 1) * CreatureInfo.LEVEL_DAMAGE_SCALE)
	)
	assert_almost_eq(large.bite_damage(), expected, 0.001)


## A level-1 individual is exactly the authored sheet. Without this, a
## scale applied at the wrong end would silently retune the whole roster.
func test_a_level_1_animal_bites_for_exactly_what_the_sheet_says():
	for species in _biting_species():
		var one = _creature_at_level(species, 1)
		assert_almost_eq(
			one.bite_damage(), SpeciesBite.bite_damage_for(species), 0.001,
			"%s at level 1 is the authored bite" % species
		)


# -- and the telegraph follows it -----------------------------------------

## The reason scaling damage is safe rather than cruel. The tell is derived
## from what fraction of your health the bite would take, so a harder-
## hitting individual is automatically warned about for longer -- but only
## if the telegraph is asked of the INDIVIDUAL. A level-5 wolf that hit for
## 10 while telegraphing like one that hits for 6 is precisely the cheap
## shot the fairness model forbids.
func test_a_harder_hitting_individual_is_telegraphed_for_at_least_as_long():
	var frail := 60.0
	for species in _biting_species():
		var small = _creature_at_level(species, 1)
		var large = _creature_at_level(species, CreatureInfo.LEVEL_RANGE)
		assert_gte(
			large.windup_seconds_against(frail), small.windup_seconds_against(frail),
			"%s must not bite harder on the same tell" % species
		)


## Stated as the invariant rather than as a comparison: whatever this
## individual bites for, its tell satisfies the fairness requirement for
## THAT bite. This is the assertion the roster is really held to.
func test_every_individual_at_every_level_is_warned_for_its_own_bite():
	for target_health in [40.0, 100.0, 145.0]:
		for species in _biting_species():
			for level in range(1, CreatureInfo.LEVEL_RANGE + 1):
				var one = _creature_at_level(species, level)
				assert_gte(
					one.windup_seconds_against(target_health),
					SpeciesBite.required_windup_seconds(one.bite_damage(), target_health),
					"%s L%d against %.0f health" % [species, level, target_health]
				)


# -- bounded by the fairness floor ----------------------------------------

## `MINIMUM_TIME_TO_KILL_SECONDS` is the invariant that caps the growth:
## however hard it bites, an animal may not take a full-health player from
## alive to dead faster than that -- below it there is no "you are in
## trouble" phase to read, only a death.
func test_no_animal_at_any_level_kills_faster_than_a_player_can_read():
	var reference: float = SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH
	for species in _biting_species():
		for level in range(1, CreatureInfo.LEVEL_RANGE + 1):
			var one = _creature_at_level(species, level)
			var cycle: float = (
				one.windup_seconds_against(reference) + one.bite_cooldown_seconds()
			)
			var dps: float = one.bite_damage() / maxf(cycle, 0.001)
			assert_gte(
				reference / maxf(dps, 0.001), SpeciesBite.MINIMUM_TIME_TO_KILL_SECONDS,
				"%s at level %d kills too fast to read" % [species, level]
			)


## And the scale is the LARGEST that clears that floor, not a smaller number
## chosen for comfort -- without this half, the growth could quietly shrink
## and levelling would drift back toward meaning nothing.
func test_the_damage_scale_is_as_large_as_the_fairness_floor_allows():
	var reference: float = SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH
	var bolder: float = CreatureInfo.LEVEL_DAMAGE_SCALE + 0.01
	var breaches := 0
	for species in _biting_species():
		var authored: float = SpeciesBite.bite_damage_for(species)
		var recovery: float = SpeciesBite.bite_cooldown_seconds_for(species)
		var floor_windup: float = SpeciesBite.profile_for(species)["windup_seconds"]
		for level in range(1, CreatureInfo.LEVEL_RANGE + 1):
			var bite: float = authored * (1.0 + (level - 1) * bolder)
			var windup: float = maxf(
				floor_windup, SpeciesBite.required_windup_seconds(bite, reference)
			)
			var dps: float = bite / maxf(windup + recovery, 0.001)
			if reference / maxf(dps, 0.001) < SpeciesBite.MINIMUM_TIME_TO_KILL_SECONDS:
				breaches += 1
	assert_gt(
		breaches, 0,
		"one hundredth bolder must breach the floor, or the growth is timider than it may be"
	)


## Which animal is doing the capping, pinned so that retuning another
## species' bite cannot quietly become the thing that sets the scale.
func test_the_bear_is_what_the_damage_scale_is_capped_by():
	var reference: float = SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH
	var bolder: float = CreatureInfo.LEVEL_DAMAGE_SCALE + 0.01
	var level: int = CreatureInfo.LEVEL_RANGE
	var bite: float = SpeciesBite.bite_damage_for("bear") * (1.0 + (level - 1) * bolder)
	var windup: float = maxf(
		SpeciesBite.profile_for("bear")["windup_seconds"],
		SpeciesBite.required_windup_seconds(bite, reference)
	)
	var dps: float = bite / (windup + SpeciesBite.bite_cooldown_seconds_for("bear"))
	assert_lt(
		reference / dps, SpeciesBite.MINIMUM_TIME_TO_KILL_SECONDS,
		"the bear is the animal the floor binds first"
	)


# -- the other axes --------------------------------------------------------

## Scaled for coherence -- a bigger animal is bigger on every axis it has.
## Both are read by nothing in the game today, so the scale is inert; it is
## asserted anyway so that the day something reads them, it reads a number
## that already grew.
func test_a_bigger_animal_carries_more_stamina_and_mana():
	var small := CreatureInfo.new("wolf")
	small.level = 1
	var one := CreatureInfo.new("wolf")
	var large_level: int = CreatureInfo.LEVEL_RANGE
	var expected_growth: float = 1.0 + (large_level - 1) * CreatureInfo.LEVEL_DAMAGE_SCALE
	var large := CreatureInfo.new("wolf", large_level - 1)
	assert_eq(large.level, large_level, "precondition: the seed rolled the top level")
	assert_almost_eq(
		large.max_stamina,
		float(CreatureInfo.MAX_STAMINA_BY_SPECIES.get("wolf", 10.0)) * expected_growth, 0.001
	)
	assert_almost_eq(
		large.max_mana,
		float(CreatureInfo.MAX_MANA_BY_SPECIES.get("wolf", 5.0)) * expected_growth, 0.001
	)


## Speed deliberately does NOT scale. Player.BASE_SPEED is 40 and
## CreatureMarker.HUNT_SPEED is 36 -- a player out-runs a hunting animal,
## but only just. Scaling pursuit with level would flip that for large
## individuals and remove disengagement entirely: you could no longer choose
## not to have the fight, which every other fairness rule is built on.
func test_a_bigger_animal_is_not_a_faster_one():
	var small = _creature_at_level("wolf", 1)
	var large = _creature_at_level("wolf", CreatureInfo.LEVEL_RANGE)
	assert_almost_eq(
		large.hunt_speed(), small.hunt_speed(), 0.001,
		"a player must always be able to walk away from a fight"
	)
