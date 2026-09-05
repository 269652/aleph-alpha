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


func _has_opaque_pixels(texture: Texture2D) -> bool:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false
