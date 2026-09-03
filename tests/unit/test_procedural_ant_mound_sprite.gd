extends GutTest

## Pixel art for an ant mound (see docs/concept/soil_fauna.md's "What the
## player sees").
##
## `AntColony` has seeded ~10 mounds per chunk since it was written and drawn
## none of them: colonies were quietly moving seed around ground that showed
## nothing at all. This is the sprite half.

const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func _opaque_pixels(image: Image) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				found.append(Vector2i(x, y))
	return found


func test_a_mound_paints_something():
	assert_gt(_opaque_pixels(ProceduralAntMoundSprite.new().generate_image(1234)).size(), 30)


func test_the_same_seed_paints_the_same_mound():
	var first := ProceduralAntMoundSprite.new().generate_image(77)
	var second := ProceduralAntMoundSprite.new().generate_image(77)
	assert_eq(str(_opaque_pixels(first)), str(_opaque_pixels(second)))


## Ten per chunk, so identical mounds would read as a stamped pattern rather
## than as ground.
func test_two_mounds_are_not_identical():
	var first := _opaque_pixels(ProceduralAntMoundSprite.new().generate_image(11))
	var second := _opaque_pixels(ProceduralAntMoundSprite.new().generate_image(12))
	assert_ne(str(first), str(second))


func test_nothing_is_painted_outside_the_canvas():
	for seed_value in 12:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		assert_eq(image.get_width(), ProceduralAntMoundSprite.SIZE.x)
		assert_eq(image.get_height(), ProceduralAntMoundSprite.SIZE.y)


# -- it has to read as excavated soil ----------------------------------------


## Soil, not a plant. Every other thing this project draws on grassland is
## green; a mound reading green would put it in the wrong category at a glance.
func test_a_mound_is_earth_coloured():
	for seed_value in 6:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		for pixel in _opaque_pixels(image):
			var colour := image.get_pixel(pixel.x, pixel.y)
			assert_gte(colour.r, colour.g, "a mound pixel is not earthy")
			assert_gte(colour.g, colour.b, "a mound pixel is not earthy")


## ...and it has to be visible against the grass it sits in. The sward pass
## learned this the hard way in the other direction: something that matches its
## background in value simply is not there.
func test_a_mound_stands_out_against_the_grass():
	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	var image := ProceduralAntMoundSprite.new().generate_image(5)
	var contrast := 0
	for pixel in _opaque_pixels(image):
		if absf(image.get_pixel(pixel.x, pixel.y).get_luminance() - grassland.get_luminance()) > 0.1:
			contrast += 1
	assert_gt(
		float(contrast) / float(_opaque_pixels(image).size()),
		0.5,
		"most of the mound is the same value as the grass around it"
	)


## The entrance is the thing that says "colony" rather than "pile of dirt", so
## there has to be a genuinely dark hole in it.
func test_a_mound_has_a_dark_entrance():
	for seed_value in 6:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		var darkest := 1.0
		var brightest := 0.0
		for pixel in _opaque_pixels(image):
			var luminance := image.get_pixel(pixel.x, pixel.y).get_luminance()
			darkest = minf(darkest, luminance)
			brightest = maxf(brightest, luminance)
		assert_lt(darkest, brightest * 0.6, "no entrance hole -- the mound is one flat tone")


## Real ant mounds throw their spoil out to ONE side rather than in a ring, so
## the silhouette is lopsided. A perfectly symmetric dome reads as a pebble.
func test_the_spoil_is_thrown_to_one_side():
	var lopsided := 0
	for seed_value in 8:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		var pixels := _opaque_pixels(image)
		var sum := Vector2.ZERO
		for pixel in pixels:
			sum += Vector2(pixel)
		var centroid := sum / float(pixels.size())
		if centroid.distance_to(Vector2(ProceduralAntMoundSprite.SIZE) * 0.5) > 0.6:
			lopsided += 1
	assert_gt(lopsided, 4, "mounds are drawn as symmetric domes, not as spoil heaps")


# -- the texture the renderer binds ------------------------------------------


func test_a_texture_is_cached_per_seed():
	var generator := ProceduralAntMoundSprite.new()
	assert_same(generator.generate_texture(42), generator.generate_texture(42))


func test_different_seeds_are_different_textures():
	var generator := ProceduralAntMoundSprite.new()
	assert_not_same(generator.generate_texture(42), generator.generate_texture(43))


# -- the workers on it -------------------------------------------------------


## A worker is a dot, not a sprite with a body: at this zoom an ant is a couple
## of pixels, and anything more detailed reads as a beetle.
func test_a_worker_is_a_small_dark_dot():
	var image := ProceduralAntMoundSprite.new().generate_worker_image()
	var pixels := _opaque_pixels(image)
	assert_gt(pixels.size(), 0, "a worker painted nothing")
	assert_lte(image.get_width(), 8, "a worker is drawn far too large")
	for pixel in pixels:
		assert_lt(
			image.get_pixel(pixel.x, pixel.y).get_luminance(),
			0.3,
			"a worker should be a dark speck"
		)


# -- it has to read as ONE feature sitting in the grass -----------------------


## 8-connected flood fill: how big the largest blob of paint is.
func _largest_component_size(image: Image) -> int:
	var remaining := {}
	for pixel in _opaque_pixels(image):
		remaining[pixel] = true
	var largest := 0
	while not remaining.is_empty():
		var frontier: Array[Vector2i] = [remaining.keys()[0]]
		remaining.erase(frontier[0])
		var size := 0
		while not frontier.is_empty():
			var here: Vector2i = frontier.pop_back()
			size += 1
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var neighbour := here + Vector2i(dx, dy)
					if remaining.has(neighbour):
						remaining.erase(neighbour)
						frontier.append(neighbour)
		largest = maxi(largest, size)
	return largest


## Seen in a real render of mounds on grassland: the first version threw its
## spoil as isolated grains up to 1.7 radii out, and the mounds grew WHISKERS --
## lone dark pixels floating in the green. At this resolution a single dark
## pixel on vivid grass does not read as a grain of soil; it reads as spatter,
## or as a dead pixel.
##
## A mound is one feature: a dome with an apron of diggings joined to it.
func test_a_mound_is_one_connected_feature():
	for seed_value in 10:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		assert_eq(
			_largest_component_size(image),
			_opaque_pixels(image).size(),
			"seed %d draws scattered specks rather than one mound" % seed_value
		)


## The entrance is a hole IN the mound, not a crater that swallows it. Also
## from the render: at its largest the hole took a fifth of the dome and read
## as a black square stamped on a brown oval.
func test_the_entrance_is_a_hole_not_a_crater():
	for seed_value in 10:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		var pixels := _opaque_pixels(image)
		var hole := 0
		for pixel in pixels:
			# Not is_equal_approx: an RGBA8 image quantises to 8 bits per
			# channel, so a painted colour never comes back exactly.
			var colour := image.get_pixel(pixel.x, pixel.y)
			var entrance: Color = ProceduralAntMoundSprite.ENTRANCE_COLOR
			if maxf(
				maxf(absf(colour.r - entrance.r), absf(colour.g - entrance.g)),
				absf(colour.b - entrance.b)
			) < 0.01:
				hole += 1
		assert_gt(hole, 2, "seed %d has no entrance" % seed_value)
		assert_lt(
			float(hole) / float(pixels.size()),
			0.1,
			"seed %d: the entrance swallows the mound" % seed_value
		)


## Lit from above, like everything else in this world. Pinned as a pure
## function rather than by averaging the rendered image, because the spoil
## apron is thrown in a random direction and would pollute any such average.
func test_a_mound_is_lit_from_above():
	var top := ProceduralAntMoundSprite.dome_lighting(-4.0, 6.0)
	var middle := ProceduralAntMoundSprite.dome_lighting(0.0, 6.0)
	var bottom := ProceduralAntMoundSprite.dome_lighting(4.0, 6.0)
	assert_gt(top, middle, "the top of the dome is not the lit side")
	assert_gt(middle, bottom, "the bottom of the dome is not the shaded side")
	assert_gt(
		ProceduralAntMoundSprite.dome_colour(top).get_luminance(),
		ProceduralAntMoundSprite.dome_colour(middle).get_luminance()
	)
	assert_gt(
		ProceduralAntMoundSprite.dome_colour(middle).get_luminance(),
		ProceduralAntMoundSprite.dome_colour(bottom).get_luminance()
	)


## The loose grains that make the dome read as soil rather than as a painted
## blob have to be seeded from the MOUND, not from the canvas. The first
## version sampled them at `int(centre.x) * 31` -- and the centre is the middle
## of a fixed-size canvas, so that is the constant 16 for every mound ever
## drawn: all ten colonies in a chunk wore one identical grain pattern, and
## only their radius and bearing differed.
func test_the_grain_pattern_differs_between_mounds():
	var patterns := {}
	for seed_value in 8:
		var grains := ""
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				grains += "1" if ProceduralAntMoundSprite.is_loose_grain(seed_value, dx, dy) else "0"
		patterns[grains] = true
	assert_gt(patterns.size(), 6, "every mound wears the same grain pattern")


## The apron is darkest where the dome shades it -- against the rim -- and
## lightens to loose crumbs at its edge. Inverted (dark crumbs at the outer
## edge, in the open) the fringe reads as hairs on the mound rather than as
## spilt soil, which is what a real render of the inverted version looked like.
##
## Stochastic per pixel, so pinned as a rate over a grid rather than pixel by
## pixel: what matters is that the shade is CONCENTRATED at the rim.
func test_the_apron_is_shaded_against_the_rim():
	var at_rim := 0
	var at_edge := 0
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			if ProceduralAntMoundSprite.apron_is_shaded(7, dx, dy, 0.1):
				at_rim += 1
			if ProceduralAntMoundSprite.apron_is_shaded(7, dx, dy, 0.9):
				at_edge += 1
	assert_gt(at_rim, at_edge * 2, "the apron is not shaded where the dome shades it")


# -- how it sits in the world ------------------------------------------------


## World size from a world-space constant, never re-derived from the art
## canvas: raising SIZE for detail must not change how big a mound looks. This
## project has hit that trap twice (see ProceduralWormSprite.world_scale).
func test_a_mound_is_about_a_tile_across():
	var painted := float(ProceduralAntMoundSprite.SIZE.x) * ProceduralAntMoundSprite.world_scale()
	assert_between(painted / float(TerrainRenderer.TILE_SIZE), 0.6, 1.4)


## Workers have to come out of the drawn HOLE, not out of the middle of the
## tile -- soil_fauna.md's second honesty rule is that every trip starts and
## ends at the entrance, and a player can see where the entrance is.
##
## Pinned against the painted pixels rather than against the number it is
## computed from, so the offset cannot drift away from the hole it names.
func test_the_entrance_offset_lands_on_the_painted_hole():
	for seed_value in 8:
		var image := ProceduralAntMoundSprite.new().generate_image(seed_value)
		var entrance: Color = ProceduralAntMoundSprite.ENTRANCE_COLOR
		var sum := Vector2.ZERO
		var count := 0
		for y in image.get_height():
			for x in image.get_width():
				var colour := image.get_pixel(x, y)
				if colour.a <= 0.0:
					continue
				if maxf(
					maxf(absf(colour.r - entrance.r), absf(colour.g - entrance.g)),
					absf(colour.b - entrance.b)
				) >= 0.01:
					continue
				sum += Vector2(x, y) + Vector2(0.5, 0.5)
				count += 1
		var painted_centre := sum / float(count)
		var claimed := (
			Vector2(ProceduralAntMoundSprite.SIZE) * 0.5
			+ ProceduralAntMoundSprite.entrance_offset(seed_value)
		)
		assert_almost_eq(painted_centre.x, claimed.x, 1.0, "seed %d: entrance x" % seed_value)
		assert_almost_eq(painted_centre.y, claimed.y, 1.0, "seed %d: entrance y" % seed_value)


## An ant drawn smaller than a world pixel is not a small ant -- it is nothing.
##
## Found in the running game, and only there: the mounds were plainly visible
## on the forest floor and the traffic on them was not, because the worker quad
## was 3 world pixels across a 4-texel canvas -- 0.75 world pixels per texel,
## so a two-texel body came out sub-pixel and dissolved into the ground. The
## art and its tests were both perfectly happy; nothing but a screenshot could
## have caught it.
##
## Pinned against the OPAQUE body rather than the canvas, because most of a
## worker's canvas is deliberately empty.
func test_a_worker_body_is_at_least_two_world_pixels_across():
	var image := ProceduralAntMoundSprite.new().generate_worker_image()
	var pixels := _opaque_pixels(image)
	var left := image.get_width()
	var right := -1
	var top := image.get_height()
	var bottom := -1
	for pixel in pixels:
		left = mini(left, pixel.x)
		right = maxi(right, pixel.x)
		top = mini(top, pixel.y)
		bottom = maxi(bottom, pixel.y)
	var scale := ProceduralAntMoundSprite.worker_world_scale()
	assert_gte(float(right - left + 1) * scale, 2.0, "a worker is sub-pixel wide in the world")
	assert_gte(float(bottom - top + 1) * scale, 2.0, "a worker is sub-pixel tall in the world")


## ...and still far smaller than the mound it lives on, or it reads as a beetle.
func test_a_worker_is_much_smaller_than_its_mound():
	var worker := (
		float(ProceduralAntMoundSprite.WORKER_SIZE.x)
		* ProceduralAntMoundSprite.worker_world_scale()
	)
	var mound := float(ProceduralAntMoundSprite.SIZE.x) * ProceduralAntMoundSprite.world_scale()
	assert_lt(worker, mound * 0.35)
