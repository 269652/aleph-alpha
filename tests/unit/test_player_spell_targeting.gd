extends GutTest

## Player-side wiring for explicit spell target selection
## (docs/concept/spell_runtime.md, "Explicit target selection"). The pure
## index/identity math already lives in SpellTargetSelection (see
## test_spell_target_selection.gd) and the visual ring already lives on
## CreatureMarker (see test_creature_marker.gd); this covers the scene-tree
## glue only: which live creatures qualify as candidates, how Tab/Shift+Tab
## move `_explicit_target`, and -- the one place a bug here would be a real
## exploit rather than just a wrong pick -- that `_resolve_cast_target`
## commits to a live explicit target even when it is out of range (a miss)
## rather than ever redirecting to something actually in range.
##
## World's click-to-target and Escape-to-clear wiring (task #44) is untested
## glue over the public `toggle_explicit_target`/`clear_explicit_target`/
## `has_explicit_target` methods this file already covers.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const SpellTargeting = preload("res://src/gameplay/spell_targeting.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player
var interior_viewport: SubViewport


func before_each():
	# World._apply_keybindings normally registers every Keybindings action
	# onto the InputMap at runtime (there is no static [input] section in
	# project.godot) -- this test instantiates Player directly, without a
	# World, so it registers the one action it needs itself that Player's
	# own _bind_key_action fallback doesn't cover (see test_player_kick.gd).
	if not InputMap.has_action("dodge"):
		InputMap.add_action("dodge")

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))

	interior_viewport = SubViewport.new()
	add_child(interior_viewport)

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	player.setup(chunk_manager, TILE_SIZE)
	player.set_interior_view_host(interior_viewport, null)
	player._last_facing_direction = Vector2.DOWN
	player.survival.stamina = 1.0


func after_each():
	remove_child(player)
	player.free()
	remove_child(interior_viewport)
	interior_viewport.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("dodge")
	Input.action_release("sprint")


func _creature_at(species: String, offset: Vector2) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new(species, 1)
	marker.wander_seed = 9
	add_child_autofree(marker)
	marker.setup(chunk_manager, TILE_SIZE)
	marker.position = player.position + offset
	return marker


# -- _nearby_enemy_candidates(): the selectable pool -------------------------
# "hostile creatures only, out to CAUTION_RADIUS" (spell_runtime.md).

func test_nothing_nearby_is_an_empty_pool():
	assert_eq(player._nearby_enemy_candidates(), [])


func test_a_predator_in_range_is_a_candidate():
	var wolf := _creature_at("wolf", Vector2(50, 0))
	var result := player._nearby_enemy_candidates()
	assert_eq(result.size(), 1)
	assert_same(result[0], wolf)


func test_an_aggressive_non_predator_in_range_is_also_a_candidate():
	var boar := _creature_at("boar", Vector2(50, 0))
	var result := player._nearby_enemy_candidates()
	assert_eq(result.size(), 1)
	assert_same(result[0], boar)


func test_a_calm_herbivore_is_never_a_candidate_however_close():
	_creature_at("horse", Vector2(10, 0))
	assert_eq(player._nearby_enemy_candidates(), [])


func test_a_hostile_creature_beyond_caution_radius_is_not_a_candidate():
	_creature_at("wolf", Vector2(CreatureMarker.CAUTION_RADIUS + 10.0, 0))
	assert_eq(player._nearby_enemy_candidates(), [])


func test_a_hostile_creature_just_inside_caution_radius_is_a_candidate():
	var wolf := _creature_at("wolf", Vector2(CreatureMarker.CAUTION_RADIUS - 1.0, 0))
	var result := player._nearby_enemy_candidates()
	assert_eq(result.size(), 1)
	assert_same(result[0], wolf)


func test_candidates_are_sorted_nearest_first():
	var far := _creature_at("wolf", Vector2(100, 0))
	var near := _creature_at("boar", Vector2(20, 0))
	var result := player._nearby_enemy_candidates()
	assert_eq(result.size(), 2)
	assert_same(result[0], near)
	assert_same(result[1], far)


# -- explicit_target()/toggle/clear: state and the visual ring --------------

func test_no_explicit_target_before_anything_sets_one():
	assert_null(player.explicit_target())
	assert_false(player.has_explicit_target())


func test_toggling_a_creature_on_selects_it_and_shows_its_ring():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)
	assert_eq(player.explicit_target(), wolf)
	assert_true(player.has_explicit_target())
	assert_true(wolf.is_targeted())


func test_toggling_the_same_creature_again_clears_it_and_hides_its_ring():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)
	player.toggle_explicit_target(wolf)
	assert_null(player.explicit_target())
	assert_false(wolf.is_targeted())


func test_toggling_a_different_creature_switches_the_ring_to_the_new_one():
	var first := _creature_at("wolf", Vector2(20, 0))
	var second := _creature_at("boar", Vector2(40, 0))
	player.toggle_explicit_target(first)
	player.toggle_explicit_target(second)
	assert_eq(player.explicit_target(), second)
	assert_false(first.is_targeted())
	assert_true(second.is_targeted())


func test_clear_explicit_target_clears_it_and_hides_the_ring():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)
	player.clear_explicit_target()
	assert_null(player.explicit_target())
	assert_false(player.has_explicit_target())
	assert_false(wolf.is_targeted())


## "Cleared automatically only on death/invalidity, never on distance"
## (spell_runtime.md) -- walking out of CAUTION_RADIUS must NOT clear it,
## even though the creature has already dropped out of
## _nearby_enemy_candidates().
func test_walking_out_of_range_does_not_clear_an_explicit_target():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)
	wolf.position = player.position + Vector2(CreatureMarker.CAUTION_RADIUS + 200.0, 0)
	assert_eq(player.explicit_target(), wolf, "only death/invalidity clears it, never distance")


## The one real invalidity case: the target died/despawned since it was
## selected. Added directly (not via _creature_at's add_child_autofree) so
## this test owns and frees it itself, with no double-free risk at teardown.
func test_a_freed_explicit_target_reads_back_as_unselected():
	var wolf := CreatureMarker.new()
	wolf.info = CreatureInfo.new("wolf", 1)
	add_child(wolf)
	wolf.setup(chunk_manager, TILE_SIZE)
	wolf.position = player.position + Vector2(20, 0)

	player.toggle_explicit_target(wolf)
	assert_eq(player.explicit_target(), wolf)

	remove_child(wolf)
	wolf.free()

	assert_null(player.explicit_target(), "a freed target must read back as unselected, not crash")


# -- _cycle_spell_target(): Tab's own cycling step ---------------------------

func test_cycling_with_nothing_nearby_leaves_no_target_selected():
	player._cycle_spell_target()
	assert_null(player.explicit_target())


func test_cycling_selects_the_nearest_hostile_first():
	var near := _creature_at("wolf", Vector2(20, 0))
	_creature_at("boar", Vector2(80, 0))
	player._cycle_spell_target()
	assert_eq(player.explicit_target(), near)


func test_cycling_again_advances_to_the_next_hostile():
	var near := _creature_at("wolf", Vector2(20, 0))
	var far := _creature_at("boar", Vector2(80, 0))
	player._cycle_spell_target()
	player._cycle_spell_target()
	assert_eq(player.explicit_target(), far)
	assert_false(near.is_targeted())
	assert_true(far.is_targeted())


func test_cycling_wraps_from_the_last_candidate_back_to_the_first():
	var near := _creature_at("wolf", Vector2(20, 0))
	_creature_at("boar", Vector2(80, 0))
	player._cycle_spell_target()
	player._cycle_spell_target()
	player._cycle_spell_target()
	assert_eq(player.explicit_target(), near)


func test_cycling_after_the_current_target_left_the_pool_restarts_at_the_nearest():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)
	wolf.position = player.position + Vector2(CreatureMarker.CAUTION_RADIUS + 200.0, 0)
	var fresh := _creature_at("boar", Vector2(30, 0))

	player._cycle_spell_target()

	assert_eq(player.explicit_target(), fresh)


# -- _dodge_step(): bare Tab still dodges, Shift+Tab cycles instead ----------

func test_a_bare_tab_still_dodges_when_sprint_is_not_held():
	Input.action_press("dodge")
	player._dodge_step()
	assert_null(player.explicit_target(), "a bare Tab must never select a target")
	assert_true(player.is_invincible(), "a bare Tab must still dodge")


func test_shift_tab_cycles_the_target_instead_of_dodging():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	Input.action_press("sprint")
	Input.action_press("dodge")
	player._dodge_step()
	assert_eq(player.explicit_target(), wolf)
	assert_false(player.is_invincible(), "Shift+Tab must not also dodge")


# -- _resolve_cast_target(): commit-to-explicit-target, exploit-safe --------
# "Once set, a cast commits to it... used even if something else is
# technically closer or even out of this cast's own range... the cast
# whiffs... rather than quietly redirecting to whatever IS in range."

func test_touch_prefers_the_explicit_target_over_a_closer_candidate():
	var closer := _creature_at("horse", Vector2(5, 0))
	var explicit_choice := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(explicit_choice)

	assert_eq(player._resolve_cast_target("touch"), explicit_choice)


## The critical regression: SpellAtomEffects.apply_to_target has no range
## check of its own anywhere, so a naive "always return the explicit target"
## would be an unlimited-range exploit. An out-of-range explicit target must
## miss outright, never fall back to the in-range decoy.
func test_touch_misses_when_the_explicit_target_is_out_of_range_rather_than_redirecting():
	_creature_at("horse", Vector2(5, 0))
	var far_target := _creature_at("wolf", Vector2(SpellTargeting.TOUCH_RANGE + 50.0, 0))
	player.toggle_explicit_target(far_target)

	assert_null(player._resolve_cast_target("touch"))


func test_projectile_commits_to_the_explicit_target_in_range_and_in_the_facing_cone():
	player._last_facing_direction = Vector2.RIGHT
	_creature_at("horse", Vector2(30, 0))
	var explicit_choice := _creature_at("wolf", Vector2(80, 0))
	player.toggle_explicit_target(explicit_choice)

	assert_eq(player._resolve_cast_target("projectile"), explicit_choice)


func test_projectile_misses_when_the_explicit_target_is_out_of_range_rather_than_redirecting():
	player._last_facing_direction = Vector2.RIGHT
	_creature_at("horse", Vector2(30, 0))
	var far_target := _creature_at("wolf", Vector2(SpellTargeting.PROJECTILE_RANGE + 50.0, 0))
	player.toggle_explicit_target(far_target)

	assert_null(player._resolve_cast_target("projectile"))


func test_projectile_misses_when_the_explicit_target_is_outside_the_facing_cone():
	player._last_facing_direction = Vector2.RIGHT
	var behind_target := _creature_at("wolf", Vector2(-80, 0))
	player.toggle_explicit_target(behind_target)

	assert_null(
		player._resolve_cast_target("projectile"),
		"a committed target outside the facing cone must miss, not redirect"
	)


func test_area_centers_on_the_explicit_target_and_still_hits_a_bystander_near_it():
	var explicit_choice := _creature_at("wolf", Vector2(60, 0))
	var bystander := _creature_at("horse", Vector2(65, 0))
	player.toggle_explicit_target(explicit_choice)

	var targets: Array = player._resolve_cast_target("area")

	assert_true(targets.has(explicit_choice))
	assert_true(targets.has(bystander))


## The second exploit: with nothing ever clearing a stale explicit target
## for mere distance, an uncapped "area" recentre would let a player select
## a hostile once, walk anywhere on the map, and still land a full-damage
## burst back at wherever it was standing -- unlimited-range artillery.
## Beyond PROJECTILE_RANGE, "area" must fall back to its ordinary
## in-front-of-the-caster center instead (spell_runtime.md's divergence
## note under "Once set, a cast commits to it").
func test_area_does_not_snipe_a_stale_explicit_target_far_beyond_its_own_reach():
	var far_target := _creature_at("wolf", Vector2(SpellTargeting.PROJECTILE_RANGE + 200.0, 0))
	player.toggle_explicit_target(far_target)
	var normal_center := player._spell_targeting.area_center(player.position, player._last_facing_direction)
	var at_normal_center := _creature_at("horse", normal_center - player.position)

	var targets: Array = player._resolve_cast_target("area")

	assert_false(targets.has(far_target), "area must not snipe a target far beyond the caster's own reach")
	assert_true(targets.has(at_normal_center), "it must fall back to the ordinary center instead")


func test_self_delivery_is_never_redirected_at_an_explicit_target():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)

	assert_eq(player._resolve_cast_target("self"), player)


# -- creature_at_click(): World's click-to-target lookup ---------------------
# World combines this with toggle_explicit_target for its own click
# dispatch (docs/concept/spell_runtime.md: "a click within HOVER_RADIUS_PX
# of a hostile creature targets it"). index_at_point's own click-tolerance/
# nearest-of-several math is already covered by
# test_spell_target_selection.gd; this only has to prove the one thing this
# method adds on top of it -- which pool it searches.

func test_creature_at_click_hits_a_hostile_creature_within_click_radius():
	var wolf := _creature_at("wolf", Vector2(20, 0))

	assert_eq(player.creature_at_click(wolf.position), wolf)


func test_creature_at_click_misses_empty_ground():
	_creature_at("wolf", Vector2(20, 0))

	assert_null(player.creature_at_click(player.position + Vector2(1000, 1000)))


## The same hostile-only pool Tab-cycling already uses -- a click can never
## select something that was never a candidate to begin with.
func test_creature_at_click_never_returns_a_non_hostile_creature():
	var horse := _creature_at("horse", Vector2(10, 0))

	assert_null(player.creature_at_click(horse.position))
