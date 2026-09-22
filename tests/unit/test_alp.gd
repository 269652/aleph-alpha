extends GutTest

## docs/concept/monsters.md, entry 3: the Alp, the night-mare.
##
## Quoted from the roster: *"it is only dangerous while you are not. It
## cannot be hit while you are standing; it approaches only while you rest
## and drains stamina rather than health. Waking is the counterplay, and the
## cost of waking is the rest you lose."*
##
## This was the roster's one BLOCKED entry: there was no sleep state for it
## to attach to. docs/concept/sleep.md built one, so the whole behaviour is
## now expressible -- and it is the exact inverse of every other creature in
## the game, which is why it needs its own rule rather than a temperament.

const NightMare = preload("res://src/gameplay/night_mare.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const WitnessConditions = preload("res://src/gameplay/witness_conditions.gd")

const ALP := "alp"
const REFERENCE := "wolf"


# -- only dangerous while you are not -------------------------------------

func test_it_ignores_a_waking_character():
	assert_false(NightMare.preys_on({"resting": false, "dark": true}))


func test_it_comes_for_a_sleeper_in_the_dark():
	assert_true(NightMare.preys_on({"resting": true, "dark": true}))


## Bound to the NIGHT as well as to the sleeper -- monsters.md calls it Tier
## C, "bound to deep forest at night". A daylight nap is not its hour.
func test_it_does_not_come_in_daylight():
	assert_false(
		NightMare.preys_on({"resting": true, "dark": false}),
		"the word is night-mare"
	)


func test_missing_facts_are_not_an_invitation():
	assert_false(NightMare.preys_on({}))


## The dark it reads is the same civil twilight everything else in this game
## calls night -- one definition, not a second opinion.
func test_its_night_is_the_shared_definition_of_night():
	assert_eq(
		NightMare.DARK_BELOW_SUN_ELEVATION_DEG,
		WitnessConditions.DARK_BELOW_SUN_ELEVATION_DEG
	)


# -- it drains stamina, not health ----------------------------------------

## The roster is explicit: stamina rather than health. A monster that killed
## you in your sleep would be a death with no counterplay.
func test_the_drain_is_stamina_and_it_is_real():
	var meters := SurvivalMeters.new()
	meters.stamina = 1.0
	NightMare.press(meters, 1.0)
	assert_lt(meters.stamina, 1.0, "it really presses")


func test_it_never_touches_health():
	var declared: Array = []
	for method in NightMare.new().get_script().get_script_method_list():
		declared.append(method["name"])
	assert_true(declared.has("press"), "reflection returned nothing -- the guard is vacuous")
	for name in declared:
		assert_false(
			String(name).contains("damage") or String(name).contains("health"),
			"%s reaches for health; this creature drains stamina" % name
		)


## A whole night of it empties the bar, or the threat is decorative -- and
## not so fast that there is nothing to wake up to.
func test_a_full_bar_is_emptied_by_a_night_but_not_instantly():
	var meters := SurvivalMeters.new()
	meters.stamina = 1.0
	var seconds := 0.0
	while meters.stamina > 0.0 and seconds < 600.0:
		NightMare.press(meters, 0.1)
		seconds += 0.1
	assert_lt(seconds, 600.0, "a drain that never empties is not a threat")
	assert_gt(seconds, 2.0, "and one that empties at once gives nothing to wake to")


## Derived rather than picked: the bar it empties is the same one
## SprintCost spends, so the press is stated in that module's own terms.
func test_the_drain_rate_is_stated_against_the_bar_it_empties():
	assert_almost_eq(
		NightMare.STAMINA_PER_SECOND,
		1.0 / NightMare.SECONDS_TO_EMPTY_A_FULL_BAR,
		0.0001
	)


func test_a_zero_or_negative_step_presses_nothing():
	var meters := SurvivalMeters.new()
	meters.stamina = 1.0
	NightMare.press(meters, 0.0)
	NightMare.press(meters, -1.0)
	assert_eq(meters.stamina, 1.0)


# -- it is a real species -------------------------------------------------

func test_it_is_defined_everywhere_an_ordinary_species_is():
	var tables := {
		"MAX_HEALTH_BY_SPECIES": CreatureInfo.MAX_HEALTH_BY_SPECIES,
		"MAX_STAMINA_BY_SPECIES": CreatureInfo.MAX_STAMINA_BY_SPECIES,
		"MAX_MANA_BY_SPECIES": CreatureInfo.MAX_MANA_BY_SPECIES,
		"DIET_BY_SPECIES": CreatureInfo.DIET_BY_SPECIES,
		"TEMPERAMENT_BY_SPECIES": CreatureInfo.TEMPERAMENT_BY_SPECIES,
	}
	for name in tables:
		assert_true(tables[name].has(ALP), "%s has no entry for the alp" % name)


func test_it_has_a_body_and_a_name_the_console_knows():
	assert_true(AnimalAnatomy.has_profile(ALP))
	assert_true(ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY.has(ALP))
	assert_true(ProceduralAnimalSprite.SPECIES_BASE_COLORS.has(ALP))
	assert_eq(ConsoleSpecies.resolve(ALP), ALP)


## Forest, and only forest -- the roster binds it there.
func test_it_lives_in_the_forest_and_nowhere_else():
	for biome in CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME:
		var pool: Array = CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME[biome]
		if biome == "forest":
			assert_true(pool.has(ALP), "the forest must be able to produce it")
		else:
			assert_false(pool.has(ALP), "%s is not its forest" % biome)


func test_it_is_rarer_than_the_forests_ordinary_predator():
	var pool: Array = CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME["forest"]
	var mine := 0
	var reference := 0
	for entry in pool:
		if String(entry) == ALP:
			mine += 1
		elif String(entry) == "lynx":
			reference += 1
	assert_gt(reference, mine)


## It presses, it does not bite -- but it still carries a profile, and the
## first draft of this test asserted the opposite. The existing invariant
## test_every_spawnable_species_has_a_profile was right and caught it: a
## spawnable species WITHOUT a profile falls back to the shared
## ATTACK_DAMAGE silently, which would have given this thing a 6-damage bite
## nobody designed. Its own figures say what it is instead.
func test_it_bites_for_less_than_anything_that_actually_hunts():
	assert_true(SpeciesBite.has_profile(ALP), "or it inherits a bite by accident")
	# Grazers bite for exactly 0.0 -- the first draft of this test claimed
	# "feeblest in the game" and a deer proved it wrong. The permanently-true
	# statement is about the things that HUNT.
	for species in ["wolf", "lynx", "bear", "lion", "jaguar", "jackal", "curupira"]:
		assert_lt(
			SpeciesBite.bite_damage_for(ALP), SpeciesBite.bite_damage_for(species),
			"%s must bite harder than the thing that does not bite" % species
		)


## And it gives up at the first scratch, because it was never going to fight
## you: waking is the counterplay, not winning.
func test_it_gives_up_at_the_first_scratch():
	assert_gt(
		float(SpeciesBite.profile_for(ALP)["tenacity"]),
		float(SpeciesBite.profile_for(REFERENCE)["tenacity"]),
		"it flees at a health an ordinary predator would press on at"
	)


# -- and it really presses a real sleeper ---------------------------------

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func test_the_marker_really_presses_a_sleeping_player():
	var tml := TileMapLayer.new()
	var ents := Node2D.new()
	var creatures := Node2D.new()
	add_child(tml); add_child(ents); add_child(creatures)
	var mgr = EarthChunkManager.new(tml, ents, creatures)
	# Real night, through the same door World pushes the sky through -- the
	# manager's default sun is daylight, so without this it is simply not
	# the Alp's hour and nothing should happen.
	mgr.set_sun_position(-20.0, 0.0)
	var renderer := CreatureRenderer.new()
	var player = PlayerScene.instantiate()
	add_child(player)
	player.position = Vector2.ZERO
	player.survival.stamina = 1.0

	var marker = renderer.spawn_single(creatures, ALP, Vector2(4.0, 0.0), mgr, TerrainRenderer.TILE_SIZE)
	assert_not_null(marker, "precondition: an alp spawned")
	marker._cached_player = player
	marker.position = Vector2(4.0, 0.0)

	# Awake: it is not its moment, whatever the hour.
	marker._alp_step(1.0)
	assert_eq(player.survival.stamina, 1.0, "it does not touch a waking character")

	player.begin_rest()
	marker._alp_step(1.0)
	assert_lt(player.survival.stamina, 1.0, "a sleeper in the dark is pressed")
	assert_gt(player.health, 0.0, "and never hurt")

	player.queue_free()
	creatures.free(); tml.free(); ents.free()


## The whole counterplay: standing up ends it.
func test_waking_makes_you_safe_from_it():
	var tml := TileMapLayer.new()
	var ents := Node2D.new()
	var creatures := Node2D.new()
	add_child(tml); add_child(ents); add_child(creatures)
	var mgr = EarthChunkManager.new(tml, ents, creatures)
	# Real night, through the same door World pushes the sky through -- the
	# manager's default sun is daylight, so without this it is simply not
	# the Alp's hour and nothing should happen.
	mgr.set_sun_position(-20.0, 0.0)
	var renderer := CreatureRenderer.new()
	var player = PlayerScene.instantiate()
	add_child(player)
	player.position = Vector2.ZERO
	player.begin_rest()

	var marker = renderer.spawn_single(creatures, ALP, Vector2(4.0, 0.0), mgr, TerrainRenderer.TILE_SIZE)
	marker._cached_player = player
	marker.position = Vector2(4.0, 0.0)
	marker._alp_step(1.0)
	assert_true(marker.info.is_aggroed, "precondition: it had its moment")

	player.wake()
	var after_waking: float = player.survival.stamina
	marker._alp_step(1.0)
	assert_eq(player.survival.stamina, after_waking, "standing up ends it")
	assert_false(marker.info.is_aggroed, "and it loses interest entirely")

	player.queue_free()
	creatures.free(); tml.free(); ents.free()


# -- it presses; it never bites -------------------------------------------

## The bug a combat audit found in the first day of this creature's life,
## and the reason this test drives the REAL `_process` rather than
## `_alp_step` alone: `_alp_step` raises `info.is_aggroed`, and then the
## ordinary AI runs on the very same frame. An aggroed creature inside
## attack range takes the ordinary attack path, bites, and
## `Player.take_damage` calls `wake()` -- so the Alp cancelled its own
## signature mechanic on the first frame it arrived. Every test above drove
## `_alp_step` directly, which is exactly why none of them saw it.
func test_it_never_bites_the_sleeper_it_is_sitting_on():
	var tml := TileMapLayer.new()
	var ents := Node2D.new()
	var creatures := Node2D.new()
	add_child(tml); add_child(ents); add_child(creatures)
	var mgr = EarthChunkManager.new(tml, ents, creatures)
	mgr.set_sun_position(-20.0, 0.0)
	var renderer := CreatureRenderer.new()
	var player = PlayerScene.instantiate()
	add_child(player)
	player.position = Vector2.ZERO
	player.survival.stamina = 1.0
	player.begin_rest()
	await get_tree().process_frame

	# Right on top of the sleeper: well inside any bite's reach, which is
	# the whole point -- this is the position the mechanic REQUIRES.
	var marker = renderer.spawn_single(creatures, ALP, Vector2(2.0, 0.0), mgr, TerrainRenderer.TILE_SIZE)
	assert_not_null(marker, "precondition: an alp spawned")
	marker._cached_player = player
	marker.position = Vector2(2.0, 0.0)
	var health_before: float = player.health

	for _i in 30:
		marker._process(0.1)

	assert_almost_eq(player.health, health_before, 0.0001, "it presses; it does not bite")
	assert_true(player.is_resting(), "and a sleeper it never hurt is never woken")
	assert_lt(player.survival.stamina, 1.0, "precondition: it really was pressing all along")

	player.queue_free()
	creatures.free(); tml.free(); ents.free()


## One name for it, in the pure rule, so the marker cannot drift from what
## `NightMare` thinks it is talking about.
func test_the_marker_and_the_rule_mean_the_same_creature():
	const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
	assert_eq(CreatureMarker.ALP_SPECIES, NightMare.SPECIES)


## And the refusal is about this creature alone: everything that really
## hunts still strikes.
func test_everything_that_hunts_still_strikes():
	for species in ["wolf", "lynx", "bear", "lion", "jaguar", "jackal", "curupira"]:
		assert_false(
			NightMare.presses_instead_of_striking(species),
			"%s hunts, so it bites" % species
		)
