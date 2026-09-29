extends GutTest

## A freshly made mage can cast, on the key, without a dev console
## (docs/concept/magic.md, spell_runtime.md).
##
## Reported from play, having picked mage at character creation:
##
##   "Z tries to sell to a merchant / /arena does not exist / 6,7,8 are
##    empty ... No way to cast anything atm"
##
## Every earlier suite here tests a PIECE of that sentence -- the executor
## resolves, the bar maps slots, the tuition list contains a projectile --
## and a player can still be unable to cast while all of them pass. So this
## one drives the whole path the game itself drives, in the same order
## `World._spawn_local_singleplayer` does it, and asks the only question
## that matters: press the key, does a spell come out.

const PlayerScene = preload("res://scenes/player.tscn")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const SpellTuition = preload("res://src/gameplay/spell_tuition.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")

var player


## The mage the game builds when a player picks that card in the character
## creator: the class lens, nothing else. No console, no granted mana, no
## hand-placed spells.
func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	player.apply_class("mage", ClassArchetype.new().stats_for("mage"))


func after_each():
	player.queue_free()


# -- the pool ---------------------------------------------------------------

func test_a_new_mage_is_born_with_mana():
	assert_gt(player.max_mana, 0.0, "a mage without a pool cannot cast anything")
	assert_almost_eq(player.mana, player.max_mana, 0.001, "and starts full")


# -- the hand ---------------------------------------------------------------

## The complaint was "6,7,8 are empty". The bar holds the Nth entry of
## known_spell_ids, so an empty slot means an empty hand.
func test_the_first_three_slots_of_the_bar_are_not_empty():
	for slot in [0, 1, 2]:
		assert_ne(
			player.spell_in_slot(slot), "",
			"slot %d (key %d) must hold a spell a new mage already knows" % [slot, slot + 6]
		)


func test_the_hand_is_the_starting_list_and_not_something_narrower():
	assert_eq(
		player.known_spell_ids().size(), SpellTuition.STARTING_SPELL_IDS.size(),
		"a new character knows exactly what the starting list says"
	)


# -- the key ----------------------------------------------------------------

## The cast key is Z and the sell key is Y, and they are different keys.
## Reported as "Z tries to sell to a merchant", which no shipped default has
## ever done -- so this pins the defaults themselves, and a collision
## between ANY two actions fails rather than being discovered in play.
func test_no_two_verbs_share_a_default_key():
	var seen := {}
	for row in Keybindings.ACTIONS:
		var key: int = int(row["default"])
		var action := String(row["action"])
		assert_false(
			seen.has(key),
			"%s and %s both default to the same key" % [action, seen.get(key, "")]
		)
		seen[key] = action


func test_the_cast_key_is_not_the_sell_key():
	var by_action := {}
	for row in Keybindings.ACTIONS:
		by_action[String(row["action"])] = int(row["default"])
	assert_ne(by_action.get("cast", -1), by_action.get("sell", -2))


# -- pressing it ------------------------------------------------------------

## The whole question, end to end: the selected spell casts and it costs
## real mana. `cast_held()` is exactly what `_cast_step` calls on the rising
## edge of the cast key, so this is the keypress with the input layer
## removed.
func test_pressing_cast_really_casts_and_really_spends():
	assert_ne(player.selected_spell_id(), "", "precondition: something is loaded")
	var before: float = player.mana

	assert_true(player.cast_held(), "the cast key must produce a spell")

	assert_lt(player.mana, before, "and it must cost the pool something")


## And every slot the bar shows can be cast from its own key, not just the
## first -- the failure reported was slots, not the cast verb.
func test_every_filled_slot_casts_from_its_own_key():
	for slot in player.spell_slot_count():
		if player.spell_in_slot(slot) == "":
			continue
		player.mana = player.max_mana
		assert_true(
			player.cast_spell_slot(slot),
			"key %d holds %s and must cast it" % [slot + 6, player.spell_in_slot(slot)]
		)


## A mage's pool must afford a real opening exchange rather than one bolt.
## Pinned as a count so a costing change that quietly halves a mage's
## opening cannot pass unnoticed.
func test_a_full_pool_is_worth_more_than_a_couple_of_casts():
	var casts := 0
	while player.cast_spell(player.selected_spell_id()) and casts < 100:
		casts += 1
	assert_gt(casts, 5, "a full pool that buys fewer than six casts is not a caster's pool")


# -- and an older character catches up --------------------------------------

## Updating the game must actually fix the empty slots, and without this it
## does not.
##
## `known_spell_ids` is persisted. A character created while the starting
## hand was `["fire_bolt"]` has exactly that in their save, so loading them
## into a build whose hand is wider restores the NARROWER list and leaves
## keys 7 and 8 empty for ever. The player updates, sees no change, and
## concludes the feature does not work.
##
## A starting spell is one every character is born knowing and none can
## unlearn, so the saved list is a floor rather than the whole truth: what
## you knew, plus whatever everyone now starts with.
func test_a_character_saved_before_the_hand_widened_learns_the_rest_on_load():
	var old_save: Dictionary = player.to_save_dict()
	old_save["known_spell_ids"] = ["fire_bolt"]

	var reloaded = PlayerScene.instantiate()
	add_child(reloaded)
	reloaded.apply_class("mage", ClassArchetype.new().stats_for("mage"))
	reloaded.apply_save_dict(old_save)

	for spell_id in SpellTuition.STARTING_SPELL_IDS:
		assert_true(
			reloaded.known_spell_ids().has(spell_id),
			"an older save must catch up to the starting hand (%s)" % spell_id
		)
	reloaded.queue_free()


## And it does not forget what that character actually learned at a guild --
## the saved list is a floor, not a replacement.
func test_catching_up_does_not_cost_a_character_what_they_were_taught():
	var old_save: Dictionary = player.to_save_dict()
	old_save["known_spell_ids"] = ["fire_bolt", "frost_lance"]

	var reloaded = PlayerScene.instantiate()
	add_child(reloaded)
	reloaded.apply_class("mage", ClassArchetype.new().stats_for("mage"))
	reloaded.apply_save_dict(old_save)

	assert_true(
		reloaded.known_spell_ids().has("frost_lance"),
		"a spell bought at a guild must survive the catch-up"
	)
	reloaded.queue_free()


# -- a cast you can see -----------------------------------------------------

## Asked from play: *"do the spells have visuals?"*
##
## They do -- `SpellEffectMarker` grows, holds and fades an atom's own
## procedural sprite. But it is spawned ONLY when `apply_to_target` returned
## true, and that returns false the moment the target is null. Fire Bolt is
## `cast(touch)` at 24 px, so unless a creature is practically underfoot,
## `_resolve_cast_target` finds nothing and the cast shows **nothing at
## all**: the mana is already spent, the character plays its swing, and no
## spell appears anywhere.
##
## A player cannot tell that from a dead key, which is exactly how this was
## reported. magic.md's rule is that an affordable spell still has to LAND --
## it is allowed to hit nothing. It is not allowed to be invisible.
const SpellEffectMarker = preload("res://src/rendering/spell_effect_marker.gd")


## Every spell effect currently in the world. Counted as a DELTA by the
## tests below rather than against zero: a marker frees itself when its
## grow-hold-fade tween finishes, and no tween advances in a headless test,
## so earlier casts in this same suite leave theirs standing.
func _effects_in_the_world() -> Array:
	var seen: Array = []
	for child in player.get_parent().get_children():
		if child is SpellEffectMarker:
			seen.append(child)
	return seen


func test_a_cast_that_hits_nothing_still_shows_itself():
	var before: int = _effects_in_the_world().size()

	player._last_facing_direction = Vector2.RIGHT
	assert_true(player.cast_spell("fire_bolt"), "precondition: the cast resolved")

	assert_gt(
		_effects_in_the_world().size(), before,
		"a spell you paid for must appear somewhere, even when it finds nothing"
	)


## And it appears where it was AIMED rather than on top of the caster, so a
## miss reads as a miss -- something left your hands and fell short --
## rather than as a fizzle.
func test_the_miss_appears_out_in_front_of_the_caster():
	var before: Array = _effects_in_the_world()

	player._last_facing_direction = Vector2.RIGHT
	player.cast_spell("fire_bolt")

	var fresh: Array = []
	for effect in _effects_in_the_world():
		if not before.has(effect):
			fresh.append(effect)
	assert_false(fresh.is_empty(), "no effect was spawned at all")
	for effect in fresh:
		assert_gt(
			effect.position.x, player.position.x,
			"a spell aimed right must show to the right of the caster"
		)


## A projectile reaches further than a touch spell, and a miss shows that:
## watching where your spell falls is how the reach of each delivery
## becomes legible without a manual.
func test_a_projectile_miss_falls_further_out_than_a_touch_miss():
	const SpellTargeting = preload("res://src/gameplay/spell_targeting.gd")
	player._last_facing_direction = Vector2.RIGHT
	assert_almost_eq(
		player._aim_point("projectile").x,
		player.position.x + SpellTargeting.PROJECTILE_RANGE, 0.001
	)
	assert_almost_eq(
		player._aim_point("touch").x,
		player.position.x + SpellTargeting.TOUCH_RANGE, 0.001
	)
	assert_gt(player._aim_point("projectile").x, player._aim_point("touch").x)


## A self-delivered spell shows on the caster, because that is where it
## happened -- a heal that appeared twenty pixels away would be a lie about
## what it did.
func test_a_self_spell_shows_on_the_caster():
	player._last_facing_direction = Vector2.RIGHT
	assert_almost_eq(player._aim_point("self").x, player.position.x, 0.001)
