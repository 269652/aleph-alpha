extends GutTest

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureWander = preload("res://src/rendering/creature_wander.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")
const RopeTether = preload("res://src/gameplay/rope_tether.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

const TILE_SIZE := 16


## Duck-typed world: every tile is the same biome unless overridden. Land
## (non-water, non-food) by default so sensing doesn't trigger food/water
## seeking in the flee/hunt tests.
class StubWorld:
	var biome := "grassland"
	func biome_at_global(_x: int, _y: int) -> String:
		return biome


## A StubWorld that also answers the herd (foot-and-mouth-like) disease
## transmission queries CreatureMarker asks EarthChunkManager for (see
## _herd_disease_step) -- population comfortably over capacity so
## DiseaseModel.herd_transmission_chance rolls near-certain, keeping the
## transmission test deterministic rather than depending on a lucky seed.
class DiseaseCapableStubWorld:
	extends StubWorld
	func herbivore_population_near(_pixel_position: Vector2) -> float:
		return 100.0
	func herbivore_capacity_near(_pixel_position: Vector2) -> float:
		return 1.0


class StubPlayer:
	extends Node2D
	var damage_taken := 0.0
	var venom_applications := 0
	var disease_bites: Array = []
	func take_damage(amount: float) -> void:
		damage_taken += amount
	func apply_venom() -> void:
		venom_applications += 1
	func apply_disease_bite(disease_id: String) -> void:
		disease_bites.append(disease_id)


## A rigged CreatureWander whose "no resource in sight, range outward to
## look for one" heading always points straight at wherever the real danger
## is (east, by convention here) -- makes the search-roam caution test
## deterministic instead of relying on the real pseudo-random heading
## happening to point that way within the test's step budget. Extends the
## real class (rather than a bare duck-typed double) since `_wander` is
## statically typed as CreatureWander on CreatureMarker.
class StubWanderTowardEast:
	extends CreatureWander
	func roam_direction(_elapsed_time: float, _seed_value: int) -> Vector2:
		return Vector2.RIGHT


var marker: CreatureMarker
var _extra: Array = []


func before_each():
	marker = CreatureMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 5
	marker.info = CreatureInfo.new("herbivore")
	add_child(marker)


## See World's mouse-hover animal-name tooltip (docs feature request).
func test_get_display_name_returns_the_infos_display_name():
	marker.info = CreatureInfo.new("herbivore")
	assert_eq(marker.get_display_name(), "Herbivore")


func test_get_display_name_returns_empty_string_without_info():
	marker.info = null
	assert_eq(marker.get_display_name(), "")


func after_each():
	remove_child(marker)
	marker.free()
	for node in _extra:
		if is_instance_valid(node):
			node.free()
	# A lethal take_damage() call anywhere in this file now leaves a real
	# Carcass sibling behind (see docs/concept/carrion.md) -- swept here
	# rather than patched into every individual death test, so a stray one
	# never leaks into whatever test runs next.
	for carcass in get_tree().get_nodes_in_group(Carcass.GROUP_NAME):
		carcass.free()
	CreatureMarker.sun_elevation_deg = CreatureMarker.DEFAULT_SUN_ELEVATION_DEG
	_extra = []


func _add_stub_creature(species: String, at: Vector2) -> CreatureMarker:
	var stub := CreatureMarker.new()
	stub.info = CreatureInfo.new(species)
	stub.position = at
	stub.home = at
	add_child(stub)
	_extra.append(stub)
	return stub


func _add_stub_player(at: Vector2) -> StubPlayer:
	var player := StubPlayer.new()
	player.position = at
	add_child(player)
	player.add_to_group(CreatureMarker.PLAYER_GROUP)
	_extra.append(player)
	return player


func test_position_changes_after_processing():
	var before := marker.position
	marker._process(0.5)
	assert_ne(marker.position, before)


func test_stays_within_a_bounded_range_of_home_over_many_steps():
	for i in 100:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), CreatureWander.WANDER_RADIUS * 2.0)


func test_two_markers_with_different_seeds_move_differently():
	var other := CreatureMarker.new()
	other.home = Vector2(100, 100)
	other.position = Vector2(100, 100)
	other.wander_seed = 99
	add_child(other)

	marker._process(0.5)
	other._process(0.5)

	assert_ne(marker.position, other.position)
	remove_child(other)
	other.free()


func test_is_added_to_the_creature_group_on_ready():
	assert_true(marker.is_in_group(CreatureMarker.GROUP_NAME))


func test_take_damage_reduces_info_health():
	var before := marker.info.health
	marker.take_damage(5.0)
	assert_eq(marker.info.health, before - 5.0)


# -- world boss aggro gating (docs/concept/worldbosses.md, BossAggro) -------

func test_a_weak_hit_against_an_unaggroed_world_boss_deals_no_damage():
	marker.info = CreatureInfo.new("krampus")
	var before := marker.info.health
	marker.take_damage(0.01)  # far below any real fraction-of-max-health threshold
	assert_eq(marker.info.health, before)


func test_a_weak_hit_against_an_unaggroed_world_boss_does_not_aggro_it():
	marker.info = CreatureInfo.new("krampus")
	marker.take_damage(0.01)
	assert_false(marker.info.is_aggroed)


func test_a_real_hit_against_an_unaggroed_world_boss_damages_it_and_aggros_it():
	marker.info = CreatureInfo.new("krampus")
	var before := marker.info.health
	marker.take_damage(marker.info.max_health)  # unmistakably above any threshold
	assert_lt(marker.info.health, before)
	assert_true(marker.info.is_aggroed)


func test_once_aggroed_even_a_weak_hit_still_deals_damage():
	marker.info = CreatureInfo.new("krampus")
	marker.info.is_aggroed = true
	var before := marker.info.health
	marker.take_damage(0.01)
	assert_lt(marker.info.health, before)


func test_non_boss_species_are_unaffected_by_the_aggro_gate():
	marker.info = CreatureInfo.new("herbivore")
	var before := marker.info.health
	marker.take_damage(0.01)
	assert_lt(marker.info.health, before, "an ordinary creature takes any amount of damage, no threshold")


func test_has_a_visible_health_bar_at_full_health():
	assert_almost_eq(marker._health_bar_fill.size.x, CreatureMarker.HEALTH_BAR_WIDTH, 0.01)


func test_health_bar_shrinks_as_the_creature_takes_damage():
	var full_width: float = marker._health_bar_fill.size.x
	marker.take_damage(marker.info.max_health * 0.5)
	assert_lt(marker._health_bar_fill.size.x, full_width)
	assert_gt(marker._health_bar_fill.size.x, 0.0)


## A serpent rotates its own sprite to face its heading (see the movement
## tests below) -- but the health bar and shadow are its CHILDREN, and a
## plain child node inherits its parent's rotation by default, which
## visibly tilted them along with the body (reported: "the health bar and
## shadow of creatures should NOT rotate together with the animal"). Both
## are `top_level` (ignores inherited transform entirely) and manually
## re-synced to the marker's POSITION only, every frame.
func test_health_bar_does_not_rotate_with_the_creature():
	assert_true(marker._health_bar_bg.top_level)
	assert_true(marker._health_bar_fill.top_level)
	marker.info = CreatureInfo.new("nonvenomous_snake")
	marker._heading = Vector2.RIGHT
	marker._advance(Vector2.DOWN, 50.0, 3.0)  # rotates the marker itself
	assert_ne(marker.rotation, 0.0, "sanity check: the marker itself did rotate")
	assert_eq(marker._health_bar_bg.rotation, 0.0)
	assert_eq(marker._health_bar_fill.rotation, 0.0)


func test_health_bar_still_tracks_the_creatures_position():
	marker.position = Vector2(500, 500)
	marker._sync_grounded_children()
	var expected := Vector2(500, 500) + Vector2(-CreatureMarker.HEALTH_BAR_WIDTH / 2.0, CreatureMarker.HEALTH_BAR_OFFSET_Y)
	assert_eq(marker._health_bar_bg.global_position, expected)


## A plain Node2D shadow (a fallback/test double, not the real silhouette
## Sprite2D CreatureRenderer actually attaches -- see the Sprite2D-rotation
## tests below) still must not pick up any rotation just by being top_level
## and re-synced.
func test_non_sprite_shadow_does_not_rotate_with_the_creature():
	var fake_shadow := Node2D.new()
	add_child(fake_shadow)
	_extra.append(fake_shadow)
	marker.set_shadow(fake_shadow)
	assert_true(fake_shadow.top_level)
	marker.info = CreatureInfo.new("nonvenomous_snake")
	marker._heading = Vector2.RIGHT
	marker._advance(Vector2.DOWN, 50.0, 3.0)
	marker._sync_grounded_children()
	assert_eq(fake_shadow.rotation, 0.0)
	assert_eq(fake_shadow.global_position, marker.global_position)


## A real silhouette shadow (Sprite2D, see DropShadow.make_silhouette_shadow)
## is a flattened copy of the creature's ACTUAL current shape -- for a
## serpent, whose whole sprite rotates to face its heading (see _advance's
## doc comment), a shadow that stayed upright while the body turned would no
## longer match the silhouette casting it. Reported directly: "The shadow
## for snakes is not rotating properly. Its shadow should render physically
## accurate when the snake is rotated." Legged animals never rotate their
## own sprite (rotation stays 0 always), so this is a no-op for them --
## rotating a Sprite2D shadow to match is only ever visible for a serpent.
func test_sprite_shadow_rotates_to_match_a_turning_serpents_body():
	var shadow := Sprite2D.new()
	add_child(shadow)
	_extra.append(shadow)
	marker.set_shadow(shadow)
	marker.info = CreatureInfo.new("nonvenomous_snake")
	marker._heading = Vector2.RIGHT
	marker._advance(Vector2.DOWN, 50.0, 3.0)  # rotates the marker itself
	marker._sync_grounded_children()
	assert_ne(marker.rotation, 0.0, "sanity check: the marker itself did rotate")
	assert_almost_eq(shadow.rotation, marker.rotation, 0.0001)


## The shadow's anchor offset deliberately does NOT rotate with the body --
## two earlier attempts at rotating it to "match the body" each put the
## shadow in the wrong place at some rotation (reported, repeatedly across
## both attempts: "the snake is the axis .. it should render below the snake
## not above ... the shadow should always render on the bottom of a creature
## regardless if it's rotated by 180deg"). Straight down, always, the same
## as every other creature's shadow, regardless of the body's rotation.
func test_sprite_shadow_offset_stays_straight_down_regardless_of_the_bodys_rotation():
	var shadow := Sprite2D.new()
	shadow.position = Vector2(0, 20.0)
	add_child(shadow)
	_extra.append(shadow)
	marker.set_shadow(shadow, Vector2.ONE)
	marker.position = Vector2(500, 500)
	marker.rotation = PI / 2.0
	marker._sync_grounded_children()
	assert_eq(shadow.global_position, marker.global_position + Vector2(0, 20.0))


## Same guarantee at a rotation past 90 degrees WITH flip_v set (the
## realistic combination -- flip_v is only ever true there, see _advance):
## the shadow must stay directly below the body, never swing out to the
## side or up above it.
func test_sprite_shadow_offset_stays_straight_down_even_when_the_serpent_is_flipped_vertically():
	var shadow := Sprite2D.new()
	shadow.position = Vector2(0, 20.0)
	add_child(shadow)
	_extra.append(shadow)
	marker.set_shadow(shadow, Vector2.ONE)
	marker.position = Vector2(500, 500)
	marker.rotation = deg_to_rad(170.0)  # past 90 deg -- flip_v would be true here
	marker.flip_v = true
	marker._sync_grounded_children()
	assert_eq(shadow.global_position, marker.global_position + Vector2(0, 20.0))


## The shadow's own baked-in flip_v (see DropShadow.make_silhouette_shadow)
## makes it read as "the body, upside down" relative to whatever the body is
## CURRENTLY showing -- so when the body itself is also flip_v'd, the
## shadow's flip has to cancel out to keep showing that same relative
## relationship, rather than doubly-flipping back to matching the body.
func test_sprite_shadow_flip_v_cancels_out_when_the_serpent_itself_is_flipped():
	var shadow := Sprite2D.new()
	shadow.flip_v = true  # as DropShadow.make_silhouette_shadow sets it initially
	add_child(shadow)
	_extra.append(shadow)
	marker.set_shadow(shadow)
	marker.flip_v = true
	marker._sync_grounded_children()
	assert_false(shadow.flip_v)

	marker.flip_v = false
	marker._sync_grounded_children()
	assert_true(shadow.flip_v)


## A real Sprite2D shadow (see DropShadow.make_silhouette_shadow, wired up by
## CreatureRenderer) is a live copy of the creature's own current look, not a
## fixed shape set once at spawn -- it has to keep tracking whichever
## animation frame/facing the marker is currently showing.
func test_silhouette_shadow_mirrors_the_creatures_current_texture_and_facing():
	var shadow := Sprite2D.new()
	add_child(shadow)
	_extra.append(shadow)
	marker.set_shadow(shadow)
	marker.texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	marker.flip_h = true
	marker._sync_grounded_children()
	assert_eq(shadow.texture, marker.texture)
	assert_true(shadow.flip_h)


## See DropShadow.stretch_for_elevation -- a low sun drags the shadow out
## longer than an overhead one.
func test_silhouette_shadow_stretches_with_the_static_sun_elevation():
	var shadow := Sprite2D.new()
	add_child(shadow)
	_extra.append(shadow)
	marker.set_shadow(shadow)

	CreatureMarker.sun_elevation_deg = 90.0
	marker._sync_grounded_children()
	var overhead_stretch := shadow.scale.y

	CreatureMarker.sun_elevation_deg = 10.0
	marker._sync_grounded_children()
	assert_gt(shadow.scale.y, overhead_stretch, "a lower sun must stretch the shadow longer")


## The shadow's foot offset is captured in the marker's own UNSCALED texture
## pixel space (see CreatureRenderer._shadow_foot_offset_y) -- but the marker
## itself is drawn at `scale` (species size x the shared art-resolution
## downscale, see art_resolution.md), so its feet appear on screen at
## foot_offset_y * scale, not the raw pixel count. Reported directly: "the
## shadow is a few pixel below sprite so it looks like it's floating" -- for
## any species whose scale isn't exactly 1.0, an unscaled offset overshoots
## past the creature's actual (scaled-down) feet.
func test_shadow_offset_scales_with_the_markers_own_scale():
	var shadow := Sprite2D.new()
	shadow.position = Vector2(0, 20.0)  # raw, unscaled foot offset
	add_child(shadow)
	_extra.append(shadow)
	marker.scale = Vector2(0.5, 0.5)
	marker.set_shadow(shadow, marker.scale)
	marker.position = Vector2(200, 200)
	marker._sync_grounded_children()
	assert_almost_eq(
		shadow.global_position.y, marker.global_position.y + 10.0, 0.01,
		"a 0.5-scaled marker's shadow must land at half the raw offset, not the full unscaled one"
	)


## A plain Node2D fake shadow (used by other tests/callers that don't want
## silhouette behavior) must not be touched -- only a real Sprite2D shadow
## gets texture/flip/stretch syncing.
func test_a_non_sprite_shadow_is_left_alone_by_the_silhouette_sync():
	var fake_shadow := Node2D.new()
	add_child(fake_shadow)
	_extra.append(fake_shadow)
	marker.set_shadow(fake_shadow)
	marker._sync_grounded_children()
	assert_eq(fake_shadow.scale, Vector2.ONE, "no silhouette syncing should touch a plain Node2D")


func test_take_damage_frees_the_marker_once_health_reaches_zero():
	marker.take_damage(marker.info.max_health)
	assert_true(marker.is_queued_for_deletion())


## Dying no longer instantly sprays loot (see docs/concept/carrion.md) --
## the exact "evaporates instead of being cut down" pattern already fixed
## once for trees. A carcass-eligible species (herbivore has hide+meat in
## LootTable) leaves a real Carcass behind instead; hide/meat only reach
## the world-item bus once a player actually butchers it. Delta-based
## rather than assuming a zero baseline -- other tests in this file kill
## creatures too, and after_each sweeps whatever carcass each one leaves,
## not every individual test.
func test_dying_leaves_a_carcass_instead_of_instant_loot():
	watch_signals(WorldItemBus)
	var before := get_tree().get_nodes_in_group(Carcass.GROUP_NAME).size()
	marker.take_damage(marker.info.max_health)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)
	var carcasses := get_tree().get_nodes_in_group(Carcass.GROUP_NAME)
	assert_eq(carcasses.size(), before + 1)
	assert_eq(carcasses[carcasses.size() - 1].species, "herbivore")


func test_a_non_lethal_hit_drops_no_loot():
	watch_signals(WorldItemBus)
	marker.take_damage(1.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)


func test_take_damage_does_not_free_the_marker_while_still_alive():
	marker.take_damage(1.0)
	assert_false(marker.is_queued_for_deletion())


func test_apply_knockback_does_not_teleport_instantly():
	# Hammerwatch-style: a hit should slide the creature over a short time,
	# not snap it to the destination the instant it's hit.
	var before := marker.position
	marker.apply_knockback(Vector2(10, -5))
	assert_eq(marker.position, before)


func test_knockback_plays_out_smoothly_over_its_duration():
	var before := marker.position
	marker.apply_knockback(Vector2(30, 0))

	var step_delta := 0.05
	marker._process(step_delta)
	var mid_distance := marker.position.distance_to(before)
	assert_gt(mid_distance, 0.0, "should have started moving")
	assert_lt(mid_distance, 30.0, "should not have covered the full distance yet")

	# Advance only through the rest of the knockback's own duration -- not a
	# single frame further, or idle wander would take over once it ends and
	# throw off the distance measurement.
	var remaining_steps := int(ceil((CreatureMarker.KNOCKBACK_DURATION - step_delta) / step_delta))
	for i in remaining_steps:
		marker._process(step_delta)
	assert_almost_eq(marker.position.distance_to(before), 30.0, 0.5, "should finish covering the full knockback")


func test_knockback_suppresses_normal_wandering_while_active():
	marker.apply_knockback(Vector2(200, 0))
	var right_after_knockback := marker.position
	marker._process(0.001)
	# Only the (tiny) knockback step should have moved it, not a wander jump.
	assert_lt(marker.position.distance_to(right_after_knockback), 5.0)


# -- behavior: fleeing (calm herbivore) ---------------------------------------

func test_herbivore_flees_away_from_a_nearby_predator():
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_creature("predator", Vector2(120, 100))  # to the east, within sense range

	marker._process(0.2)

	assert_lt(marker.position.x, 100.0, "herbivore should move west, away from the predator")


func test_herbivore_flees_away_from_a_nearby_player():
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_player(Vector2(120, 100))

	marker._process(0.2)

	assert_lt(marker.position.x, 100.0, "herbivore should move away from the player")


## End-to-end soak test with realistic per-frame deltas (not the big 0.2-0.3s
## jumps the other behavior tests use) and the REAL (non-rigged) wander
## heading -- reported again even after the search/wander caution fixes:
## "the horse still has flee hystery and tries to walk into the players
## flee radius; getting stuck walking back and forth instead of continuing
## foraging or wandering." Home sits well within CAUTION_RADIUS of a
## stationary player -- the scenario most likely to expose any remaining
## gap, since nearly every wander/search step this creature ever takes is
## caution-checked. Across a long simulated run, with every need cycling
## naturally (not forced), the creature's OWN movement should never close
## the distance enough to trigger its own flee.
func test_creature_never_self_triggers_flee_while_home_sits_near_a_stationary_player():
	var world := StubWorld.new()
	world.biome = "grassland"
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.setup(world, TILE_SIZE)
	var player := _add_stub_player(Vector2(100 + CreatureMarker.CAUTION_RADIUS - 20.0, 100))

	var min_distance := INF
	for i in 3000:
		marker._process(1.0 / 60.0)
		min_distance = minf(min_distance, marker.position.distance_to(player.position))

	assert_gt(
		min_distance,
		CreatureMarker.SENSE_RADIUS,
		"a creature should never close the distance enough to trigger its own flee just by wandering/foraging near a stationary player"
	)


## _flee_commit_remaining only ever decremented WHILE actively fleeing --
## if a flee episode ended (the creature escaped SENSE_RADIUS) before its
## own commit window fully expired, the leftover timer and heading froze
## rather than resetting, and got reused verbatim the NEXT time a threat
## was sensed. If that later threat is somewhere else entirely, the stale
## heading can point TOWARD it instead of away (reported again: "the horse
## still has flee hystery and tries to walk into the players flee radius").
## Two separate flee episodes here, threat on the opposite side the second
## time -- reusing the first episode's stale heading would walk the
## creature straight at it.
func test_a_second_flee_episode_does_not_reuse_a_stale_heading_from_the_first():
	marker.setup(StubWorld.new(), TILE_SIZE)
	var player := _add_stub_player(Vector2(150, 100))  # east -- flee west
	# Each tick's delta exceeds SENSE_INTERVAL (0.25s) so sensing is always
	# fresh, not throttled-stale -- this test cares about exactly what each
	# step senses, not the throttling behavior itself.
	marker._process(0.3)
	assert_lt(marker.position.x, 100.0, "first episode: should have fled west, away from the eastern threat")
	assert_gt(marker._flee_commit_remaining, 0.0, "commit window should still be running, not expired")

	# Far enough to leave SENSE_RADIUS (which ends the flee episode -- the
	# point of this step) but still inside SimulationLod.FULL_RATE_RADIUS_PX,
	# so the creature keeps updating every frame. Teleporting the player to
	# the far side of the world also parked this creature at the lowest
	# update rate, which is correct behaviour and simply not what this test
	# is about.
	player.position = marker.position + Vector2(300, 0)  # threat leaves sense range
	marker._process(0.3)

	# New threat WEST of the creature's current (already-fled-west) position
	# -- correct flee response is now EAST, the opposite of the first
	# episode's stale heading. The first eastward frame is a facing REVERSAL,
	# which the facing commit rightly refuses while its window runs (the
	# creature stands rather than moonwalks -- see FACING_COMMIT_SECONDS),
	# so process enough frames for the window to elapse before asserting the
	# eastward escape actually happened.
	player.position = marker.position - Vector2(50, 0)
	var before_second_episode := marker.position.x
	marker._process(0.3)
	marker._process(0.3)
	marker._process(0.3)

	assert_gt(
		marker.position.x, before_second_episode,
		"second episode: should flee east, away from the NEW western threat, not reuse the stale westward heading"
	)


func test_herbivore_ignores_a_predator_that_is_far_out_of_sense_range():
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_creature("predator", Vector2(100000, 100))

	marker._process(0.2)

	# No threat sensed -> idle wander stays near home, doesn't bolt away.
	assert_lt(marker.position.distance_to(marker.home), CreatureWander.WANDER_RADIUS)


# -- behavior: predator hunting/predation -------------------------------------

func test_hungry_predator_moves_toward_a_distant_herbivore():
	var predator := _make_predator(Vector2(100, 100))
	predator._needs.hunger = 1.0
	_add_stub_creature("herbivore", Vector2(160, 100))  # east, in sense range but not adjacent

	predator._process(0.2)

	assert_gt(predator.position.x, 100.0, "hungry predator should move toward its prey")


func test_hungry_predator_eats_an_adjacent_herbivore_and_is_no_longer_hungry():
	var predator := _make_predator(Vector2(100, 100))
	predator._needs.hunger = 1.0
	var prey := _add_stub_creature("herbivore", Vector2(105, 100))  # within predation range

	predator._process(0.2)

	assert_true(prey.is_queued_for_deletion(), "caught prey should be killed")
	assert_false(predator._needs.is_hungry(), "eating should sate the predator")


func test_sated_predator_does_not_chase_prey():
	var predator := _make_predator(Vector2(100, 100))
	predator._needs.hunger = 0.0
	_add_stub_creature("herbivore", Vector2(160, 100))

	predator._process(0.2)

	assert_lt(predator.position.distance_to(predator.home), CreatureWander.WANDER_RADIUS)


# -- behavior: predator vs player (strong attacks, weak flees) -----------------

func test_strong_aggressive_predator_attacks_a_nearby_player():
	var predator := _make_predator(Vector2(100, 100))
	var player := _add_stub_player(Vector2(108, 100))  # within attack range

	predator._process(0.2)

	assert_gt(player.damage_taken, 0.0, "a strong predator should damage the player")


## See docs/concept/ecosystem_dynamics.md's Species roster -- venomous_snake
## is the one predator whose bite has a real mechanical difference.
func test_venomous_snake_applies_venom_when_it_attacks_the_player():
	marker.position = Vector2(1_000_000, 1_000_000)  # keep the herbivore out of the way
	var snake := CreatureMarker.new()
	snake.info = CreatureInfo.new("venomous_snake")
	snake.position = Vector2(100, 100)
	snake.home = snake.position
	snake.wander_seed = 3
	snake.setup(StubWorld.new(), TILE_SIZE)
	add_child(snake)
	_extra.append(snake)
	var player := _add_stub_player(Vector2(108, 100))

	snake._process(0.2)

	assert_gt(player.damage_taken, 0.0, "the snake should still deal ordinary bite damage")
	assert_eq(player.venom_applications, 1, "a venomous snake's bite should apply venom")


func test_nonvenomous_predator_does_not_apply_venom():
	var predator := _make_predator(Vector2(100, 100))
	var player := _add_stub_player(Vector2(108, 100))

	predator._process(0.2)

	assert_gt(player.damage_taken, 0.0)
	assert_eq(player.venom_applications, 0, "an ordinary predator's bite should not apply venom")


# -- disease (see docs/concept/disease.md / DiseaseModel) ---------------------

func test_a_new_marker_starts_disease_free():
	assert_eq(marker.disease_state, DiseaseModel.State.SUSCEPTIBLE)
	assert_eq(marker.disease_id, "")
	assert_eq(marker.disease_severity, 0.0)


func test_apply_disease_bite_infects_a_susceptible_creature():
	marker.apply_disease_bite(DiseaseModel.HERD)
	assert_eq(marker.disease_state, DiseaseModel.State.INFECTED)
	assert_eq(marker.disease_id, DiseaseModel.HERD)


func test_apply_disease_bite_does_nothing_once_already_infected():
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker._disease_step(5.0)  # let severity climb off zero
	var severity_before: float = marker.disease_severity
	marker.apply_disease_bite(DiseaseModel.CARRION)  # a second, different exposure
	assert_eq(marker.disease_id, DiseaseModel.HERD, "an already-infected creature keeps its ORIGINAL disease")
	assert_eq(marker.disease_severity, severity_before)


func test_disease_step_does_nothing_while_susceptible():
	marker._disease_step(5.0)
	assert_eq(marker.disease_severity, 0.0)
	assert_eq(marker.disease_state, DiseaseModel.State.SUSCEPTIBLE)


func test_disease_step_increases_severity_while_infected():
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker._disease_step(5.0)
	assert_gt(marker.disease_severity, 0.0)


## A disease death must route through the EXACT same carcass path a
## predation kill already uses (docs/concept/disease.md "Feeds carrion") --
## verified the same way test_dying_leaves_a_carcass_instead_of_instant_loot
## verifies take_damage's own death path.
func test_a_lethal_disease_death_leaves_a_carcass_and_frees_the_marker():
	var before := get_tree().get_nodes_in_group(Carcass.GROUP_NAME).size()
	marker.apply_disease_bite(DiseaseModel.CARRION)  # lethal-capable archetype
	# A huge delta drives DiseaseModel's per-second death chance past 1.0 --
	# deterministic regardless of seed (see test_disease_model.gd's own
	# identical trick), not a flaky roll.
	marker._disease_step(1000.0)
	assert_true(marker.is_queued_for_deletion())
	var carcasses := get_tree().get_nodes_in_group(Carcass.GROUP_NAME)
	assert_eq(carcasses.size(), before + 1)


func test_infected_predator_spreads_disease_when_it_bites_the_player():
	var predator := _make_predator(Vector2(100, 100))
	predator.apply_disease_bite(DiseaseModel.PREDATOR)
	# HARD region pressure (2.4x) on top of the 0.5 base bite chance clamps
	# the roll to certain -- deterministic regardless of seed, the same
	# "push the chance past 1.0" trick test_disease_model.gd's own death-roll
	# tests use, not a coin flip this test happens to win.
	predator.region_tier = RegionDifficulty.Tier.HARD
	var player := _add_stub_player(Vector2(108, 100))

	predator._process(0.2)

	assert_gt(player.damage_taken, 0.0, "the bite should still deal ordinary damage")
	assert_eq(player.disease_bites, [DiseaseModel.PREDATOR])


func test_healthy_predator_does_not_spread_disease_when_it_bites_the_player():
	var predator := _make_predator(Vector2(100, 100))
	var player := _add_stub_player(Vector2(108, 100))

	predator._process(0.2)

	assert_gt(player.damage_taken, 0.0)
	assert_eq(player.disease_bites.size(), 0)


## Visible symptoms (docs/concept/disease.md "What you see is what's real"):
## reuses Sprite2D's own `modulate`, not a new rendering system.
func test_an_infected_creature_is_visually_tinted():
	var healthy_tint := marker.modulate
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker._disease_step(0.1)
	assert_ne(marker.modulate, healthy_tint, "an infected creature should visibly read as sick")


## The doc's real "secondary effect": herd disease doesn't damage directly,
## it makes the carrier measurably easier prey by slowing it down (see
## DiseaseModel.movement_speed_multiplier).
func test_herd_disease_severity_slows_an_infected_herbivores_movement():
	var start := marker.position
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker.disease_severity = 1.0  # full severity -- worst-case slowdown
	marker._advance(Vector2.RIGHT, 100.0, 1.0)
	var sick_distance := marker.position.distance_to(start)

	marker.position = start
	marker.disease_state = DiseaseModel.State.SUSCEPTIBLE
	marker.disease_id = ""
	marker._facing_commit_remaining = 0.0
	marker._advance(Vector2.RIGHT, 100.0, 1.0)
	var healthy_distance := marker.position.distance_to(start)

	assert_lt(sick_distance, healthy_distance)


func test_herd_disease_transmits_to_a_nearby_susceptible_herbivore():
	var world := DiseaseCapableStubWorld.new()
	marker.setup(world, TILE_SIZE)
	marker.region_tier = RegionDifficulty.Tier.HARD
	marker.apply_disease_bite(DiseaseModel.HERD)

	var other := CreatureMarker.new()
	other.info = CreatureInfo.new("herbivore")
	other.position = marker.position + Vector2(5, 0)
	other.home = other.position
	other.wander_seed = 11
	other.setup(world, TILE_SIZE)
	add_child(other)
	_extra.append(other)

	marker._process(0.2)  # first _process always runs a sense tick immediately

	assert_eq(other.disease_state, DiseaseModel.State.INFECTED)
	assert_eq(other.disease_id, DiseaseModel.HERD)


## Carrion (anthrax-like): docs/concept/disease.md's insect-vector chain ends
## with "infecting herbivores that graze there afterward" -- simplified here
## to direct proximity to the contaminated Carcass itself (this project has
## no separately-tracked "contaminated patch of grass" object -- see
## _carrion_disease_step's own doc comment).
func test_a_herbivore_grazing_near_a_contaminated_carcass_is_exposed():
	marker.setup(StubWorld.new(), TILE_SIZE)
	marker.region_tier = RegionDifficulty.Tier.HARD  # clamps the graze roll to certain

	var contaminated_carcass := Carcass.new()
	contaminated_carcass.species = "boar"
	contaminated_carcass.contaminated = true
	contaminated_carcass.position = marker.position + Vector2(5, 0)
	add_child(contaminated_carcass)
	_extra.append(contaminated_carcass)

	marker._process(0.2)

	assert_eq(marker.disease_state, DiseaseModel.State.INFECTED)
	assert_eq(marker.disease_id, DiseaseModel.CARRION)


func test_a_herbivore_does_not_get_exposed_by_an_uncontaminated_carcass():
	marker.setup(StubWorld.new(), TILE_SIZE)
	marker.region_tier = RegionDifficulty.Tier.HARD

	var clean_carcass := Carcass.new()
	clean_carcass.species = "boar"
	clean_carcass.contaminated = false
	clean_carcass.position = marker.position + Vector2(5, 0)
	add_child(clean_carcass)
	_extra.append(clean_carcass)

	marker._process(0.2)

	assert_eq(marker.disease_state, DiseaseModel.State.SUSCEPTIBLE)


func test_weakened_predator_flees_the_player_instead_of_attacking():
	var predator := _make_predator(Vector2(100, 100))
	predator.info.health = 1.0  # health_fraction well below the fight threshold
	var player := _add_stub_player(Vector2(120, 100))

	predator._process(0.2)

	assert_lt(predator.position.x, 100.0, "a weak predator should flee the player")
	assert_eq(player.damage_taken, 0.0, "a fleeing predator should not attack")


# -- behavior: needs (drink/graze in place) -----------------------------------

func test_thirsty_creature_drinks_when_standing_on_water():
	var world := StubWorld.new()
	world.biome = "ocean"
	marker.setup(world, TILE_SIZE)
	marker._needs.thirst = 1.0

	marker._process(0.2)

	assert_false(marker._needs.is_thirsty(), "standing on water should quench thirst")


## Standing on living ground still feeds a herbivore -- but as a head-down
## BOUT now, not instantly (see GrazerForaging.FOOD_UNDERFOOT). Feeding on the
## first frame of hunger was why a horse on grassland was never hungry long
## enough to have any reason to go anywhere, and why eating was never
## something the player could see happen.
func test_hungry_herbivore_grazes_when_standing_on_a_food_biome():
	var world := StubWorld.new()
	world.biome = "grassland"
	marker.setup(world, TILE_SIZE)
	marker._needs.hunger = 1.0

	marker._process(0.2)
	assert_true(marker._needs.is_hungry(), "one frame is not a meal")

	for _i in 600:
		marker._process(1.0 / 60.0)
		if not marker._needs.is_hungry():
			break
	assert_false(marker._needs.is_hungry(), "grazing on food terrain should sate hunger")


## "search_water"/"search_food" (roaming to LOOK for a resource, nothing
## sensed yet) used to bypass caution-radius avoidance entirely -- only
## ordinary idle wander routed through it (see _wander_step/ThreatAvoidant-
## Wander). A thirsty/hungry creature near a stationary player would range
## outward regardless of them, occasionally roam straight toward them,
## cross into SENSE_RADIUS and flee, then immediately resume searching
## (still thirsty) and roam right back -- the exact "back and forth" the
## caution radius was built to prevent for ordinary wander (reported again
## for "the horse and other animals... same flee hysteria the snake had at
## the beginning"). The player here sits just outside SENSE_RADIUS (80) but
## well within CAUTION_RADIUS (160) -- close enough that avoidance must
## still steer the search away, far enough that flee itself never triggers.
## The search heading is rigged (StubWanderTowardEast) to always point
## straight at the player, so the test doesn't depend on the real
## pseudo-random heading happening to do so within its own step budget.
func test_thirsty_creature_avoids_a_nearby_player_while_searching_for_water():
	var world := StubWorld.new()
	world.biome = "grassland"  # no water anywhere -> search_water, not seek_water
	marker.setup(world, TILE_SIZE)
	marker._needs.thirst = 1.0
	marker._wander = StubWanderTowardEast.new()
	var player := _add_stub_player(Vector2(100 + CreatureMarker.CAUTION_RADIUS - 10.0, 100))

	var min_distance := INF
	for i in 60:
		marker._process(0.3)
		min_distance = minf(min_distance, marker.position.distance_to(player.position))

	assert_gt(
		min_distance,
		CreatureMarker.SENSE_RADIUS,
		"a searching creature should never close the distance enough to trigger its own flee"
	)


func test_thirsty_creature_with_no_water_in_sight_roams_far_beyond_its_home():
	# Grassland everywhere: it grazes so never travels for food, but there's
	# no water anywhere, so a thirsty creature should roam to search -- ranging
	# well past the tight idle-wander radius instead of orbiting home.
	var world := StubWorld.new()
	world.biome = "grassland"
	marker.setup(world, TILE_SIZE)
	marker._needs.thirst = 1.0  # thirsty, and grassland has no water to quench it

	var max_distance := 0.0
	for i in 80:
		marker._process(0.3)
		max_distance = maxf(max_distance, marker.position.distance_to(marker.home))

	# Well past anything home-bounded idle-wander could reach (it clamps to
	# ~WANDER_RADIUS plus a single step's overshoot) -- proving real roaming.
	assert_gt(max_distance, CreatureWander.WANDER_RADIUS * 2.5,
		"a searching creature should range far beyond the idle-wander radius")


# -- movement: legged animals move freely; serpents turn-then-rotate ----------
#
# Two body plans, two genuinely different treatments -- tried unifying them
# twice this session and both failed for the same underlying reason: a
# legged animal's art is a strict LEFT/RIGHT side-view silhouette with legs
# baked pointing toward the ground. Forcing it through a turn-before-advance
# heading (the serpent treatment) just made it turn toward directions it
# could never actually draw. Rotating the whole sprite to face the heading
## (like a serpent) was tried too and is worse: the instant the heading isn't
# near-horizontal, the legs rotate away from the ground with it (a horse
# "facing up" ends up lying on its side, reported directly: "that literally
# rotates the horse so that it's legs are upside down"). So a legged animal
# now simply advances straight toward `desired` -- sideways, diagonal,
# whatever -- and only ever flips to keep its drawn facing matching which way
# it's actually currently walking, immediately, off the requested direction
# itself rather than off a lagging position delta -- so it can never appear
# to walk backwards relative to its own facing (reported requirement: "make
# it move sideways but not backwards, if wants to walk backwards flip it to
# orient"). A serpent is different: a long thin body genuinely reads fine
# rotated to any angle, so IT still turns its heading first and rotates the
# whole sprite to it, unchanged from before.

func test_legged_creatures_move_freely_toward_the_requested_direction():
	marker.info = CreatureInfo.new("horse")
	marker.position = Vector2(100, 100)
	marker._advance(Vector2.UP, 100.0, 0.05)
	# No heading smoothing for legged animals -- it goes exactly where asked,
	# immediately, including a direction its side-view art can't itself draw.
	var expected := Vector2(100, 100) + Vector2.UP * 100.0 * 0.05
	assert_almost_eq(marker.position.x, expected.x, 0.01)
	assert_almost_eq(marker.position.y, expected.y, 0.01)


## Asserts on facing_sign (which way the creature VISUALLY faces), never on
## flip_h directly. flip_h only means "mirrored from whatever the source art
## happens to be", and the source art does NOT face a consistent direction:
## horse.png is drawn facing left while deer.png/boar.png and every
## procedural sprite face right. Every facing test here used to assert
## flip_h under a blanket right-facing assumption -- the same wrong
## assumption the production code made -- so they all passed green while the
## horse rendered mirrored and walked backwards in every direction for the
## entire session. _art_faces_left is set explicitly in these tests to the
## real value for the species under test, since _advance is being called
## directly here without _animation_step having run to derive it.
func test_legged_creature_flips_to_face_a_sustained_new_direction():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true  # horse.png is drawn facing left
	marker._advance(Vector2.LEFT, 50.0, 0.016)
	assert_eq(marker.facing_sign(), -1.0, "should visually face left on the very first frame it's asked to go left")


## The same requirement for a species whose art faces the other way -- the
## rule is about the direction the creature is SEEN to face, so it must hold
## identically for both art conventions.
func test_legged_creature_with_right_facing_art_also_faces_its_direction_of_travel():
	marker.info = CreatureInfo.new("deer")
	marker._art_faces_left = false  # deer.png is drawn facing right
	marker._advance(Vector2.LEFT, 50.0, 0.016)
	assert_eq(marker.facing_sign(), -1.0, "should visually face left regardless of which way its art is drawn")
	# Walk the committed way until the facing-commit window has elapsed --
	# an instant reversal is (correctly) refused, see FACING_COMMIT_SECONDS.
	var elapsed := 0.0
	while elapsed < CreatureMarker.FACING_COMMIT_SECONDS:
		marker._advance(Vector2.LEFT, 50.0, 0.1)
		elapsed += 0.1
	marker._advance(Vector2.RIGHT, 50.0, 0.016)
	assert_eq(marker.facing_sign(), 1.0)


## A DISTANCE-based commit (must travel 3 tiles before flipping again) used
## to gate this, meant to stop rapid per-frame direction noise from
## flickering the facing. It overcorrected: a creature given a genuinely
## SUSTAINED new direction (not noise -- asked for the same new direction on
## every one of many consecutive frames) still held its stale OLD facing
## until it had physically covered 3 tiles, which is REAL backward/sideways-
## backward translation the whole time it hadn't -- reported as "the horse
## walks backwards or diagonally backwards sometimes... looks like it's
## moonwalking". A legged animal's own art can only ever show one of two
## facings, so unlike a serpent (which continuously turns its heading toward
## `desired`, meaning its travel direction and visual orientation can never
## disagree by construction) it has no way to represent "still catching up"
## -- any frame spent facing the wrong way IS a frame of visible backward
## sliding. The fix removes the distance commit entirely and flips on the
## very same frame a new direction's sign disagrees with the current facing
## (still gated by FACING_DEADZONE, see below, so per-frame near-vertical
## noise still doesn't flicker it) -- "quadrupeds should only be allowed to
## move forward and sideways... for backwards movement they need to flip to
## orient". The instability that originally motivated the distance commit
## (ThreatAvoidantWander recomputing "away from threat" fresh every single
## frame) is gone too: flee now commits to one heading for FLEE_COMMIT_
## SECONDS (see _apply_decision) and wander/search only re-derive a new
## heading once per DIRECTION_CHANGE_INTERVAL, so the direction fed into
## _advance is no longer noisy frame-to-frame in the first place.
func test_legged_creature_flips_immediately_when_a_sustained_direction_reverses():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	marker._advance(Vector2.LEFT, 50.0, 0.016)  # faces left; travels ~0.8px
	assert_eq(marker.facing_sign(), -1.0)

	# The requested direction reverses again RIGHT AWAY, well under any old
	# distance-commit threshold (48px at the default tile size) -- must turn
	# on THIS very frame regardless, not after covering any distance in
	# the new direction first.
	marker._advance(Vector2.RIGHT, 50.0, 0.016)
	assert_eq(marker.facing_sign(), 1.0, "should turn the instant the direction reverses, never sliding backward first")


## A facing change is COMMITTED for FACING_COMMIT_SECONDS: a fresh reversal
## request inside that window is refused outright -- the creature stands
## still that frame instead of either flipping again (erratic) or walking
## backward against its facing (moonwalking, the failure mode that killed
## the old distance-based commit; refusing to MOVE is what makes a
## time-based commit safe now). Reported, explicitly: "if it gets blocked by
## a tree and changes direction it should not be allowed to instantly flip
## again". Real animals do exactly this: stop, then turn.
func test_a_freshly_flipped_creature_refuses_to_instantly_flip_back():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	marker.flip_h = true  # visually facing right, with no commit running
	marker._advance(Vector2.LEFT, 50.0, 0.016)  # genuine flip to left -- starts the commit
	assert_eq(marker.facing_sign(), -1.0)
	var at_flip := marker.position

	marker._advance(Vector2.RIGHT, 50.0, 0.016)  # reversal INSIDE the commit window

	assert_eq(marker.facing_sign(), -1.0, "must not flip back inside the commit window")
	assert_eq(marker.position, at_flip, "and must stand rather than moonwalk against its facing")
	assert_false(marker._is_moving, "standing still must read as idle, not a walk cycle in place")


func test_the_facing_commit_expires_and_a_later_reversal_is_honored():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	marker.flip_h = true  # visually facing right, with no commit running
	marker._advance(Vector2.LEFT, 50.0, 0.016)  # flip; commit starts
	assert_eq(marker.facing_sign(), -1.0)

	# Keep walking the committed way until the window has fully elapsed.
	var elapsed := 0.0
	while elapsed < CreatureMarker.FACING_COMMIT_SECONDS:
		marker._advance(Vector2.LEFT, 50.0, 0.1)
		elapsed += 0.1

	marker._advance(Vector2.RIGHT, 50.0, 0.016)
	assert_eq(marker.facing_sign(), 1.0, "a reversal after the commit window is a real decision -- honor it")


## Immediate flipping (above) is only correct if the DIRECTION it follows is
## itself stable -- otherwise every wobble in the requested direction shows
## up as a visible flip (reported: "now it constantly flips back and forth").
## Wander re-derives its heading only once per CreatureWander.
## DIRECTION_CHANGE_INTERVAL (1.5s), so over 30 simulated seconds an
## undisturbed creature has ~20 genuine chances to change direction, and
## only some of those reverse its x sign -- anything beyond a few dozen
## flips is chatter, not real decisions.
func test_a_wandering_creature_does_not_rapidly_flip_its_facing():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)

	var flips := 0
	var last := marker.facing_sign()
	for i in 1800:  # 30s at 60fps
		marker._process(1.0 / 60.0)
		if marker.facing_sign() != last:
			flips += 1
			last = marker.facing_sign()

	assert_lt(flips, 30, "facing should follow real direction changes, not chatter every few frames")


## The same property with a stationary player parked just inside
## CAUTION_RADIUS -- the situation actually reported. Avoidance
## (_caution_biased_step) reshapes the wander heading every frame from the
## live relative angle, so if that reshaping is unstable it shows up here
## even when the underlying wander heading is not.
func test_a_creature_wandering_near_a_stationary_player_does_not_rapidly_flip_its_facing():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_player(Vector2(100 + CreatureMarker.CAUTION_RADIUS - 20.0, 100))

	var flips := 0
	var last := marker.facing_sign()
	for i in 1800:
		marker._process(1.0 / 60.0)
		if marker.facing_sign() != last:
			flips += 1
			last = marker.facing_sign()

	assert_lt(flips, 30, "avoiding a stationary player should not make the facing chatter")


## A player parked right AT the flee boundary made the creature oscillate in
## and out of fleeing: cross SENSE_RADIUS, flee outward, drop back to wander,
## drift back in, flee again -- switching intent (and usually direction, and
## so facing) every couple of seconds. Measured 16-23 facing flips per 30
## simulated seconds with the player at 60-90px, versus 2 when well clear.
## This is the last mechanism behind a long-running report ("the flee
## hystery still persists... check how you fixed that one for the snake and
## do the same for all animals that flee"), and the fix is the same shape as
## every other one in this file: hysteresis. Fleeing is entered at
## SENSE_RADIUS but only released once the threat is FLEE_RELEASE_RADIUS
## away, so the two thresholds can't be straddled by one position.
func test_a_creature_does_not_oscillate_in_and_out_of_fleeing_at_the_sense_boundary():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_player(Vector2(100 + CreatureMarker.SENSE_RADIUS, 100))

	var flips := 0
	var last := marker.facing_sign()
	for i in 1800:
		marker._process(1.0 / 60.0)
		if marker.facing_sign() != last:
			flips += 1
			last = marker.facing_sign()

	assert_lt(flips, 10, "sitting on the flee boundary should not make it dither in and out of fleeing")


## Hysteresis must not turn into never letting go: once the threat is
## genuinely far away, the creature has to stop fleeing and resume normal
## life, or it would sprint forever after one scare.
func test_a_creature_stops_fleeing_once_the_threat_is_well_clear():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	var player := _add_stub_player(Vector2(100 + CreatureMarker.SENSE_RADIUS - 5.0, 100))
	marker._process(0.3)
	assert_gt(marker._flee_commit_remaining, 0.0, "should be fleeing while the threat is inside sense range")

	player.position = Vector2(100 + CreatureMarker.FLEE_RELEASE_RADIUS + 20.0, 100)
	marker._process(0.3)
	marker._process(0.3)

	assert_eq(marker._flee_commit_remaining, 0.0, "well past the release radius it should be back to ordinary life")


## Stand-in for a tree/stone: CreatureMarker finds real obstacles by group
## (see CreatureMarker.TREE_GROUP/STONE_GROUP) and sizes them from their own
## CollisionShape2D, so a bare Node2D in the group exercises the fallback
## radius rather than needing a full StaticBody2D + shape.
class StubObstacle:
	extends Node2D


func _add_stub_tree(at: Vector2) -> StubObstacle:
	var tree := StubObstacle.new()
	tree.position = at
	add_child(tree)
	tree.add_to_group(CreatureMarker.TREE_GROUP)
	_extra.append(tree)
	return tree


## A world that answers solid_obstacles_near itself (the real
## EarthChunkManager does, from its per-chunk tree/stone bookkeeping --
## O(nearby)). When the world offers it, the marker must use it INSTEAD of
## scanning the whole "tree"/"stone" node groups, which was every node in
## every loaded chunk, per creature, per sensing tick (reported: "since the
## last change the game is laggy").
class StubWorldWithObstacles:
	extends StubWorld
	var obstacles: Array = []
	func solid_obstacles_near(_at: Vector2, _radius: float) -> Array:
		return obstacles


## No group nodes exist here AT ALL -- if the marker were still scanning
## groups it would see open ground everywhere and walk; only by asking the
## world can it learn it is enclosed. Standing still proves the world's
## answer is what it actually uses.
func test_obstacles_come_from_the_world_when_it_offers_a_bounded_lookup():
	var world := StubWorldWithObstacles.new()
	for i in 14:
		var angle := TAU * float(i) / 14.0
		world.obstacles.append(
			{"position": Vector2(100, 100) + Vector2.RIGHT.rotated(angle) * 14.0, "radius": 14.0}
		)
	marker.info = CreatureInfo.new("horse")
	marker.setup(world, TILE_SIZE)

	for i in 60:
		marker._process(1.0 / 60.0)

	assert_false(marker._is_moving, "enclosed by world-reported obstacles: it should stand still")
	assert_lt(marker.position.distance_to(Vector2(100, 100)), 2.0)


## The reported situation, end to end: wedged between the player on one side
## and trees on every other, with genuinely nowhere to go. Before the
## movement gate the creature kept picking a new direction every frame,
## trying to move, failing, and flipping its facing each time (reported:
## "when it's stuck between player and blocked by a tree it still flips
## erratically... same when blocked by a stone"). It must now stand still --
## no facing changes at all -- rather than thrash.
func test_a_creature_with_nowhere_to_go_stands_still_instead_of_flipping():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_player(Vector2(140, 100))
	# Ring the creature in, leaving only the player's side notionally open.
	for i in 14:
		var angle := TAU * float(i) / 14.0
		_add_stub_tree(marker.position + Vector2.RIGHT.rotated(angle) * 14.0)

	var flips := 0
	var last := marker.facing_sign()
	for i in 600:
		marker._process(1.0 / 60.0)
		if marker.facing_sign() != last:
			flips += 1
			last = marker.facing_sign()

	assert_eq(flips, 0, "a creature with nowhere to go should not flip at all")
	assert_false(marker._is_moving, "and should read as standing still, so it shows the idle pose")


## Boxed in must mean IDLE, not a walk cycle played on the spot -- "it should
## just stay in idle mode without walk animation or flips".
func test_a_creature_with_nowhere_to_go_shows_the_idle_pose_not_the_walk_cycle():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	for i in 14:
		var angle := TAU * float(i) / 14.0
		_add_stub_tree(marker.position + Vector2.RIGHT.rotated(angle) * 14.0)

	for i in 30:
		marker._process(1.0 / 60.0)

	assert_true(marker._animation_frames.has("idle"))
	assert_false(marker._animation_frames.has("walk"), "it never walked, so no walk frames should have been built")


## A single tree ahead is an obstacle to walk AROUND, not a reason to stop --
## the gate must only surrender when there is genuinely nothing open.
func test_a_creature_still_moves_when_only_one_side_is_blocked():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_tree(Vector2(120, 100))

	var start := marker.position
	for i in 120:
		marker._process(1.0 / 60.0)

	assert_gt(marker.position.distance_to(start), 5.0, "one tree should not pin a creature in place")


## The reverse of the above: repeatedly re-requesting the SAME already-
## current-facing direction must never flip it back and forth -- there's
## nothing here to debounce (every one of these frames agrees with the
## current facing), this just proves a steady direction doesn't self-
## destabilize once the distance commit is gone.
func test_legged_creature_facing_stays_put_while_the_direction_stays_the_same():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	for i in 20:
		marker._advance(Vector2.RIGHT, 50.0, 0.016)
	assert_eq(marker.facing_sign(), 1.0, "should still be facing right -- the direction never actually changed")


func test_legged_creature_facing_ignores_near_vertical_direction():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	marker.flip_h = true  # visually facing right (left-drawn art, mirrored)
	marker._advance(Vector2(0.05, -1.0), 50.0, 0.016)  # almost straight up
	assert_eq(marker.facing_sign(), 1.0, "not enough horizontal component to justify turning")


## FACING_DEADZONE deliberately refuses to flip on a near-vertical direction
## (above) -- but the small backward x was still being APPLIED, so the
## creature slid a little the wrong way while facing forward. That's the
## residual moonwalking left over after immediate flipping fixed the big
## reversals (measured at 266 backward frames per 1800 before this fix).
## "Quadrupeds should only be allowed to move forward and sideways" -- so
## inside the deadzone the backward component is dropped and the movement
## becomes purely sideways, rather than either flipping (which would
## flicker on near-vertical noise) or sliding backward.
func test_legged_creature_never_slides_backward_on_a_near_vertical_direction():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	marker.flip_h = true  # visually facing right
	marker.position = Vector2(100, 100)

	marker._advance(Vector2(-0.1, -0.99), 50.0, 0.1)  # |x| under the deadzone

	assert_eq(marker.facing_sign(), 1.0, "still too near-vertical to justify turning")
	assert_almost_eq(marker.position.x, 100.0, 0.001, "must not slide backward -- move purely sideways instead")
	assert_lt(marker.position.y, 100.0, "the sideways (vertical) part of the movement should still happen")


## The mirror of the above: only BACKWARD movement is suppressed inside the
## deadzone. A small FORWARD x is perfectly natural (walking mostly-vertically
## while drifting the way it already faces) and must be left alone.
func test_legged_creature_still_drifts_forward_on_a_near_vertical_direction():
	marker.info = CreatureInfo.new("horse")
	marker._art_faces_left = true
	marker.flip_h = true  # visually facing right
	marker.position = Vector2(100, 100)

	marker._advance(Vector2(0.1, -0.99), 50.0, 0.1)

	assert_gt(marker.position.x, 100.0, "a small forward drift is fine -- only backward is suppressed")


## The end-to-end guarantee, over a long realistic run: a legged creature
## must never translate against its own drawn facing, in ANY frame, for any
## reason (reported repeatedly: "the horse walks backwards or diagonally
## backwards sometimes... so it looks like it's moonwalking").
func test_a_wandering_creature_never_translates_against_its_own_facing():
	marker.info = CreatureInfo.new("horse")
	marker.setup(StubWorld.new(), TILE_SIZE)
	_add_stub_player(Vector2(100 + CreatureMarker.CAUTION_RADIUS - 20.0, 100))

	var backward_frames := 0
	for i in 1800:
		var before := marker.position
		marker._process(1.0 / 60.0)
		var moved := marker.position.x - before.x
		# Compared against facing_sign (which way it's actually SEEN to
		# face), not flip_h -- see the comment on
		# test_legged_creature_flips_to_face_a_sustained_new_direction for
		# why asserting on flip_h here let a fully-mirrored horse pass.
		if absf(moved) > 0.001 and signf(moved) != marker.facing_sign():
			backward_frames += 1

	assert_eq(backward_frames, 0, "a quadruped should only ever move forward or sideways, never backward")


## The same end-to-end guarantee for a right-facing-art species, so the
## suite can't pass again by accidentally agreeing with one art convention.
func test_a_right_facing_species_also_never_translates_against_its_own_facing():
	marker.info = CreatureInfo.new("deer")
	marker.setup(StubWorld.new(), TILE_SIZE)

	var backward_frames := 0
	for i in 900:
		var before := marker.position
		marker._process(1.0 / 60.0)
		var moved := marker.position.x - before.x
		if absf(moved) > 0.001 and signf(moved) != marker.facing_sign():
			backward_frames += 1

	assert_eq(backward_frames, 0)


func test_legged_creatures_never_rotate():
	marker.info = CreatureInfo.new("horse")
	marker._advance(Vector2.UP, 50.0, 0.5)
	assert_eq(marker.rotation, 0.0, "legs must stay planted toward the ground, never tipped over")


func test_serpents_still_turn_before_advancing():
	marker.info = CreatureInfo.new("nonvenomous_snake")
	marker._heading = Vector2.RIGHT
	marker._advance(Vector2.UP, 100.0, 0.05)
	# Should have started turning toward UP, not snapped fully there in one
	# small step -- unlike legged animals, which go exactly where asked.
	assert_lt(marker._heading.angle(), 0.0, "should have started turning toward UP")
	assert_gt(marker._heading.angle(), -PI / 2.0, "should not have reached UP in a single small step")


func test_serpents_still_rotate_their_whole_body_to_face_their_heading():
	marker.info = CreatureInfo.new("nonvenomous_snake")
	marker._heading = Vector2.RIGHT
	marker._advance(Vector2.DOWN, 50.0, 3.0)  # a big delta so the turn fully completes
	assert_almost_eq(marker.rotation, marker._heading.angle(), 0.01)


# -- movement: leg animation only plays while actually advancing --------------

func test_advance_marks_the_creature_as_moving_when_it_actually_moves():
	marker._advance(Vector2.RIGHT, 50.0, 0.1)
	assert_true(marker._is_moving)


func test_advance_marks_the_creature_as_not_moving_for_a_near_zero_direction():
	marker._is_moving = true
	marker._advance(Vector2.ZERO, 50.0, 0.1)
	assert_false(marker._is_moving)


## _is_moving used to be derived purely from the requested direction's own
## length, not from whether the creature's position actually changed --
## anything that leaves a creature's position unchanged despite a nonzero
## requested direction (e.g. blocked by an obstacle like a tree) would still
## play the walk-gait animation forever, a gap the idle-pose fix above
## didn't cover (reported: "should only render walk animation when moving,
## not when stuck against a tree or standing still"). speed=0.0 here stands
## in for "wanted to move, didn't actually go anywhere" without needing a
## real collision system to reproduce it.
func test_advance_marks_the_creature_as_not_moving_when_blocked_despite_a_real_direction():
	marker.position = Vector2(100, 100)
	marker._is_moving = true
	marker._advance(Vector2.RIGHT, 0.0, 0.1)
	assert_false(marker._is_moving)


func test_processing_a_zero_delta_frame_leaves_is_moving_false():
	marker.setup(StubWorld.new(), TILE_SIZE)
	marker._is_moving = true  # leftover state from a previous, actually-moving frame
	marker._process(0.0)
	assert_false(marker._is_moving)


func test_animation_step_uses_the_idle_pose_when_not_moving():
	marker.info = CreatureInfo.new("horse")
	marker._current_action = "walk"
	marker._is_moving = false
	marker._animation_step()
	assert_true(marker._animation_frames.has("idle"))
	assert_false(marker._animation_frames.has("walk"))


func test_animation_step_uses_the_walk_gait_while_moving():
	marker.info = CreatureInfo.new("horse")
	marker._current_action = "walk"
	marker._is_moving = true
	marker._animation_step()
	assert_true(marker._animation_frames.has("walk"))


# -- illustrated species (real art) vs. procedural (see IllustratedAnimal
# Sprite) -- reported: "the procedural generated sprites are too bad...
# let's switch to illustrated ones". A species with real art (horse/deer/
# boar) uses it for walk/eat/idle; every other action, and every other
# species, still falls back to the procedural generator entirely.

const IllustratedAnimalSprite = preload("res://src/rendering/illustrated_animal_sprite.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")


## Illustrated walk art is 8 hand-drawn frames, not ProceduralAnimalAnimation's
## 5-frame procedural gait -- the frame count is what proves which generator
## actually ran.
func test_animation_step_uses_illustrated_walk_frames_for_a_species_with_real_art():
	marker.info = CreatureInfo.new("horse")
	marker._current_action = "walk"
	marker._is_moving = true
	marker._animation_step()
	assert_eq(marker._animation_frames["walk"].size(), IllustratedAnimalSprite.new().generate_textures("horse", "walk").size())


## A species with no registered art (e.g. predator) must keep using the
## procedural generator exactly as before -- switching horse/deer/boar to
## real art must not silently break, or change the look of, everything else.
func test_animation_step_still_uses_procedural_frames_for_a_species_without_real_art():
	marker.info = CreatureInfo.new("predator")
	marker._current_action = "walk"
	marker._is_moving = true
	marker._animation_step()
	const ProceduralAnimalAnimation = preload("res://src/rendering/procedural_animal_animation.gd")
	assert_eq(marker._animation_frames["walk"].size(), ProceduralAnimalAnimation.WALK_FRAME_COUNT)


## No eat/drink/swim/attack art exists -- an illustrated species falls back
## to the procedural generator for any action outside walk/eat/idle, rather
## than crashing or showing a blank/frozen sprite.
## Illustrated species now have art (dedicated or fallen-back) for EVERY
## action a creature can perform -- attack was the last one dropping to the
## procedural generator, which visibly changed a charging boar's art style
## mid-lunge (reported: "when the boar is attacking it switches to old
## procedural sprite"). So the procedural path is now reached only by
## species with no sheet at all, which
## test_animation_step_still_uses_procedural_frames_for_a_species_without_real_art
## already covers. This asserts the new guarantee instead: an illustrated
## species never falls back, whatever it is doing.
func test_an_illustrated_species_never_falls_back_to_procedural_art():
	const ProceduralAnimalAnimation = preload("res://src/rendering/procedural_animal_animation.gd")
	for action in ProceduralAnimalAnimation.ACTIONS:
		marker.info = CreatureInfo.new("boar")
		marker._current_action = action
		marker._is_moving = true
		marker._animation_step()
		assert_true(
			marker._illustrated.has_action("boar", action),
			"a boar must stay on its own art while %s" % action
		)


## `scale` used to be set ONCE at spawn time (see CreatureRenderer.
## _build_marker), calibrated for whichever canvas that species' INITIAL
## texture used -- an illustrated species' idle frame. Switching to an
## action illustrated art doesn't cover (swim/drink/attack, or eat for
## horse specifically) swaps to a MUCH smaller procedural canvas (48x32,
## see ProceduralAnimalSprite.WIDTH/HEIGHT) without ever revisiting scale,
## rendering the creature far too small (reported: "when the horse enters
## the water it becomes tiny"). _animation_step must recompute scale for
## whichever canvas the CURRENT action's frames actually came from.
## "attack" (unlike "swim"/"drink" -- see IllustratedAnimalSprite.
## has_action's own doc comment) has no illustrated fallback at all, so it's
## the one action guaranteed to still fall through to the procedural
## generator for every illustrated species -- the right one to exercise
## this rescale with.
## An action can come from its OWN source file at its OWN resolution (horse's
## idle is a 1536x1024 portrait; its walk is a 2172x724 sheet), so `scale`
## must be recomputed per action or the creature would visibly change size
## the instant it stopped walking. Originally written against the
## illustrated→procedural swap, which no longer exists for these species --
## the per-action-file case is now the real one.
##
## Species matters here, not just as a stand-in for "some illustrated
## species": marker_scale measures frame 0's content width AFTER
## normalize_frames has already rescaled the whole action's frame batch so
## its OWN widest pose fills the shared canvas (see normalize_frames' own
## doc comment) -- so the measured width, and therefore marker_scale, comes
## out identical across actions whenever frame 0 happens to BE that batch's
## widest, canvas-width-bound pose. That is a real, deterministic property
## of the ART, not a computation bug -- verified by hand-measuring boar's
## three sheets, where frame 0 is exactly that pose in walk, idle, AND eat
## alike, so every boar action lands on the exact same scale (confirmed via
## IllustratedAnimalSprite.marker_scale("boar", ...)). Boar is therefore the
## one species where this test's premise doesn't hold; horse's walk/idle
## frame-0 poses are NOT both the width-bound extreme of their batches, so
## their measured scales genuinely differ.
func test_animation_step_rescales_when_an_action_comes_from_a_different_source_file():
	marker.info = CreatureInfo.new("horse")
	marker._current_action = "walk"
	marker._is_moving = true
	marker._animation_step()
	var walk_scale := marker.scale

	marker._current_action = "walk"
	marker._is_moving = false  # resolves to idle, which is its own file
	marker._animation_step()

	assert_ne(marker.scale, walk_scale, "scale must change once the texture source changes")
	var expected: float = marker._illustrated.marker_scale("horse", "idle")
	assert_almost_eq(marker.scale.x, expected, 0.0001, "should match that action's own measured scale")


## The walk cycle's cadence is driven by DISTANCE actually covered, not by
## wall-clock time -- stride frequency is proportional to speed, the real
## physical relationship (reported: "adapt the horse animation to be faster
## when it moves faster... walking should look natural and realistic"). A
## time-based cycle plays the same leisurely 0.3s-per-frame gait whether the
## creature ambles at 24px/s or flees at 40px/s, which reads as legs
## slipping over the ground at speed. GAIT_STRIDE_PER_FRAME is derived, not
## eyeballed: at CreatureWander.WANDER_SPEED the cadence works out to
## exactly the old ANIMATION_FRAME_DURATION, so ambling looks unchanged and
## everything faster scales up proportionally.
func test_walk_cycle_cadence_scales_with_actual_movement_speed():
	var changes := {}
	for speed in [CreatureWander.WANDER_SPEED, CreatureMarker.FLEE_SPEED]:
		marker._gait_distance = 0.0
		marker.info = CreatureInfo.new("horse")
		marker._current_action = "walk"
		var count := 0
		var last: Texture2D = null
		for i in 120:
			marker._advance(Vector2.RIGHT, speed, 1.0 / 60.0)
			marker._animation_step()
			if marker.texture != last:
				count += 1
				last = marker.texture
		changes[speed] = count
	assert_gt(
		changes[CreatureMarker.FLEE_SPEED],
		changes[CreatureWander.WANDER_SPEED],
		"a fleeing creature's legs must visibly cycle faster than an ambling one's"
	)


func test_gait_stride_per_frame_matches_the_old_cadence_at_wander_speed():
	assert_almost_eq(
		CreatureMarker.GAIT_STRIDE_PER_FRAME,
		CreatureWander.WANDER_SPEED * CreatureMarker.ANIMATION_FRAME_DURATION,
		0.001,
		"derived so an ambling creature's cadence is exactly what it was when time-based"
	)


## Advancing exactly one stride's worth of ground moves the cycle exactly
## one frame -- the precise pin behind the proportionality above.
func test_walk_cycle_advances_one_frame_per_stride_of_ground_covered():
	marker.info = CreatureInfo.new("horse")
	marker._current_action = "walk"
	marker._is_moving = true  # walk resolves to idle otherwise (see _animation_step)
	marker._gait_distance = 0.0
	marker._animation_step()
	var frame_before: Texture2D = marker.texture

	marker._gait_distance = CreatureMarker.GAIT_STRIDE_PER_FRAME * 1.001
	marker._is_moving = true
	marker._animation_step()

	assert_ne(marker.texture, frame_before, "one stride of ground should be the next gait frame")


## Illustrated swim frames reuse the WALK cycle (see IllustratedAnimalSprite.
## has_action), which on its own is just a horse walking across the surface
## -- reported: "it doesn't have a swim animation instead it walks on the
## water... sprite should be submerged and tinted like the others". The
## "others" is SubmersionShader, already used by the player: a world-space
## waterline below which pixels tint blue and fade. Procedural swim frames
## bake their own tint in (ProceduralAnimalAnimation._swim_frame) and must
## NOT also get the shader, or they'd read as double-tinted.
func test_an_illustrated_species_gets_a_submersion_waterline_while_swimming():
	marker.info = CreatureInfo.new("horse")
	marker.position = Vector2(100, 100)
	marker._current_action = "swim"
	marker._is_moving = true

	marker._animation_step()

	assert_not_null(marker.material, "a swimming illustrated creature should get the submersion material")
	var waterline: float = marker.material.get_shader_parameter("water_world_y")
	assert_lt(waterline, 90000.0, "should be a real world Y, not the 'nothing is submerged' sentinel")
	assert_almost_eq(waterline, 100.0, 60.0, "the waterline should sit on the creature's own body")


func test_the_submersion_waterline_is_released_once_it_leaves_the_water():
	marker.info = CreatureInfo.new("horse")
	marker.position = Vector2(100, 100)
	marker._current_action = "swim"
	marker._is_moving = true
	marker._animation_step()

	marker._current_action = "walk"
	marker._animation_step()

	var waterline: float = marker.material.get_shader_parameter("water_world_y")
	assert_gt(waterline, 90000.0, "back on dry land nothing should render as submerged")


## A procedural species' swim frames already have the water baked into the
## pixels, so adding the shader on top would tint them twice.
func test_a_procedural_species_does_not_also_get_the_submersion_shader():
	marker.info = CreatureInfo.new("predator")
	marker._current_action = "swim"
	marker._is_moving = true

	marker._animation_step()

	assert_null(marker.material, "procedural swim art is already tinted; it must not be shaded again")


## The shadow's own scale (see set_shadow/_sync_grounded_children) must
## track the SAME rescale, or a procedural-fallback action would show a
## correctly-resized body next to a shadow still frozen at the illustrated
## size. set_shadow (mirroring CreatureRenderer._build_marker's real spawn-
## time call) seeds an illustrated-sized base scale first, so this actually
## exercises the shadow catching up rather than two untouched defaults
## coincidentally already matching.
func test_animation_step_rescales_the_shadow_alongside_the_body():
	marker.info = CreatureInfo.new("boar")
	var shadow := Node2D.new()
	_extra.append(shadow)
	marker.set_shadow(shadow, Vector2.ONE * 0.17)
	marker._current_action = "walk"
	marker._is_moving = false  # idle: its own source file, its own scale
	marker._animation_step()

	assert_eq(marker._shadow_base_scale, marker.scale)
	assert_ne(marker._shadow_base_scale, Vector2.ONE * 0.17, "should have moved off the stale illustrated-sized base scale")


func _make_predator(at: Vector2) -> CreatureMarker:
	# The before_each herbivore `marker` shares the scene tree and the creature
	# group; park it far away so it doesn't register as prey in these tests.
	marker.position = Vector2(1_000_000, 1_000_000)

	var predator := CreatureMarker.new()
	predator.info = CreatureInfo.new("predator")
	predator.position = at
	predator.home = at
	predator.wander_seed = 3
	predator.setup(StubWorld.new(), TILE_SIZE)
	add_child(predator)
	_extra.append(predator)
	return predator


# -- active foraging: a grazer walks to its food (see GrazerForaging) ---------
#
# Herbivores used to absorb food from the BIOME they stood on: a hungry horse
# anywhere on grassland simply stopped being hungry, with nothing visible
# happening. Now it picks a tuft it can see, walks there, and puts its head
# down (reported: "add foraging behaviour for Horse, Boars, Deers").

class ForageWorld:
	extends RefCounted
	var grass: Array = []
	var fruit: Array = []
	var seeds: Array = []
	var worms: Array = []
	var grazed: Array = []
	var taken_fruit: Array = []

	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"

	func grass_near(_p: Vector2, _r: int = 8) -> Array:
		return grass

	func fruit_near(_p: Vector2, _r: int = 8) -> Array:
		return fruit

	func seeds_near(_p: Vector2, _r: int = 8) -> Array:
		return seeds

	func worms_near(_p: Vector2, _r: int = 8) -> Array:
		return worms

	func graze_grass_at(p: Vector2) -> bool:
		grazed.append(p)
		grass = grass.filter(func(g): return g.position != p)
		return true

	func take_fruit_at(p: Vector2) -> String:
		taken_fruit.append(p)
		return "apple"

	func take_seed_at(_p: Vector2) -> String:
		return ""

	func take_worm_at(_p: Vector2) -> bool:
		return true

	func solid_obstacles_near(_p: Vector2, _r: float) -> Array:
		return []


func _hungry_grazer(species: String, world) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new(species, 1)
	marker.wander_seed = 3
	add_child_autofree(marker)
	marker.setup(world, 16)
	marker.position = Vector2.ZERO
	marker._needs.hunger = 1.0
	return marker


func test_a_hungry_horse_heads_for_a_tuft_it_can_see():
	var world := ForageWorld.new()
	world.grass = [{"position": Vector2(90, 0)}]
	var horse := _hungry_grazer("horse", world)
	# Long enough to cover the step-between-bites interval it walks out
	# before committing (GrazerForaging.REGRAZE_SECONDS) plus the approach
	# itself -- a two-second window only ever caught it mid-stroll.
	var reached := false
	for _i in 900:
		horse._process(1.0 / 60.0)
		if horse.position.distance_to(Vector2(90, 0)) <= GrazerForaging.ARRIVAL_DISTANCE:
			reached = true
			break
	assert_true(reached, "it should walk to the tuft rather than wander off")


func test_arriving_at_the_tuft_it_stops_and_eats_it():
	var world := ForageWorld.new()
	world.grass = [{"position": Vector2(20, 0)}]
	var horse := _hungry_grazer("horse", world)
	var ate := false
	for _i in 900:
		horse._process(1.0 / 60.0)
		if not world.grazed.is_empty():
			ate = true
			break
	assert_true(ate, "the tuft it walked to actually gets eaten")
	assert_eq(horse._current_action, "eat", "and it has its head down doing it")


func test_eating_a_tuft_settles_the_hunger_that_sent_it_there():
	var world := ForageWorld.new()
	world.grass = [{"position": Vector2(20, 0)}]
	var horse := _hungry_grazer("horse", world)
	for _i in 900:
		horse._process(1.0 / 60.0)
		if not world.grazed.is_empty():
			break
	assert_false(horse._needs.is_hungry(), "a fed animal is not still hunting for food")


## A deer is a mixed feeder and works windfall; a horse is a strict grazer and
## walks past it (see GrazerForaging.FORAGE_KINDS_BY_SPECIES).
func test_a_deer_takes_the_windfall_a_horse_ignores():
	var deer_world := ForageWorld.new()
	deer_world.fruit = [{"position": Vector2(20, 0), "species": "apple"}]
	var deer := _hungry_grazer("deer", deer_world)
	var horse_world := ForageWorld.new()
	horse_world.fruit = [{"position": Vector2(20, 0), "species": "apple"}]
	var horse := _hungry_grazer("horse", horse_world)
	for _i in 900:
		deer._process(1.0 / 60.0)
		horse._process(1.0 / 60.0)
	assert_false(deer_world.taken_fruit.is_empty(), "a deer works fallen fruit")
	assert_true(horse_world.taken_fruit.is_empty(), "a horse does not")


## Nothing to walk to must not mean standing around starving: an animal on
## food terrain still crops what is under it, so a bare meadow with no tuft
## entities behaves as it always did.
func test_an_empty_meadow_still_feeds_an_animal_standing_in_it():
	var world := ForageWorld.new()  # no grass entities at all
	var horse := _hungry_grazer("horse", world)
	var fed := false
	for _i in 900:
		horse._process(1.0 / 60.0)
		if not horse._needs.is_hungry():
			fed = true
			break
	assert_true(fed, "biome grazing still backs up entity foraging")


## Predators feed by hunting and must not be handed a graze cycle.
func test_a_predator_does_not_graze():
	var world := ForageWorld.new()
	world.grass = [{"position": Vector2(20, 0)}]
	var lynx := _hungry_grazer("lynx", world)
	for _i in 600:
		lynx._process(1.0 / 60.0)
	assert_true(world.grazed.is_empty(), "a lynx does not eat grass")


# -- restrained by a lasso (see docs/concept/taming.md) -----------------------
#
# A caught animal is not a wandering animal that happens to be near you: it
# stops making its own decisions about where to go, fights the rope on its own
# clock, and is held at rope length by whatever end of it is anchored.

class TamingWorld:
	extends RefCounted

	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"

	func solid_obstacles_near(_p: Vector2, _r: float) -> Array:
		return []


func _catchable(species: String) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new(species, 1)
	marker.wander_seed = 5
	add_child_autofree(marker)
	marker.setup(TamingWorld.new(), 16)
	marker.position = Vector2.ZERO
	return marker


func test_an_animal_starts_out_free():
	var horse := _catchable("horse")
	assert_false(horse.is_restrained())
	assert_eq(horse.trust, 0.0)


func test_catching_an_animal_restrains_it():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2(20, 0))
	assert_true(horse.is_restrained())


## The rope is what holds it, so releasing gives the animal itself back --
## trust it has already earned is NOT lost, or feeding would be pointless.
func test_releasing_an_animal_keeps_the_trust_it_earned():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	horse._needs.hunger = 1.0  # a treat only counts when the animal wants it
	horse.feed_treat()
	var earned: float = horse.trust
	assert_gt(earned, 0.0, "precondition: it learned something")
	horse.release()
	assert_false(horse.is_restrained())
	assert_eq(horse.trust, earned)


## The rope is a rope: whatever the AI wanted this frame, the animal cannot
## end up further from its anchor than the rope is long.
func test_a_restrained_animal_cannot_wander_off_the_end_of_its_rope():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	var held_frames := 0
	for _i in 600:
		horse._process(1.0 / 60.0)
		if not horse.is_restrained():
			break  # it fought the rope off; past the end is now allowed
		held_frames += 1
		assert_lte(
			horse.position.distance_to(Vector2.ZERO), RopeTether.ROPE_LENGTH + 0.01,
			"the horse got past the end of the rope"
		)
	assert_gt(held_frames, 0, "precondition: it was actually held for a while")


## Leading: the anchor moves with the player, so the animal follows it.
func test_a_led_animal_follows_its_holder():
	var horse := _catchable("horse")
	var holder := Vector2.ZERO
	for step in 600:
		holder = Vector2(float(step) * 0.5, 0)
		horse.restrain_to(holder)
		horse._process(1.0 / 60.0)
	assert_lt(
		horse.position.distance_to(holder), RopeTether.ROPE_LENGTH + 0.01,
		"it should have been towed along, not left behind"
	)


# The healthy-herd counterpart of the test below now lives in
# test_the_measured_catch_rate_matches_the_model at the bottom of this file:
# it measures the same property over sixty animals instead of forty and
# asserts a stated band, where this one asserted "more than half" and landed
# on exactly half often enough to be a coin flip of its own.

## ... and a worn-down one usually does not, which is what makes wearing an
## animal down a real strategy.
func test_a_worn_down_herd_mostly_stays_caught():
	var escapes := 0
	for seed_value in 40:
		var horse := _catchable("horse")
		horse.wander_seed = seed_value
		horse.info.health = horse.info.max_health * 0.12
		horse.restrain_to(Vector2.ZERO)
		for _i in 240:
			horse._process(1.0 / 60.0)
			if not horse.is_restrained():
				escapes += 1
				break
	assert_lt(escapes, 20, "an exhausted horse should usually stay caught")


## Feeding only counts when the animal is hungry -- the rule the whole system
## rests on (see Taming.trust_after_feeding). Asserted here at the marker so
## the wiring cannot quietly ignore it.
func test_feeding_a_full_animal_teaches_it_nothing():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	horse._needs.hunger = 0.0
	horse.feed_treat()
	assert_eq(horse.trust, 0.0)


func test_feeding_a_hungry_animal_enough_times_tames_it():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	var feeds := 0
	while not horse.is_tame() and feeds < 20:
		horse._needs.hunger = 1.0
		horse.feed_treat()
		feeds += 1
	assert_true(horse.is_tame(), "feeding a hungry horse should eventually tame it")
	assert_between(feeds, 4, 8)


## A predator is not tameable with a rope and a carrot.
func test_a_predator_shrugs_off_the_rope():
	var lynx := _catchable("lynx")
	lynx.restrain_to(Vector2.ZERO)
	assert_false(lynx.is_restrained(), "a lynx does not become a pet")


# -- what the player can read off a caught animal ----------------------------
#
# Hunger already exists in the simulation and trust now does too; taming is
# unplayable if neither is visible, because "feed it when it is hungry" is an
# instruction the player cannot follow against a hidden number.

func test_a_wild_animal_shows_no_taming_state():
	var horse := _catchable("horse")
	horse._process(1.0 / 60.0)
	assert_false(horse._trust_bar.visible, "a horse in a field is not a project")
	assert_false(horse._hunger_pip.visible)


func test_a_caught_animal_shows_how_far_along_its_taming_is():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	horse._process(1.0 / 60.0)
	assert_true(horse._trust_bar.visible, "the player has to see progress to believe in it")


func test_the_trust_bar_fills_as_the_animal_is_won_over():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	horse._process(1.0 / 60.0)
	var empty: float = horse._trust_bar.size.x
	horse._needs.hunger = 1.0
	horse.feed_treat()
	horse._process(1.0 / 60.0)
	assert_gt(horse._trust_bar.size.x, empty)


## The cue that it is time to feed it. Shown only when the animal is actually
## hungry, because that is exactly when feeding does anything.
func test_a_hungry_caught_animal_asks_to_be_fed():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	horse._needs.hunger = 1.0
	horse._process(1.0 / 60.0)
	assert_true(horse._hunger_pip.visible)


func test_a_fed_animal_stops_asking():
	var horse := _catchable("horse")
	horse.restrain_to(Vector2.ZERO)
	horse._needs.hunger = 0.0
	horse._process(1.0 / 60.0)
	assert_false(horse._hunger_pip.visible)


# -- a tamed animal takes orders (see docs/concept/taming.md) -----------------

func _tamed(species: String) -> CreatureMarker:
	var horse := _catchable(species)
	horse.restrain_to(Vector2.ZERO)
	while not horse.is_tame():
		horse._needs.hunger = 1.0
		horse.feed_treat()
	horse.release()
	return horse


func test_a_wild_animal_ignores_orders():
	var horse := _catchable("horse")
	assert_false(horse.set_order(Taming.ORDER_STAY), "a wild horse is nobody's to command")


func test_a_tamed_animal_takes_an_order():
	var horse := _tamed("horse")
	assert_true(horse.set_order(Taming.ORDER_STAY))
	assert_eq(horse.order, Taming.ORDER_STAY)


## The bug this is here to prevent: the player is sensed as a THREAT, so
## without this a horse you spent five carrots taming would spend the rest of
## its life fleeing from you.
func test_a_tamed_animal_stops_being_afraid_of_its_owner():
	var horse := _tamed("horse")
	assert_false(horse.fears_players(), "a tamed animal does not flee its owner")
	assert_true(_catchable("horse").fears_players(), "a wild one still does")


## Told to stay, it holds the ground it was told to hold -- that is what makes
## "stay" different from "wander off".
func test_an_animal_told_to_stay_holds_its_ground():
	var horse := _tamed("horse")
	horse.position = Vector2(100, 100)
	horse.set_order(Taming.ORDER_STAY)
	for _i in 900:
		horse._process(1.0 / 60.0)
	assert_lt(
		horse.position.distance_to(Vector2(100, 100)), CreatureMarker.STAY_RADIUS + 1.0,
		"it should mill about where it was left, not wander off"
	)


## Told to follow, it comes with you -- and closes the gap rather than merely
## not running away.
func test_an_animal_told_to_follow_closes_on_its_owner():
	var horse := _tamed("horse")
	horse.position = Vector2(200, 0)
	horse.set_order(Taming.ORDER_FOLLOW)
	horse.follow_target = Vector2.ZERO
	var start := horse.position.distance_to(Vector2.ZERO)
	for _i in 900:
		horse._process(1.0 / 60.0)
	assert_lt(horse.position.distance_to(Vector2.ZERO), start, "it should have come to you")


func test_a_following_animal_stops_short_rather_than_standing_on_you():
	var horse := _tamed("horse")
	horse.position = Vector2(200, 0)
	horse.set_order(Taming.ORDER_FOLLOW)
	horse.follow_target = Vector2.ZERO
	for _i in 1800:
		horse._process(1.0 / 60.0)
	assert_gt(
		horse.position.distance_to(Vector2.ZERO), 1.0,
		"a horse walks up to you, it does not stand inside you"
	)


## The rate the player actually sees, measured across many INDEPENDENT
## animals rather than derived: fresh, full-health, held until the struggle
## resolves. Pinned here because the model and the game drifted apart once
## before -- the per-attempt number said one thing and the compounded reality
## another (reported: "both horses and deer always break free").
func test_the_measured_catch_rate_matches_the_model():
	var held := 0
	var trials := 60
	for seed_value in trials:
		var horse := _catchable("horse")
		horse.wander_seed = seed_value * 7919
		horse.info.health = horse.info.max_health
		horse.restrain_to(Vector2.ZERO)
		for _i in 3000:
			horse._process(1.0 / 60.0)
			if not horse.is_restrained():
				break
			horse.restrain_to(Vector2.ZERO)
		if horse.is_restrained():
			held += 1
	var rate := float(held) / float(trials)
	gut.p("measured hold rate: %.2f (model says %.2f)" % [rate, Taming.hold_chance(1.0)])
	assert_between(
		rate, 0.2, 0.55,
		"catching a healthy horse should be a real chance, neither a certainty nor a lottery"
	)


# -- death is booked against the region (see EcosystemSimulation.record_death) -
#
# _die() is the single choke point every death goes through -- combat, disease,
# starvation alike -- so it is the one place the individual half of the
# simulation can tell the aggregate half that an animal is gone. Without this
# the two halves disagree and _reconcile_chunk_creatures restocks whatever the
# player just hunted (see concept/animal_husbandry.md's "Consequence").

class DeathRecordingWorld:
	extends StubWorld
	var deaths: Array = []
	func record_death_at(at: Vector2, is_predator: bool) -> void:
		deaths.append({"at": at, "is_predator": is_predator})


func _dying(species: String, world: DeathRecordingWorld) -> CreatureMarker:
	var dying := CreatureMarker.new()
	dying.info = CreatureInfo.new(species, 1)
	dying.wander_seed = 5
	add_child_autofree(dying)
	dying.setup(world, 16)
	dying.position = Vector2(64, 32)
	return dying


func test_a_killed_animal_is_booked_against_its_region():
	var world := DeathRecordingWorld.new()
	var deer := _dying("herbivore", world)
	deer.take_damage(deer.info.max_health)
	assert_eq(world.deaths.size(), 1)
	assert_eq(world.deaths[0]["at"], Vector2(64, 32))


## A wolf and a deer come out of two different pools, and the predator pool's
## own capacity is derived from the herbivore one -- so which pool a death
## lands in has to travel with the death, not be guessed at the far end.
func test_a_killed_predator_is_booked_as_a_predator():
	var world := DeathRecordingWorld.new()
	var wolf := _dying("wolf", world)
	wolf.take_damage(wolf.info.max_health)
	assert_eq(world.deaths.size(), 1)
	assert_true(world.deaths[0]["is_predator"])


func test_a_killed_herbivore_is_not_booked_as_a_predator():
	var world := DeathRecordingWorld.new()
	var deer := _dying("herbivore", world)
	deer.take_damage(deer.info.max_health)
	assert_false(world.deaths[0]["is_predator"])


## Carrying capacity governs WILD animals; the player's stock is deliberately
## extra (see KeptAnimals, and _thin_creatures' refusal to cull anything the
## player has a stake in). A barn losing a sheep is not the land losing one, so
## a tamed animal's death must not come off the region's books.
func test_a_tamed_animals_death_is_not_booked_against_the_wild_population():
	var world := DeathRecordingWorld.new()
	var sheep := _dying("herbivore", world)
	sheep.trust = 1.0
	sheep.take_damage(sheep.info.max_health)
	assert_eq(world.deaths.size(), 0)


## Same rule, the other half of KeptAnimals.is_worth_keeping: an animal on the
## end of a rope is one the player has a stake in even at zero trust.
func test_a_restrained_animals_death_is_not_booked_against_the_wild_population():
	var world := DeathRecordingWorld.new()
	var horse := _dying("horse", world)
	horse.restrain_to(Vector2(70, 32))
	horse.take_damage(horse.info.max_health)
	assert_eq(world.deaths.size(), 0)


## The marker must not assume the world can take the call: plenty of stub and
## partially-built worlds cannot, and a death is not worth a crash.
func test_a_world_that_cannot_record_deaths_is_survivable():
	var plain := StubWorld.new()
	var deer := CreatureMarker.new()
	deer.info = CreatureInfo.new("herbivore", 1)
	deer.wander_seed = 5
	add_child_autofree(deer)
	deer.setup(plain, 16)
	deer.take_damage(deer.info.max_health)
	assert_true(true, "a death against a world with no record_death_at must not crash")
