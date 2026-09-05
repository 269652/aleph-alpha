extends GutTest

## A purely decorative, one-shot visual: an ant walking a fixed path (mound
## -> harvested item's last position -> cache/plant target), spawned right
## after AntColony's own instant, data-level forage-and-cache resolution
## already happened (see EarthChunkManager._forage_seed_near_mound). The
## actual game-state effect is already real and correct on its own -- this
## marker exists ONLY so a player can actually see it happen.

const AntForagerMarker = preload("res://src/rendering/ant_forager_marker.gd")
const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## add_child_autofree (see _spawned_at) fully covers cleanup -- no separate
## per-test var/after_each needed, unlike test_decomposer_marker.gd's own
## carcass fixture, which is a genuinely SEPARATE node from the marker.


func _spawned_at(path: Array) -> AntForagerMarker:
	var forager := AntForagerMarker.new()
	forager.path = path
	forager.position = path[0]
	add_child_autofree(forager)
	return forager


func test_joins_the_ant_forager_group():
	var f := _spawned_at([Vector2.ZERO, Vector2(10, 0)])
	assert_true(f.is_in_group(AntForagerMarker.GROUP_NAME))


func test_has_a_real_ant_sprite_texture():
	var f := _spawned_at([Vector2.ZERO, Vector2(10, 0)])
	var sprite := f.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)


## Real illustrated ant art now exists (see IllustratedDecomposerSprite) --
## checked first, same has_X()-gated fallback convention every other
## optional illustrated-art seam in this codebase uses. Scale is measured
## from the real art (marker_scale), not the procedural generator's fixed
## ArtResolution.SPRITE_SCALE.
func test_sprite_is_scaled_down_like_every_other_decomposer_ant():
	var f := _spawned_at([Vector2.ZERO, Vector2(10, 0)])
	var sprite := f.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * IllustratedDecomposerSprite.new().marker_scale("ant", "walk"))


## Before reaching the pickup waypoint, a forager has nothing to carry yet
## -- it should show the plain walk cycle.
func test_shows_the_walk_pose_before_reaching_the_pickup_waypoint():
	var f := _spawned_at([Vector2(0, 0), Vector2(20, 0), Vector2(20, 50)])
	var sprite := f.get_child(0) as Sprite2D
	var walk_frames := IllustratedDecomposerSprite.new().generate_textures("ant", "walk")
	assert_true(walk_frames.has(sprite.texture))


## After picking the item up (reaching waypoint 1, the SECOND path entry),
## the forager is carrying it to the cache -- ant.png's carry row exists
## exactly for this leg (see IllustratedDecomposerSprite's own doc
## comment), so it should switch to those frames instead of continuing to
## show an empty-handed walk cycle.
func test_switches_to_the_carry_pose_after_reaching_the_pickup_waypoint():
	var f := _spawned_at([Vector2(0, 0), Vector2(20, 0), Vector2(20, 50)])
	for i in 20:  # comfortably more than enough real walking to close 20px
		f._process(0.1)
	assert_eq(f._waypoint_index, 2, "should have advanced onto the cache leg")
	var sprite := f.get_child(0) as Sprite2D
	var carry_frames := IllustratedDecomposerSprite.new().generate_textures("ant", "carry")
	assert_true(carry_frames.has(sprite.texture))


func test_walks_toward_the_first_waypoint():
	var f := _spawned_at([Vector2(0, 0), Vector2(100, 0)])
	f._process(0.1)
	assert_gt(f.position.x, 0.0)
	assert_lt(f.position.x, 100.0)


func test_advances_to_the_next_waypoint_once_the_first_is_reached():
	var f := _spawned_at([Vector2(0, 0), Vector2(20, 0), Vector2(20, 50)])
	for i in 20:  # comfortably more than enough real walking to close 20px
		f._process(0.1)
	assert_eq(f._waypoint_index, 2, "should have advanced past the first waypoint onto the second")


## queue_free()'d nodes stay "valid" until the next frame boundary (the same
## Godot quirk DecomposerMarker._target_still_here's own doc comment already
## documents) -- is_queued_for_deletion() is the real, immediate signal a
## synchronous test loop (no frame boundary ever passes) can actually see.
func test_frees_itself_once_the_final_waypoint_is_reached():
	var f := _spawned_at([Vector2(0, 0), Vector2(5, 0)])
	for i in 20:
		if f.is_queued_for_deletion():
			break
		f._process(0.5)
	assert_true(f.is_queued_for_deletion(), "a forager should free itself once its whole path is walked")


## Same overshoot-forever bug DecomposerMarker._step_approaching hit this
## same session, now avoided from the start rather than re-earned: a single
## big step must not overshoot a short leg and land past it.
func test_does_not_overshoot_a_short_leg():
	var f := _spawned_at([Vector2(0, 0), Vector2(10, 0), Vector2(10, 200)])
	f._process(1.0)  # WALK_SPEED*1.0 = 24px, far more than the 10px first leg
	assert_almost_eq(f.position.x, 10.0, 0.01, "should land exactly on the short waypoint, not overshoot past it")
