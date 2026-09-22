extends GutTest

## A spell is a blow (docs/concept/spell_runtime.md's rule of that name).
##
## `CreatureMarker.struck_by` is the door a blow is supposed to come
## through: it takes the damage, records the attacker, and sets
## `is_aggroed`. `take_damage` does only the first. Measured before this
## suite existed: `struck_by` had **exactly one caller in the whole game**,
## the melee swing in `_perform_attack` -- so every other way the player
## dealt damage went through the door the world does not notice.
##
## What that made of magic, concretely: a caster could stand inside
## `SpellTargeting.TOUCH_RANGE` of anything on the roster and tap the cast
## key until it died, and it never turned on them, never paid XP, and never
## left a mote. Not a weaker attack -- a different kind of act, one with no
## risk and no reward. And the mage, the one class the Weave exists for, was
## the one character whose own kills could not fill it.
##
## So these tests do not ask "does a spell do damage" (test_battle_loop.gd
## already pins that). They ask whether a kill is a kill.

const PlayerScene = preload("res://scenes/player.tscn")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const SpellDraft = preload("res://src/gameplay/spell_draft.gd")

var player
var creatures_parent: Node2D
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var manager: EarthChunkManager
var renderer: CreatureRenderer

## Well inside SpellTargeting.TOUCH_RANGE and inside ATTACK_RANGE too, so
## the sword and the spell can be compared over the same ground.
const IN_REACH := Vector2(12.0, 0.0)

## The starting spell, so this suite tests the hand a real character is
## dealt rather than one the dev console gave it.
const STARTER := "fire_bolt"


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	add_child(creatures_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	renderer = CreatureRenderer.new()
	player = PlayerScene.instantiate()
	add_child(player)
	player.position = Vector2.ZERO
	# A bare instantiated player has no pool (ClassArchetype's lens is where
	# mana comes from). This suite is about what a landed cast DOES, not
	# about affording it.
	player.max_mana = 1000.0
	player.mana = player.max_mana


func after_each():
	player.queue_free()
	creatures_parent.free()
	tile_map_layer.free()
	entities_parent.free()


func _creature_at(species: String, offset: Vector2):
	var marker = renderer.spawn_single(
		creatures_parent, species, player.position + offset, manager, TerrainRenderer.TILE_SIZE
	)
	# Only the frames a test drives itself (the two-clocks rule -- see
	# tests/unit/test_bite_telegraph.gd).
	marker.set_process(false)
	return marker


func _face(marker) -> void:
	player._last_facing_direction = (marker.position - player.position).normalized()


## Casts until the thing is dead or the cap is hit, and says how many casts
## it took. The cap is generous and only exists so a bug cannot hang a test.
func _burn_down(marker) -> int:
	for i in 200:
		if marker.info == null or marker._death_has_begun():
			return i
		player.cast_spell(STARTER)
		player.mana = player.max_mana
	return -1


# -- it fights back -------------------------------------------------------

## The heart of it. A wolf that has just been set on fire is in a fight.
func test_a_creature_burned_by_a_spell_turns_on_the_caster():
	await get_tree().process_frame
	var wolf = _creature_at("wolf", IN_REACH)
	_face(wolf)
	assert_false(wolf.info.is_aggroed, "precondition: it was minding its own business")

	assert_true(player.cast_spell(STARTER), "precondition: the cast landed")

	assert_true(wolf.info.is_aggroed, "a creature a spell hurts must fight back")
	assert_eq(wolf.aggressor(), player, "and must know who did it")


## The same claim for the woven spell, which is the mage's own verb and
## reaches the world through a different call site.
func test_a_creature_burned_by_a_woven_spell_also_turns_on_the_caster():
	await get_tree().process_frame
	var wolf = _creature_at("wolf", IN_REACH)
	_face(wolf)
	player.grant_mote("fire_damage")
	assert_true(
		player.weave(SpellDraft.make(["fire_damage"], "touch")),
		"precondition: a legal one-atom weave"
	)

	assert_true(player.cast_woven(), "precondition: the weave cast")

	assert_true(wolf.info.is_aggroed, "a woven spell is a blow too")
	assert_eq(wolf.aggressor(), player)


# -- and the kill pays ----------------------------------------------------

## XP for a spell kill, the same XP a sword kill pays.
func test_a_creature_killed_by_a_spell_pays_its_experience():
	await get_tree().process_frame
	var wolf = _creature_at("wolf", IN_REACH)
	_face(wolf)
	var level: int = wolf.info.level
	var before: int = player.experience.total_xp

	var casts := _burn_down(wolf)
	assert_gt(casts, 0, "precondition: it really died, and not on the first frame")

	assert_eq(
		player.experience.total_xp - before, Player.XP_PER_KILL * level,
		"a kill is a kill, however it was dealt"
	)


## A kill is a kill, stated as the invariant rather than as two numbers:
## the same animal on the same ground pays the same whichever verb killed
## it. This is the assertion that cannot drift when XP_PER_KILL is retuned.
##
## Both are pinned to the same level first. `spawn_single` rolls a level per
## individual and the award is `XP_PER_KILL * level`, so two wolves are not
## the same animal until they are -- a first draft of this test compared a
## level-3 sword kill against a level-2 spell kill and read the difference
## as a bug in the credit.
func test_the_sword_and_the_spell_pay_exactly_the_same_for_the_same_animal():
	await get_tree().process_frame

	var by_sword = _creature_at("wolf", IN_REACH)
	by_sword.info.level = 1
	_face(by_sword)
	var sword_before: int = player.experience.total_xp
	for _i in 60:
		if by_sword.info == null or by_sword._death_has_begun():
			break
		player._attack_cooldown_remaining = 0.0
		player._perform_attack()
	var sword_paid: int = player.experience.total_xp - sword_before
	assert_gt(sword_paid, 0, "precondition: the sword kill paid something")
	# Let the felled marker actually leave the tree. queue_free() does not
	# take effect until the frame ends, and a cast resolved in the same
	# frame picks the corpse rather than the live wolf standing on it.
	await get_tree().process_frame

	var by_spell = _creature_at("wolf", IN_REACH)
	by_spell.info.level = 1
	_face(by_spell)
	var spell_before: int = player.experience.total_xp
	_burn_down(by_spell)
	var spell_paid: int = player.experience.total_xp - spell_before

	assert_eq(spell_paid, sword_paid, "the same animal is worth the same either way")


## And the mote, which is the whole Magicraft supply loop
## (docs/concept/spell_weaving.md). Asserted as the same invariant so it
## cannot be satisfied by a spell kill that merely rolls its own odds.
func test_the_sword_and_the_spell_leave_exactly_the_same_mote():
	await get_tree().process_frame

	var by_sword = _creature_at("wolf", IN_REACH)
	_face(by_sword)
	for _i in 60:
		if by_sword.info == null or by_sword._death_has_begun():
			break
		player._attack_cooldown_remaining = 0.0
		player._perform_attack()
	var after_sword: Dictionary = player.motes()
	await get_tree().process_frame

	var by_spell = _creature_at("wolf", IN_REACH)
	_face(by_spell)
	_burn_down(by_spell)
	var after_spell: Dictionary = player.motes()

	# Both kills happen at the same position, and MoteDrop is seeded from
	# the kill's position -- so the two kills roll the SAME thing, and the
	# pouch must therefore have gained it twice, or not at all, but never
	# once.
	for atom_id in after_spell:
		var gained: int = int(after_spell[atom_id]) - int(after_sword.get(atom_id, 0))
		var by_the_sword: int = int(after_sword.get(atom_id, 0))
		assert_eq(
			gained, by_the_sword,
			"the spell kill must leave what the sword kill left (%s)" % atom_id
		)


# -- and it answers -------------------------------------------------------

## A swing that lands puts a number on the thing it hit
## (docs/concept/feedback.md). A cast that lands must too -- the Answerback
## table has had a `cast` row since it was written and nothing ever raised
## it, so a spell that hit and a spell that whiffed looked identical.
func test_a_cast_that_lands_answers_with_the_damage_it_dealt():
	await get_tree().process_frame
	var wolf = _creature_at("wolf", IN_REACH)
	_face(wolf)
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))

	assert_true(player.cast_spell(STARTER))

	var casts: Array = seen.filter(func(f): return f.get("action") == "cast")
	assert_eq(casts.size(), 1, "a landed cast must answer exactly once")
	# The number the player actually sees: Answerback renders the context
	# into `float_text`, the same way a swing's "-12" is rendered.
	var floated := String(casts[0].get("float_text", ""))
	assert_false(floated.is_empty(), "and the answer must carry a number, not a blank")
	assert_gt(
		absf(floated.replace("-", "").replace("+", "").to_float()), 0.0,
		"and that number must be what it actually took off"
	)


## The other half of that, which is what makes it information rather than
## noise: a cast that touched nothing must NOT claim a number.
func test_a_cast_that_lands_on_nothing_does_not_claim_damage():
	await get_tree().process_frame
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))

	player._last_facing_direction = Vector2.RIGHT
	assert_true(player.cast_spell(STARTER), "precondition: an empty cast still resolves")

	var casts: Array = seen.filter(func(f): return f.get("action") == "cast")
	for one in casts:
		assert_true(
			String(one.get("float_text", "")).is_empty(),
			"a cast into empty air has no number to float"
		)


# -- and so does anything else the player throws ---------------------------

## The same rule wearing different clothes. A thrown stone damaged a
## creature and shoved it and never made it angry, so the stone was the
## second way to hurt something without being in a fight with it.
##
## Driven through `_resolve_thrown_stone_impact` directly: the release-power
## and flight machinery above it has its own tests, and what is under test
## here is only which door the impact comes through.
func test_a_creature_hit_by_a_thrown_stone_turns_on_the_thrower():
	await get_tree().process_frame
	var wolf = _creature_at("wolf", IN_REACH)
	assert_false(wolf.info.is_aggroed, "precondition: it was minding its own business")
	var health_before: float = wolf.info.health

	# A momentum well past the bounce threshold, so the stone really bites.
	player._resolve_thrown_stone_impact(wolf.position, 40.0)

	assert_lt(wolf.info.health, health_before, "precondition: the stone really hurt it")
	assert_true(wolf.info.is_aggroed, "a stone that draws blood starts a fight")
	assert_eq(wolf.aggressor(), player, "and the thing knows who threw it")
