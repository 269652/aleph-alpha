extends GutTest

const AnimScript := preload("res://src/rendering/procedural_animal_animation.gd")

var anim


func before_each() -> void:
	anim = AnimScript.new()


func _pixel_diff(a: Image, b: Image) -> int:
	var diff := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				diff += 1
	return diff


func test_actions_constant_lists_all_five() -> void:
	assert_eq(AnimScript.ACTIONS, ["walk", "attack", "eat", "swim", "drink"])


## "walk" is special-cased: a legged species gets a real gait cycle
## (WALK_FRAME_COUNT), not the generic 2-frame shift every other action
## still uses (see QuadrupedGait).
func test_every_action_produces_declared_frame_count() -> void:
	for action in AnimScript.ACTIONS:
		var frames: Array = anim.generate_frames("boar", action, 7)
		var expected: int = AnimScript.WALK_FRAME_COUNT if action == "walk" else AnimScript.FRAME_COUNTS[action]
		assert_eq(frames.size(), expected, "frame count for %s" % action)
		assert_gte(frames.size(), 2, "at least 2 frames for %s" % action)


func test_frames_within_action_differ() -> void:
	for action in AnimScript.ACTIONS:
		var frames: Array = anim.generate_frames("lynx", action, 3)
		for i in range(1, frames.size()):
			assert_gt(_pixel_diff(frames[0], frames[i]), 0,
				"frame %d differs from frame 0 for %s" % [i, action])


func test_deterministic_per_species_action_seed() -> void:
	var a: Array = anim.generate_frames("predator", "walk", 42)
	var b: Array = anim.generate_frames("predator", "walk", 42)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(_pixel_diff(a[i], b[i]), 0, "frame %d identical" % i)


# -- swimming: water tints the body, it doesn't paint a rectangle -----------
#
# The lower band used to be filled with flat WATER_COLOR across the FULL
# tile width -- including every transparent background pixel -- which is
# exactly why it read as a solid blue block sitting on the animal rather
# than water covering part of it (reported: "remove the blue rectangle ...
# make the water realistically cover parts of the body").

## THE regression this exists to catch: background must stay transparent
## below the waterline. A solid band there is the rectangle coming back.
func test_swim_frame_background_stays_transparent_below_the_waterline() -> void:
	var sprite := preload("res://src/rendering/procedural_animal_sprite.gd").new()
	var base := sprite.generate_image("herbivore", 1)
	var frame: Image = anim.generate_frames("herbivore", "swim", 1)[0]
	var water_top := int(float(base.get_height()) * AnimScript.WATER_TOP_FRACTION)
	for y in range(water_top + 1, base.get_height()):
		for x in base.get_width():
			if base.get_pixel(x, y).a <= 0.0:
				assert_eq(
					frame.get_pixel(x, y).a, 0.0,
					"background pixel (%d,%d) must stay transparent, not become part of a water rectangle" % [x, y]
				)


## The body itself must visibly change below the waterline -- tinted and
## faded -- or "swimming" reads as no different from standing.
func test_swim_frame_tints_body_pixels_below_the_waterline() -> void:
	var sprite := preload("res://src/rendering/procedural_animal_sprite.gd").new()
	var base := sprite.generate_image("herbivore", 1)
	var frame: Image = anim.generate_frames("herbivore", "swim", 1)[0]
	var water_top := int(float(base.get_height()) * AnimScript.WATER_TOP_FRACTION)
	var found_tinted_body_pixel := false
	for y in range(water_top + 1, base.get_height()):
		for x in base.get_width():
			var dry := base.get_pixel(x, y)
			if dry.a <= 0.0:
				continue
			var wet: Color = frame.get_pixel(x, y)
			if wet != dry:
				found_tinted_body_pixel = true
	assert_true(found_tinted_body_pixel, "at least one submerged body pixel should be visibly tinted")


## Dry (above-waterline) body pixels must be untouched -- only the submerged
## part of the animal changes. Compared with a small tolerance, not exact
## equality: the frame is built by re-writing pixels read back out of an
## intermediate image (see _shifted), and FORMAT_RGBA8's 8-bit quantization
## isn't perfectly idempotent across that round-trip for every value --
## unrelated to swim tinting, and the same tolerance this codebase already
## uses elsewhere for exactly this reason (see ProceduralTreeSprite's
## _TONE_EPSILON).
const _TONE_EPSILON := 1.0 / 255.0


func test_swim_frame_leaves_the_dry_body_unchanged() -> void:
	var sprite := preload("res://src/rendering/procedural_animal_sprite.gd").new()
	var base := sprite.generate_image("herbivore", 1)
	var frame: Image = anim.generate_frames("herbivore", "swim", 1)[0]  # index 0: no bob shift
	var water_top := int(float(base.get_height()) * AnimScript.WATER_TOP_FRACTION)
	for y in water_top:
		for x in base.get_width():
			var dry := base.get_pixel(x, y)
			var rendered := frame.get_pixel(x, y)
			assert_almost_eq(rendered.r, dry.r, _TONE_EPSILON, "dry pixel (%d,%d)" % [x, y])
			assert_almost_eq(rendered.g, dry.g, _TONE_EPSILON, "dry pixel (%d,%d)" % [x, y])
			assert_almost_eq(rendered.b, dry.b, _TONE_EPSILON, "dry pixel (%d,%d)" % [x, y])
			assert_almost_eq(rendered.a, dry.a, _TONE_EPSILON, "dry pixel (%d,%d)" % [x, y])


func test_unknown_action_falls_back_to_walk() -> void:
	var unknown: Array = anim.generate_frames("boar", "moonwalk", 5)
	var walk: Array = anim.generate_frames("boar", "walk", 5)
	assert_eq(unknown.size(), walk.size())
	for i in walk.size():
		assert_eq(_pixel_diff(unknown[i], walk[i]), 0, "frame %d matches walk" % i)


func test_generate_textures_returns_image_textures() -> void:
	var textures: Array = anim.generate_textures("lynx", "eat", 9)
	assert_eq(textures.size(), AnimScript.FRAME_COUNTS["eat"])
	for t in textures:
		assert_true(t is ImageTexture)


# -- a snake has no legs to shift, so it must move a different way ----------
#
# _walk_frame only shifts pixels in the bottom LEG_TOP_FRACTION band. A
# serpent's whole body sits above that band (see AnimalAnatomy's zero
# leg_length), so the generic leg-cycle shifted nothing at all: a snake's
# "walk" animation was two pixel-identical frames -- completely static
# (reported: "snakes looked way better before the engine was used ... should
# have whole body animated with natural slithering movements").

func test_a_snakes_walk_frames_are_not_pixel_identical() -> void:
	for species in ["venomous_snake", "nonvenomous_snake"]:
		var frames: Array = anim.generate_frames(species, "walk", 11)
		for i in range(1, frames.size()):
			assert_gt(
				_pixel_diff(frames[0], frames[i]), 0,
				"%s frame %d must differ from frame 0 -- the whole body should slither" % [species, i]
			)


## The slither must move the body itself (a lateral wave along its length),
## not just a band near the feet -- a serpent's body sits above
## LEG_TOP_FRACTION entirely (see AnimalAnatomy's zero leg_length), the band
## the old leg-shift exclusively operated on.
func test_a_snakes_slither_moves_pixels_above_the_old_leg_band() -> void:
	var frames: Array = anim.generate_frames("nonvenomous_snake", "walk", 4)
	var base: Image = frames[0]
	var moved: Image = frames[1]
	var leg_top := int(float(base.get_height()) * AnimScript.LEG_TOP_FRACTION)
	var above_leg_band_diff := 0
	for y in leg_top:
		for x in base.get_width():
			if base.get_pixel(x, y) != moved.get_pixel(x, y):
				above_leg_band_diff += 1
	assert_gt(above_leg_band_diff, 0, "the slither should move body pixels the old leg-shift never reached")


## A believable ripple needs more than a two-frame twitch -- pinned so the
## slither doesn't quietly regress back to the generic two-frame cycle.
func test_a_snakes_walk_cycle_has_more_than_two_frames() -> void:
	var frames: Array = anim.generate_frames("venomous_snake", "walk", 2)
	assert_gt(frames.size(), AnimScript.FRAME_COUNTS["walk"])


## Non-serpents must keep the ordinary gait cycle -- the slither is a
## snake-specific fix, not a wholesale animation rewrite.
func test_non_snake_species_are_unaffected_by_the_slither() -> void:
	var frames: Array = anim.generate_frames("boar", "walk", 2)
	assert_eq(frames.size(), AnimScript.WALK_FRAME_COUNT)


# -- legs actually articulate for a walk cycle -------------------------------
#
# The walk cycle used to shift the leg-shaped PIXELS of one static image
# sideways -- there was no joint to move, which is why "a horse should walk
# more like a horse". generate_frames now poses the hip/knee fresh each
# frame (see QuadrupedGait / ProceduralAnimalSprite.generate_image's
# gait_phase). See test_procedural_animal_sprite.gd for the geometry itself;
# these pin the INTEGRATION -- that generate_frames actually drives it.

func test_a_legged_species_walk_cycle_has_more_than_two_frames() -> void:
	var frames: Array = anim.generate_frames("horse", "walk", 5)
	assert_eq(frames.size(), AnimScript.WALK_FRAME_COUNT)
	assert_gt(frames.size(), 2, "a real gait cycle needs more room than a two-frame twitch")


## Every step of the gait must be a genuinely different pose, not just the
## first two frames alternating -- a real stride passes through several
## distinct hip/knee positions, not a two-pose twitch stretched over 6 slots.
func test_every_frame_of_a_walk_cycle_is_a_distinct_pose():
	var frames: Array = anim.generate_frames("horse", "walk", 5)
	for i in frames.size():
		for j in range(i + 1, frames.size()):
			assert_gt(_pixel_diff(frames[i], frames[j]), 0, "frames %d and %d should differ" % [i, j])


# -- standing still: a static neutral pose, not a frozen mid-stride one -----
#
# CreatureMarker used to cycle the "walk" gait purely off elapsed time, so
# legs kept swinging through the stride even while the creature genuinely
# wasn't moving (reported: "their legs are animated even when they stand
# still"). It now asks for this "idle" action instead whenever it isn't
# actually advancing -- a single static pose at gait_phase 0.0, the same
# neutral standing silhouette every other non-walk action's base image
# already uses.

## A single frozen frame read fine back when idle was rare, but it stopped
## being rare (grazing pauses, a boxed-in creature with nowhere to go -- see
## CreatureWander.is_pausing / creature_movement_gate.gd) -- a creature that
## spends real time standing still needs somewhere to go BEYOND a single
## photograph. See test_idle_frames_differ_from_each_other for the visible
## half of that, and idle_frame_index below for how CreatureMarker picks
## between them without a whole herd cycling through in lockstep.
func test_idle_action_returns_more_than_one_frame():
	var frames: Array = anim.generate_frames("horse", "idle", 5)
	assert_eq(frames.size(), AnimScript.IDLE_FRAME_COUNT)
	assert_gt(frames.size(), 1, "a single static frame reads as frozen, not a living idle pose")


func test_idle_frame_matches_the_neutral_standing_pose():
	var sprite := preload("res://src/rendering/procedural_animal_sprite.gd").new()
	var standing := sprite.generate_image("horse", 5)  # gait_phase defaults to 0.0
	var frame: Image = anim.generate_frames("horse", "idle", 5)[0]
	assert_eq(_pixel_diff(standing, frame), 0, "idle should be the same neutral pose, not a mid-stride one")


func test_idle_is_deterministic_per_species_and_seed():
	var a: Array = anim.generate_frames("horse", "idle", 8)
	var b: Array = anim.generate_frames("horse", "idle", 8)
	assert_eq(_pixel_diff(a[0], b[0]), 0)


## The second idle frame has to be a real, visible change -- not a duplicate
## of frame 0 -- or growing IDLE_FRAME_COUNT past 1 is a distinction with no
## visual difference.
func test_idle_frames_differ_from_each_other():
	var frames: Array = anim.generate_frames("herbivore", "idle", 3)
	for i in range(1, frames.size()):
		assert_gt(
			_pixel_diff(frames[0], frames[i]), 0,
			"idle frame %d should differ from frame 0 -- a standing animal still breathes" % i
		)


# -- per-individual idle timing: a herd should not breathe in lockstep ------
#
# Frame selection during idle used to depend on elapsed_time alone (see
# CreatureMarker._animation_step), and every creature's own elapsed_time
# starts at 0.0 and advances by the same per-frame delta absent an LOD
# stagger -- so even once idle grew a second frame, a whole herd that spawned
# together would have cycled through it in perfect unison. idle_frame_index
# folds each creature's own seed into a per-individual phase offset, the same
# deterministic-per-seed hash shape CreatureWander.is_pausing already uses
# for its own seeded roll.

func test_idle_frame_index_is_deterministic_for_the_same_inputs():
	var a: int = anim.idle_frame_index(12.5, 7, 2)
	var b: int = anim.idle_frame_index(12.5, 7, 2)
	assert_eq(a, b)


func test_idle_frame_index_always_stays_in_bounds():
	for seed_value in range(0, 500, 13):
		for elapsed_time in [0.0, 0.3, 1.19, 1.2, 4.75, 100.05]:
			var index: int = anim.idle_frame_index(elapsed_time, seed_value, AnimScript.IDLE_FRAME_COUNT)
			assert_between(
				index, 0, AnimScript.IDLE_FRAME_COUNT - 1, "seed %d at %f" % [seed_value, elapsed_time]
			)


## With only one frame to show (every illustrated species' idle -- see
## IllustratedAnimalSprite, which has no per-seed variation at all) there is
## nothing to cycle through, whatever the seed or the clock says.
func test_idle_frame_index_with_a_single_frame_is_always_zero():
	for seed_value in [0, 1, 5, 999, -3]:
		assert_eq(anim.idle_frame_index(37.0, seed_value, 1), 0)


## The actual minimum bar: across a spread of seeds, idling individuals must
## be ABLE to land on different frames at the exact same elapsed_time -- not
## guaranteed to for any one arbitrary pair (a real hash can coincide), but
## demonstrably possible, which is what would fail if frame selection
## silently dropped seed_value and went back to reading elapsed_time alone.
func test_idle_frame_index_varies_across_seeds_at_the_same_elapsed_time():
	var seen := {}
	for seed_value in range(0, 200):
		seen[anim.idle_frame_index(9.0, seed_value, AnimScript.IDLE_FRAME_COUNT)] = true
	assert_gt(seen.size(), 1, "different individuals should not all breathe in perfect lockstep")


# -- generated frames are shared, not rebuilt per animal ----------------------
#
# Every CreatureMarker generated its own frame set the first time it played an
# action, and nothing cached the result across creatures. Measured live: 25
# creatures crossing into "eat" together burned 1.18 SECONDS of frame
# generation inside one 5-second window (~47ms each), which is exactly the
# 130-145ms frame spikes reported as lag. Every animal in a herd getting
# hungry on the same tick is CreatureNeeds' half of the same bug.

func test_the_same_animal_gets_its_frames_back_instead_of_redrawing_them():
	var animation = AnimScript.new()
	var first = animation.textures_for("herbivore", "walk", 7)
	var second = animation.textures_for("herbivore", "walk", 7)
	assert_same(first, second, "one walk cycle per look, not one per animal")


## The cache is shared across generator INSTANCES too -- each marker holds its
## own ProceduralAnimalAnimation, so a per-instance cache would still redraw
## once per animal.
func test_two_animals_of_one_look_share_the_frames():
	var a = AnimScript.new().textures_for("herbivore", "walk", 3)
	var b = AnimScript.new().textures_for("herbivore", "walk", 3)
	assert_same(a, b)


## Individual variety survives: a species still shows a bounded set of
## distinct looks rather than collapsing to one.
func test_a_species_still_shows_more_than_one_look():
	var animation = AnimScript.new()
	var looks := {}
	for seed_value in 40:
		looks[animation.textures_for("herbivore", "walk", seed_value)] = true
	assert_gt(looks.size(), 1, "a herd is not clones")
	assert_lte(
		looks.size(), AnimScript.LOOK_VARIANTS,
		"and generation stays bounded however many animals live"
	)


func test_different_actions_do_not_share_a_frame_set():
	var animation = AnimScript.new()
	assert_not_same(
		animation.textures_for("herbivore", "walk", 5), animation.textures_for("herbivore", "eat", 5)
	)


func test_cached_frames_still_match_freshly_drawn_ones():
	var animation = AnimScript.new()
	var cached: Array = animation.textures_for("herbivore", "eat", 2)
	var fresh: Array = animation.generate_textures("herbivore", "eat", 2)
	assert_eq(cached.size(), fresh.size())
	for i in cached.size():
		assert_eq(cached[i].get_image().get_data(), fresh[i].get_image().get_data())
