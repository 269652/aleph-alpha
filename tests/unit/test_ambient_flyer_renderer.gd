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
## A real place, not an arbitrary number. Row 128 of the world's 19980 is
## 88.85 deg N -- 130 km from the north pole -- so every butterfly assertion
## below used to be made on a "grassland" chunk deep inside the arctic. Once
## flyers are range-gated (see AmbientFlyerRenderer.FLYER_RANGE) that stops
## being merely odd and starts being wrong, so these tests now stand on the
## German meadow the reported bug was about.
const CHUNK_ORIGIN := Vector2i(64, GERMANY_ROW)

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
		# Varying x only, so every sampled chunk stays at the SAME latitude --
		# `coord_x * 7` walked rows 0..133 (all within 130 km of the pole),
		# where no butterfly can live.
		var origin := Vector2i(coord_x * CHUNK_SIZE, GERMANY_ROW)
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


## build_bird: places one songbird directly, for callers assembling a scene
## by hand rather than spawning a chunk's worth -- the same shape FishRenderer
## .spawn_fish_at already established for the character preview diorama's own
## pond (reported live, for that exact diorama: "add ... birds").
func test_build_bird_returns_a_marker_with_a_texture_at_the_given_position():
	var position := Vector2(40, 60)
	var bird := renderer.build_bird(parent, "sparrow", position, 5)
	assert_true(bird is AmbientFlyerMarker)
	assert_not_null(bird.texture)
	assert_eq(bird.position, position)
	assert_eq(bird.home, position)
	assert_eq(bird.species, "sparrow")


## The real world's own BIRD_RADIUS (70 world units) comfortably exceeds a
## diorama-scale footprint -- callers with a small scene must be able to
## scale the circling down to fit, the same way FISH_SWIM_SPEED already
## scales fish movement down for the diorama's own tiny pond.
func test_build_bird_defaults_to_the_real_world_radius_but_accepts_an_override():
	var default_bird := renderer.build_bird(parent, "sparrow", Vector2.ZERO, 1)
	assert_eq(default_bird.get("_movement").radius, AmbientFlyerRenderer.BIRD_RADIUS)
	var scaled_bird := renderer.build_bird(parent, "sparrow", Vector2.ZERO, 2, 20.0)
	assert_eq(scaled_bird.get("_movement").radius, 20.0)


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
# -- where a flyer can actually live -----------------------------------------
#
# The aerial tier was the one creature category with no biogeography at all:
# a fixed global species pool, gated only by biome, so a Blue Morpho -- a
# Neotropical rainforest butterfly -- and a Monarch -- a Nearctic one -- both
# flew over a German meadow at 52.5 deg N. Every other category is range-gated
# (see CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME).
#
# The rows below are REAL rows on this project's Earth: the world is
# EarthChunkGenerator.WORLD_HEIGHT_TILES (19980) rows tall and
# GeoCoordinates.latitude_for_tile maps a row to its latitude, so these are
# the same coordinates the biome under the butterfly was generated from.

const GERMANY_ROW := 4162  # 52.50 deg N -- Brandenburg, the reported bug's coordinate
const AMAZON_ROW := 9435  #  4.99 deg N -- the Amazon basin


## Samples many chunks along ONE row of the world, so latitude is held fixed
## while the per-chunk spawn hash varies -- the same "sample many chunks"
## idiom as tests/unit/test_creature_renderer.gd's _species_seen_across_chunks.
##
## `bird_population` feeds BOTH robin_population and sparrow_population --
## unlike butterflies/bees, a bird's COUNT is promotion-from-aggregate-
## population, not a flat min/max roll (see spawn_ambient_flyers' own doc
## comment), so a caller that wants to see robin/sparrow show up at all (as
## opposed to just checking they are properly range-gated OUT somewhere)
## must hand this a real nonzero population. Defaults to 0.0 so every
## existing butterfly/bee-focused caller here is unaffected.
func _species_seen_along_row(
	row: int, biome_name: String, chunk_count: int = 40, bird_population: float = 0.0
) -> Dictionary:
	var seen := {}
	for coord_x in range(chunk_count):
		var chunk := _make_chunk(biome_name)
		var origin := Vector2i(coord_x * CHUNK_SIZE, row)
		for flyer in renderer.spawn_ambient_flyers(
			parent, chunk, origin, TILE_SIZE, biome_name, 1.0, null, bird_population, bird_population
		):
			seen[flyer.species] = true
	return seen


func test_a_german_meadow_has_no_monarchs_and_no_blue_morphos():
	var seen := _species_seen_along_row(GERMANY_ROW, "grassland")
	assert_false(
		seen.has("blue_morpho"),
		"a 52.5N German meadow spawned a blue_morpho -- a Neotropical rainforest butterfly"
	)
	assert_false(
		seen.has("monarch"), "a 52.5N German meadow spawned a monarch -- a Nearctic butterfly"
	)


## The other half of the same fix: gating must not empty the meadow. Papilio
## machaon, the OLD WORLD swallowtail, really is the swallowtail a German
## meadow has, and honeybees and both songbirds belong there too.
func test_a_german_meadow_still_has_its_own_swallowtails_and_bees():
	var seen := _species_seen_along_row(
		GERMANY_ROW, "grassland", 40, float(AmbientFlyerRenderer.MAX_ROBINS_PER_CHUNK)
	)
	assert_true(seen.has("swallowtail"), "a German meadow should still have swallowtails")
	assert_true(seen.has("bee"), "a German meadow should still have bees")
	assert_true(seen.has("sparrow"), "a German meadow should still have sparrows")
	assert_true(seen.has("robin"), "a German meadow should still have robins")


func test_the_amazon_has_blue_morphos_and_no_monarchs():
	var seen := _species_seen_along_row(AMAZON_ROW, "rainforest")
	assert_true(seen.has("blue_morpho"), "the Amazon is where a blue morpho actually lives")
	assert_false(seen.has("monarch"), "the Amazon basin is outside the monarch's breeding range")
	assert_false(
		seen.has("swallowtail"), "Papilio machaon is a Palearctic butterfly, not an Amazonian one"
	)


## A chunk no butterfly can live in must spawn no butterflies -- not divide by
## zero. Rainforest at 52.5N is not a combination the generator produces, but
## it is reachable through this public API, and once the pools are filtered
## per species an empty pool is a real state: `species_pool[seed % size()]`
## on an empty pool is a modulo by zero. Bees and songbirds are unaffected
## here (both range that far north), so this pins the butterfly pool alone.
func test_a_chunk_no_butterfly_species_can_live_in_spawns_none_and_does_not_crash():
	var chunk := _make_chunk("rainforest")
	var spawned := renderer.spawn_ambient_flyers(
		parent, chunk, Vector2i(64, GERMANY_ROW), TILE_SIZE, "rainforest"
	)
	for flyer in spawned:
		assert_false(
			AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL.has(flyer.species),
			"no true butterfly can live in a 52.5N rainforest, but a %s spawned" % flyer.species
		)


const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

## How far outside a band a sample row is taken. Comfortably wider than the
## ~0.14 deg a 32-tile chunk's middle row shifts the measured latitude (see
## AmbientFlyerRenderer._abs_latitude_for), so this test never sits on an edge.
const BAND_MARGIN_DEGREES := 5.0

## Sampling budgets for the band sweep below. Deliberately much smaller than
## _species_seen_along_row's default: the sweep visits ~30 rows and each
## sampled chunk ranks all 1024 of its cells three times, so the default 40
## would turn one test into several minutes. A biome/band pair narrows the
## pool to one or two species and every chunk spawns 2-4 butterflies and 1-3
## birds, so PRESENCE_CHUNKS is ample; ABSENCE is a hard filter rule rather
## than a sampling question, so a handful of chunks is enough to catch it (the
## pre-fix red was hit on the first row sampled).
const BAND_PRESENCE_CHUNKS := 12
const BAND_ABSENCE_CHUNKS := 6


## The northern-hemisphere chunk origin row whose chunk MIDDLE sits at
## `latitude` -- the row AmbientFlyerRenderer._abs_latitude_for measures.
func _row_for_northern_latitude(latitude: float) -> int:
	return (
		GeoCoordinates.new().tile_for_latitude(latitude, EarthChunkGenerator.WORLD_HEIGHT_TILES)
		- CHUNK_SIZE / 2
	)


## The tuned numbers in FLYER_RANGE are pinned as DATA, not as eyeballed
## comments: every species must actually be present inside its own band and
## actually absent outside it, in every biome it claims.
##
## A generous bird population is passed to every call here (harmless for the
## butterfly/bee species this sweep also covers, which ignore it entirely):
## robin/sparrow's COUNT is population-driven, not a flat min/max roll (see
## spawn_ambient_flyers' own doc comment), so a population of 0.0 would fail
## every "present inside its own band" assertion for them regardless of
## whether the real geographic gate is correct.
func test_every_spawned_species_is_inside_its_own_latitude_band():
	var bird_population := float(AmbientFlyerRenderer.MAX_ROBINS_PER_CHUNK)
	for species in AmbientFlyerRenderer.FLYER_RANGE:
		var species_range: Dictionary = AmbientFlyerRenderer.FLYER_RANGE[species]
		var band: Vector2 = species_range["abs_latitude"]
		for biome_name in species_range["biomes"]:
			var inside := _species_seen_along_row(
				_row_for_northern_latitude((band.x + band.y) * 0.5), biome_name, BAND_PRESENCE_CHUNKS,
				bird_population
			)
			assert_true(
				inside.has(species),
				"%s should be present in %s inside its own band" % [species, biome_name]
			)
			if band.x - BAND_MARGIN_DEGREES > 0.0:
				var too_far_south := _species_seen_along_row(
					_row_for_northern_latitude(band.x - BAND_MARGIN_DEGREES), biome_name,
					BAND_ABSENCE_CHUNKS, bird_population
				)
				assert_false(
					too_far_south.has(species),
					"%s spawned in %s below its own range" % [species, biome_name]
				)
			if band.y + BAND_MARGIN_DEGREES < 90.0:
				var too_far_north := _species_seen_along_row(
					_row_for_northern_latitude(band.y + BAND_MARGIN_DEGREES), biome_name,
					BAND_ABSENCE_CHUNKS, bird_population
				)
				assert_false(
					too_far_north.has(species),
					"%s spawned in %s above its own range" % [species, biome_name]
				)


## The anti-drift pin that lets the tier-wide biome gates and the per-species
## table coexist: whatever biomes the species table claims, collectively, must
## be exactly the biomes the tier-wide gate opens. Otherwise a biome could
## qualify for butterflies while no butterfly species can live there (a chunk
## that spawns nothing for no visible reason), or a species could claim a
## biome the tier-wide gate never opens (a dead table row).
# -- built flyers reuse cached textures, not fresh ones per marker ----------
#
# _build_marker used to call ProceduralButterflySprite/ProceduralBirdSprite's
# generate_texture/generate_flap_textures/generate_perched_texture directly,
# and none of those three cached anything -- every spawned butterfly/bee/bird
# paid real generation cost AND was permanently unbatchable with every other
# flyer of the same species/state under Godot's gl_compatibility renderer
# (see scenes/world.tscn's y_sort_enabled Entities/Creatures tiers). The fix
# lives in the sprite generators themselves (mirroring
# ProceduralTreeSprite._tree_texture_cache / ProceduralFishSprite.LOOK_VARIANTS
# / ProceduralAnimalAnimation.textures_for), so these confirm the caching is
# actually visible through the renderer's own public building calls.

func test_two_birds_of_the_same_species_and_seed_share_one_texture_instance():
	var first := renderer.build_bird(parent, "sparrow", Vector2.ZERO, 4)
	var second := renderer.build_bird(parent, "sparrow", Vector2(10, 10), 4)
	assert_same(first.texture, second.texture, "same species+seed should reuse the cached texture")


func test_two_birds_of_the_same_species_and_seed_share_flap_frames():
	var first := renderer.build_bird(parent, "sparrow", Vector2.ZERO, 4)
	var second := renderer.build_bird(parent, "sparrow", Vector2(10, 10), 4)
	assert_same(
		first.flap_frames, second.flap_frames,
		"same species+seed should reuse the cached flap-frame sequence"
	)


func test_two_birds_of_the_same_species_and_seed_share_one_perched_texture():
	var first := renderer.build_bird(parent, "sparrow", Vector2.ZERO, 4)
	var second := renderer.build_bird(parent, "sparrow", Vector2(10, 10), 4)
	assert_not_null(first.perched_frame)
	assert_same(
		first.perched_frame, second.perched_frame,
		"same species+seed should reuse the cached perched texture"
	)


func test_two_butterflies_of_the_same_species_and_seed_share_texture_and_flap_frames():
	var first := renderer.spawn_offspring(parent, "monarch", Vector2.ZERO, 4)
	var second := renderer.spawn_offspring(parent, "monarch", Vector2(5, 5), 4)
	assert_same(first.texture, second.texture)
	assert_same(first.flap_frames, second.flap_frames)


func test_flyer_range_biomes_agree_with_the_tier_wide_biome_gates():
	var pollinator_biomes := {}
	for species in AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL + AmbientFlyerRenderer.BEE_SPECIES_POOL:
		for biome_name in AmbientFlyerRenderer.FLYER_RANGE[species]["biomes"]:
			pollinator_biomes[biome_name] = true
	assert_eq(
		pollinator_biomes.keys(), AmbientFlyerRenderer.BUTTERFLY_BIOMES.keys(),
		"the butterfly/bee range table and BUTTERFLY_BIOMES have drifted apart"
	)
	var bird_biomes := {}
	for species in AmbientFlyerRenderer.BIRD_SPECIES_POOL:
		for biome_name in AmbientFlyerRenderer.FLYER_RANGE[species]["biomes"]:
			bird_biomes[biome_name] = true
	assert_eq(
		bird_biomes.keys(), AmbientFlyerRenderer.BIRD_BIOMES.keys(),
		"the bird range table and BIRD_BIOMES have drifted apart"
	)


# -- butterflies club up; nothing else does ----------------------------------
#
# FlyerSpawnLayout can be measured on its own all day and still not be
# CALLED, which is this codebase's dominant defect class. These two pin the
# wiring: the live renderer's own output, compared against the layout module's
# own answer.

const FlyerSpawnLayout = preload("res://src/rendering/flyer_spawn_layout.gd")
const Courtship = preload("res://src/gameplay/courtship.gd")


func _spawn_grassland_at(origin: Vector2i) -> Array[Node2D]:
	return renderer.spawn_ambient_flyers(
		parent, _make_chunk("grassland"), origin, TILE_SIZE, "grassland"
	)


func test_a_chunks_butterflies_spawn_as_one_club_the_layout_module_placed():
	for x in 5:
		var origin := Vector2i(x * CHUNK_SIZE, GERMANY_ROW)
		var butterflies: Array = []
		for flyer in _spawn_grassland_at(origin):
			if AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL.has(flyer.species):
				butterflies.append(flyer.position)
		assert_gt(butterflies.size(), 1, "precondition: this chunk has a meadow's worth")

		var wanted := FlyerSpawnLayout.wanted_count(
			origin, "butterfly_spawn",
			AmbientFlyerRenderer.MIN_BUTTERFLIES_PER_CHUNK,
			AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK,
			CHUNK_SIZE * CHUNK_SIZE
		)
		assert_eq(
			butterflies,
			Array(FlyerSpawnLayout.aggregated_positions(
				origin, CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "butterfly_spawn", wanted
			)),
			"the live renderer must place butterflies where the layout module says"
		)
		# ...and the point of that: they can actually find each other.
		for a in butterflies:
			for b in butterflies:
				assert_lte(a.distance_to(b), Courtship.NOTICE_RADIUS_PX + 0.001)


## A club that all whirled on the same frame and then all fell silent
## together would read as choreography (see SpiralFlight.stagger_seconds).
## The renderer is what knows a flyer is one of a chunk's freshly-loaded many;
## a marker built by hand in a test is not staggered at all.
func test_a_freshly_spawned_club_is_staggered_not_synchronised():
	var cooldowns := {}
	var butterflies := 0
	for x in 10:
		for flyer in _spawn_grassland_at(Vector2i(x * CHUNK_SIZE, GERMANY_ROW)):
			if not AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL.has(flyer.species):
				continue
			butterflies += 1
			assert_lt(flyer._spiral_cooldown, SpiralFlight.COOLDOWN_SECONDS)
			assert_gte(flyer._spiral_cooldown, 0.0)
			cooldowns[snappedf(flyer._spiral_cooldown, 0.5)] = true
	assert_gt(butterflies, 10, "precondition: ten German chunks hold a few dozen butterflies")
	assert_gt(cooldowns.size(), 5, "a meadow must not be choreographed")


const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")


## Bees deliberately do NOT club up: a honeybee commutes from a hive and works
## the whole meadow, and turning the buzz into one knot would be wrong about
## the animal as well as making the meadow look staged.
func test_bees_are_still_scattered_across_the_whole_meadow():
	var origin := Vector2i(3 * CHUNK_SIZE, GERMANY_ROW)
	var bees: Array = []
	for flyer in _spawn_grassland_at(origin):
		if flyer.species == "bee":
			bees.append(flyer.position)
	assert_gt(bees.size(), 0, "precondition: a German meadow has bees")

	var wanted := FlyerSpawnLayout.wanted_count(
		origin, "bee_spawn",
		AmbientFlyerRenderer.MIN_BEES_PER_CHUNK,
		AmbientFlyerRenderer.MAX_BEES_PER_CHUNK,
		CHUNK_SIZE * CHUNK_SIZE
	)
	var expected: Array = []
	for cell in FlyerSpawnLayout.scattered_cells(
		origin, CHUNK_SIZE, CHUNK_SIZE, "bee_spawn", wanted
	):
		expected.append(Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE))
	assert_eq(bees, expected, "bees must still use the scatter, not the club")
