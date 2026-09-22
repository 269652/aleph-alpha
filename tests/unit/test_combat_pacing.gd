extends GutTest

## The reference exchange (docs/concept/combat.md).
##
## `combat.md` was twenty-four lines of aspiration with no numeric half at
## all, and for as long as it had none the numbers drifted where nothing was
## watching. Measured, driving the real code: the character the game builds
## for a new player felled a wolf in **three swings, 1.5 s**, against a
## `Dodge.COOLDOWN_DURATION` of 1.5 s and a bear rear-up of 0.90 s. The
## telegraph, the windup freeze, the i-frames, the reach asymmetry and the
## braced-knockback rule -- every mechanic built for this fight -- were real,
## tested, and never got a turn.
##
## So this suite pins the rule that says how long a fight must last, and it
## drives the REAL default character rather than a bare `player.tscn`. That
## distinction is the whole point: `test_fight_is_loseable.gd` instantiates
## a player with no class and no item, which swings for 5 instead of 13.6 --
## 2.7x weaker than anything a player ever holds -- so a suite built that
## way would have passed happily through the defect above.

const PlayerScene = preload("res://scenes/player.tscn")
const CombatPacing = preload("res://src/gameplay/combat_pacing.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const StarterKit = preload("res://src/gameplay/starter_kit.gd")
const NightMare = preload("res://src/gameplay/night_mare.gd")

var player


## The character the game actually builds: the warrior lens plus the default
## starting kit, with the axe in hand. Not a bare instantiation.
func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	var archetype := ClassArchetype.new()
	player.apply_class("warrior", archetype.stats_for("warrior"))
	for item_id in StarterKit.DEFAULT_CHOICES:
		var made = player._item_catalog.make(item_id)
		player.inventory.add(made, 1)
		if item_id == "iron_axe":
			player.equip_item(made)


func after_each():
	player.queue_free()


## What the reference character takes off a creature in one swing, computed
## through the same path `_perform_attack` uses -- never restated here, or
## this suite would be checking its own arithmetic instead of the game's.
func _reference_swing() -> float:
	var base: float = (
		player._melee_attack.attack_damage(player._held_weapon(), player.UNARMED_DAMAGE)
		+ player.class_attack_bonus
		+ player._skill_attack_bonus
	)
	return (
		player._material_damage.effective_damage(base, player._held_kind(), "flesh")
		* player._damage_buff_multiplier()
	)


## The health a real individual of `species` is born with, at the level that
## every species shares as its floor, so the comparison is across species
## rather than across dice.
func _base_health_of(species: String) -> float:
	var info := CreatureInfo.new(species)
	info.level = 1
	return (
		float(CreatureInfo.MAX_HEALTH_BY_SPECIES.get(species, 10.0))
		* CombatPacing.EXCHANGE_HEALTH_SCALE
	)


func _bound_species() -> Array:
	var out: Array = []
	for species in SpeciesBite.species_list():
		if CombatPacing.stands_and_trades(species):
			out.append(species)
	return out


# -- the reference character is the one the game builds ------------------

## The precondition the whole suite rests on, asserted rather than assumed.
## An iron axe is a TOOL, so `_held_weapon()` returns null and the swing is
## unarmed damage plus the class bonus -- times the axe-into-flesh
## multiplier, which the axe DOES earn. Getting this wrong in either
## direction retunes the rule below by 60%.
func test_the_reference_character_swings_for_what_the_default_kit_gives():
	assert_almost_eq(_reference_swing(), 13.6, 0.001, "5 unarmed + 12 class, x0.8 into flesh")
	assert_almost_eq(player.ATTACK_COOLDOWN, 0.5, 0.001)


# -- the rule, as arithmetic ---------------------------------------------

## Two windups and one recovery, not two whole cycles: the recovery after
## the last bite is time the fight does not need.
func test_landing_two_bites_does_not_charge_for_the_recovery_after_the_second():
	var windup: float = SpeciesBite.windup_seconds_for("boar", player.max_health)
	var recovery: float = SpeciesBite.bite_cooldown_seconds_for("boar")
	assert_almost_eq(
		CombatPacing.seconds_to_land_bites("boar", player.max_health, 2),
		2.0 * windup + recovery, 0.0001
	)
	assert_lt(
		CombatPacing.seconds_to_land_bites("boar", player.max_health, 2),
		2.0 * (windup + recovery),
		"charging for the trailing recovery would demand more health than the rule needs"
	)


## The first swing lands immediately, so the exchange is the gaps BETWEEN
## swings. Counting a leading cooldown would credit the rule with half a
## second nobody spends.
func test_the_exchange_is_the_gaps_between_swings_not_one_per_swing():
	assert_almost_eq(CombatPacing.exchange_seconds(1, 0.5), 0.0, 0.0001, "one swing takes no time")
	assert_almost_eq(CombatPacing.exchange_seconds(6, 0.5), 2.5, 0.0001)


# -- the rule, against the real roster ------------------------------------

## The heart of it.
func test_every_animal_that_stands_and_trades_gets_two_bites_in():
	var swing := _reference_swing()
	var bound := _bound_species()
	assert_gt(bound.size(), 5, "precondition: the rule binds a real roster, not one animal")
	for species in bound:
		assert_true(
			CombatPacing.lasts_long_enough(
				species, _base_health_of(species), swing,
				player.ATTACK_COOLDOWN, player.max_health
			),
			"%s must live long enough to bite twice" % species
		)


## And the constant is a measurement, not a preference: one tenth lower and
## the roster stops satisfying the rule. Without this half, any number large
## enough would pass and the scale could drift upward unnoticed, making every
## fight a chore in the name of a rule that never asked for it.
func test_the_scale_is_the_smallest_tenth_that_works():
	var swing := _reference_swing()
	var smaller: float = CombatPacing.EXCHANGE_HEALTH_SCALE - 0.1
	var failures := 0
	for species in _bound_species():
		var health: float = float(CreatureInfo.MAX_HEALTH_BY_SPECIES.get(species, 10.0)) * smaller
		if not CombatPacing.lasts_long_enough(
			species, health, swing, player.ATTACK_COOLDOWN, player.max_health
		):
			failures += 1
	assert_gt(
		failures, 0,
		"a tenth lower must break something, or the scale is bigger than the rule requires"
	)


## Which species is doing the binding, pinned so that retuning any other
## animal's health cannot quietly become the thing that sets the scale.
func test_the_boar_is_what_the_scale_is_set_by():
	var swing := _reference_swing()
	var smaller: float = CombatPacing.EXCHANGE_HEALTH_SCALE - 0.1
	var health: float = float(CreatureInfo.MAX_HEALTH_BY_SPECIES.get("boar", 10.0)) * smaller
	assert_false(
		CombatPacing.lasts_long_enough(
			"boar", health, swing, player.ATTACK_COOLDOWN, player.max_health
		),
		"the boar is felled fastest relative to what its own clock asks for"
	)


# -- who the rule does not bind -------------------------------------------

## Exempt by a property the code already owns, never by a name on a list
## here -- so an exemption cannot outlive the reason for it.
func test_the_alp_is_exempt_because_it_never_strikes():
	assert_true(NightMare.presses_instead_of_striking("alp"), "precondition: it presses")
	assert_false(
		CombatPacing.stands_and_trades("alp"),
		"an animal that never strikes has no bites to land"
	)


func test_a_venomous_animal_is_exempt_because_its_threat_outlives_it():
	assert_true(SpeciesBite.VENOMOUS_SPECIES.has("venomous_snake"), "precondition")
	assert_false(
		CombatPacing.stands_and_trades("venomous_snake"),
		"a glass cannon's threat is what it leaves behind, not what it survives"
	)


func test_a_grazer_is_not_a_fight_and_the_rule_says_nothing_about_it():
	assert_false(CombatPacing.stands_and_trades("deer"))
	assert_true(
		CombatPacing.lasts_long_enough("deer", 1.0, 999.0, 0.5, 100.0),
		"an animal the rule does not bind cannot fail it"
	)


# -- and a real creature is really born with it ---------------------------

## The wiring. The rule above is arithmetic until a spawned animal carries
## the health it describes -- this repo's signature failure is a correct,
## tested module with no caller.
func test_a_real_creature_is_born_with_the_scaled_health():
	var info := CreatureInfo.new("wolf")
	var base: float = float(CreatureInfo.MAX_HEALTH_BY_SPECIES["wolf"])
	var levelled: float = base * (1.0 + (info.level - 1) * CreatureInfo.LEVEL_HEALTH_SCALE)
	assert_almost_eq(
		info.max_health, levelled * CombatPacing.EXCHANGE_HEALTH_SCALE, 0.001,
		"the exchange scale reaches the creature the player actually meets"
	)
	assert_almost_eq(info.health, info.max_health, 0.001, "and it is born full")


## The table itself is NOT scaled, and that is deliberate: `Taming`'s
## `PREDATOR_BREAK_FREE_MULTIPLIER` is derived from it, so touching the
## table would make wild animals harder to tame for a reason that has
## nothing to do with taming.
func test_the_species_table_is_left_alone_so_taming_does_not_move():
	assert_almost_eq(
		float(CreatureInfo.MAX_HEALTH_BY_SPECIES["wolf"]), 29.0, 0.001,
		"the authored table is the biology, not the pacing"
	)
