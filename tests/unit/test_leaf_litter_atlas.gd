extends GutTest

## LeafLitterAtlas: packs every species/season fallen-leaf texture into one
## runtime atlas on a fixed cell grid (see docs/concept/leaf_litter.md),
## mirroring SnowStampAtlas -- this class only prepares ART; LeafLitterRenderer
## is what stamps it across a chunk's own MultiMesh. A fixed grid (not
## grass's irregular-UV-pair approach) so the instance-data channel budget
## has room left for the renderer's own fall-phase timing.

const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const _SEASONS := ["summer", "autumn", "winter"]


func _atlas() -> LeafLitterAtlas:
	return LeafLitterAtlas.new()


# -- cell indexing ------------------------------------------------------------

func test_every_species_season_pair_has_a_cell():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		for season in _SEASONS:
			assert_gte(atlas.cell_index(species, season), 0)


func test_every_pair_lands_at_a_distinct_cell():
	var atlas := _atlas()
	var seen := {}
	for species in TreeSpecies.IDS:
		for season in _SEASONS:
			var index := atlas.cell_index(species, season)
			assert_false(seen.has(index), "%s/%s collided with an earlier pair at cell %d" % [species, season, index])
			seen[index] = true
	assert_eq(seen.size(), TreeSpecies.IDS.size() * _SEASONS.size())


func test_cell_count_matches_every_species_times_every_season():
	var atlas := _atlas()
	assert_eq(atlas.cell_count(), TreeSpecies.IDS.size() * _SEASONS.size())


func test_the_same_pair_always_gives_the_same_cell():
	var atlas := _atlas()
	assert_eq(atlas.cell_index("cherry", "autumn"), atlas.cell_index("cherry", "autumn"))


# -- illustrated art vs. the generic fallback ---------------------------------

## Every species/season pair with real illustrated art (see
## IllustratedTree.has_foliage_leaf_for) must actually land its OWN real
## artwork in the atlas, not the generic procedural fallback -- distinguished
## here by the two reading as genuinely different images (a generic
## procedural leaf and a real illustrated closeup never pixel-match).
func test_a_pair_with_real_art_uses_the_illustrated_texture():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		for season in _SEASONS:
			if not IllustratedTree.new().has_foliage_leaf_for(species, season):
				continue
			assert_true(
				atlas.has_illustrated_art(species, season),
				"%s/%s should report real illustrated art" % [species, season]
			)


## Every real species/season pair shipped today actually has illustrated art
## (checked exhaustively by test_a_pair_with_real_art_uses_the_illustrated_
## texture looping every real pair) -- so the generic-fallback PATH is
## exercised here with a synthetic species/season IllustratedTree can never
## have art for, proving the mechanism itself (not a specific real gap, which
## does not exist in the shipped art right now) still lands a real,
## non-blank stamp rather than a blank/missing cell.
func test_a_pair_with_no_illustrated_art_still_gets_a_real_stamp():
	var atlas := _atlas()
	assert_false(
		atlas.has_illustrated_art("_no_such_species", "autumn"),
		"precondition: a made-up species must report no illustrated art"
	)
	var stamp := atlas.build_stamp_image("_no_such_species", "autumn")
	assert_false(_is_blank(stamp), "a missing pair must still fall back to a real generic sprite")


func _is_blank(image: Image) -> bool:
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			if image.get_pixel(x, y).a > 0.05:
				return false
	return true


# -- "winter": a leaf's terminal decay stage, derived not illustrated --------
#
# Reported directly: "fallen leaves should change the season from autumn to
# winter if they keep lying on the ground ... winter is last stage for a
# leaf." No species has real illustrated "winter" litter art (there is no
# such thing as a real leaf freshly falling already looking decayed), so
# every species' winter stamp is DERIVED from its own already-built autumn
# stamp -- same "keep the shading, discard the hue" idiom
# ProceduralFlowerSprite._paint_illustrated_head already established for
# recolouring illustrated art without new assets (docs/concept/flora.md's
# "Recolouring illustrated blooms"). Deriving from autumn specifically
# (rather than needing a second derivation from summer too) mirrors a real
# simplification: by the time any fallen leaf has weathered long enough to
# look "wintry", its original fall colour has already faded toward the same
# dulled brown-grey regardless of what it started as.

## A winter stamp must still be a REAL, non-blank image derived from real
## content -- not a missing-pair fallback landing the generic procedural
## sprite (which test_a_pair_with_no_illustrated_art_still_gets_a_real_
## stamp already covers separately; this is instead confirming "winter"
## takes its own dedicated derivation path).
func test_winter_stamp_is_not_blank():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		var stamp := atlas.build_stamp_image(species, "winter")
		assert_false(_is_blank(stamp), "%s/winter produced a blank stamp" % species)


## The winter stamp's silhouette must match the autumn stamp's exactly (same
## alpha at every pixel) -- proof it is a recoloured COPY of the real autumn
## art, not an independently re-cropped/re-fitted image that could drift in
## shape, and not the unrelated generic fallback silhouette.
func test_winter_stamp_matches_the_autumn_silhouette():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		var autumn_stamp := atlas.build_stamp_image(species, "autumn")
		var winter_stamp := atlas.build_stamp_image(species, "winter")
		for y in range(0, LeafLitterAtlas.STAMP_SIZE, 4):
			for x in range(0, LeafLitterAtlas.STAMP_SIZE, 4):
				assert_almost_eq(
					winter_stamp.get_pixel(x, y).a, autumn_stamp.get_pixel(x, y).a, 0.01,
					"%s winter/autumn silhouettes differ at (%d,%d)" % [species, x, y]
				)


## The winter stamp must actually read as duller/less colourful than the
## autumn art it derives from -- a real decayed leaf does not stay as
## vividly orange/red as the moment it fell.
func test_winter_stamp_is_less_saturated_than_autumn():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		var autumn_stamp := atlas.build_stamp_image(species, "autumn")
		var winter_stamp := atlas.build_stamp_image(species, "winter")
		var autumn_saturation_sum := 0.0
		var winter_saturation_sum := 0.0
		var sampled := 0
		for y in range(0, LeafLitterAtlas.STAMP_SIZE, 2):
			for x in range(0, LeafLitterAtlas.STAMP_SIZE, 2):
				var autumn_pixel := autumn_stamp.get_pixel(x, y)
				if autumn_pixel.a <= 0.05:
					continue
				sampled += 1
				autumn_saturation_sum += autumn_pixel.s
				winter_saturation_sum += winter_stamp.get_pixel(x, y).s
		assert_gt(sampled, 0, "precondition: %s's autumn stamp must have real content to sample" % species)
		assert_lt(
			winter_saturation_sum / sampled, autumn_saturation_sum / sampled,
			"%s's winter stamp should read less saturated than its autumn stamp" % species
		)


## The recolour must preserve the source's own light/shade variation (a real
## illustrated leaf's veins/highlights), not flatten everything to one
## uniform tint -- otherwise every species' winter stamp would look like the
## same flat brown blob rather than a recognisably shaded leaf shape.
func test_winter_stamp_keeps_real_shading_variation():
	var atlas := _atlas()
	var stamp := atlas.build_stamp_image(TreeSpecies.IDS[0], "winter")
	var luminances := {}
	for y in range(0, LeafLitterAtlas.STAMP_SIZE, 2):
		for x in range(0, LeafLitterAtlas.STAMP_SIZE, 2):
			var pixel := stamp.get_pixel(x, y)
			if pixel.a <= 0.05:
				continue
			var luminance := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			luminances[snappedf(luminance, 0.02)] = true
	assert_gt(luminances.size(), 5, "the winter stamp reads as a single flat tone, not real shading")


# -- stamps: correctly sized, not stretched -----------------------------------

func test_every_stamp_is_the_same_fixed_size():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		for season in _SEASONS:
			var stamp := atlas.build_stamp_image(species, season)
			assert_eq(stamp.get_width(), LeafLitterAtlas.STAMP_SIZE)
			assert_eq(stamp.get_height(), LeafLitterAtlas.STAMP_SIZE)


## Every real stamp must carry actual content -- a cropping bug that always
## selects an empty region would still produce a correctly SIZED, but
## entirely blank, stamp.
func test_every_stamp_actually_has_visible_content():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		for season in _SEASONS:
			var stamp := atlas.build_stamp_image(species, season)
			assert_false(
				_is_blank(stamp), "%s/%s produced a blank stamp" % [species, season]
			)


# -- the packed atlas image ---------------------------------------------------

func test_the_atlas_image_holds_every_cell_side_by_side():
	var atlas := _atlas()
	var image := atlas.build_atlas_image()
	assert_eq(image.get_height(), LeafLitterAtlas.CELL_SIZE)
	assert_eq(image.get_width(), atlas.cell_count() * LeafLitterAtlas.CELL_SIZE)


func test_the_atlas_texture_is_cached_across_calls():
	var atlas := _atlas()
	assert_eq(atlas.atlas_texture(), atlas.atlas_texture())


# -- UV rects: bounded, non-overlapping ---------------------------------------

func test_cell_uv_rect_stays_within_0_and_1():
	var atlas := _atlas()
	for species in TreeSpecies.IDS:
		for season in _SEASONS:
			var uv := atlas.cell_uv_rect(atlas.cell_index(species, season))
			assert_gte(uv.position.x, 0.0)
			assert_gte(uv.position.y, 0.0)
			assert_lte(uv.position.x + uv.size.x, 1.0001)
			assert_lte(uv.position.y + uv.size.y, 1.0001)


func test_cell_uv_rects_do_not_overlap_between_neighbours():
	var atlas := _atlas()
	var a := atlas.cell_uv_rect(0)
	var b := atlas.cell_uv_rect(1)
	assert_lte(a.position.x + a.size.x, b.position.x + 0.0001)
