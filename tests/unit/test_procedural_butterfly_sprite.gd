extends GutTest

## Small ambient-flyer pixel art (see docs/concept/ecosystem_dynamics.md's
## Species roster). Same "one shared shape, colorful per-species variants"
## approach as ProceduralFishSprite.

const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")

var generator := ProceduralButterflySprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("monarch", 0)
	assert_eq(image.get_width(), ProceduralButterflySprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralButterflySprite.SIZE.y)


func test_has_transparent_corners_and_an_opaque_body():
	var image := generator.generate_image("monarch", 0)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := Vector2i(ProceduralButterflySprite.SIZE.x / 2, ProceduralButterflySprite.SIZE.y / 2)
	assert_gt(image.get_pixel(mid.x, mid.y).a, 0.0)


func test_is_deterministic_for_the_same_species_and_seed():
	var a := generator.generate_image("swallowtail", 5)
	var b := generator.generate_image("swallowtail", 5)
	assert_eq(a.get_data(), b.get_data())


## Colorful and multiple varieties, same "the point" as fish.
func test_every_known_species_has_a_distinct_base_color():
	var seen_colors := {}
	for species in ProceduralButterflySprite.SPECIES_IDS:
		seen_colors[ProceduralButterflySprite.SPECIES_BASE_COLORS[species]] = true
	assert_eq(
		seen_colors.size(), ProceduralButterflySprite.SPECIES_IDS.size(),
		"every species should have a unique base color"
	)


func test_species_colors_are_vividly_saturated_not_muddy():
	# Butterflies really are this vivid in life -- unlike songbirds (see
	# procedural_bird_sprite.gd), vividness is real-world-grounded here, not
	# just decorative.
	#
	# The FLY is the deliberate exception, and is checked from the other side
	# by test_a_fly_is_darker_than_any_butterfly: it shares this painter so it
	# flaps and banks like the rest, but it must read instantly as
	# not-a-butterfly. Grounded the same way -- a housefly really is drab.
	for species in ProceduralButterflySprite.SPECIES_IDS:
		if species == "fly":
			continue
		var color: Color = ProceduralButterflySprite.SPECIES_BASE_COLORS[species]
		assert_gt(color.s, 0.4, "%s should read as a colorful, vivid butterfly" % species)


func test_different_species_render_different_images():
	var a := generator.generate_image("monarch", 0)
	var b := generator.generate_image("swallowtail", 0)
	assert_ne(a.get_data(), b.get_data())


func test_unknown_species_falls_back_to_a_valid_image_rather_than_crashing():
	var image := generator.generate_image("not_a_real_butterfly", 0)
	assert_eq(image.get_width(), ProceduralButterflySprite.SIZE.x)


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("blue_morpho", 3)
	assert_eq(texture.get_width(), ProceduralButterflySprite.SIZE.x)


# -- flies -------------------------------------------------------------------

## A fly is drawn from the same painter as the bees and butterflies, so it
## flaps, banks and animates like the rest of the ambient flyers rather than
## being a speck bolted on beside them.
func test_a_fly_has_its_own_art():
	assert_true(ProceduralButterflySprite.SPECIES_IDS.has("fly"))
	var image := generator.generate_image("fly", 3)
	assert_gt(image.get_width(), 0)


## Dark and drab: a fly should read instantly as not-a-butterfly, because the
## player needs to tell "this windfall has gone over" from "this meadow has
## pollinators" at a glance.
func test_a_fly_is_darker_than_any_butterfly():
	var fly: Color = ProceduralButterflySprite.SPECIES_BASE_COLORS["fly"]
	for species in ["monarch", "swallowtail", "blue_morpho", "bee"]:
		var other: Color = ProceduralButterflySprite.SPECIES_BASE_COLORS[species]
		assert_lt(fly.v, other.v, "a fly should be darker than a %s" % species)


## And smaller than a bee, which is the smallest thing already flying.
func test_a_fly_is_smaller_than_a_bee():
	var AmbientFlyerRenderer := load("res://src/rendering/ambient_flyer_renderer.gd")
	assert_lt(
		float(AmbientFlyerRenderer.FLYER_WORLD_SCALE["fly"]),
		float(AmbientFlyerRenderer.FLYER_WORLD_SCALE["bee"])
	)


# -- generated textures are shared, not rebuilt per butterfly ----------------
#
# generate_texture/generate_flap_textures each built a brand-new Texture2D
# (or, for flaps, a brand-new array of them) on every call, so every spawned
# butterfly/bee paid its own image-generation cost AND ended up permanently
# unbatchable with every other flyer, even of the same species, because each
# got its own unique Texture2D object -- same bug
# ProceduralFishSprite.generate_texture was fixed for fish (see its own
# "generated textures are shared" tests).

func test_the_same_species_and_seed_share_one_cached_texture():
	var a := generator.generate_texture("monarch", 3)
	var b := generator.generate_texture("monarch", 3)
	assert_same(a, b, "same species+seed butterfly should share one cached texture")


## The cache is shared across generator INSTANCES too -- AmbientFlyerRenderer
## holds its own ProceduralButterflySprite, so a per-instance cache would
## still redraw once per butterfly.
func test_two_generators_of_one_look_share_the_texture():
	var a := ProceduralButterflySprite.new().generate_texture("swallowtail", 9)
	var b := ProceduralButterflySprite.new().generate_texture("swallowtail", 9)
	assert_same(a, b)


## Individual variety survives bucketing: a species still shows more than one
## look across many seeds, but the distinct-texture count stays bounded by
## LOOK_VARIANTS rather than growing one-per-butterfly.
func test_generate_texture_still_shows_more_than_one_look_but_stays_bounded():
	var seen := {}
	for seed_value in ProceduralButterflySprite.LOOK_VARIANTS * 5:
		seen[generator.generate_texture("blue_morpho", seed_value)] = true
	assert_gt(seen.size(), 1, "individuals of one species should still show more than one look")
	assert_lte(seen.size(), ProceduralButterflySprite.LOOK_VARIANTS)


func test_the_same_species_and_seed_share_one_cached_flap_sequence():
	var a := generator.generate_flap_textures("monarch", 3)
	var b := generator.generate_flap_textures("monarch", 3)
	assert_same(a, b, "same species+seed butterfly should share one cached flap-frame array")
	for i in a.size():
		assert_same(a[i], b[i], "flap frame %d should be the same cached texture instance" % i)


func test_flap_texture_cache_is_shared_across_generator_instances():
	var a := ProceduralButterflySprite.new().generate_flap_textures("bee", 9)
	var b := ProceduralButterflySprite.new().generate_flap_textures("bee", 9)
	assert_same(a, b)



# -- the NECTARING pose: wings shut over the back ---------------------------
#
# `perched_frame` is generated by ProceduralBirdSprite alone -- it is the only
# generate_perched_texture in src/rendering -- so a butterfly had no settled
# frame at all and AmbientFlyerMarker._animate_wings fell straight through to
# flap_frames while it was standing on a bloom drinking. A butterfly beating
# its wings, motionless, on one pixel, for PollinatorForaging.DRINK_SECONDS is
# exactly the reported "butterflies get stuck in front of a flower".
#
# Real butterflies perch to feed (hovering while nectaring is a hawkmoth
# trait) and hold the wings CLOSED OVER THE BACK, opening them only
# occasionally to bask. Seen from above that collapses the wings to their
# edge: what is left is little more than the body.

## The species that ever actually show this pose -- the only ones the marker
## can put into a drink at all (see FlyerDiet.DIET_BY_SPECIES). A fly is
## generated for completeness but never nectars.
const NECTAR_FEEDERS := ["monarch", "swallowtail", "blue_morpho", "bee"]


## How much insect there is to see: opaque pixels.
##
## AREA rather than silhouette width, because the widest thing on a butterfly
## at this canvas size is its ANTENNAE -- which a feeding butterfly holds out
## exactly as a flying one does, so overall width barely moves between the
## poses and measures the wrong thing. Area is what "the wings are folded
## away" actually means.
func _drawn_pixels(image: Image) -> int:
	var count := 0
	for x in image.get_width():
		for y in image.get_height():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _smallest_flap_area(species: String) -> int:
	var smallest := 1 << 30
	for frame in generator.generate_flap_images(species, 0):
		smallest = mini(smallest, _drawn_pixels(frame))
	return smallest


func test_settled_images_have_the_expected_size():
	for frame in generator.generate_settled_images("monarch", 0):
		assert_eq(frame.get_width(), ProceduralButterflySprite.SIZE.x)
		assert_eq(frame.get_height(), ProceduralButterflySprite.SIZE.y)


func test_there_is_a_real_settled_sequence_not_a_single_frozen_pose():
	var frames := generator.generate_settled_images("monarch", 0)
	assert_gt(frames.size(), 1, "a basking butterfly opens and shuts -- that needs frames")
	assert_eq(frames.size(), ProceduralButterflySprite.SETTLED_FRAME_COUNT)


## THE point of the pose. Frame 0 is the wings-shut one, and it must show less
## wing than anything the FLIGHT stroke ever passes through -- a butterfly
## that feeds in a pose it also flies in has not visibly landed.
##
## Asserted on the BUTTERFLIES. The bee is checked separately below: its drawn
## wing is about three pixels across, so once the legibility floor has claimed
## its one pixel there is simply no pixel left to spend on the distinction,
## and the rasterised areas tie. The invariant that still holds for it -- and
## for every nectar feeder -- is the one on the spread itself, in
## test_the_shut_spread_stays_tighter_than_the_tightest_flight_frame.
func test_the_shut_pose_shows_less_wing_than_any_flight_frame():
	for species in ["monarch", "swallowtail", "blue_morpho"]:
		var shut := _drawn_pixels(generator.generate_settled_images(species, 0)[0])
		var tightest_flap := _smallest_flap_area(species)
		assert_lt(
			shut, tightest_flap,
			"%s: wings shut over the back (%d px) must show less than the tightest"
				% [species, shut]
				+ " point of the flight stroke (%d px)" % [tightest_flap]
		)


func test_no_nectar_feeder_splays_its_wings_wider_to_feed_than_it_flies():
	for species in NECTAR_FEEDERS:
		assert_lte(
			_drawn_pixels(generator.generate_settled_images(species, 0)[0]),
			_smallest_flap_area(species),
			"%s must never show MORE wing settled than mid-beat" % species
		)


## ...and it must still BE something. The real ratio (a monarch spans about
## 100 mm open and about 6 mm across the shut wings and thorax) is sub-pixel
## on this canvas, and a butterfly that VANISHES when it lands would be a
## worse picture than the hovering one being fixed. Pinned against the wing
## half-extent floor that exists for exactly this reason.
func test_the_shut_pose_is_still_a_visible_insect_with_wings_on_it():
	for species in NECTAR_FEEDERS:
		var openness := generator.settled_closed_openness(species)
		assert_gte(
			openness * float(ProceduralButterflySprite.SIZE.x)
				* float(ProceduralButterflySprite.SPECIES_WINGS[species].forewing.x),
			ProceduralButterflySprite.MIN_VISIBLE_WING_HALF_PX - 0.0001,
			"%s's shut wing must still be wide enough to rasterise" % species
		)
		assert_gt(
			_drawn_pixels(generator.generate_settled_images(species, 0)[0]), 0,
			"%s must still read as an insect standing on the flower" % species
		)


## The shut pose is the real 6/100 ratio wherever there are pixels for it, and
## the legibility floor only where there are not. For a monarch the floor is
## what binds -- worth pinning, so nobody later "simplifies" the floor away
## and makes the butterfly disappear on landing.
func test_the_shut_spread_is_the_real_ratio_floored_at_one_visible_pixel():
	var plan: Dictionary = ProceduralButterflySprite.SPECIES_WINGS["monarch"]
	var spread_px: float = float(plan.forewing.x) * float(ProceduralButterflySprite.SIZE.x)
	assert_lt(
		ProceduralButterflySprite.SETTLED_CLOSED_SPREAD * spread_px,
		ProceduralButterflySprite.MIN_VISIBLE_WING_HALF_PX,
		"precondition: a real monarch's shut wing IS sub-pixel on this canvas"
	)
	assert_almost_eq(
		generator.settled_closed_openness("monarch"),
		ProceduralButterflySprite.MIN_VISIBLE_WING_HALF_PX / spread_px,
		0.0001,
		"so the floor is what it lands on"
	)


## Whatever the floor does, the shut pose must still be tighter than the
## tightest point of the flight stroke -- otherwise "settled" and "mid-beat"
## are the same picture.
func test_the_shut_spread_stays_tighter_than_the_tightest_flight_frame():
	for species in NECTAR_FEEDERS:
		assert_lt(
			generator.settled_closed_openness(species),
			ProceduralButterflySprite._WING_CLOSE,
			"%s must fold tighter to feed than it ever does in flight" % species
		)


## The other end of the swing is a full basking spread -- a basking butterfly
## opens all the way, so the widest settled frame matches the widest flight
## frame rather than being some third, narrower thing.
func test_the_open_pose_is_a_full_basking_spread():
	var frames := generator.generate_settled_images("monarch", 0)
	var widest_flap := 0
	for frame in generator.generate_flap_images("monarch", 0):
		widest_flap = maxi(widest_flap, _drawn_pixels(frame))
	assert_eq(
		_drawn_pixels(frames[frames.size() - 1]), widest_flap,
		"a basking butterfly opens all the way"
	)


func test_the_settled_sequence_opens_monotonically():
	var previous := -1
	for frame in generator.generate_settled_images("blue_morpho", 0):
		var area := _drawn_pixels(frame)
		assert_gte(area, previous, "the wings only ever open across the sequence")
		previous = area


func test_settled_images_are_deterministic_for_the_same_species_and_seed():
	var a := generator.generate_settled_images("swallowtail", 5)
	var b := generator.generate_settled_images("swallowtail", 5)
	for i in a.size():
		assert_eq(a[i].get_data(), b[i].get_data(), "settled frame %d must be reproducible" % i)


func test_the_same_species_and_seed_share_one_cached_settled_sequence():
	var a := generator.generate_settled_textures("monarch", 3)
	var b := generator.generate_settled_textures("monarch", 3)
	assert_same(a, b, "same species+seed should share one cached settled-frame array")
	for i in a.size():
		assert_same(a[i], b[i], "settled frame %d should be the same cached texture instance" % i)


func test_settled_texture_cache_is_shared_across_generator_instances():
	var a := ProceduralButterflySprite.new().generate_settled_textures("bee", 9)
	var b := ProceduralButterflySprite.new().generate_settled_textures("bee", 9)
	assert_same(a, b, "the settled cache is static, like the flap one")


func test_an_unknown_species_still_gets_a_settled_pose():
	var frames := generator.generate_settled_images("not_a_real_butterfly", 0)
	assert_eq(frames.size(), ProceduralButterflySprite.SETTLED_FRAME_COUNT)
	assert_gt(_drawn_pixels(frames[0]), 0)
