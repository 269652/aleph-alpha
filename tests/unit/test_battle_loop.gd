extends GutTest

## Does a fight actually work? (docs/concept/combat.md, magic.md,
## spell_weaving.md, predator_profiles.md.)
##
## Asked directly: *"we need a way to battletest the new spells and skills"*.
## Every piece of this has its own unit tests -- SpellDraft costs, SpellAtom
## Effects applies, SpellTargeting picks, SpeciesBite bites, SkillWeb grants
## -- and NONE of them answer the only question a player has: if I weave a
## spell and press the key while something is in front of me, does that thing
## die?
##
## So this file is deliberately end to end: a real Player scene, a real
## CreatureMarker out of the real CreatureRenderer, and the real cast path
## (`cast_held` -> `_resolve_cast_target` -> `SpellAtomEffects`). No mocks,
## because every mock here would be a second opinion about the thing under
## test.

const PlayerScene = preload("res://scenes/player.tscn")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const SpellDraft = preload("res://src/gameplay/spell_draft.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var player
var creatures_parent: Node2D
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var manager: EarthChunkManager
var renderer: CreatureRenderer

## Well inside SpellTargeting.TOUCH_RANGE and the projectile cone, so a miss
## is a real miss rather than a range accident.
const IN_REACH := Vector2(12.0, 0.0)


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
	# Mana comes from the class lens and a bare instantiated player has none
	# (ClassArchetype.max_mana) -- this suite is about whether a cast LANDS,
	# not about where a mage's pool comes from.
	player.max_mana = 100.0
	player.mana = player.max_mana


func after_each():
	player.queue_free()
	creatures_parent.free()
	tile_map_layer.free()
	entities_parent.free()


## One real creature of `species`, standing `offset` from the player.
func _creature_at(species: String, offset: Vector2):
	var marker = renderer.spawn_single(
		creatures_parent, species, player.position + offset, manager, TerrainRenderer.TILE_SIZE
	)
	return marker


func _face_the_creature(marker) -> void:
	player._last_facing_direction = (marker.position - player.position).normalized()


# -- the question nothing else answers -----------------------------------

## The whole Magicraft loop, end to end, against something that can die.
func test_a_woven_spell_really_damages_a_real_creature():
	var marker = _creature_at("boar", IN_REACH)
	assert_not_null(marker, "precondition: a real creature spawned")
	_face_the_creature(marker)
	var before: float = marker.info.health
	assert_gt(before, 0.0, "precondition: it is alive to begin with")

	player.grant_mote("fire_damage")
	assert_true(player.weave(SpellDraft.make(["fire_damage"], "projectile")), "precondition: legal weave")
	assert_true(player.cast_held(), "the cast key really casts the woven spell")
	# A real projectile now travels (docs/concept/spell_runtime.md,
	# "Projectile flight: a cast that truly homes") -- its damage lands on
	# arrival, not the same frame it launched.
	_let_every_bolt_land()

	assert_lt(marker.info.health, before, "and the thing in front of it really took damage")


## A cast with nothing in front of it must not crash and must not charge the
## player for a hit that never happened -- the mana IS spent (the spell was
## cast), but nothing takes damage.
func test_casting_at_empty_ground_hurts_nothing_and_does_not_crash():
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))
	player._last_facing_direction = Vector2.RIGHT
	assert_true(player.cast_held(), "an empty field is not a refusal")


## Order is load-bearing in a weave (spell_weaving.md), so a two-atom draft
## has to survive the whole path and still land.
func test_a_two_atom_weave_lands_on_a_real_creature():
	var marker = _creature_at("boar", IN_REACH)
	_face_the_creature(marker)
	var before: float = marker.info.health

	player.grant_mote("frost_damage")
	player.grant_mote("ignite")
	assert_true(player.weave(SpellDraft.make(["frost_damage", "ignite"], "projectile")))
	assert_true(player.cast_held())
	_let_every_bolt_land()

	assert_lt(marker.info.health, before, "a composed spell is a real spell")


## And the learned spell, for a character who has never opened the Weave --
## the fallback path `cast_held` keeps.
func test_the_learned_spell_also_lands_on_a_real_creature():
	var marker = _creature_at("boar", IN_REACH)
	_face_the_creature(marker)
	var before: float = marker.info.health
	assert_true(player.cast_held(), "fire_bolt, the one spell a new character knows")
	assert_lt(marker.info.health, before)


## Enough casts kill it. This is the assertion that makes a fight a fight
## rather than a nuisance: the loop has to TERMINATE.
func test_a_creature_can_actually_be_killed_by_casting():
	var marker = _creature_at("boar", IN_REACH)
	_face_the_creature(marker)
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))

	var casts := 0
	while is_instance_valid(marker) and marker.info.health > 0.0 and casts < 200:
		player.mana = player.max_mana
		# A cast now has a cooldown (docs/concept/spell_runtime.md); this
		# loop is about whether enough casts kill it, not about the real-
		# time pacing between them.
		player._cast_cooldown_remaining = 0.0
		_face_the_creature(marker)
		player.cast_held()
		# A real projectile now travels; let THIS cast's bolt land before the
		# loop re-checks whether the creature is still alive.
		_let_every_bolt_land()
		casts += 1

	assert_lt(casts, 200, "a fight that never ends is not a fight")
	assert_true(
		not is_instance_valid(marker) or marker.info.health <= 0.0,
		"it really died"
	)


# -- a projectile cast truly homes (docs/concept/spell_runtime.md,
# "Projectile flight: a cast that truly homes") -----------------------------
#
# Real play: "selecting a threat with tab doesn't make the spells homing."
# A projectile-delivery cast now spawns a real SpellProjectileMarker that
# tracks its resolved target's LIVE position and only deals damage on
# arrival -- these tests drive it the same way _let_the_jaws_close already
# drives a creature's windup, rather than asserting the same frame a cast
# is thrown.

const SpellProjectileMarker = preload("res://src/rendering/spell_projectile_marker.gd")


func _projectiles_in_the_world() -> Array:
	var seen: Array = []
	for child in player.get_parent().get_children():
		if child is SpellProjectileMarker:
			seen.append(child)
	return seen


## Re-scans every call (rather than snapshotting the list once) since a
## resolved bolt frees itself mid-loop and a chained multi-atom cast can
## still be launching later bolts while an earlier one is already in flight.
func _let_every_bolt_land() -> void:
	var guard := 0
	while not _projectiles_in_the_world().is_empty() and guard < 600:
		for bolt in _projectiles_in_the_world():
			bolt._process(1.0 / 60.0)
		guard += 1


func test_a_projectile_cast_does_not_damage_its_target_the_same_frame():
	var marker = _creature_at("boar", IN_REACH)
	_face_the_creature(marker)
	var before: float = marker.info.health
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))

	assert_true(player.cast_held(), "the cast is accepted")

	assert_almost_eq(
		marker.info.health, before, 0.001,
		"a true projectile has not arrived yet -- damage must not land on the same frame it was thrown"
	)
	assert_false(_projectiles_in_the_world().is_empty(), "a real bolt must have launched")


func test_a_projectile_cast_damages_its_target_once_it_arrives():
	var marker = _creature_at("boar", IN_REACH)
	_face_the_creature(marker)
	var before: float = marker.info.health
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))
	player.cast_held()

	_let_every_bolt_land()

	assert_lt(marker.info.health, before, "the bolt must deal its damage once it actually lands")


## True homing, through the real cast path: the creature moves WHILE the
## bolt it drew is still travelling, and the bolt still catches it -- the
## same claim test_spell_projectile_marker.gd already pins at the node
## level, now proven through Player.cast_held() end to end.
func test_a_projectile_cast_still_catches_a_target_that_moves_mid_flight():
	var marker = _creature_at("boar", Vector2(100.0, 0.0))
	_face_the_creature(marker)
	var before: float = marker.info.health
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))
	player.cast_held()
	var bolts := _projectiles_in_the_world()
	assert_false(bolts.is_empty(), "precondition: a bolt launched")
	bolts[0]._process(1.0 / 60.0)
	marker.position += Vector2(0.0, 40.0)  # steps off the bolt's original line

	_let_every_bolt_land()

	assert_lt(marker.info.health, before, "a bolt that truly homes must still catch a target that moved")


## A miss still throws something real -- it just resolves at empty air
## instead of a creature, the same "a cast is always visible" principle the
## old instant-pop miss already honoured, now proven for the travelling
## case too.
func test_a_projectile_cast_with_nothing_in_range_still_launches_and_whiffs():
	player.grant_mote("fire_damage")
	player.weave(SpellDraft.make(["fire_damage"], "projectile"))
	player._last_facing_direction = Vector2.RIGHT

	player.cast_held()

	assert_false(_projectiles_in_the_world().is_empty(), "an empty-air cast must still launch a real bolt")
	_let_every_bolt_land()
	# Reaching here without error/hang is the assertion: a bolt aimed at a
	# fixed point with nothing to track must resolve and free itself.


# -- and the other direction ---------------------------------------------

## A battletest needs something that fights BACK, or it is target practice.
##
## A bite is no longer instantaneous (docs/concept/predator_profiles.md,
## "The telegraph, in the engine"): `_try_attack` COMMITS, and the jaws
## close a windup later, re-checking reach. So the exchange is driven for
## the species' own telegraph rather than asserted on the same frame.
func test_a_predator_really_damages_the_player():
	var marker = _creature_at("wolf", IN_REACH)
	assert_not_null(marker, "precondition: a wolf spawned")
	var before: float = player.health
	# The real bite, through the real private attack path -- not a
	# hand-rolled number and not a public shortcut invented for this test.
	marker.position = player.position + Vector2(4.0, 0.0)
	marker._attack_cooldown_remaining = 0.0
	marker._try_attack(player)
	_let_the_jaws_close(marker)
	assert_lt(player.health, before, "a predator that cannot hurt you is scenery")


## And it bites for its OWN figure, not some number this test chose.
func test_the_bite_that_landed_is_the_species_own_profile():
	var marker = _creature_at("wolf", IN_REACH)
	var before: float = player.health
	marker.position = player.position + Vector2(4.0, 0.0)
	marker._attack_cooldown_remaining = 0.0
	marker._try_attack(player)
	_let_the_jaws_close(marker)
	assert_almost_eq(before - player.health, marker.bite_damage(), 0.001)


## Real frames until a committed creature's windup runs out. Deliberately
## the creature's OWN remaining clock rather than a round number, so this
## helper cannot quietly go stale when a species' telegraph changes.
func _let_the_jaws_close(marker) -> void:
	var frame := 1.0 / 60.0
	var guard := 0
	while marker.is_winding_up() and guard < 600:
		marker._process(frame)
		guard += 1


func test_the_bite_is_the_species_own_rather_than_one_shared_number():
	var wolf = _creature_at("wolf", IN_REACH)
	var bear = _creature_at("bear", IN_REACH * 2.0)
	assert_ne(
		wolf.bite_damage(), bear.bite_damage(),
		"a bear and a wolf must not bite for the same amount"
	)
