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
