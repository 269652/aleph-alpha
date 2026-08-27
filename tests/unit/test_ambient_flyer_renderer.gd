extends GutTest

## Chunk-based spawn/despawn of ambient wildlife (butterflies, songbirds) --
## same shape as FishRenderer/CreatureRenderer, but decorative/capped only,
## not population-simulated (see docs/concept/ecosystem_dynamics.md's
## Species roster).

const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_ORIGIN := Vector2i(64, 128)

const ProceduralBirdSprite = preload("res://src/rendering/procedural_bird_sprite.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const ProceduralEggSprite = preload("res://src/rendering/procedural_egg_sprite.gd")

var renderer: AmbientFlyerRenderer
var parent: Node2D


func before_each():
	renderer = AmbientFlyerRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_chunk(biome_name: String, size: int = CHUNK_SIZE) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append(biome_name)
	return chunk


func test_spawns_butterflies_and_birds_on_a_large_grassland_chunk():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland", 1.0, null, 2.0, 2.0
	)
	assert_gt(spawned.size(), 0)
	assert_eq(parent.get_child_count(), spawned.size())


## Butterfly/bee spawn count is a guaranteed range (MIN..MAX), not an
## independent per-cell probability roll that could plausibly land on zero
## for some real-world coordinates -- every qualifying chunk gets at least
## the minimum, every time, the same reliability fix already applied to fish
## (see FishRenderer's target_count). Robin/sparrow are population-driven
## instead (see the "birds are promoted from their aggregate population"
## section below) and have no such flat minimum.
func test_every_qualifying_chunk_spawns_at_least_the_minimum_butterflies():
	for coord_x in range(20):
		var chunk := _make_chunk("grassland")
		var origin := Vector2i(coord_x * CHUNK_SIZE, coord_x * 7)
		var spawned := renderer.spawn_ambient_flyers(parent, chunk, origin, TILE_SIZE, "grassland")
		var butterflies := 0
		for flyer in spawned:
			if AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL.has(flyer.species):
				butterflies += 1
		assert_gte(
			butterflies, AmbientFlyerRenderer.MIN_BUTTERFLIES_PER_CHUNK,
			"chunk at x=%d should have at least the minimum butterflies" % coord_x
		)


func test_spawns_nothing_on_desert():
	var chunk := _make_chunk("desert")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "desert")
	assert_eq(spawned.size(), 0)


func test_spawns_nothing_on_tundra():
	var chunk := _make_chunk("tundra")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "tundra")
	assert_eq(spawned.size(), 0)


func test_spawns_nothing_on_ocean():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "ocean")
	assert_eq(spawned.size(), 0)


func test_never_exceeds_the_combined_per_chunk_cap():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland", 1.0, null, 500.0, 500.0
	)
	assert_lte(
		spawned.size(),
		AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK + AmbientFlyerRenderer.MAX_BEES_PER_CHUNK
		+ AmbientFlyerRenderer.MAX_ROBINS_PER_CHUNK + AmbientFlyerRenderer.MAX_SPARROWS_PER_CHUNK
	)


# -- birds are promoted from their aggregate population, not a flat cap ------
#
# robin/sparrow used to fill up to a flat MIN..MAX range with no relation to
# any food source at all -- eating a worm or a seed had zero effect on how
# many birds existed. Promotion now mirrors CreatureRenderer's own
# aggregate-population-to-marker-count shape: one marker per rounded unit of
# THIS species' real aggregate population, capped for perf.

func test_spawns_no_robins_or_sparrows_without_population():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	for flyer in spawned:
		assert_false(flyer.species == "robin" or flyer.species == "sparrow")


func test_spawns_one_robin_per_rounded_unit_of_robin_population():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland", 1.0, null, 2.4, 0.0
	)
	var robins := 0
	for flyer in spawned:
		if flyer.species == "robin":
			robins += 1
	assert_eq(robins, 2)


func test_spawns_one_sparrow_per_rounded_unit_of_sparrow_population():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland", 1.0, null, 0.0, 3.2
	)
	var sparrows := 0
	for flyer in spawned:
		if flyer.species == "sparrow":
			sparrows += 1
	assert_eq(sparrows, 3)


func test_caps_robin_count_for_a_very_large_population():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland", 1.0, null, 500.0, 0.0
	)
	var robins := 0
	for flyer in spawned:
		if flyer.species == "robin":
			robins += 1
	assert_lte(robins, AmbientFlyerRenderer.MAX_ROBINS_PER_CHUNK)
	assert_gt(robins, 0)


func test_caps_sparrow_count_for_a_very_large_population():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland", 1.0, null, 0.0, 500.0
	)
	var sparrows := 0
	for flyer in spawned:
		if flyer.species == "sparrow":
			sparrows += 1
	assert_lte(sparrows, AmbientFlyerRenderer.MAX_SPARROWS_PER_CHUNK)
	assert_gt(sparrows, 0)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("grassland")
	var first := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	var first_positions: Array[Vector2] = []
	for flyer in first:
		first_positions.append(flyer.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_ambient_flyers(other_parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	var second_positions: Array[Vector2] = []
	for flyer in second:
		second_positions.append(flyer.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


## Butterflies render at half size (a real-world scale difference from
## songbirds, and easier to read against tall grass/trees at this pixel
## density than the full 14x10 source art).
## Butterflies render at half a bird's size. Asserted as a RATIO, not as
## absolute scale values: the previous version pinned literal numbers, which
## is exactly what let a stray `marker.scale = ...` overwrite -- applied
## AFTER the real calculation -- sit unnoticed while every per-species size
## was silently discarded.
func test_a_butterfly_renders_at_half_a_sparrows_size():
	var butterfly := AmbientFlyerRenderer.FLYER_WORLD_SCALE["monarch"]
	var sparrow := AmbientFlyerRenderer.FLYER_WORLD_SCALE["sparrow"]
	assert_almost_eq(butterfly / sparrow, 0.5, 0.06)

func test_spawned_flyers_are_ambient_flyer_markers_with_a_texture():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	assert_gt(spawned.size(), 0)
	for flyer in spawned:
		assert_true(flyer is AmbientFlyerMarker)
		assert_not_null(flyer.texture)


# -- sized against a fish ---------------------------------------------------
#
# Flyer sizes are expressed as multiples of a fish, the nearest visible
# reference in the world: "butterflies should be half the size of a fish and
# a sparrow roughly the size of a fish... other birds may be bigger".

const FishRenderer = preload("res://src/rendering/fish_renderer.gd")


func test_a_sparrow_is_about_the_size_of_a_fish():
	assert_almost_eq(AmbientFlyerRenderer.FLYER_WORLD_SCALE["sparrow"], 1.0, 0.05)


func test_butterflies_are_about_half_a_fish():
	for species in ["monarch", "swallowtail", "blue_morpho"]:
		assert_between(AmbientFlyerRenderer.FLYER_WORLD_SCALE[species], 0.45, 0.65, species)


func test_the_kingfisher_is_the_largest_of_the_birds():
	var sparrow: float = AmbientFlyerRenderer.FLYER_WORLD_SCALE["sparrow"]
	assert_gt(AmbientFlyerRenderer.FLYER_WORLD_SCALE["kingfisher"], sparrow)


func test_every_butterfly_is_smaller_than_every_bird():
	for butterfly in ["monarch", "swallowtail", "blue_morpho"]:
		for bird in ["sparrow", "robin", "kingfisher"]:
			assert_lt(
				AmbientFlyerRenderer.FLYER_WORLD_SCALE[butterfly],
				AmbientFlyerRenderer.FLYER_WORLD_SCALE[bird],
				"%s should be smaller than %s" % [butterfly, bird]
			)


## "A robin should only be slightly bigger than a fish" -- the birds here
## are all SMALL birds, so the whole range stays narrow.
## A robin is about one and a half fish -- noticeably bigger than a
## sparrow, well short of the kingfisher.
func test_a_robin_is_about_one_and_a_half_fish():
	assert_between(AmbientFlyerRenderer.FLYER_WORLD_SCALE["robin"], 1.4, 1.6)


## The birds run smallest to largest: sparrow, robin, kingfisher.
func test_the_birds_run_smallest_to_largest():
	var sparrow: float = AmbientFlyerRenderer.FLYER_WORLD_SCALE["sparrow"]
	var robin: float = AmbientFlyerRenderer.FLYER_WORLD_SCALE["robin"]
	var kingfisher: float = AmbientFlyerRenderer.FLYER_WORLD_SCALE["kingfisher"]
	assert_lt(sparrow, robin)
	assert_lt(robin, kingfisher)


# -- offspring are born of their own kind ------------------------------------
#
# spawn_offspring hardcoded the butterfly sprite and butterfly movement for
# every species, on an assumption written into its own comment -- "courtship
# only applies to the pollinators" -- that nothing enforced. Sparrows court
# sparrows, so a sparrow chick came out with monarch wings: it flew like a
# butterfly and looked like one, while the hover panel said "sparrow" and it
# went off to eat seeds.

func test_a_bird_chick_is_a_bird_not_a_butterfly():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var chick := renderer.spawn_offspring(parent, "sparrow", Vector2.ZERO, 7)
	assert_eq(chick.species, "sparrow")
	assert_eq(
		chick.texture.get_image().get_data(),
		ProceduralBirdSprite.new().generate_texture("sparrow", 7).get_image().get_data(),
		"a sparrow must be drawn as a sparrow"
	)


func test_a_butterfly_chick_is_still_a_butterfly():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var chick := renderer.spawn_offspring(parent, "monarch", Vector2.ZERO, 7)
	assert_eq(chick.species, "monarch")
	assert_eq(
		chick.texture.get_image().get_data(),
		ProceduralButterflySprite.new().generate_texture("monarch", 7).get_image().get_data()
	)


## A bird flies like a bird: the movement profile has to match the species
## too, or a sparrow flutters about like a monarch.
func test_a_bird_chick_flies_like_a_bird():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := renderer.spawn_offspring(parent, "sparrow", Vector2.ZERO, 3)
	var butterfly := renderer.spawn_offspring(parent, "monarch", Vector2.ZERO, 3)
	assert_ne(
		bird._movement.speed, butterfly._movement.speed,
		"a sparrow and a monarch should not share a flight profile"
	)


# -- flying things are ABOVE the ground --------------------------------------
#
# Flowers, grass and flyers all sort by Y in one tree, and a flower sprite is
# anchored at its stem FOOT so it can sort against the player like a tree
# does. A butterfly hovering at the blossom is therefore higher on screen --
# a SMALLER y -- than the flower it is visiting, so it sorted behind it and
# vanished into the bloom (reported: "butterflies and bees render behind the
# flowers").
#
# Y-sorting cannot fix this, because the two are answering different
# questions: the flower's sort position is where it is rooted, and the
# butterfly's is where it is flying. A flyer is simply above the ground plane.

func test_a_flyer_draws_above_ground_clutter():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var flyer := renderer.spawn_offspring(parent, "monarch", Vector2.ZERO, 1)
	assert_gt(flyer.z_index, 0, "a flying thing must draw over the flowers it visits")


# -- offspring are built ready for the pre-hatch egg sprite ------------------
#
# AmbientFlyerMarker._animate_wings shows `egg_frame` for the whole
# COURTING/MATED/EGG span (see ProceduralEggSprite) -- every marker this
# renderer builds must actually be handed one, or an offspring born in front
# of the player would still render as the old tiny-scaled-adult the moment it
# spawns, because nothing ever gave it an egg sprite to switch to.

func test_offspring_are_built_with_an_egg_frame():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var chick := renderer.spawn_offspring(parent, "monarch", Vector2.ZERO, 7)
	assert_not_null(chick.egg_frame, "an offspring needs an egg sprite ready for its pre-hatch span")
	assert_eq(
		chick.egg_frame.get_image().get_data(),
		ProceduralEggSprite.new().generate_texture(7).get_image().get_data()
	)


## A regular chunk-spawned adult is never going to be an egg (age_seconds
## starts at LifeCycle.MATURE_SECONDS), but it still gets the same egg_frame
## wiring as an offspring -- one shared build path, not a special case only
## spawn_offspring takes.
func test_chunk_spawned_flyers_are_also_built_with_an_egg_frame():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland"
	)
	assert_gt(spawned.size(), 0, "precondition: something spawned")
	for flyer in spawned:
		assert_not_null(flyer.egg_frame, "%s should have an egg sprite ready" % flyer.species)
