extends RefCounted

## The shared, species/instance-agnostic caloric-balance core every real,
## live creature mass in this project runs on -- see docs/concept/
## metabolism.md. Same stateful-instance-plus-advance(delta) shape
## SurvivalMeters/CreatureNeeds already establish for hunger/thirst/warmth,
## applied here to MASS: `current_mass_kg` is the ONE real, live value a
## creature instance carries (see docs/concept/metabolism.md's "one real
## mass per creature" pillar) -- CreatureMass.mass_kg_for(species) only
## ever seeds it, once, at construction; nothing about a live instance's
## OWN current weight is read from that table again.
##
## Generalizes the real Kleiber's-law math MushroomBiting.
## satiation_seconds_for already derived a satiation-duration EXPONENT
## from into a real, direct BMR/calorie/mass model: burn depends on the
## creature's own current mass (Kleiber) AND its real, already-observed
## activity level (MET-style tiers); intake comes from real eating events
## (feed_mass_kg); net calories drive real mass drift, bounded by a real
## starvation floor and overfeeding ceiling so an untended creature reads
## as "thin" or "healthy", never as unbounded or negative.
##
## Pure math lives in the static functions; only current_mass_kg (and the
## seed it's bounded against) is real per-instance state.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Kleiber's law (Kleiber, 1932, "Body size and metabolism"): basal
## metabolic rate scales with body mass to roughly the 0.75 power, not
## linearly -- BMR(kcal/day) ~= 70 * mass_kg^0.75. Holds, famously, from
## mice to elephants. The real, standard, commonly-cited coefficient/
## exponent pair -- not tuned against any one species in this project.
const KLEIBER_COEFFICIENT_KCAL_PER_DAY := 70.0
const KLEIBER_MASS_EXPONENT := 0.75

## Real, MET-inspired (Metabolic Equivalent of Task) activity tiers this
## module's OWN closed vocabulary -- NOT an Ethogram/Drives concept (see
## docs/concept/metabolism.md: confirmed, by reading both docs in full,
## that neither ethogram.md nor behavior_dsl.md ever mentions metabolic
## cost). Each creature family's own controller maps its real,
## already-existing phase/intent signal to one of these four at the call
## site -- this module knows nothing about any other module's enums.
const ACTIVITY_RESTING := "resting"
const ACTIVITY_FEEDING := "feeding"
const ACTIVITY_MOVING := "moving"
const ACTIVITY_EXERTION := "exertion"

## Real-world MET ballpark: resting is the 1x baseline by definition;
## stationary feeding sits just above it; ordinary ambulatory
## activity (walking/foraging/wandering) is real light-activity MET
## territory; genuine exertion (fleeing, fighting, chasing, courting) is
## real vigorous-activity MET territory. Four real, ordered tiers, not a
## continuous invented curve -- pinned by
## test_activity_tiers_are_ordered_like_real_met_values.
const _ACTIVITY_MULTIPLIER := {
	ACTIVITY_RESTING: 1.0,
	ACTIVITY_FEEDING: 1.2,
	ACTIVITY_MOVING: 1.75,
	ACTIVITY_EXERTION: 5.0,
}

## The standard real energy-to-tissue-mass conversion: ~3500 kcal per
## pound of body mass, converted to metric (3500 / 0.45359237 ~= 7716,
## commonly rounded to 7700) -- applied uniformly across every species as
## an honest, named simplification (see docs/concept/metabolism.md's own
## real-world-grounding section): real body composition varies, this is
## the standard cited figure.
const KCAL_PER_KG_BODY_MASS := 7700.0

## Fresh whole food (plant, fungal, or animal) commonly runs in the very
## rough real range of 1-3 kcal per gram wet mass; 2 kcal/g (2000 kcal/kg)
## sits centrally and stands in for every food type this pass wires
## through the shared model, the same level of coarse-but-real honesty
## NutrientRelease's own "vitamins" abstraction already accepts for
## itself.
const CALORIES_PER_KG_FOOD := 2000.0

## Real starvation has a floor -- a severely starved real animal loses on
## the rough order of half its healthy body mass before death, not all of
## it. Real overfeeding has a ceiling -- a well-fed animal accumulates fat
## but does not balloon indefinitely. Both bound current_mass_kg relative
## to the SEED it was constructed with, so an untended creature always
## reads as "thin" or "healthy", never mathematically unbounded or
## negative. Pinned by test_starvation_floor_is_a_real_partial_loss_not_
## zero_or_full_loss / test_overfeeding_ceiling_is_a_real_partial_gain_
## not_unbounded.
const MIN_MASS_FRACTION_OF_SEED := 0.5
const MAX_MASS_FRACTION_OF_SEED := 1.5

## The one real, live mass value -- see this file's own class doc comment.
var current_mass_kg: float

var _seed_mass_kg: float


## `seed_mass_kg` is the species archetype figure a fresh creature
## initializes to -- CreatureMass.mass_kg_for(species) for wildlife/
## decomposers, CreatureMass.PLAYER_MASS_KG for the player. Never read
## again after this call: from here on current_mass_kg is the one real
## value (see docs/concept/metabolism.md's "one real mass per creature"
## pillar).
func _init(seed_mass_kg: float) -> void:
	_seed_mass_kg = seed_mass_kg
	current_mass_kg = seed_mass_kg


## `activity`'s real MET-style multiplier -- an unrecognized string
## (a typo, or an integration that hasn't mapped its own phase yet) fails
## SAFE to the resting baseline, never to the most expensive tier.
static func activity_multiplier_for(activity: String) -> float:
	if _ACTIVITY_MULTIPLIER.has(activity):
		return float(_ACTIVITY_MULTIPLIER[activity])
	return float(_ACTIVITY_MULTIPLIER[ACTIVITY_RESTING])


## Kleiber's law directly -- see this file's own const doc comment.
static func bmr_kcal_per_day(mass_kg: float) -> float:
	return KLEIBER_COEFFICIENT_KCAL_PER_DAY * pow(mass_kg, KLEIBER_MASS_EXPONENT)


## Real kcal burned over `delta_seconds` at `mass_kg`'s own BMR, scaled by
## `activity`'s real multiplier -- BMR is a PER-DAY figure, converted
## against the world's own day (SeasonCycle.SECONDS_PER_DAY), the same
## clock every other body-clock in this project already keeps (see
## test_resting_for_one_world_day_costs_exactly_one_days_bmr).
static func calories_burned(mass_kg: float, activity: String, delta_seconds: float) -> float:
	return (
		bmr_kcal_per_day(mass_kg)
		/ SeasonCycle.SECONDS_PER_DAY
		* activity_multiplier_for(activity)
		* delta_seconds
	)


## Real kcal one whole, real `food_mass_kg` of fresh food actually
## contains -- see CALORIES_PER_KG_FOOD's own doc comment.
static func calories_from_food_mass_kg(food_mass_kg: float) -> float:
	return maxf(food_mass_kg, 0.0) * CALORIES_PER_KG_FOOD


## Real signed mass change a net `kcal` calorie balance produces -- see
## KCAL_PER_KG_BODY_MASS's own doc comment. Positive kcal (a surplus)
## yields a positive (gain) mass delta; negative (a deficit) a loss.
static func mass_delta_kg_for_calories(kcal: float) -> float:
	return kcal / KCAL_PER_KG_BODY_MASS


## Burns `delta_seconds` of real calories at this creature's OWN current
## mass and `activity` -- the ongoing, continuous half of the balance
## (see feed_mass_kg for the discrete, event-driven half).
func advance(delta_seconds: float, activity: String = ACTIVITY_RESTING) -> void:
	_apply_calorie_delta(-calories_burned(current_mass_kg, activity, delta_seconds))


## A real, discrete eating event: `food_mass_kg` of real food just eaten
## (already itself scaled by however much of a whole item this bite
## actually consumed -- see docs/concept/metabolism.md's mushroom-gap
## section) converts to real calories and drives a real mass gain.
func feed_mass_kg(food_mass_kg: float) -> void:
	_apply_calorie_delta(calories_from_food_mass_kg(food_mass_kg))


## A real, discrete eating event expressed as a FRACTION of a whole day's
## hunger-meter relief -- the same 0..1-scaled unit CreatureNeeds/Drives'
## `feed`/`feed_amount` and the fruit/mushroom NutrientRelease "sugar"
## fraction already produce -- rather than a raw food mass. Lets every one
## of those existing wildlife bite call sites feed this same real
## Metabolism instance with no separate per-food-type mass table: relieving
## a WHOLE day's hunger (relief_fraction 1.0) is grounded against THIS
## creature's own real BMR for one day (see bmr_kcal_per_day), so a big
## animal's "one full meal" implies more real calories than a small one's,
## for free. `feed_mass_kg` stays the right call for a caller that already
## knows a real food mass (a picked-up item's own mass_kg).
func feed_hunger_relief(relief_fraction: float) -> void:
	_apply_calorie_delta(maxf(relief_fraction, 0.0) * bmr_kcal_per_day(current_mass_kg))


## The one path both advance()/feed_mass_kg() route a calorie delta
## through -- so there is exactly one place current_mass_kg is ever
## written, and exactly one place the real starvation floor/overfeeding
## ceiling are enforced.
func _apply_calorie_delta(kcal: float) -> void:
	current_mass_kg = clampf(
		current_mass_kg + mass_delta_kg_for_calories(kcal),
		_seed_mass_kg * MIN_MASS_FRACTION_OF_SEED,
		_seed_mass_kg * MAX_MASS_FRACTION_OF_SEED
	)
