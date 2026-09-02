extends GutTest

## How close the player gets before an animal breaks (see
## docs/concept/animal_husbandry.md "The approach").
##
## `CreatureMarker.SENSE_RADIUS` is ONE constant for every creature in the
## world, which is why a mouse and a horse react identically and why the
## approach cannot be played around. This is its replacement for the player
## half: one composed function, one owner.
##
## Every test here is an ORDERING or an INVARIANT, never a number. The
## multipliers must stay retunable; what must not change is that a bigger
## animal breaks earlier, that trust and a crouch bring the player closer, and
## that no combination of the four inputs can ever reach the Schmitt trigger's
## release radius.

const FlightDistance = preload("res://src/gameplay/flight_distance.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const Player = preload("res://scenes/player.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")

const CALM := 0.0
const NO_TRUST := 0.0
const STANDING := false
const CROUCHED := true


# -- the species term --------------------------------------------------------


## Flight-initiation distance really does scale with body size: a bigger prey
## animal is seen from further away, is worth more to a predator, and breaks
## sooner. Derived from AnimalAnatomy's own `world_scale` rather than a second
## hand-authored size table, so the art and the rule cannot disagree.
func test_a_larger_prey_animal_flees_earlier_than_a_smaller_one():
	var ladder := ["mouse", "sheep", "goat", "deer", "horse"]
	var previous := -1.0
	for species in ladder:
		var radius := FlightDistance.radius(species, CALM, NO_TRUST, STANDING)
		assert_gt(radius, previous, "%s should break earlier than the one below it" % species)
		previous = radius


## And the ladder is the real body-size one, not an accident of the table:
## the species term must track world_scale monotonically for the WHOLE roster.
func test_the_species_term_tracks_real_body_size():
	var by_scale := []
	for species in AnimalAnatomy.SPECIES:
		by_scale.append(
			{
				"species": species,
				"scale": float(AnimalAnatomy.profile_for(species).get("world_scale", 1.0)),
				"radius": FlightDistance.radius(species, CALM, NO_TRUST, STANDING),
			}
		)
	by_scale.sort_custom(func(a, b): return a["scale"] < b["scale"])
	for i in range(1, by_scale.size()):
		assert_gte(
			by_scale[i]["radius"],
			by_scale[i - 1]["radius"] - 0.001,
			"%s (scale %.2f) must not break later than %s (scale %.2f)"
			% [
				by_scale[i - 1]["species"],
				by_scale[i - 1]["scale"],
				by_scale[i]["species"],
				by_scale[i]["scale"]
			]
		)


## An unknown id is a real case in this codebase, not defensiveness: it must
## get a workable middle radius rather than zero (never flees) or something
## enormous.
func test_an_unknown_species_still_gets_a_workable_radius():
	var radius := FlightDistance.radius("griffin", CALM, NO_TRUST, STANDING)
	assert_gt(radius, 0.0)
	assert_lt(radius, CreatureMarker.FLEE_RELEASE_RADIUS)


# -- the invariant that owns the Schmitt gap ---------------------------------


## THE single owner of this invariant. Fleeing is entered at the flight radius
## and only released at FLEE_RELEASE_RADIUS; if any legal combination of the
## four inputs could return a radius at or above the release radius, the
## Schmitt trigger inverts and the measured dithering bug (16-23 facing flips
## per 30 simulated seconds) comes straight back.
func test_a_graded_flight_radius_never_dithers():
	for species in AnimalAnatomy.SPECIES:
		for wariness_step in 5:
			for trust_step in 5:
				for crouched in [false, true]:
					var wariness := float(wariness_step) / 4.0
					var trust := float(trust_step) / 4.0
					var radius := FlightDistance.radius(species, wariness, trust, crouched)
					assert_lt(
						radius,
						CreatureMarker.FLEE_RELEASE_RADIUS,
						(
							"%s at wariness %.2f trust %.2f crouched %s reaches the release radius"
							% [species, wariness, trust, crouched]
						)
					)
					assert_gt(radius, 0.0, "%s never flees at all" % species)


# -- the composition directions ----------------------------------------------


func test_a_higher_trust_animal_lets_you_closer():
	var stranger := FlightDistance.radius("horse", CALM, 0.0, STANDING)
	var acquaintance := FlightDistance.radius("horse", CALM, 0.5, STANDING)
	var friend := FlightDistance.radius("horse", CALM, 1.0, STANDING)
	assert_lt(acquaintance, stranger)
	assert_lt(friend, acquaintance)


func test_a_spooked_animal_flees_earlier_than_a_calm_one():
	assert_gt(
		FlightDistance.radius("deer", 1.0, NO_TRUST, STANDING),
		FlightDistance.radius("deer", 0.0, NO_TRUST, STANDING)
	)


## The two composition directions meeting: a crouch is the answer to a spooked
## animal, not a separate mode. Crouching a spooked animal must bring it back
## inside where it stood before it was spooked, or patience is the ONLY verb
## and the stalk buys nothing.
func test_crouching_shrinks_the_radius_a_spooked_animal_widened():
	var calm_standing := FlightDistance.radius("sheep", 0.0, NO_TRUST, STANDING)
	var spooked_standing := FlightDistance.radius("sheep", 1.0, NO_TRUST, STANDING)
	var spooked_crouched := FlightDistance.radius("sheep", 1.0, NO_TRUST, CROUCHED)
	assert_gt(spooked_standing, calm_standing)
	assert_lt(spooked_crouched, spooked_standing)
	assert_lt(spooked_crouched, calm_standing, "a crouch should beat the spook it answers")


# -- the shy threshold -------------------------------------------------------


## Above this approach speed the player reads as a rush no matter what they are
## holding, wearing or crouching behind. Pinned by ORDERING against constants
## that already exist rather than as a number of pixels per second.
func test_the_shy_speed_sits_between_a_crouch_and_a_walk():
	assert_gt(FlightDistance.SHY_SPEED, Player.BASE_SPEED * FlightDistance.CROUCH_SPEED_MULTIPLIER)
	assert_lte(FlightDistance.SHY_SPEED, Player.BASE_SPEED)


func test_a_crouched_approach_is_never_a_rush():
	assert_false(FlightDistance.is_a_rush(Player.BASE_SPEED * FlightDistance.CROUCH_SPEED_MULTIPLIER))


## Taming.MOUNTED_SPEED is 150 against BASE_SPEED 80, so riding a horse up to a
## wild sheep must never work -- and today it silently might.
func test_a_mounted_approach_is_always_a_rush():
	assert_true(FlightDistance.is_a_rush(Taming.MOUNTED_SPEED))


## Standing still is the opposite of a rush, and it is the thing the player
## does while waiting for a baited animal to arrive.
func test_standing_still_is_never_a_rush():
	assert_false(FlightDistance.is_a_rush(0.0))


# -- the smell channel -------------------------------------------------------


## The stalk's other half. Sight is a radius; smell is a plume, and in still
## air it already reaches PAST the radius -- so a keen-nosed animal knows about
## a standing player before its eyes would have made the decision. Which is
## why the direction you come from is the mechanic and not a detail.
func test_a_keen_nose_reaches_past_its_own_flight_radius():
	var flight_tiles := (
		FlightDistance.radius("deer", CALM, NO_TRUST, STANDING) / float(TerrainRenderer.TILE_SIZE)
	)
	assert_true(
		FlightDistance.smells_player("deer", flight_tiles * 1.2),
		"a deer should smell a player standing just outside its flight radius"
	)


## ...but not indefinitely. Smell is loud, not omniscient.
func test_nothing_smells_the_player_from_beyond_smelling_range():
	assert_false(FlightDistance.smells_player("deer", Olfaction.MAX_RANGE_TILES + 1.0))


## A species with no nose at all cannot be given away by the wind, which is
## what keeps the mechanic honest rather than universal.
func test_a_noseless_thing_never_smells_the_player():
	assert_false(FlightDistance.smells_player("griffin", 1.0))


## Species differ, and that is the point: a horse's musk sensitivity is lower
## than a deer's, so a horse is the animal you can walk up to and a deer is the
## one you have to think about the wind for.
func test_a_duller_nose_reaches_less_far_than_a_keen_one():
	var far := Olfaction.MAX_RANGE_TILES * 0.25
	assert_true(FlightDistance.smells_player("deer", far))
	assert_false(FlightDistance.smells_player("horse", far))


## The smell channel gets the same Schmitt gap the sight channel already has,
## expressed in strength instead of distance -- otherwise an animal parked at
## the alarm threshold flickers in and out of fleeing, which is the exact bug
## FLEE_RELEASE_RADIUS exists to prevent.
func test_the_smell_alarm_never_dithers():
	assert_lt(FlightDistance.MUSK_RELEASE_STRENGTH, FlightDistance.MUSK_ALARM_STRENGTH)


func test_an_already_alarmed_animal_keeps_smelling_the_player_slightly_further_out():
	var edge := Olfaction.MAX_RANGE_TILES
	for step in 40:
		var tiles := float(step) / 39.0 * edge
		if FlightDistance.smells_player("deer", tiles, false):
			continue
		# The first distance at which a calm animal loses the scent: an already
		# alarmed one must still have it.
		assert_true(
			FlightDistance.smells_player("deer", tiles, true),
			"the release threshold must be looser than the alarm one at %.2f tiles" % tiles
		)
		return
	fail_test("a deer never loses the player's scent inside smelling range")


## The ceiling is not decoration: it has to leave a gap big enough for the
## Schmitt trigger to still be a Schmitt trigger rather than one threshold with
## a rounding error either side of it.
func test_the_ceiling_leaves_a_real_schmitt_gap():
	assert_lt(FlightDistance.MAX_RADIUS, CreatureMarker.FLEE_RELEASE_RADIUS)
	assert_gte(
		CreatureMarker.FLEE_RELEASE_RADIUS - FlightDistance.MAX_RADIUS,
		FlightDistance.MAX_RADIUS * 0.1,
		"the release radius must stay a real distance above the widest flight radius"
	)


## The calibration that keeps this change from being a nerf: a horse -- the
## animal the tested taming loop is built around -- must not have become
## harder to approach than it was under the flat 80 px constant it replaces.
func test_a_horse_is_no_warier_than_the_flat_radius_it_replaces():
	assert_gte(FlightDistance.radius("horse", CALM, NO_TRUST, STANDING), CreatureMarker.SENSE_RADIUS)


## ...and the change the player actually feels: a small animal now lets them
## much closer than one flat radius for everything ever could.
func test_a_mouse_lets_the_player_much_closer_than_the_flat_radius_did():
	assert_lt(FlightDistance.radius("mouse", CALM, NO_TRUST, STANDING), CreatureMarker.SENSE_RADIUS)
