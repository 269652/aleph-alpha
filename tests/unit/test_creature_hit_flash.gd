extends GutTest

## docs/concept/feedback.md: a blow landing on a creature, seen.
##
## Measured before this: `grep -rni "hit_flash|damage_flash|flash_timer"`
## over `src/`, `scenes/` and `tests/` returned **zero hits** -- the feedback
## doc's own diagnosis said there was no hit flash anywhere in this project
## and that was still exactly true. `CreatureMarker.take_damage`'s only
## visual call, `_begin_one_shot("hurt")`, is a guaranteed no-op for every
## species shipping today (no illustrated "hurt" row exists), so hitting an
## animal changed a number on a bar and nothing else.
##
## The hard part is not the flash. It is that a `CreatureMarker` IS the
## `Sprite2D`, and its `modulate` already has two owners: the one-shot coat
## tint written in `_ready`, and the disease tint rewritten every stepped
## frame for anything not SUSCEPTIBLE. A flash that restores `Color.WHITE`
## erases a creature's coat for the rest of its life.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const HitFlash = preload("res://src/rendering/hit_flash.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")

var marker


func before_each():
	marker = CreatureMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 5
	marker.info = CreatureInfo.new("herbivore")
	add_child(marker)
	# Only the frames a test drives by hand may age this flash -- see the
	# guard in test_bite_telegraph.gd. A marker left on the engine's own
	# `_process` is also aged by real frames, which are milliseconds alone
	# and can be seconds in a loaded batch run.
	marker.set_process(false)


func after_each():
	marker.queue_free()


# -- the rule, pure -------------------------------------------------------

## It composes rather than replaces. A creature washed out to flat white
## loses its silhouette, its coat tell and its disease pallor in the same
## frame, and a player who cannot tell WHICH animal they just hit has been
## handed a worse picture, not a better one.
func test_the_flash_leans_a_creature_toward_red_without_erasing_it():
	var coat := Color(0.4, 0.9, 0.6)
	var flashed: Color = HitFlash.tint(coat, HitFlash.SECONDS)
	assert_gt(flashed.r, coat.r, "it really reddens")
	assert_ne(flashed, HitFlash.colour(), "but it is not simply repainted")


func test_a_flash_that_has_run_out_is_exactly_the_body_underneath():
	var coat := Color(0.4, 0.9, 0.6)
	assert_eq(HitFlash.tint(coat, 0.0), coat)
	assert_eq(HitFlash.tint(coat, -1.0), coat)


func test_the_flash_fades_rather_than_switching_off():
	var coat := Color(0.4, 0.9, 0.6)
	var early: Color = HitFlash.tint(coat, HitFlash.SECONDS)
	var late: Color = HitFlash.tint(coat, HitFlash.SECONDS * 0.25)
	assert_gt(early.r, late.r)
	assert_gt(late.r, coat.r)


## A sick creature that is hit reads as both: still pale, and struck.
func test_it_composes_with_whatever_the_creature_was_already_wearing():
	var pale := CreatureMarker.SICK_MODULATE_COLOR
	var coat := Color(0.4, 0.9, 0.6)
	assert_ne(HitFlash.tint(pale, HitFlash.SECONDS), HitFlash.tint(coat, HitFlash.SECONDS))


## The red is not this module's own opinion: it is the same one the feedback
## table hands the number that floats off the same blow.
func test_the_red_is_the_feedback_tables_own():
	assert_eq(HitFlash.colour(), Answerback.flash_color_for(Answerback.FLASH_HIT))


## Never so far that the body is gone, and never so little that nothing
## happened -- both ends pinned rather than eyeballed.
func test_the_blend_stops_well_short_of_repainting_the_animal():
	assert_lt(HitFlash.PEAK_BLEND, 1.0, "a repainted creature is an unrecognisable one")
	assert_gt(HitFlash.PEAK_BLEND, 0.0, "a flash nobody can see is silence")


## One blow, one flash: as long as the player's own hurt answer is gated
## at, so the two sides of an exchange read on the same clock.
func test_the_flash_lasts_as_long_as_the_other_half_of_the_exchange():
	assert_almost_eq(HitFlash.SECONDS, Answerback.interval_for(Answerback.HURT), 0.0001)


# -- and the marker really wears it ---------------------------------------

## The baseline a flash has to return to, which nothing in this codebase
## could name before: the creature's OWN coat.
func test_a_creatures_baseline_is_its_own_coat():
	var vibrancy: float = AnimalFitness.new().phenotype_for(marker.wander_seed)["coat_vibrancy"]
	assert_eq(marker.base_modulate(), CreatureMarker.coat_tint_for(vibrancy))


## The bug that had to be fixed before a flash could exist at all:
## `HEALTHY_MODULATE_COLOR` was `Color.WHITE`, so the first time a creature
## recovered from a disease its coat tell was erased for the rest of its
## life. A flash restoring the same WHITE would have done it on every blow.
func test_a_recovered_creature_gets_its_own_coat_back_not_flat_white():
	var coat: Color = marker.base_modulate()
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker._disease_step(0.1)
	assert_ne(marker.modulate, coat, "precondition: being sick really shows")
	marker.disease_state = DiseaseModel.State.RECOVERED
	marker._update_disease_tint()
	assert_eq(marker.modulate, coat, "a recovered animal is itself again, not a white one")


func test_a_struck_creature_visibly_flashes():
	var coat: Color = marker.base_modulate()
	marker.take_damage(1.0)
	marker._process(0.0)
	assert_ne(marker.modulate, coat, "hitting an animal shows")


## And it goes back to being itself, rather than staying lit or going white.
func test_the_flash_wears_off_back_to_the_creatures_own_coat():
	var coat: Color = marker.base_modulate()
	marker.take_damage(1.0)
	marker._process(HitFlash.SECONDS * 2.0)
	assert_eq(marker.modulate, coat)


## The trap: an infected creature's tint is rewritten every stepped frame,
## so a flash written once would be stomped on the next step. It has to be
## applied after that writer, not before it.
func test_a_sick_creature_flashes_too():
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker._disease_step(0.1)
	var sick: Color = marker.modulate
	marker.take_damage(1.0)
	marker._process(0.0)
	assert_ne(marker.modulate, sick, "the disease tint must not swallow the blow")


# -- a tick is not a blow, on this side of the fight either ---------------

const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")


## The mirror of the bug that was fixed on the player side, found by an
## adversarial read of THIS change rather than of the old code:
## `_spell_status_step` calls `take_damage` with a per-frame fraction every
## stepped frame, so an ignited creature would relight its own flash sixty
## times a second and sit pinned at peak red for the whole burn. A creature
## permanently the colour of "just hit" tells the player nothing about when
## it was actually hit.
func test_an_ignited_creature_does_not_sit_pinned_at_peak_red():
	marker.apply_spell_debuff(SpellStatusEffects.IGNITE, 10.0)
	for _i in 20:
		marker._spell_status_step(1.0 / 60.0)
	assert_eq(marker.modulate, marker.base_modulate(), "a burn is a condition, not a blow")


## And burning still really hurts -- the flash is what must not fire, not
## the damage.
func test_a_burn_still_burns():
	marker.apply_spell_debuff(SpellStatusEffects.IGNITE, 10.0)
	var before: float = marker.info.health
	for _i in 60:
		marker._spell_status_step(1.0 / 60.0)
	assert_lt(marker.info.health, before, "ignite is real damage")


## A tick does not make an animal angry at anybody either: nothing bit it.
func test_a_burn_does_not_pick_a_fight():
	marker.apply_spell_debuff(SpellStatusEffects.IGNITE, 10.0)
	marker._spell_status_step(1.0 / 60.0)
	assert_null(marker.aggressor(), "a burn has nobody to blame")


# -- and the blow's SIZE reads too ----------------------------------------

## The other half of "the exchange reads BOTH ways". The player's own screen
## flash scales with how much of their bar a bite took; a creature's did
## not, so a scratch and a near-killing blow lit an animal identically.
func test_a_heavier_blow_lights_a_creature_harder():
	var light := CreatureMarker.new()
	light.wander_seed = 5
	light.info = CreatureInfo.new("herbivore")
	add_child_autofree(light)
	light.take_damage(light.info.max_health * 0.05)
	var faint: Color = light.modulate

	var heavy := CreatureMarker.new()
	heavy.wander_seed = 5
	heavy.info = CreatureInfo.new("herbivore")
	add_child_autofree(heavy)
	heavy.take_damage(heavy.info.max_health * 0.6)

	# Measured as distance toward the flash colour rather than "more red",
	# and the difference matters: a coat tint can boost a channel ABOVE 1.0
	# (see coat_tint_for), so leaning such a coat toward UiTheme.NEGATIVE --
	# whose own red is 0.85 -- actually LOWERS the red channel while plainly
	# reddening the animal. The first draft of this test asserted `.r` and
	# was wrong for exactly that reason.
	assert_lt(
		_distance(heavy.modulate, HitFlash.colour()),
		_distance(faint, HitFlash.colour()),
		"how hard it was hit reads on the animal"
	)


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## The scale itself, on the pure rule: a scratch and a killing blow are two
## different depths, and both are somewhere short of repainting the animal.
func test_the_blend_runs_from_a_scratch_to_a_killing_blow():
	assert_lt(HitFlash.FAINTEST_BLEND, HitFlash.PEAK_BLEND)
	assert_gt(HitFlash.FAINTEST_BLEND, 0.0, "a scratch still shows")
	assert_lt(HitFlash.PEAK_BLEND, 1.0, "and a killing blow still leaves an animal")


func test_a_caller_with_no_size_to_report_still_gets_a_full_flash():
	var coat := Color(0.4, 0.9, 0.6)
	assert_eq(
		HitFlash.tint(coat, HitFlash.SECONDS), HitFlash.tint(coat, HitFlash.SECONDS, 1.0)
	)
