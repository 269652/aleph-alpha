extends GutTest

## docs/concept/spell_weaving.md: a spell part is a thing you witnessed,
## then a thing you find, and what you compose from them is a real spell
## cast through the game's own existing pipeline.
##
## Measured before this: 25 atoms, a parser, a cost model, an executor and
## a bound cast key all existed -- and the player could only ever cast a
## fixed authored table (spell_book.gd). There was no way to acquire a part
## or to compose one, which is the whole of the Magicraft loop.

const PlayerScene = preload("res://scenes/player.tscn")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const SpellDraft = preload("res://src/gameplay/spell_draft.gd")
const WitnessConditions = preload("res://src/gameplay/witness_conditions.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()


# -- owning a part ------------------------------------------------------

func test_a_new_character_owns_no_motes():
	assert_eq(player.motes(), {})


func test_witnessing_a_phenomenon_grants_the_mote_it_teaches():
	var atom := SpellMote.first_witness_atom_for(SpellMote.PHENOMENON_WARMED_AT_A_FIRE)
	assert_ne(atom, "", "precondition: standing at a fire teaches something")
	assert_true(player.witness(SpellMote.PHENOMENON_WARMED_AT_A_FIRE), "the first time grants")
	assert_eq(int(player.motes().get(atom, 0)), 1)


## The first one is a story; it does not repeat as one.
func test_witnessing_the_same_phenomenon_again_grants_nothing():
	player.witness(SpellMote.PHENOMENON_WARMED_AT_A_FIRE)
	assert_false(player.witness(SpellMote.PHENOMENON_WARMED_AT_A_FIRE), "already learned")
	var atom := SpellMote.first_witness_atom_for(SpellMote.PHENOMENON_WARMED_AT_A_FIRE)
	assert_eq(int(player.motes().get(atom, 0)), 1, "still one, not two")


func test_an_experience_that_teaches_nothing_grants_nothing():
	assert_false(player.witness("stubbed_a_toe"))
	assert_eq(player.motes(), {})


## After the first witness, motes are a supply: found, not re-learned.
func test_a_found_mote_stacks():
	player.grant_mote("fire_damage")
	player.grant_mote("fire_damage")
	assert_eq(int(player.motes().get("fire_damage", 0)), 2)


# -- composing it -------------------------------------------------------

func test_a_draft_of_motes_you_own_is_accepted():
	player.grant_mote("fire_damage")
	player.grant_mote("ignite")
	assert_true(player.weave(SpellDraft.make(["fire_damage", "ignite"], "projectile")))
	assert_eq(SpellDraft.atoms_of(player.woven_draft()), ["fire_damage", "ignite"])


func test_a_draft_using_a_mote_you_do_not_own_is_refused_with_a_reason():
	player.grant_mote("fire_damage")
	assert_false(player.weave(SpellDraft.make(["fire_damage", "frost_damage"], "projectile")))
	assert_string_contains(player.cast_message.to_lower(), "frost")


func test_an_invalid_draft_is_refused_by_the_shared_validator():
	player.grant_mote("fire_damage")
	assert_false(player.weave(SpellDraft.make([], "projectile")), "an empty weave is not a spell")


# -- and casting it -----------------------------------------------------

## The hinge of the whole feature: what the player composed goes through
## the REAL parser, the REAL cost model and the REAL executor, with no
## second interpreter anywhere.
func test_casting_the_woven_spell_spends_its_real_derived_cost():
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))
	# A bare instantiated player has no class, and mana comes from one
	# (ClassArchetype's max_mana lens), so give this character a pool to
	# spend from -- the test is about the cost being the shared model's,
	# not about where a mage's mana comes from.
	player.max_mana = 50.0
	player.mana = player.max_mana
	var before: float = player.mana
	assert_true(player.cast_woven(), "a composed spell really casts")
	var expected: float = SpellDraft.cost_of(player.woven_draft())
	assert_almost_eq(before - player.mana, expected, 0.001, "the cost is the shared model's own")


func test_casting_with_no_weave_is_a_refusal_not_a_crash():
	assert_false(player.cast_woven())


func test_casting_without_the_mana_is_refused_and_spends_nothing():
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))
	player.mana = 0.0
	assert_false(player.cast_woven())
	assert_eq(player.mana, 0.0)


func test_the_woven_spell_survives_a_save_and_load():
	player.grant_mote("fire_damage")
	player.grant_mote("ignite")
	player.weave(SpellDraft.make(["fire_damage", "ignite"], "projectile"))
	var saved: Dictionary = player.to_save_dict()

	var loaded = PlayerScene.instantiate()
	add_child(loaded)
	loaded.apply_save_dict(saved)
	assert_eq(SpellDraft.atoms_of(loaded.woven_draft()), ["fire_damage", "ignite"], "the weave is kept")
	assert_eq(int(loaded.motes().get("fire_damage", 0)), 1, "and so are the parts")
	loaded.queue_free()


# -- and the world really teaches them ----------------------------------
#
# A witness table nothing calls is exactly the "real, tested, zero
# callers" pattern the diagnosis found all over this codebase. These
# assert the call sites exist in the paths that already detect each
# condition, so the phenomena are learnable in play rather than in theory.

## Freezing and the fire are decided by the shared rule now
## (WitnessConditions) rather than by two `if`s in the step, so these ask
## the RULE whether the path exists and the player whether it lands --
## which is what they were always about. The old form asserted that one
## particular string appeared in player.gd, and would have gone red on a
## refactor that changed nothing a player can feel.
func test_the_freezing_path_teaches_what_freezing_teaches():
	assert_true(
		WitnessConditions.taught_by({"freezing": true}).has(SpellMote.PHENOMENON_FROZE),
		"the cold that is already killing you is where frost is learned"
	)
	assert_true(player.witness(SpellMote.PHENOMENON_FROZE), "and it reaches the pouch")


func test_the_venom_path_teaches_what_venom_teaches():
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_true(source.contains("SpellMote.PHENOMENON_ENVENOMATED"))


func test_standing_at_a_fire_teaches_fire():
	assert_true(
		WitnessConditions.taught_by({"at_a_fire": true}).has(
			SpellMote.PHENOMENON_WARMED_AT_A_FIRE
		)
	)
	assert_true(player.witness(SpellMote.PHENOMENON_WARMED_AT_A_FIRE))


## Being bitten really does hand over the mote, through the real path.
func test_being_envenomated_really_grants_the_mote():
	assert_eq(player.motes(), {}, "precondition")
	player.apply_venom()
	var atom := SpellMote.first_witness_atom_for(SpellMote.PHENOMENON_ENVENOMATED)
	assert_eq(int(player.motes().get(atom, 0)), 1, "the bite taught it")


# -- and the cast key really reaching it ---------------------------------
#
# Found by playing it: `cast_woven` had ZERO callers. The Weave window
# authored a spell, `weave` accepted it, `cast_woven` was tested -- and the
# cast key still ran `cast_spell(DEFAULT_CAST_SPELL_ID)` unconditionally, so
# pressing it cast Fire Bolt whatever the player had composed. The whole
# Magicraft loop was a surface with no trigger, which is exactly the "real,
# tested, zero callers" pattern this overhaul was diagnosing.

func test_the_cast_key_casts_what_the_player_wove():
	player.grant_mote("frost_damage")
	player.weave(SpellDraft.make(["frost_damage"], "projectile"))
	player.max_mana = 50.0
	player.mana = player.max_mana
	var before: float = player.mana
	assert_true(player.cast_held(), "the key casts")
	var woven_cost: float = SpellDraft.cost_of(player.woven_draft())
	assert_almost_eq(
		before - player.mana, woven_cost, 0.001,
		"what it spent is the WOVEN spell's cost, not the default spell's"
	)


## The other half of the same fact: the default spell has to still be there
## for a character who has woven nothing, or the key goes dead for everyone
## who never opens the Weave.
func test_the_cast_key_still_casts_the_learned_spell_when_nothing_is_woven():
	assert_eq(player.woven_draft(), {}, "precondition: nothing composed")
	player.max_mana = 50.0
	player.mana = player.max_mana
	assert_true(player.cast_held(), "a character who never wove anything can still cast")
	assert_lt(player.mana, 50.0, "and it really spent something")


## The two paths must be distinguishable, or the test above could pass while
## casting the wrong spell.
func test_the_woven_cost_really_differs_from_the_default_spells():
	player.grant_mote("frost_damage")
	player.grant_mote("ignite")
	assert_true(
		player.weave(SpellDraft.make(["frost_damage", "ignite"], "projectile")),
		"precondition: this really is a legal arrangement"
	)
	player.max_mana = 90.0
	player.mana = player.max_mana
	var woven_cost: float = SpellDraft.cost_of(player.woven_draft())
	player.cast_held()
	var spent_woven: float = 90.0 - player.mana

	var plain = PlayerScene.instantiate()
	add_child(plain)
	plain.max_mana = 90.0
	plain.mana = plain.max_mana
	plain.cast_held()
	var spent_default: float = 90.0 - plain.mana
	plain.queue_free()

	assert_almost_eq(spent_woven, woven_cost, 0.001)
	assert_ne(spent_woven, spent_default, "the two paths must be telling apart")


## The key is the one the game says it is -- not a second opinion about
## which key casts.
func test_the_cast_step_goes_through_the_one_shared_entry_point():
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_true(
		source.contains("cast_held()"),
		"the input step must call the shared decision, not re-make it"
	)
