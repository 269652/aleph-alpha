extends GutTest

## Real hand-illustrated bird sprite-sheet animation (assets/sprites/birds/
## sparrow.png, robin.png, blackbird.png, kingfisher.png) -- see
## docs/concept/ecosystem_dynamics.md's "A new aerial tier" and
## IllustratedAnimalSprite, the quadruped analog this mirrors: a hand-
## measured per-action Y-band per species, sliced+normalized by the shared
## SpriteSheetSlicer, replacing ProceduralBirdSprite's primitive-shape
## generation for species with real art. Phase 1 scope only: idle,
## perched (same pose as idle in this art -- see class doc comment),
## flap (takeoff+glide concatenated into one longer wingbeat cycle, the
## same shape AmbientFlyerMarker/FlapGlide already expect from
## generate_flap_textures), and pecking. Walk/court/sing rows exist on the
## sheets but are out of scope until later phases.

const IllustratedBirdSprite = preload("res://src/rendering/illustrated_bird_sprite.gd")

var sprite: IllustratedBirdSprite


func before_each():
	sprite = IllustratedBirdSprite.new()


func test_has_species_recognizes_all_four_real_sheets():
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		assert_true(sprite.has_species(species), "%s should have real illustrated art" % species)


func test_has_species_rejects_a_pollinator():
	# Pollinators keep ProceduralButterflySprite entirely -- this class must
	# never claim to cover them.
	assert_false(sprite.has_species("monarch"))
	assert_false(sprite.has_species("bee"))
	assert_false(sprite.has_species(""))


func test_generate_texture_returns_real_content_for_every_species():
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		var texture := sprite.generate_texture(species, 0)
		assert_not_null(texture, species)
		assert_true(_has_opaque_pixels(texture), "%s idle texture is blank" % species)


func test_perched_is_the_same_pose_as_idle():
	# The sheets draw exactly one "standing still" pose (row 1) -- there is
	# no separate folded-wing perch row the way ProceduralBirdSprite draws
	# one, so perched reuses idle's own band rather than inventing a second
	# one that doesn't exist in the art.
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		var idle := sprite.generate_texture(species, 0)
		var perched := sprite.generate_perched_texture(species, 0)
		assert_eq(idle.get_size(), perched.get_size(), species)


func test_generate_flap_textures_concatenates_takeoff_and_glide():
	# Two 8-frame rows (wings-up takeoff, wings-level glide) become one
	# 16-frame cycle -- FlapGlide.wing_cycles already expects a single
	# array covering a full beat-then-glide cycle from generate_flap_
	# textures, the exact shape ProceduralBirdSprite's own (shorter) cycle
	# already provides.
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		var frames := sprite.generate_flap_textures(species, 0)
		assert_eq(frames.size(), 16, species)
		for frame in frames:
			assert_true(_has_opaque_pixels(frame), species)


func test_generate_pecking_texture_returns_real_content():
	# Every species must get SOMETHING real back -- never null -- even
	# where there is no dedicated peck row to draw it from.
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		var texture := sprite.generate_pecking_texture(species, 0)
		assert_not_null(texture, species)
		assert_true(_has_opaque_pixels(texture), "%s pecking texture is blank" % species)


## Only sparrow's sheet has a dedicated head-down, seed-crumb pecking row --
## confirmed by looking at the actual pixels, not assumed from a shared
## template (see _SHEETS' own doc comment: robin/blackbird's sheets simply
## don't have one, real divider lines bound every row on both with nothing
## left over). Pinned as its own test because losing this distinction --
## e.g. "helpfully" pointing robin/blackbird's peck band at their display
## row because a template says every species has one -- would silently
## show a robin fanning its tail while the game thinks it's eating a worm.
func test_only_sparrow_has_a_dedicated_pecking_row():
	assert_ne(
		sprite.generate_pecking_texture("sparrow", 0),
		sprite.generate_texture("sparrow", 0),
		"sparrow's peck frame must be real peck art, not a fallback to idle"
	)
	for species in ["robin", "blackbird", "kingfisher"]:
		assert_eq(
			sprite.generate_pecking_texture(species, 0),
			sprite.generate_texture(species, 0),
			"%s has no dedicated peck row and must fall back to idle" % species
		)


func test_every_generated_frame_shares_one_canvas_size():
	var reference: Vector2 = sprite.generate_texture("sparrow", 0).get_size()
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		assert_eq(sprite.generate_texture(species, 0).get_size(), reference, species)
		assert_eq(sprite.generate_perched_texture(species, 0).get_size(), reference, species)
		for frame in sprite.generate_flap_textures(species, 0):
			assert_eq(frame.get_size(), reference, species)


func test_frames_are_cached_not_rebuilt_per_call():
	# Same contract as IllustratedAnimalSprite's own _frame_cache: repeat
	# calls for the same key must return the exact same texture instance,
	# not merely an equal one, since AmbientFlyerRenderer asks once per
	# spawned marker and a hedgerow full of sparrows must share pictures.
	var a := sprite.generate_texture("robin", 0)
	var b := sprite.generate_texture("robin", 0)
	assert_same(a, b)


## Reported live: "robins and sparrows are now gigantic". Root cause: the
## renderers apply ONE flat marker.scale tuned for ProceduralBirdSprite's
## tiny 32x20 canvas to whatever texture the chosen generator produced --
## and IllustratedBirdSprite's real-art canvas measures roughly 6-9x wider
## in actual content, so the same flat scale drew a bird 6-9x too big.
## marker_scale is the fix, mirroring IllustratedAnimalSprite.marker_scale
## exactly: a per-species multiplier that normalizes the MEASURED content
## width back down to a real target world width, so the renderer applies
## THIS instead of the flat procedural-tuned scale whenever this generator
## is the one in use.
func test_marker_scale_keeps_every_species_a_normal_creature_size():
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		var content_width := _content_width_px(sprite.generate_texture(species, 0))
		var world_width: float = sprite.marker_scale(species) * content_width
		# A fish is FishRenderer.FISH_WORLD_SCALE-scaled art at roughly this
		# same order of magnitude, and birds are meant to read as roughly
		# fish-sized (see AmbientFlyerRenderer.FLYER_WORLD_SCALE's own doc
		# comment: "a sparrow about one fish"). Comfortably bounds a normal
		# bird while catching the reported bug's ~6-9x-too-big regime by a
		# wide margin.
		assert_between(
			world_width, 1.5, 10.0,
			"%s renders %.1f world px wide -- gigantic (or invisible) again" % [species, world_width]
		)


func test_marker_scale_relative_sizes_roughly_match_intended_proportions():
	# Sparrow is the reference (AmbientFlyerRenderer.FLYER_WORLD_SCALE
	# ["sparrow"] == 1.0); kingfisher and blackbird are both meant to read
	# as bigger birds than a sparrow or a robin (see FLYER_WORLD_SCALE's own
	# table) -- not pinned to the exact ratios (real illustrated art has its
	# own proportions a hand-authored multiplier cannot predict exactly),
	# just the same ordering, so a future art swap can't quietly make a
	# kingfisher read as the smallest bird on screen.
	var widths := {}
	for species in ["sparrow", "robin", "blackbird", "kingfisher"]:
		widths[species] = sprite.marker_scale(species) * _content_width_px(sprite.generate_texture(species, 0))
	assert_gt(widths["robin"], widths["sparrow"] * 0.9)
	assert_gt(widths["kingfisher"], widths["sparrow"] * 0.9)
	assert_gt(widths["blackbird"], widths["sparrow"] * 0.9)


func _content_width_px(texture: Texture2D) -> float:
	var image := texture.get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return float(max_x - min_x + 1)


func _has_opaque_pixels(texture: Texture2D) -> bool:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false
