extends GutTest

## The behaviour kernel (see docs/concept/ethogram.md §6): ordered wirings,
## expressed receptors, drive gains and this tick's stimuli in; one intent
## and a heading out. The kernel ranks; the caller commits.

const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")

## Every gate open, so a test about ranking is not accidentally about gating.
const ALL_OPEN := {"fear": 1.0, "thirst": 1.0, "hunger": 1.0, "courtship": 1.0}


func _stimulus(at: Vector2, features: Dictionary) -> Dictionary:
	return {"position": at, "features": features}


func _receptors(sensitivity: Dictionary, valence: Dictionary) -> Dictionary:
	return {"sensitivity": sensitivity, "valence": valence}


## A two-rung ladder with no shared channels, for the ordering tests.
func _ladder() -> Array:
	return [
		{"gate": "hunger", "channels": ["flesh"], "approach": "hunt"},
		{"gate": "hunger", "channels": ["forage"], "approach": "seek_food", "search": "search_food"},
	]


func _omnivore() -> Dictionary:
	return _receptors({"flesh": 1.0, "forage": 1.0}, {"flesh": 1.0, "forage": 1.0})


# -- ordered wirings ---------------------------------------------------------

func test_with_nothing_sensed_the_answer_is_wander_with_a_zero_direction():
	var decision := BehaviorKernel.decide([], _omnivore(), ALL_OPEN, Vector2.ZERO, [])
	assert_eq(decision["intent"], "wander")
	assert_eq(decision["direction"], Vector2.ZERO)


func test_the_first_wiring_with_a_scoring_stimulus_wins():
	var stimuli := [_stimulus(Vector2(0, 10), {"forage": 1.0}), _stimulus(Vector2(50, 0), {"flesh": 1.0})]
	var decision := BehaviorKernel.decide(_ladder(), _omnivore(), ALL_OPEN, Vector2.ZERO, stimuli)
	assert_eq(decision["intent"], "hunt", "hunting is listed first, so it wins even though forage is nearer")
	var reversed := _ladder()
	reversed.reverse()
	assert_eq(BehaviorKernel.decide(reversed, _omnivore(), ALL_OPEN, Vector2.ZERO, stimuli)["intent"], "seek_food")


func test_a_closed_gate_skips_its_wiring_entirely():
	var stimuli := [_stimulus(Vector2(50, 0), {"flesh": 1.0})]
	var sated := {"hunger": 0.0}
	var decision := BehaviorKernel.decide(_ladder(), _omnivore(), sated, Vector2.ZERO, stimuli)
	assert_eq(decision["intent"], "wander", "a closed gate neither approaches nor searches")


func test_a_drive_missing_from_the_table_counts_as_open():
	var stimuli := [_stimulus(Vector2(50, 0), {"flesh": 1.0})]
	assert_eq(BehaviorKernel.decide(_ladder(), _omnivore(), {}, Vector2.ZERO, stimuli)["intent"], "hunt")


func test_an_open_gate_with_nothing_sensed_falls_back_to_search():
	var decision := BehaviorKernel.decide(_ladder(), _omnivore(), ALL_OPEN, Vector2.ZERO, [])
	assert_eq(decision["intent"], "search_food")
	assert_eq(decision["direction"], Vector2.ZERO, "the caller supplies the roaming heading")


func test_a_wiring_without_a_search_fallback_passes_to_the_next_one():
	# Only the second rung can search; the first, finding no prey, must not
	# stop the walk down the ladder.
	var decision := BehaviorKernel.decide(_ladder(), _omnivore(), ALL_OPEN, Vector2.ZERO, [])
	assert_ne(decision["intent"], "wander")


# -- approach and avoid by the sign of the pull ------------------------------

func test_a_positive_pull_approaches_toward_the_stimulus():
	var decision := BehaviorKernel.decide(
		_ladder(), _omnivore(), ALL_OPEN, Vector2.ZERO, [_stimulus(Vector2(0, 30), {"forage": 1.0})]
	)
	assert_eq(decision["intent"], "seek_food")
	assert_almost_eq(decision["direction"].y, 1.0, 0.001)
	assert_eq(decision["target"], Vector2(0, 30))


func test_a_negative_pull_avoids_away_from_the_stimulus():
	var wirings := [{"gate": "fear", "channels": ["danger"], "approach": "attack", "avoid": "flee"}]
	var timid := _receptors({"danger": 1.0}, {"danger": -1.0})
	var decision := BehaviorKernel.decide(
		wirings, timid, ALL_OPEN, Vector2.ZERO, [_stimulus(Vector2(10, 0), {"danger": 1.0})]
	)
	assert_eq(decision["intent"], "flee")
	assert_lt(decision["direction"].x, 0.0)


## The pillar: the verdict lives in the animal. Same stimulus, same wiring,
## opposite valence, opposite behaviour.
func test_the_verdict_lives_in_the_animal_not_the_stimulus():
	var wirings := [{"gate": "fear", "channels": ["danger"], "approach": "attack", "avoid": "flee"}]
	var threat := [_stimulus(Vector2(10, 0), {"danger": 1.0})]
	var fighter := _receptors({"danger": 1.0}, {"danger": 1.0})
	var decision := BehaviorKernel.decide(wirings, fighter, ALL_OPEN, Vector2.ZERO, threat)
	assert_eq(decision["intent"], "attack")
	assert_gt(decision["direction"].x, 0.0)


## A deer that smells a carcass walks on; it does not bolt from a fruit.
func test_a_repellent_stimulus_on_a_wiring_with_no_avoid_is_ignored():
	var wirings := [{"gate": "hunger", "channels": ["decay"], "approach": "seek_food"}]
	var averse := _receptors({"decay": 1.0}, {"decay": -1.0})
	var decision := BehaviorKernel.decide(
		wirings, averse, ALL_OPEN, Vector2.ZERO, [_stimulus(Vector2(10, 0), {"decay": 1.0})]
	)
	assert_eq(decision["intent"], "wander")


## An un-aggroed world boss does not perceive the player as a threat at all,
## so it neither attacks nor flees: zero SENSITIVITY, not zero valence.
func test_zero_sensitivity_makes_a_stimulus_invisible():
	var wirings := [{"gate": "fear", "channels": ["danger"], "approach": "attack", "avoid": "flee"}]
	var oblivious := _receptors({"danger": 0.0}, {"danger": 1.0})
	var decision := BehaviorKernel.decide(
		wirings, oblivious, ALL_OPEN, Vector2.ZERO, [_stimulus(Vector2(10, 0), {"danger": 1.0})]
	)
	assert_eq(decision["intent"], "wander")


# -- ranking -----------------------------------------------------------------

func test_between_equal_stimuli_the_nearer_wins():
	var wirings := [{"gate": "fear", "channels": ["danger"], "approach": "attack", "avoid": "flee"}]
	var timid := _receptors({"danger": 1.0}, {"danger": -1.0})
	var threats := [_stimulus(Vector2(100, 0), {"danger": 1.0}), _stimulus(Vector2(0, 5), {"danger": 1.0})]
	var decision := BehaviorKernel.decide(wirings, timid, ALL_OPEN, Vector2.ZERO, threats)
	# Nearest threat is below (positive y), so flee upward (negative y).
	assert_lt(decision["direction"].y, 0.0)
	assert_eq(decision["target"], Vector2(0, 5))


func test_between_unequal_stimuli_the_stronger_pull_wins_even_when_farther():
	var wirings := [{"gate": "hunger", "channels": ["sugar"], "approach": "seek_food"}]
	var sweet_tooth := _receptors({"sugar": 1.0}, {"sugar": 1.0})
	var faint_near := _stimulus(Vector2(30, 0), {"sugar": 0.2})
	var strong_far := _stimulus(Vector2(60, 0), {"sugar": 1.0})
	var decision := BehaviorKernel.decide(
		wirings, sweet_tooth, ALL_OPEN, Vector2.ZERO, [faint_near, strong_far]
	)
	assert_eq(decision["target"], Vector2(60, 0))


## A drive is a gain: the level multiplies the score, which is what will let
## a slightly hungry animal be slightly interested once levels are ramps.
func test_the_drive_level_scales_the_score():
	var stimuli := [_stimulus(Vector2(10, 0), {"forage": 1.0})]
	var keen := BehaviorKernel.decide(_ladder(), _omnivore(), {"hunger": 1.0}, Vector2.ZERO, stimuli)
	var peckish := BehaviorKernel.decide(_ladder(), _omnivore(), {"hunger": 0.5}, Vector2.ZERO, stimuli)
	assert_gt(keen["score"], 0.0)
	assert_almost_eq(peckish["score"], keen["score"] * 0.5, 0.0001)


func test_a_stimulus_may_carry_its_features_under_olfactions_mixture_key():
	var wirings := [{"gate": "hunger", "channels": ["sugar"], "approach": "seek_food"}]
	var sweet_tooth := _receptors({"sugar": 1.0}, {"sugar": 1.0})
	var smelled := {"position": Vector2(20, 0), "mixture": {"sugar": 1.0}}
	assert_eq(BehaviorKernel.decide(wirings, sweet_tooth, ALL_OPEN, Vector2.ZERO, [smelled])["intent"], "seek_food")


# -- overlap -----------------------------------------------------------------

func test_overlapping_a_threat_still_yields_a_nonzero_flee_direction():
	var wirings := [{"gate": "fear", "channels": ["danger"], "approach": "attack", "avoid": "flee"}]
	var timid := _receptors({"danger": 1.0}, {"danger": -1.0})
	var decision := BehaviorKernel.decide(
		wirings, timid, ALL_OPEN, Vector2(5, 5), [_stimulus(Vector2(5, 5), {"danger": 1.0})]
	)
	assert_eq(decision["intent"], "flee")
	assert_gt(decision["direction"].length(), 0.5)


# -- the payoff: a species is data --------------------------------------------

## "All animals search for food when they are hungry" is one wiring. Three
## species run it with zero species-specific code.
func test_three_species_share_one_hunger_wiring():
	var hungry := {"fear": 1.0, "thirst": 0.0, "hunger": 1.0, "courtship": 0.0}
	for species in ["boar", "deer", "horse"]:
		var decision := BehaviorKernel.decide(
			Ethogram.wirings_for("mammal"), Ethogram.express(species), hungry, Vector2.ZERO,
			[_stimulus(Vector2(0, 10), {"forage": 1.0})]
		)
		assert_eq(decision["intent"], "seek_food", species)
		assert_almost_eq(decision["direction"].y, 1.0, 0.001, species)


## The same ladder, fed the real fruit mixtures, sends a fly and a boar to
## different fruit -- olfaction's pillar, reached through the kernel. Smells
## arrive through the smell sense (ScentForaging.stimuli_from), which is what
## gives each one its loudness at this range; the smell wiring's floor is
## stated in those units.
func test_a_fly_and_a_boar_choose_different_fruit_through_the_kernel():
	var hungry := {"fear": 1.0, "thirst": 0.0, "hunger": 1.0, "courtship": 0.0}
	var ripe := {"position": Vector2(60, 0), "mixture": Olfaction.fruit_mixture("apple", 1.0)}
	var rotten := {"position": Vector2(-60, 0), "mixture": Olfaction.fruit_mixture("apple", 0.0)}
	var smelled := ScentForaging.stimuli_from(Vector2.ZERO, [ripe, rotten])
	var boar := BehaviorKernel.decide(
		Ethogram.wirings_for("mammal"), Ethogram.express("boar"), hungry, Vector2.ZERO, smelled
	)
	var fly := BehaviorKernel.decide(
		Ethogram.wirings_for("mammal"), Ethogram.express("fly"), hungry, Vector2.ZERO, smelled
	)
	assert_eq(boar["intent"], "seek_food")
	assert_gt(boar["direction"].x, 0.0, "the boar heads for the ripe apple")
	assert_eq(fly["intent"], "seek_food")
	assert_lt(fly["direction"].x, 0.0, "the fly heads for the rotten one")


func test_a_sated_animal_walks_past_a_windfall():
	var sated := {"fear": 1.0, "thirst": 0.0, "hunger": 0.0, "courtship": 0.0}
	var ripe := {"position": Vector2(60, 0), "mixture": Olfaction.fruit_mixture("apple", 1.0)}
	var decision := BehaviorKernel.decide(
		Ethogram.wirings_for("mammal"), Ethogram.express("boar"), sated, Vector2.ZERO, [ripe]
	)
	assert_eq(decision["intent"], "wander")


## An individual's receptor genes reach the decision: a boar born without a
## decay receptor cannot be drawn by a windfall it would otherwise take.
func test_an_expressed_receptor_gene_changes_what_an_individual_does():
	var hungry := {"fear": 1.0, "thirst": 0.0, "hunger": 1.0, "courtship": 0.0}
	var rotten: Dictionary = ScentForaging.stimuli_from(
		Vector2.ZERO, [{"position": Vector2(-60, 0), "mixture": {"decay": 1.0}}]
	)[0]
	var typical := BehaviorKernel.decide(
		Ethogram.wirings_for("mammal"), Ethogram.express("boar"), hungry, Vector2.ZERO, [rotten]
	)
	var anosmic := BehaviorKernel.decide(
		Ethogram.wirings_for("mammal"), Ethogram.express("boar", {"receptor_decay": 0.0}), hungry,
		Vector2.ZERO, [rotten]
	)
	assert_eq(typical["intent"], "seek_food")
	assert_eq(anosmic["intent"], "search_food", "it smells nothing, so it roams for food instead")


# -- slice 2: payloads, sense-supplied strength, floors, helpers -------------

## The winning stimulus comes back whole, so a caller that tagged it with its
## own payload (a node reference, say) gets that payload back.
func test_a_decision_carries_the_winning_stimulus_payload():
	var tagged := {"position": Vector2(10, 0), "features": {"flesh": 1.0}, "node": "wolf-7"}
	var decision := BehaviorKernel.decide(_ladder(), _omnivore(), ALL_OPEN, Vector2.ZERO, [tagged])
	assert_eq(decision["stimulus"]["node"], "wolf-7")
	assert_eq(BehaviorKernel.decide([], _omnivore(), ALL_OPEN, Vector2.ZERO, [])["stimulus"], null)


## A sense that knows how loud a thing is at this range (smell, with its own
## dilution law) says so on the stimulus, and that replaces the distance
## ranking: a strong far smell beats a faint near one.
func test_a_stimulus_may_carry_its_own_strength_instead_of_distance_ranking():
	var wirings := [{"gate": "hunger", "channels": ["sugar"], "approach": "seek_food"}]
	var sweet_tooth := _receptors({"sugar": 1.0}, {"sugar": 1.0})
	var faint_near := {"position": Vector2(10, 0), "features": {"sugar": 1.0}, "strength": 0.1}
	var strong_far := {"position": Vector2(200, 0), "features": {"sugar": 1.0}, "strength": 0.9}
	var decision := BehaviorKernel.decide(
		wirings, sweet_tooth, ALL_OPEN, Vector2.ZERO, [faint_near, strong_far]
	)
	assert_eq(decision["target"], Vector2(200, 0))


func test_a_stimulus_with_zero_strength_is_out_of_range_and_never_chosen():
	var wirings := [
		{"gate": "hunger", "channels": ["sugar"], "approach": "seek_food", "search": "search_food"}
	]
	var sweet_tooth := _receptors({"sugar": 1.0}, {"sugar": 1.0})
	var gone := {"position": Vector2(10, 0), "features": {"sugar": 1.0}, "strength": 0.0}
	assert_eq(
		BehaviorKernel.decide(wirings, sweet_tooth, ALL_OPEN, Vector2.ZERO, [gone])["intent"],
		"search_food"
	)


## Below a wiring floor an animal is not interested enough to cross a field:
## ScentForaging.MIN_INTEREST, now a property of the wiring.
func test_a_wiring_floor_ignores_a_stimulus_too_faint_to_cross_a_field():
	var wirings := [{"gate": "hunger", "channels": ["sugar"], "approach": "seek_food", "floor": 0.5}]
	var sweet_tooth := _receptors({"sugar": 1.0}, {"sugar": 1.0})
	var faint := {"position": Vector2(10, 0), "features": {"sugar": 0.1}, "strength": 1.0}
	var strong := {"position": Vector2(10, 0), "features": {"sugar": 1.0}, "strength": 1.0}
	assert_eq(BehaviorKernel.decide(wirings, sweet_tooth, ALL_OPEN, Vector2.ZERO, [faint])["intent"], "wander")
	assert_eq(BehaviorKernel.decide(wirings, sweet_tooth, ALL_OPEN, Vector2.ZERO, [strong])["intent"], "seek_food")


## The ranking on its own, for a motor program that wants to pick a target
## and commit to it itself (the grazer choosing what to smell its way to).
func test_best_stimulus_ranks_like_decide_and_reports_pull_and_score():
	var sweet_tooth := _receptors({"sugar": 1.0, "decay": 1.0}, {"sugar": 1.0, "decay": -1.0})
	var ripe := {"position": Vector2(30, 0), "features": {"sugar": 1.0}}
	var rotten := {"position": Vector2(10, 0), "features": {"decay": 1.0}}
	var best := BehaviorKernel.best_stimulus(sweet_tooth, ["sugar", "decay"], Vector2.ZERO, [ripe, rotten])
	assert_eq(
		best["stimulus"]["position"], Vector2(10, 0),
		"the rotten one is nearer and pulls as hard, only the other way"
	)
	assert_lt(best["pull"], 0.0)
	assert_gt(best["score"], 0.0)
	assert_true(BehaviorKernel.best_stimulus(sweet_tooth, ["sugar"], Vector2.ZERO, []).is_empty())


## What an animal NOTICES on some channels, whatever it makes of it: the
## marker uses this for "is anything dangerous around" (lift the head from
## grazing, widen the flee radius) whether it would fight or flee.
func test_perceived_lists_the_stimuli_with_any_pull_on_the_channels():
	var boar := _receptors(
		{"predator": 1.0, "player": 0.0, "flesh": 1.0}, {"predator": 1.0, "player": -1.0, "flesh": 0.0}
	)
	var wolf := {"position": Vector2(10, 0), "features": {"predator": 1.0}}
	var person := {"position": Vector2(20, 0), "features": {"player": 1.0}}
	var sheep := {"position": Vector2(30, 0), "features": {"flesh": 1.0}}
	var noticed := BehaviorKernel.perceived(boar, ["predator", "player"], [wolf, person, sheep])
	assert_eq(noticed.size(), 1, "the wolf is noticed (to fight); the player is unsensed; the sheep is off-channel")
	assert_eq(noticed[0]["position"], Vector2(10, 0))
