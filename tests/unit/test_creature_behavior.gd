extends GutTest

const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")

var behavior: CreatureBehavior


func before_each():
	behavior = CreatureBehavior.new()


## Builds a full decision context with sensible "nothing happening" defaults,
## overridden per-test.
func _context(overrides: Dictionary) -> Dictionary:
	var base := {
		"position": Vector2.ZERO,
		"temperament": "calm",
		"is_predator": false,
		"health_fraction": 1.0,
		"hungry": false,
		"thirsty": false,
		"threats": [],
		"prey": [],
		"food_direction": Vector2.ZERO,
		"water_direction": Vector2.ZERO,
		"is_courting": false,
		"partner_position": Vector2.ZERO,
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func test_wanders_when_nothing_is_happening():
	var decision := behavior.decide(_context({}))
	assert_eq(decision.intent, "wander")


func test_calm_creature_flees_a_nearby_threat():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm", "threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "flee")
	# Away from the threat -> negative x.
	assert_lt(decision.direction.x, 0.0)


func test_aggressive_strong_creature_attacks_a_nearby_threat():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "attack")
	# Toward the threat -> positive x.
	assert_gt(decision.direction.x, 0.0)


func test_aggressive_but_weak_creature_flees_instead_of_attacking():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 0.1,
		"threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "flee")


func test_flees_from_the_nearest_of_several_threats():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm",
		"threats": [Vector2(100, 0), Vector2(0, 5)]
	}))
	# Nearest threat is below (positive y), so flee upward (negative y).
	assert_lt(decision.direction.y, 0.0)


func test_hungry_predator_hunts_the_nearest_prey():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "is_predator": true,
		"hungry": true, "prey": [Vector2(10, 0), Vector2(50, 0)]
	}))
	assert_eq(decision.intent, "hunt")
	# Toward the nearer prey (positive x).
	assert_gt(decision.direction.x, 0.0)


func test_sated_predator_does_not_hunt():
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": false,
		"prey": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "wander")


func test_thirsty_creature_seeks_water():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2(1, 0)
	}))
	assert_eq(decision.intent, "seek_water")
	assert_almost_eq(decision.direction.x, 1.0, 0.001)


func test_hungry_herbivore_seeks_food():
	var decision := behavior.decide(_context({
		"hungry": true, "food_direction": Vector2(0, 1)
	}))
	assert_eq(decision.intent, "seek_food")
	assert_almost_eq(decision.direction.y, 1.0, 0.001)


func test_threat_takes_priority_over_hunger_and_thirst():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm",
		"threats": [Vector2(10, 0)],
		"thirsty": true, "water_direction": Vector2(1, 0),
		"hungry": true, "food_direction": Vector2(1, 0),
	}))
	assert_eq(decision.intent, "flee")


func test_thirst_takes_priority_over_hunger():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2(1, 0),
		"hungry": true, "food_direction": Vector2(0, 1),
	}))
	assert_eq(decision.intent, "seek_water")


func test_hungry_predator_with_no_prey_in_range_searches_for_food():
	# A hungry predator that can't see prey should roam to find some, not idle.
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": true, "prey": []
	}))
	assert_eq(decision.intent, "search_food")


func test_thirsty_creature_with_no_water_sensed_searches_for_water():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2.ZERO
	}))
	assert_eq(decision.intent, "search_water")


func test_hungry_herbivore_with_no_food_sensed_searches_for_food():
	var decision := behavior.decide(_context({
		"hungry": true, "food_direction": Vector2.ZERO
	}))
	assert_eq(decision.intent, "search_food")


func test_searching_leaves_direction_for_the_caller_to_fill_in():
	var decision := behavior.decide(_context({"thirsty": true, "water_direction": Vector2.ZERO}))
	assert_eq(decision.direction, Vector2.ZERO)


func test_flee_direction_is_nonzero_even_when_overlapping_the_threat():
	var decision := behavior.decide(_context({
		"position": Vector2(5, 5), "temperament": "calm", "threats": [Vector2(5, 5)]
	}))
	assert_eq(decision.intent, "flee")
	assert_gt(decision.direction.length(), 0.5)


func test_wander_returns_a_zero_direction_for_the_caller_to_fill_in():
	var decision := behavior.decide(_context({}))
	assert_eq(decision.direction, Vector2.ZERO)


# -- courtship (land mammals -- see MammalCourtship / World._pair_up_courtships) --

## An eligible creature with a paired partner nearby walks toward it rather
## than wandering aimlessly -- courtship is a real, watched two-partner state,
## not a silent solo spawn.
func test_a_courting_creature_moves_toward_its_partner():
	var decision := behavior.decide(_context({
		"is_courting": true, "position": Vector2.ZERO, "partner_position": Vector2(10, 0),
	}))
	assert_eq(decision.intent, "court")
	assert_gt(decision.direction.x, 0.0)


func test_threat_takes_priority_over_courtship():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm", "threats": [Vector2(10, 0)],
		"is_courting": true, "partner_position": Vector2(0, 10),
	}))
	assert_eq(decision.intent, "flee")


# -- world boss aggro gating (docs/concept/worldbosses.md) -------------------
#
# A world boss should not attack a low-level player just for being nearby,
# the way an ordinary aggressive+strong creature does -- and it shouldn't
# flee one either, which a bare "ignore the aggressive rule" toggle would
# accidentally produce (falling through to the calm-creature branch). It
# should not perceive the player as a threat AT ALL until provoked by a
# real hit (see BossAggro/CreatureMarker.take_damage, which sets
# is_aggroed). Once aggroed, it behaves exactly like any other creature of
# its temperament -- no special "bosses never flee" rule invented here.

func test_unaggroed_world_boss_ignores_a_nearby_threat_and_wanders():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": false,
	}))
	assert_eq(decision.intent, "wander")


func test_unaggroed_world_boss_does_not_flee_a_threat_either():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm", "health_fraction": 0.1,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": false,
	}))
	assert_ne(decision.intent, "flee")


func test_aggroed_world_boss_fights_like_an_ordinary_aggressive_creature():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": true,
	}))
	assert_eq(decision.intent, "attack")


func test_aggroed_world_boss_still_flees_if_weak_like_any_other_creature():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 0.1,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": true,
	}))
	assert_eq(decision.intent, "flee")


func test_thirst_takes_priority_over_courtship():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2(1, 0),
		"is_courting": true, "partner_position": Vector2(0, 10),
	}))
	assert_eq(decision.intent, "seek_water")


## A hungry predator with prey in reach still hunts rather than courting --
## eating comes before mating.
func test_hunting_takes_priority_over_courtship():
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": true,
		"prey": [Vector2(10, 0)], "is_courting": true, "partner_position": Vector2(0, 10),
	}))
	assert_eq(decision.intent, "hunt")


func test_hunger_takes_priority_over_courtship():
	var decision := behavior.decide(_context({
		"hungry": true, "food_direction": Vector2(0, 1),
		"is_courting": true, "partner_position": Vector2(10, 0),
	}))
	assert_eq(decision.intent, "seek_food")


# -- juvenile: never fights, regardless of temperament/health (see
# MammalGrowth / CreatureMarker) -------------------------------------------
#
# A real juvenile of even an aggressive-tempered species (boar, bear, lion)
# flees rather than fights -- "is_mature" is supplied by CreatureMarker every
# frame (mirroring is_courting/partner_position); omitted from _context()'s
# base dict on purpose so every pre-existing test above (which never sets it)
# keeps exercising exactly today's behaviour via the missing-key default.

## The core property: otherwise-eligible-to-attack (aggressive temperament,
## full health) but immature must still flee, never attack.
func test_an_immature_aggressive_healthy_creature_flees_instead_of_attacking():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)], "is_mature": false,
	}))
	assert_eq(decision.intent, "flee")


## Control case: the same context with is_mature explicitly true attacks
## exactly as before -- proves the new key is additive, not a regression.
func test_a_mature_aggressive_healthy_creature_still_attacks_when_is_mature_is_explicit():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)], "is_mature": true,
	}))
	assert_eq(decision.intent, "attack")


## Second control case: omitting is_mature entirely (as every pre-existing
## test above does) must default to mature -- today's exact behaviour.
func test_omitting_is_mature_defaults_to_todays_mature_behavior():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)],
	}))
	assert_eq(decision.intent, "attack")


## Courtship outranks aimless wandering -- covered implicitly by the "moves
## toward its partner" test above (nothing else is set), pinned explicitly
## here so the priority place in the tree can't silently regress to below
## wander.
func test_courtship_outranks_wander():
	var decision := behavior.decide(_context({
		"is_courting": true, "position": Vector2.ZERO, "partner_position": Vector2(5, 5),
	}))
	assert_ne(decision.intent, "wander")
# -- "skittish" temperament (docs/concept/easter_eggs.md's Champ) -----------
#
# Champ is deliberately "skittish, NOT calm" (distinct from Coilnecca's
# placid "calm") in CreatureInfo, but _will_fight only special-cases the
# literal string "aggressive" -- so any other temperament value, including
# this new one, must already flee a threat exactly like "calm" does,
# regardless of health. Pinned here as a real regression test rather than
# an assumption: introducing a brand-new temperament string is exactly the
# kind of change that could silently break if this file ever grew a
# temperament allow-list.


func test_skittish_creature_flees_a_nearby_threat_just_like_calm():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "skittish", "threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "flee")
	assert_lt(decision.direction.x, 0.0)


func test_skittish_creature_never_fights_even_at_full_health():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "skittish", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)]
	}))
	assert_ne(decision.intent, "attack")


func test_unaggroed_world_boss_still_seeks_food_and_water_normally():
	# Ignoring the player as a threat must not make it ignore everything --
	# ordinary needs still drive it exactly like any other creature.
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive",
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": false,
		"thirsty": true, "water_direction": Vector2(1, 0),
	}))
	assert_eq(decision.intent, "seek_water")


# -- the ethogram underneath (docs/concept/ethogram.md §7) --------------------
#
# decide() is now the land-mammal adapter onto BehaviorKernel: the ladder
# above is Ethogram.BODY_PLANS["mammal"]["wirings"], and everything the tests
# above pin is the regression bar for that. What follows is what the adapter
# can do that the old ladder could not: name what it chose, take a species
# and its genome, and hunt by nose through the same entry point.

const Olfaction = preload("res://src/gameplay/olfaction.gd")


func test_a_decision_names_its_target_and_score():
	var hunt := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": true,
		"prey": [Vector2(10, 0), Vector2(50, 0)],
	}))
	assert_eq(hunt["target"], Vector2(10, 0))
	assert_gt(hunt["score"], 0.0)
	var idle := behavior.decide(_context({}))
	assert_eq(idle["target"], null)
	assert_eq(idle["score"], 0.0)


## Smells reach the ladder through the context as `smells`, the same
## {position, mixture} list EarthChunkManager.smells_near already returns.
## Nothing live passes them yet (ScentForaging does this job in the marker
## until slice 2); this pins that the seam exists and ranks like a nose.
func test_a_hungry_boar_with_smells_in_its_context_heads_for_the_ripe_apple():
	var decision := behavior.decide(_context({
		"species": "boar", "hungry": true,
		"smells": [
			{"position": Vector2(60, 0), "mixture": Olfaction.fruit_mixture("apple", 1.0)},
			{"position": Vector2(-60, 0), "mixture": Olfaction.fruit_mixture("apple", 0.0)},
		],
	}))
	assert_eq(decision.intent, "seek_food")
	assert_gt(decision.direction.x, 0.0)


func test_a_hungry_deer_walks_past_a_rotten_apple_and_keeps_searching():
	var decision := behavior.decide(_context({
		"species": "deer", "hungry": true,
		"smells": [{"position": Vector2(-60, 0), "mixture": Olfaction.fruit_mixture("apple", 0.0)}],
	}))
	assert_eq(decision.intent, "search_food", "repelled, and with nothing else sensed, it roams")


func test_smells_never_outrank_thirst_or_a_threat():
	var smells := [{"position": Vector2(60, 0), "mixture": Olfaction.fruit_mixture("apple", 1.0)}]
	var thirsty := behavior.decide(_context({
		"species": "boar", "hungry": true, "smells": smells,
		"thirsty": true, "water_direction": Vector2(0, 1),
	}))
	assert_eq(thirsty.intent, "seek_water")
	var hunted := behavior.decide(_context({
		"species": "boar", "hungry": true, "smells": smells, "threats": [Vector2(0, 10)],
	}))
	assert_eq(hunted.intent, "flee")


## A species with no ethogram record (most of the roster today) still runs
## the whole mammal ladder on the body plan's defaults.
func test_a_species_without_a_record_still_runs_the_mammal_ladder():
	var decision := behavior.decide(_context({
		"species": "lynx", "temperament": "calm", "threats": [Vector2(10, 0)],
	}))
	assert_eq(decision.intent, "flee")
	assert_eq(behavior.decide(_context({"species": "lynx", "hungry": true})).intent, "search_food")


## An individual's receptor genes reach its decision: a boar born without a
## decay receptor cannot be drawn by carrion the species would take. (A
## rotten APPLE would still draw it a little -- the fruit keeps a trace of
## sugar as it goes over, and a boar likes sugar -- which is olfaction.md's
## point that a smell is a mixture, not a label; so this uses a pure decay
## source.)
func test_an_individuals_receptor_genes_reach_its_decision():
	var carrion := [{"position": Vector2(-60, 0), "mixture": {Olfaction.DECAY: 1.0}}]
	var typical := behavior.decide(_context({"species": "boar", "hungry": true, "smells": carrion}))
	var anosmic := behavior.decide(_context({
		"species": "boar", "hungry": true, "smells": carrion, "genome": {"receptor_decay": 0.0},
	}))
	assert_eq(typical.intent, "seek_food")
	assert_eq(anosmic.intent, "search_food")


# -- slice 2: the marker publishes stimuli; the verdict is the valence -------

const Ethogram = preload("res://src/gameplay/ethogram.gd")


func _wolf(at: Vector2) -> Dictionary:
	return {"position": at, "features": {Ethogram.PREDATOR: 1.0}, "node": "wolf"}


func _person(at: Vector2) -> Dictionary:
	return {"position": at, "features": {Ethogram.PLAYER: 1.0}, "node": "player"}


func _sheep(at: Vector2) -> Dictionary:
	return {"position": at, "features": {Ethogram.FLESH: 1.0}, "node": "sheep"}


## The scan reports what the other creature IS; the species decides what
## that means. A calm herbivore flees a predator it is handed as a stimulus.
func test_a_calm_creature_flees_a_predator_stimulus():
	var decision := behavior.decide(_context({"stimuli": [_wolf(Vector2(10, 0))]}))
	assert_eq(decision.intent, "flee")
	assert_lt(decision.direction.x, 0.0)
	assert_eq(decision["stimulus"]["node"], "wolf")


## Predators are not threatened by other creatures, only by the player --
## the rule the marker used to apply while scanning, now a valence.
func test_a_predator_ignores_another_predator_but_answers_a_player():
	var ignores := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "stimuli": [_wolf(Vector2(10, 0))],
	}))
	assert_eq(ignores.intent, "wander")
	var attack := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "stimuli": [_person(Vector2(10, 0))],
	}))
	assert_eq(attack.intent, "attack")
	assert_eq(attack["stimulus"]["node"], "player")


func test_a_hungry_predator_hunts_a_flesh_stimulus_and_names_the_node():
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": true,
		"stimuli": [_sheep(Vector2(50, 0)), _sheep(Vector2(10, 0))],
	}))
	assert_eq(decision.intent, "hunt")
	assert_eq(decision["target"], Vector2(10, 0))
	assert_eq(decision["stimulus"]["node"], "sheep")


## A herbivore handed the same flesh stimulus wants nothing from it.
func test_a_herbivore_ignores_a_flesh_stimulus():
	var decision := behavior.decide(_context({"hungry": true, "stimuli": [_sheep(Vector2(10, 0))]}))
	assert_eq(decision.intent, "search_food")


## A tamed animal does not perceive people as anything: sensitivity, not valence.
func test_an_animal_that_no_longer_fears_players_does_not_perceive_them():
	var decision := behavior.decide(_context({
		"fears_players": false, "stimuli": [_person(Vector2(10, 0))],
	}))
	assert_eq(decision.intent, "wander")


## When the caller publishes stimuli, the legacy position lists are not read
## on top of them -- one source of truth per call.
func test_published_stimuli_replace_the_legacy_lists():
	var decision := behavior.decide(_context({"threats": [Vector2(10, 0)], "stimuli": []}))
	assert_eq(decision.intent, "wander")


func test_an_aggressive_strong_herbivore_stands_and_fights_a_predator():
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "health_fraction": 1.0, "stimuli": [_wolf(Vector2(10, 0))],
	}))
	assert_eq(decision.intent, "attack")


## What the animal NOTICES on the fear channels, fight or flee alike -- the
## marker keeps this as its threat list (lift the head from grazing, widen
## the flee-release radius) instead of deciding who counts while scanning.
func test_threats_lists_what_the_animal_notices_on_the_fear_channels():
	var wolf := _wolf(Vector2(10, 0))
	var person := _person(Vector2(20, 0))
	var sheep := _sheep(Vector2(30, 0))
	var calm := behavior.threats(_context({"stimuli": [wolf, person, sheep]}))
	assert_eq(calm.size(), 2, "a herbivore notices the wolf and the person, not the sheep")
	var fighter := behavior.threats(_context({
		"temperament": "aggressive", "health_fraction": 1.0, "stimuli": [wolf, person, sheep],
	}))
	assert_eq(fighter.size(), 2, "a fighter still notices what it would fight")
	var hunter := behavior.threats(_context({"is_predator": true, "stimuli": [wolf, person, sheep]}))
	assert_eq(hunter.size(), 1, "a predator notices only the person")
	assert_eq(hunter[0]["node"], "player")
	var tame := behavior.threats(_context({"fears_players": false, "stimuli": [wolf, person]}))
	assert_eq(tame.size(), 1, "a tamed animal still notices the wolf, and no longer the person")
	assert_eq(tame[0]["node"], "wolf")


# -- slice 3: drives as gains -------------------------------------------------

## A caller that hands over its drive gains (Drives.gains) is taken at its
## word; the hungry/thirsty booleans are the older shape.
func test_published_drive_gains_replace_the_booleans():
	var starving := behavior.decide(_context({
		"hungry": false, "drives": {"hunger": 1.0}, "food_direction": Vector2(0, 1),
	}))
	assert_eq(starving.intent, "seek_food")
	var sated := behavior.decide(_context({
		"hungry": true, "drives": {"hunger": 0.0}, "food_direction": Vector2(0, 1),
	}))
	assert_eq(sated.intent, "wander")


## A partial gain still opens the gate -- the kernel scales the score, the
## ladder decides.
func test_a_partial_gain_still_opens_the_gate():
	var peckish := behavior.decide(_context({
		"drives": {"hunger": 0.4}, "food_direction": Vector2(0, 1),
	}))
	assert_eq(peckish.intent, "seek_food")
	assert_gt(peckish["score"], 0.0)


# -- slice 4: a boldness gene raises the fear floor (docs/concept/ethogram.md §9) --

## A far-off predator that a population-median individual still flees does
## not register at all for the boldest possible individual: its fear wiring
## requires the threat within about a tile, per Ethogram.fear_floor.
func test_a_bold_individuals_fear_wiring_ignores_a_faint_threat_a_typical_one_flees():
	var far_threat := [_wolf(Vector2(500, 0))]
	var typical := behavior.decide(_context({
		"genome": {"boldness": Ethogram.NEUTRAL_BOLDNESS_GENE}, "stimuli": far_threat,
	}))
	assert_eq(typical.intent, "flee", "a population-median individual still flees a distant threat")
	var bold := behavior.decide(_context({"genome": {"boldness": 1.0}, "stimuli": far_threat}))
	assert_ne(bold.intent, "flee", "the boldest individual does not register so faint a threat")


## An absent genome (every pre-existing test above, and any context built
## before this gene existed) behaves exactly as it always has: the neutral
## gene IS the old, only, zero floor.
func test_no_genome_at_all_behaves_exactly_like_the_neutral_gene():
	var far_threat := [_wolf(Vector2(500, 0))]
	assert_eq(behavior.decide(_context({"stimuli": far_threat})).intent, "flee")


## Calling threats() before decide() has ever run must not leave the fear
## wiring's per-individual floor stuck at its default: threats() also caches
## the genome (it calls _receptors() too), and if the wirings array isn't
## populated by the time that cache first warms, the floor patch lands on
## an empty array and never gets a second chance -- a real bug this pinned,
## not a hypothetical one (CreatureMarker calls threats() before its first
## decide() every time).
func test_threats_called_before_the_first_decide_still_lets_the_floor_apply():
	var far_threat := [_wolf(Vector2(500, 0))]
	var bold_genome := {"boldness": 1.0}
	behavior.threats(_context({"genome": bold_genome, "stimuli": far_threat}))
	var decision := behavior.decide(_context({"genome": bold_genome, "stimuli": far_threat}))
	assert_ne(decision.intent, "flee", "the boldest individual still shouldn't register so faint a threat")
