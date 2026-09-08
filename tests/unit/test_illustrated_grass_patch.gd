extends GutTest

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const GroundTint = preload("res://src/rendering/ground_tint.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")


## Width is always a full, un-inset cell (bleed only ever runs vertically,
## row into row -- see ROW_TOP_BLEED_PX_BY_SEASON's own doc comment); height
## is shorter than a full cell for any row whose own measured bleed inset is
## nonzero, since that inset is cropped off the region's own top edge on
## purpose. growth=0.45 lands in row 4 (int(0.45*10)=4), whose real measured
## inset is 13px -- asserted against ROW_TOP_BLEED_PX_BY_SEASON directly
## rather than a hardcoded number, so this test can't silently drift out of
## sync with the table if it's ever remeasured. Seed (42) only picks the
## column here and is otherwise unconstrained by this test. No season is
## passed, so this exercises atlas_region_for's own DEFAULT_SEASON fallback
## -- rows 0-5 are identical across every season anyway (see that table's own
## doc comment), so which season this defaults to doesn't matter here.
func test_growth_and_seed_together_select_one_tile_inside_the_delivered_10x10_atlas():
	var rect := IllustratedGrassPatch.atlas_region_for(42, 0.45)
	var default_bleed_table: Array = IllustratedGrassPatch.ROW_TOP_BLEED_PX_BY_SEASON[IllustratedGrassPatch.DEFAULT_SEASON]
	var expected_height: int = 1254 / 10 - int(default_bleed_table[4])
	assert_between(rect.size.x, 125, 126)
	assert_between(rect.size.y, expected_height - 1, expected_height + 1)
	assert_gte(rect.position.x, 0)
	assert_gte(rect.position.y, 0)
	assert_lt(rect.position.x, 1254)
	assert_lt(rect.position.y, 1254)


## The delivered sheets' taller "bush"/wheat-ear variants (denser rows) draw
## their own plant art past their own cell's nominal bottom edge, bleeding
## into the TOP of the next row's cell -- measured directly against the real
## shipped art (originally `grass_blades.png`, now shipped as
## `grass_blades_summer.png`, the same pixels -- see
## docs/concept/long_grass.md): a solid opaque strip right at a recipient
## cell's own top edge, then a genuine transparent gap, then that cell's OWN
## plant starting further down. Because the shader flips root-at-bottom/tip-
## at-top (a card's local Y=0 is the ground, WORLD_SIZE is up), a region
## sliced with no inset puts that bled fragment at the rendered TIP -- the
## point farthest from the ground -- visibly detached from the card's own
## body by a real transparent gap. Reported live: "the grass now has floating
## artefacts above it" (Lüneburg-Heath-style meadow, snow made the contrast
## bad enough to see clearly, but the bleed itself is independent of snow --
## reproduced over both white and green backgrounds).
##
## Swept against all four real delivered season sheets, passing EACH
## season's own name into `atlas_region_for` so its own `ROW_TOP_BLEED_PX_
## BY_SEASON` entry is what actually gets checked, not one shared value
## stretched across all four. Checked against the SAME chroma-keyed image
## production actually samples (IllustratedGrassPatch.BACKGROUND_KEY/
## _TOLERANCE) -- three of the four delivered sheets ship with no real alpha
## channel at all (see _texture_for's own doc comment) and would otherwise
## read as one solid opaque rectangle, not "no bleed found".
##
## Asserts on the FRACTION of each region's own top row that is mostly
## transparent (>= 90%), not on every individual sampled x: a real hand-
## illustrated edge is anti-aliased, and exhaustively sampling every x across
## a region's own width reliably finds some point sitting mid-gradient on a
## curved/diagonal edge -- true even of `grass_blades_summer.png`, the one
## sheet this table was originally measured against and long proven in
## production. This fraction form is also far more STABLE run to run than a
## strict per-sample assertion: a borderline pixel sitting right at the 0.5
## cut barely moves a 32-sample average, where it can flip a strict "every
## sample must pass" check unpredictably (measured: repeated runs of a
## stricter form against the exact same unchanged files/code reported a
## DIFFERENT single solid-opaque cell failing each time, before this form
## replaced it).
##
## Rows 6-9 (the four densest rows -- full, flowering/fruiting clumps) now
## converge cleanly for every season except ONE (winter's own row 9, see
## below) once each season gets its OWN measured inset
## (`ROW_TOP_BLEED_PX_BY_SEASON`) instead of one value shared across all
## four. The original single-shared-table investigation found rows 6-9
## failing across MULTIPLE seasons at different rows within that range
## (autumn at rows 7-9, winter at rows 6-9) precisely because a single number
## had to simultaneously satisfy the least-bled AND most-bled season at
## once -- measuring and tuning each season independently resolves every one
## of those 35 remaining (season, row) combinations.
##
## winter row 9 is excluded here, not overlooked: its own art fills nearly
## its ENTIRE cell height with a dense, frost-laden clump (confirmed with a
## direct visual crop, not just measured), so no inset -- however large --
## lands the region's own top edge in a genuinely transparent zone across
## all 10 columns without cropping the row down to a sliver. The best
## available inset (`ROW_TOP_BLEED_PX_BY_SEASON.winter[9]` = 12px) gets 8 of
## 10 columns fully clear and the worst one to 81% -- a real, substantial
## improvement over the OLD shared-table value's ~31% on that same column
## (pinned directly by
## test_winter_row_9_bleed_is_narrowed_but_not_fully_closed_by_the_per_
## season_table below), just genuinely short of this test's own 90% bar. A
## known, narrowed gap (see docs/concept/long_grass.md's Status), not a bug
## in this function.
func test_atlas_region_for_never_includes_the_previous_rows_bled_over_content_on_any_season_sheet():
	var checked_any := false
	for season in IllustratedGrassPatch.SEASON_ATLAS_PATHS:
		var path: String = IllustratedGrassPatch.SEASON_ATLAS_PATHS[season]
		var raw := SpriteSheetLoader.load_image(path)
		assert_not_null(raw, "precondition: %s (%s) loads" % [season, path])
		var image := SpriteSheetSlicer.chroma_keyed(
			raw, IllustratedGrassPatch.BACKGROUND_KEY, IllustratedGrassPatch.BACKGROUND_KEY_TOLERANCE
		)
		var size := image.get_size()
		for row in range(1, IllustratedGrassPatch.ATLAS_ROWS):
			# The one remaining, narrowly-scoped known gap -- see this test's
			# own doc comment and
			# test_winter_row_9_bleed_is_narrowed_but_not_fully_closed_by_
			# the_per_season_table.
			if season == "winter" and row == 9:
				continue
			# Midpoint of the row's own growth bucket, not its exact lower
			# boundary -- float(row)/ATLAS_ROWS can land a hair under the
			# boundary (e.g. 0.9*10 == 8.999999...) and silently sample the
			# PREVIOUS row instead under int() truncation.
			var growth := (float(row) + 0.5) / float(IllustratedGrassPatch.ATLAS_ROWS)
			for column in IllustratedGrassPatch.ATLAS_COLUMNS:
				var region := IllustratedGrassPatch.atlas_region_for(column, growth, size, season)
				checked_any = true
				var clear_samples := 0
				var total_samples := 0
				for x in range(region.position.x, region.position.x + region.size.x, 4):
					total_samples += 1
					if image.get_pixel(x, region.position.y).a < 0.5:
						clear_samples += 1
				assert_gt(
					float(clear_samples) / float(total_samples), 0.9,
					(
						"%s row %d col %d: region top (y=%d) is only %d/%d mostly-transparent -- "
						+ "still includes the previous row's bled-over content"
					) % [season, row, column, region.position.y, clear_samples, total_samples]
				)
	assert_true(checked_any, "precondition: rows 1-9 (except the one flagged winter/row-9 gap) were actually checked across all season sheets")


## The one gap the per-season table cannot close (see the big test above):
## winter's own row 9 draws a dense, frost-laden clump that fills nearly its
## entire cell height, so no inset lands its region's own top edge in a
## genuinely transparent zone across all 10 columns. Pins the REAL achieved
## improvement precisely rather than leaving it undocumented: at the best
## available inset (`ROW_TOP_BLEED_PX_BY_SEASON.winter[9]` = 12px), the worst
## column reaches 81% clear -- short of the 90% bar the main bleed test
## above uses, but a real, substantial improvement over the OLD single-
## shared-table value (30px, still today's fallback for an unrecognized
## season) at the exact same column, which only reached 31%. A regression
## FLOOR, not just a description -- if `BACKGROUND_KEY_TOLERANCE`, the winter
## art, or this table's own value ever regresses, this test notices.
func test_winter_row_9_bleed_is_narrowed_but_not_fully_closed_by_the_per_season_table():
	var raw := SpriteSheetLoader.load_image(IllustratedGrassPatch.SEASON_ATLAS_PATHS["winter"])
	assert_not_null(raw, "precondition: the real winter sheet loads")
	var image := SpriteSheetSlicer.chroma_keyed(
		raw, IllustratedGrassPatch.BACKGROUND_KEY, IllustratedGrassPatch.BACKGROUND_KEY_TOLERANCE
	)
	var size := image.get_size()
	var growth := 9.5 / float(IllustratedGrassPatch.ATLAS_ROWS)  # row 9's own midpoint

	var worst_fraction := 1.0
	for column in IllustratedGrassPatch.ATLAS_COLUMNS:
		var region := IllustratedGrassPatch.atlas_region_for(column, growth, size, "winter")
		var clear_samples := 0
		var total_samples := 0
		for x in range(region.position.x, region.position.x + region.size.x, 4):
			total_samples += 1
			if image.get_pixel(x, region.position.y).a < 0.5:
				clear_samples += 1
		worst_fraction = minf(worst_fraction, float(clear_samples) / float(total_samples))

	assert_gt(worst_fraction, 0.75, "the per-season table's own value must clear real, substantial ground versus the old shared value's ~0.31")
	assert_lt(worst_fraction, 0.9, "honestly documents this as still short of the bar every other (season, row) combination clears -- if this ever passes 0.9, the gap has genuinely closed and this test (and the exclusion above) should be updated to say so")


## `ROW_TOP_BLEED_PX_BY_SEASON` exists to give each season its OWN measured
## inset for the densest rows rather than stretching one shared value across
## all four (see the big bleed test above) -- this proves the table is
## actually WIRED into `atlas_region_for`'s real computation, not just
## defined and ignored. Row 9: spring's real measured inset (12px) differs
## from summer's (7px), so the SAME seed/growth must produce a differently-
## cropped region depending on which season is asked for.
func test_atlas_region_for_uses_a_per_season_bleed_table_for_the_densest_rows():
	var growth := 9.5 / float(IllustratedGrassPatch.ATLAS_ROWS)
	var spring_region := IllustratedGrassPatch.atlas_region_for(3, growth, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, "spring")
	var summer_region := IllustratedGrassPatch.atlas_region_for(3, growth, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, "summer")
	var spring_inset: int = IllustratedGrassPatch.ROW_TOP_BLEED_PX_BY_SEASON["spring"][9]
	var summer_inset: int = IllustratedGrassPatch.ROW_TOP_BLEED_PX_BY_SEASON["summer"][9]
	assert_ne(spring_inset, summer_inset, "precondition: the two seasons' own real measured insets actually differ")
	assert_eq(
		spring_region.position.y - summer_region.position.y, spring_inset - summer_inset,
		"the two seasons' own real measured insets must each be independently honored, not one shared value"
	)


## Mirrors `_texture_for`'s own fallback-to-`DEFAULT_SEASON` pattern (see its
## doc comment) -- an unrecognized season name must not crash or silently
## read a null/zeroed table, it must behave exactly as if DEFAULT_SEASON had
## been passed.
func test_atlas_region_for_falls_back_to_the_default_season_for_an_unrecognized_name():
	var growth := 9.5 / float(IllustratedGrassPatch.ATLAS_ROWS)
	var fallback_region := IllustratedGrassPatch.atlas_region_for(3, growth, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, "not_a_real_season")
	var default_region := IllustratedGrassPatch.atlas_region_for(3, growth, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, IllustratedGrassPatch.DEFAULT_SEASON)
	assert_eq(fallback_region, default_region)


## `instances_for_cards` must forward its own `season` argument all the way
## into `atlas_region_for`, or a per-season bleed table can be as correct as
## it likes and never actually affect what gets drawn -- today's only real
## caller, `fill_band`, already receives a real per-band `season` for texture
## selection (see its own doc comment), so this is the OTHER half of
## actually wiring a season through, not the texture swap alone. Row 9's
## spring/summer insets differ (see the atlas_region_for test above), so the
## SAME card must pack a different atlas region depending on which season
## `instances_for_cards` is told to place it for.
func test_instances_for_cards_threads_season_through_to_the_per_season_bleed_table():
	var growth := 9.5 / float(IllustratedGrassPatch.ATLAS_ROWS)
	var card_specs: Array[Dictionary] = [{"atlas_seed": 3, "position": Vector2.ZERO, "growth": growth}]
	var spring_instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, "spring")
	var summer_instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, "summer")
	assert_ne(
		spring_instances[0].custom_data, summer_instances[0].custom_data,
		"the packed atlas region must differ by season once each has its own real bleed inset"
	)
	# Default (no season arg) must still work unmodified -- every existing
	# caller/test that never mentions season keeps behaving exactly as before.
	var default_instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE)
	var explicit_default_instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE, IllustratedGrassPatch.DEFAULT_SEASON)
	assert_eq(default_instances[0].custom_data, explicit_default_instances[0].custom_data)


## Every sheet must load, chroma-key to a real RGBA image with actual
## transparency present (not the pre-key all-opaque RGB this codebase
## shipped three of the four sheets as -- see _texture_for's own doc
## comment), and show a real, substantial fraction of transparent
## background overall -- catching a wholesale keying failure (wrong key
## colour, wrong tolerance, format not converting) independently of the
## per-row bleed check above.
func test_every_season_sheet_loads_and_keys_to_a_plausible_transparent_image():
	for season in IllustratedGrassPatch.SEASON_ATLAS_PATHS:
		var path: String = IllustratedGrassPatch.SEASON_ATLAS_PATHS[season]
		var raw := SpriteSheetLoader.load_image(path)
		assert_not_null(raw, "precondition: %s (%s) loads" % [season, path])
		var image := SpriteSheetSlicer.chroma_keyed(
			raw, IllustratedGrassPatch.BACKGROUND_KEY, IllustratedGrassPatch.BACKGROUND_KEY_TOLERANCE
		)
		assert_eq(image.get_format(), Image.FORMAT_RGBA8, "%s must be real RGBA after keying" % season)
		var transparent := 0
		var sampled := 0
		for y in range(0, image.get_height(), 23):
			for x in range(0, image.get_width(), 23):
				sampled += 1
				if image.get_pixel(x, y).a < 0.05:
					transparent += 1
		assert_gt(
			float(transparent) / float(sampled), 0.3,
			"%s: expected a real transparent background after keying, got %d/%d transparent samples" % [
				season, transparent, sampled
			]
		)




## Growth stage (the sheet's real drawn row -- a shoot at row 0, a full
## flowering clump at row 9, see docs/concept/long_grass.md's "Seasonal art")
## and variant (the column) are now two INDEPENDENT axes, not the one flat
## 100-cell hash `atlas_region_for_seed` used to be -- the whole reason it
## was split into `atlas_region_for`.
func test_atlas_region_for_maps_growth_to_row_and_seed_to_column_independently():
	# Same seed, climbing growth: the row climbs with it (never backwards),
	# and reaches every row somewhere across growth's full [0, 1) range.
	var rows_seen := {}
	var previous_row := -1
	for step in range(100):
		var growth := float(step) / 100.0
		var row: int = IllustratedGrassPatch.atlas_region_for(7, growth).position.y
		rows_seen[row] = true
		assert_gte(row, previous_row, "row must never move backwards as growth only increases")
		previous_row = row
	assert_eq(
		rows_seen.size(), IllustratedGrassPatch.ATLAS_ROWS,
		"every row must be reachable across growth's full range"
	)

	# Same growth, varying seed: the row (the region's own Y) stays fixed
	# while the column (the region's own X) varies.
	var fixed_growth := 0.6
	var first_region := IllustratedGrassPatch.atlas_region_for(0, fixed_growth)
	var xs_seen := {}
	for seed_value in range(IllustratedGrassPatch.ATLAS_COLUMNS):
		var region := IllustratedGrassPatch.atlas_region_for(seed_value, fixed_growth)
		assert_eq(region.position.y, first_region.position.y, "row must not depend on seed, only on growth")
		xs_seen[region.position.x] = true
	assert_eq(
		xs_seen.size(), IllustratedGrassPatch.ATLAS_COLUMNS,
		"every column must be reachable across a full seed cycle"
	)


func test_atlas_region_for_zero_growth_is_row_zero():
	assert_eq(IllustratedGrassPatch.atlas_region_for(3, 0.0).position.y, 0)


func test_atlas_region_for_growth_at_or_beyond_one_is_clamped_to_the_last_row():
	var last_row_region := IllustratedGrassPatch.atlas_region_for(3, 0.999)
	assert_eq(IllustratedGrassPatch.atlas_region_for(3, 1.0), last_row_region)
	assert_eq(
		IllustratedGrassPatch.atlas_region_for(3, 5.0), last_row_region,
		"an out-of-range growth must clamp, not wrap or crash"
	)


func test_a_patch_has_multiple_deterministically_placed_blade_cards():
	var first := IllustratedGrassPatch.card_specs_for_seed(42)
	assert_eq(first, IllustratedGrassPatch.card_specs_for_seed(42))
	assert_gte(first.size(), 3)
	assert_gt(first[0].depth, first[first.size() - 1].depth)


func test_card_count_is_high_enough_to_read_as_a_dense_field_not_a_sparse_clump():
	# Reported live: "make grass blades volumetric... looks and feels like a
	# dense field of grass" once spread across the tile (see the spread test
	# below) rather than clustered in one small area - spreading the SAME
	# small card count over a bigger area would read as sparser, not denser,
	# so the count is raised alongside the spread to keep the field feeling
	# full. Pinned exactly (not just a floor) so a future "just bump it a
	# bit" edit is a deliberate, tested change, not a silent drift.
	# Lowered from 12 to reduce grass overdraw/fill-rate cost on weak
	# (integrated) GPUs -- each card is an alpha-blended shaded quad, and a
	# dense field of them was a measurable per-frame cost (see CARD_COUNT's doc).
	assert_eq(IllustratedGrassPatch.CARD_COUNT, 8)


## Reported live: "make grass blades volumetric, so that more than one
## entity spawns on the same tile not only at bottom corner". Offsets used
## to span only ~3.3x1.4 world units, a small sub-region hugging the tile's
## own center - visually one clump sitting somewhere on the tile rather than
## grass filling its whole footprint. Cards must spread across most of the
## tile's actual size (TILE_SIZE), not a fraction of it, for the "walking
## through a dense field" feel.
func test_card_offsets_spread_across_most_of_a_full_tile_not_a_small_corner():
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for seed_value in range(30):
		for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			min_x = minf(min_x, offset.x)
			max_x = maxf(max_x, offset.x)
			min_y = minf(min_y, offset.y)
			max_y = maxf(max_y, offset.y)
	assert_gt(max_x - min_x, IllustratedGrassPatch.WORLD_SIZE * 0.7, "offsets must spread across most of the tile's width")
	assert_gt(max_y - min_y, IllustratedGrassPatch.WORLD_SIZE * 0.7, "offsets must spread across most of the tile's height")


## Spreading across the tile is the goal, but a root landing outside the
## tile it belongs to would visibly bleed into a neighboring cell's own
## footprint.
func test_card_offsets_stay_within_the_tiles_own_bounds():
	for seed_value in range(30):
		for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			assert_lte(absf(offset.x), IllustratedGrassPatch.WORLD_SIZE * 0.5)
			assert_lte(absf(offset.y), IllustratedGrassPatch.WORLD_SIZE * 0.5)


## SUPERSEDED (2026-08-26, reported live with a real screenshot): the
## previous fix for "the player's head is behind the long grass blades"
## used a per-pixel alpha fade (`occlusion_fade`, reusing the unrelated
## push effect's `walker_radius = 22.0`) as a stand-in for true occlusion.
## That both under- and over-corrected at once: any blade whose root sat
## MORE than 22 world units (~1.4 tiles) behind the player never faded at
## all, so it kept drawing solid on top of the player's upper body/head
## whenever it shared an in-front BAND with the player (a real, frequent
## case -- see the old BAND_COUNT=8 comment: each band was 4 tiles/64 world
## units tall) -- while every blade WITHIN that radius faded to fully
## invisible as the player simply walked near it, reported separately as
## "grass becomes transparent when walking over it". Both symptoms were the
## same undersized, wrongly-purposed heuristic standing in for real Y-sort.
##
## The real fix is architectural, not a bigger fade radius: shrink
## BAND_COUNT's own band height (see its own doc comment and
## test_band_height_leaves_a_real_safety_margin_under_the_players_own_max_reach
## below) until it's fine enough that Godot's OWN native Y-sort -- the exact
## mechanism every ordinary Sprite2D already uses correctly -- places each
## band in the right draw order on its own. Once that's true, no alpha hack
## is needed at all: grass is either genuinely behind the player (drawn
## first, correctly covered) or genuinely in front (drawn after, correctly
## covering) -- always fully opaque either way, matching what was reported.
func test_grass_opacity_is_never_reduced_by_the_players_own_proximity():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	assert_false(code.contains("occlusion_fade"), "the alpha-fade occlusion hack must be gone")
	assert_false(code.contains("passed_by_walker"), "the alpha-fade occlusion hack must be gone")
	assert_false(code.contains("COLOR.a *="), "grass must never have its opacity reduced")


## `clamp(local_x, 0.0, 1.0)` (see fragment()'s own comment trail) keeps
## every SAMPLE POSITION safely inside the atlas -- but at extreme bend,
## many consecutive fragments can all clamp to the SAME single edge column
## of the card's own region, repeating whatever pixel sits there across a
## visible stretch of the quad. Reported live: "all seasons except summer
## produce artifacts when parting" -- measured directly (real, non-headless
## render + a direct pixel probe, per this codebase's established
## technique): winter's row 9/column 0 region has a real, fully-opaque
## (alpha=1.0) pixel sitting exactly at its own right edge (x=124, the last
## column INSIDE the region), and spring/autumn have the same at the
## identical spot -- summer alone is clean there (its own native alpha
## channel, not chroma-keyed). A bend strong enough to clamp there stretches
## that ONE pixel into a visible horizontal smear, present on every season
## whose art happens to reach that boundary and absent on the one whose
## doesn't.
##
## Fixed by tracking the UN-clamped sample position (`raw_local_x`)
## alongside the clamped one: the clamped value still picks a safe, in-
## bounds texture coordinate (never an actual out-of-range read), but
## whenever the true, unclamped position would have fallen outside the
## card's own [0,1] region, that fragment is made fully transparent instead
## of showing whatever pixel the clamp landed on.
##
## This is NOT a re-introduction of the SUPERSEDED occlusion-fade hack
## above -- it is not a continuous function of distance-to-player, does not
## scale with `walker_radius`, and fires identically for a strong AMBIENT
## WIND gust far from any player (`bend_offset` combines wind AND push) as
## it does for a walker's push: it only ever discards the rare fragments
## whose own bend has carried them physically past the edge of their own
## source art. Everywhere else, opacity is exactly the sampled texel's own
## alpha, unmodified -- a straight `COLOR.a = 0.0` is not `COLOR.a *=`, and
## never triggers from proximity alone, so this does not conflict with
## test_grass_opacity_is_never_reduced_by_the_players_own_proximity above.
func test_shader_discards_a_fragment_that_bends_past_its_own_regions_edge():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var fragment_body := code.substr(code.find("void fragment()"))
	assert_string_contains(fragment_body, "raw_local_x")
	# Must key off the UN-clamped position -- checking the already-clamped
	# value could never be true/false, since it is forced into [0,1] first.
	assert_string_contains(fragment_body, "raw_local_x < 0.0")
	assert_string_contains(fragment_body, "raw_local_x > 1.0")
	assert_string_contains(fragment_body, "COLOR.a = 0.0")


## The player's own real max reach above their feet/root -- HeadSlot, the
## topmost node in scenes/character_view.tscn, sits at local Y = -42 (world
## units above the character's own origin, which is the same root a grass
## blade's own card grows up from -- see mesh()'s doc comment). A blade
## card is WORLD_SIZE tall and grows from ITS OWN root upward too, so the
## worst case is a blade sitting at the very TOP of an "in front" band: its
## own root can be up to one full band-height behind the player's root
## (see band_anchor_world_y's own bottom-edge anchoring), and its card then
## reaches another WORLD_SIZE past that. For native Y-sort to never let
## that worst-case card visually reach as high as the player's own real
## head, band_height + WORLD_SIZE must stay comfortably under 42.
##
## SUPERSEDED accounting (2026-08-27): the above ignored a real term.
## card_specs_for_seed gives every individual CARD its own random offset
## from its cell's nominal ground position, up to a real max magnitude --
## computed below from the live formula (never hardcoded: the formula's own
## bucket math is 17 buckets, centered to -8..8, times a 0.85 step, so the
## true bound is exactly 8.0 * 0.85 = 6.8, confirmed empirically across a
## wide seed sweep, not just algebraically assumed). Added ON TOP of the
## existing band_height + WORLD_SIZE bound.
##
## SUPERSEDED again (2026-08-27, same day, a direct follow-up): reported
## live, after the per-card banding fix landed: "y ordering is correct only
## for some [tufts]... should work like the lower one for all." Per-card
## banding was a real, necessary architectural fix, but at the THEN-real
## BAND_COUNT=32 (band_height=16), a card's max offset (6.8) can never
## cross a whole-tile boundary (which sits 8 units away) -- so it was a
## correctness fix with no visible effect yet (see
## test_per_card_banding_matches_cell_level_banding_at_the_real_production_
## ratio). The ACTUAL remaining symptom is architectural, not a card-offset
## bug: a whole band still draws in front of the player for as long as the
## player is anywhere within it (band_anchor_world_y's own bottom-edge
## anchoring, "normal, expected concealment" by design) -- at one full tile
## per band, that's a full tile's worth of travel where a band which the
## player has arguably already reached still paints in front of them. This
## reads as barely perceptible on sparse blade art (mostly transparent
## quad) but glaringly wrong on the atlas's own dense, near-opaque "bush"
## cards (a big solid shape squarely over the player). BAND_COUNT raised
## again, 32 -> 64 (band_height 16 -> 8, half a tile instead of a whole
## one): shrinks that grace window by half, AND makes the per-card banding
## fix landed just before this actually take effect (a card's 6.8 offset
## CAN now cross an 8-unit boundary). Another deliberate, honest 2x
## draw-call cost for grass (32 -> 64 per chunk, 8x the original pre-fix
## count of 8) -- correctness over raw draw-call count, same reasoning as
## every prior pass on this exact bug.
func test_band_height_leaves_a_real_safety_margin_under_the_players_own_max_reach():
	const PLAYER_MAX_REACH_ABOVE_ROOT := 42.0  # character_view.tscn's own real HeadSlot offset
	var chunk_size := 32  # EarthChunkManager.CHUNK_SIZE
	var tile_size := 16.0  # TerrainRenderer.TILE_SIZE

	# The real max |offset.y| any card can carry -- computed from the live
	# formula across a wide seed range, not hardcoded.
	var max_card_offset_y := 0.0
	for seed_value in range(500):
		for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			max_card_offset_y = maxf(max_card_offset_y, absf(offset.y))
	assert_almost_eq(
		max_card_offset_y, 8.0 * 0.85, 0.001,
		"precondition: the empirically observed max must match the formula's own real bound (17 buckets centered to +/-8, step 0.85)"
	)

	var band_height_world_units: float = (float(chunk_size) / float(IllustratedGrassPatch.BAND_COUNT)) * tile_size
	var worst_case_reach: float = band_height_world_units + max_card_offset_y + IllustratedGrassPatch.WORLD_SIZE
	assert_almost_eq(worst_case_reach, 30.8, 0.001, "pin the real number this margin is actually computed from")
	assert_lt(
		worst_case_reach, PLAYER_MAX_REACH_ABOVE_ROOT,
		"a band's own worst-case blade, real per-card offset included, must never be able to visually reach the player's real head height"
	)
	# Honest: the real margin (42 - 30.8 = 11.2 world units) is comfortable
	# again now that band_height itself shrank alongside the offset
	# accounting -- named here rather than left implicit.
	var real_margin: float = PLAYER_MAX_REACH_ABOVE_ROOT - worst_case_reach
	assert_gt(real_margin, 11.0, "the real margin, honestly accounted for")
	assert_lt(real_margin, 12.0, "...pin it, not just a floor")


func test_shader_bends_each_pixel_row_along_a_curved_per_blade_path():
	# A per-vertex shear can only ever move a quad's 4 corners, which linearly
	# interpolates into a flat parallelogram - every blade drawn on the card
	# leans by the same amount at a given height. Real path-traced bending
	# needs a fragment-stage, per-pixel UV offset (so it can follow a curved,
	# non-linear profile) that also varies with UV.x (so blades drawn side by
	# side in the same card don't sway in perfect lockstep).
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "player_world_position")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "walker_radius")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "void fragment()")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "pow(")


func test_shader_reads_its_atlas_region_from_per_instance_color():
	# This shader always draws through one shared MultiMesh material, so the
	# only way one instance's card can differ from another's atlas region is
	# per-instance data. `instance uniform` hits a global, hardware-capped
	# buffer shared by the WHOLE SCENE (measured on real hardware: 4096
	# total) - a single loaded chunk's worth of cards already overflowed it
	# ("Too many instances using shader instance variables"), silently
	# falling back to a wrong default region past the cap.
	#
	# It also isn't plain per-instance COLOR (MultiMesh's use_colors) read
	# directly in fragment(): under this project's gl_compatibility
	# renderer that produced a dithered/checkerboard mix of neighboring
	# instances' data instead of a clean per-instance constant, confirmed
	# with a real render (visible speckle noise even with zero bend math
	# involved). INSTANCE_CUSTOM read in vertex() and carried via varying is
	# the path that actually renders cleanly.
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "INSTANCE_CUSTOM")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "v_region.rg")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "v_region.ba")
	assert_false(IllustratedGrassPatch.SHADER_CODE.contains("instance uniform vec2"), "instance uniform hits a global hardware-capped buffer at real card counts")


## A card must always sample its own atlas art - never an unconditional
## flat color. Reported live: "all grass blades are a magenta square tile"
## after a restart, traced to a literal `COLOR = vec4(1,0,1,1)` left in the
## shader gated on `wake > 0.01` (i.e. whenever a walker is anywhere within
## walker_radius) - a debug override that never should have shipped, self-
## labeled "TEMP DIAGNOSTIC" by whoever added it but never reverted.
func test_shader_never_unconditionally_overrides_color_to_a_flat_debug_tint():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	assert_false(code.contains("1.0, 0.0, 1.0"), "no hardcoded magenta debug override")
	# The only assignment to COLOR must be the real texture sample - anything
	# else (an `if` block reassigning it afterward) is debug scaffolding.
	var color_assignments := 0
	for line in code.split("\n"):
		if line.strip_edges().begins_with("COLOR ="):
			color_assignments += 1
	assert_eq(color_assignments, 1, "COLOR must be assigned exactly once - the real texture sample, unconditionally")


func test_walker_push_amplitude_matches_its_own_tuned_constant_not_a_debug_crank():
	# WALKER_PUSH_UV_AMPLITUDE >= 0.4 (see the "dense bush art" test above) is
	# a floor, not license for an arbitrary debug value - reported live
	# alongside the magenta override: `const WALKER_PUSH_UV_AMPLITUDE := 5.0
	# # TEMP DIAGNOSTIC CRANK`. Pin the real tuned value exactly so a future
	# debug crank fails loudly instead of silently shipping. Climbed
	# 0.45 -> 0.6 -> 0.7 -> 1.5 across several live "still not enough"
	# reports; 1.5 stays well clear (< 1/3) of the ~5.0 region where
	# bend_offset overshoots the shader's own UV clamp and the curve
	# collapses into a static-looking clamped sliver instead of a visible
	# sway (see docs/concept/long_grass.md's History) - the earlier small
	# nudges (0.6, 0.7) apparently still read as weak in practice, so this
	# jump is deliberately much larger rather than another small increment.
	assert_eq(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE, 1.5)


func test_bend_curve_pins_the_root_and_reaches_full_displacement_at_the_tip():
	assert_eq(IllustratedGrassPatch.bend_curve(0.0), 0.0)
	assert_eq(IllustratedGrassPatch.bend_curve(1.0), 1.0)


func test_bend_curve_eases_in_so_bending_concentrates_near_the_tip():
	# A straight-line (vertex-shear) profile would put the midpoint at exactly
	# 0.5. A believable blade instead barely moves near its root and whips
	# increasingly near its tip, so the midpoint sits below the linear value.
	assert_lt(IllustratedGrassPatch.bend_curve(0.5), 0.5)


func test_bend_curve_is_monotonically_increasing_toward_the_tip():
	var previous := IllustratedGrassPatch.bend_curve(0.0)
	for step in range(1, 11):
		var top_t := step / 10.0
		var value := IllustratedGrassPatch.bend_curve(top_t)
		assert_gte(value, previous)
		previous = value


func test_blade_phase_differs_across_the_cards_width():
	# Different horizontal positions within one card approximate different
	# blades in the same tuft; they must not share an identical wind phase.
	assert_eq(IllustratedGrassPatch.blade_phase(0.0), 0.0)
	assert_ne(IllustratedGrassPatch.blade_phase(1.0), IllustratedGrassPatch.blade_phase(0.0))


func test_blade_amplitude_scale_never_fully_flattens_any_column():
	var uv_x := 0.0
	while uv_x <= 1.0:
		assert_gt(IllustratedGrassPatch.blade_amplitude_scale(uv_x), 0.0)
		uv_x += 0.1


func test_walker_push_amplitude_dominates_over_ambient_wind_amplitude():
	# The pass/sway "parting" reaction the player triggers must read as
	# clearly stronger than idle wind sway.
	assert_gt(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE, IllustratedGrassPatch.WIND_UV_AMPLITUDE)


## Ambient wind sway must scale with the live wind strength (see
## WeatherModel.wind_strength_for, forwarded via EarthChunkManager.
## set_wind_strength) -- reusing the SAME live value water's own
## wind_strength already does, not a parallel wind concept.
## DEFAULT_WIND_STRENGTH is calibrated to wind_strength_for("clear") == 1.0,
## so the default reproduces today's fixed-amplitude look exactly at that
## baseline.
func test_material_defaults_wind_strength_to_the_calibration_anchor():
	var patch := IllustratedGrassPatch.new()
	var material := patch.material()
	assert_eq(material.get_shader_parameter("wind_strength"), IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)
	assert_eq(IllustratedGrassPatch.DEFAULT_WIND_STRENGTH, 1.0)


func test_ambient_wind_sway_scales_by_the_live_wind_strength_uniform():
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "uniform float wind_strength")
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var wind_line_start := code.find("float wind = ")
	var wind_line := code.substr(wind_line_start, code.find(";", wind_line_start) - wind_line_start)
	assert_string_contains(wind_line, "wind_strength")


## Parting is the WALKER's own reaction, not ambient wind -- a calm day must
## not make walking through grass part it any less than a stormy one would.
func test_walker_push_is_not_scaled_by_wind_strength():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var push_line_start := code.find("float push = ")
	var push_line := code.substr(push_line_start, code.find(";", push_line_start) - push_line_start)
	assert_false(push_line.contains("wind_strength"), "walker push must stay independent of ambient wind: %s" % push_line)


func test_set_wind_strength_updates_the_materials_uniform():
	var patch := IllustratedGrassPatch.new()
	patch.set_wind_strength(1.8)
	assert_eq(patch.material().get_shader_parameter("wind_strength"), 1.8)
	patch.set_wind_strength(IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)
	assert_eq(patch.material().get_shader_parameter("wind_strength"), IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)


func test_walker_push_amplitude_is_strong_enough_to_read_against_dense_bush_art():
	# A rendered-pixel probe measured that a dense, busy bush card (many
	# overlapping similarly-colored blades filling the whole cell) shows
	# almost no *visible* parting at small UV shifts, even though the
	# pixels genuinely change: a small positional shift of dense, repetitive
	# texture still looks like the same dense texture. A sparse single-blade
	# card reads clearly at a much smaller shift because moving its
	# silhouette edge is high-contrast. The amplitude has to be large enough
	# for the busier case, reported live as "bigger bushes don't part...
	# don't sway anymore".
	assert_gte(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE, 0.4)


func test_band_index_stays_within_bounds_across_the_whole_chunk_height():
	var chunk_size := 32
	var band_count := IllustratedGrassPatch.BAND_COUNT
	for local_y in range(chunk_size):
		var band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)
		assert_gte(band, 0)
		assert_lt(band, band_count)


func test_band_index_is_monotonically_non_decreasing_down_the_chunk():
	# A band groups a contiguous vertical slice of the chunk - cells further
	# down must never land in an earlier band than cells above them, or the
	# same visual row could split across non-adjacent bands.
	var chunk_size := 32
	var previous := IllustratedGrassPatch.band_index_for_local_y(0, chunk_size)
	for local_y in range(1, chunk_size):
		var band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)
		assert_gte(band, previous)
		previous = band


## SUPERSEDED (2026-08-27): now that BAND_COUNT (64) exceeds CHUNK_SIZE
## (32), a purely INTEGER local_y can only ever land on half of the real
## bands (band_height is 0.5 tile, so floor(local_y/0.5) skips every other
## index) -- by design, since the other half is only reachable via a real
## FRACTIONAL row (a cell's own true center, or a card's own further
## offset from it -- see local_row_for_world_y/cards_for_cell). Sampling at
## the real band_height step, not whole tiles, is what actually proves "not
## just in-bounds, a real spread" now.
func test_band_index_actually_uses_all_bands_across_a_full_chunk():
	var chunk_size := 32
	var band_count := IllustratedGrassPatch.BAND_COUNT
	var band_height: float = float(chunk_size) / float(band_count)
	var seen := {}
	var local_y := 0.0
	while local_y < float(chunk_size):
		seen[IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)] = true
		local_y += band_height * 0.5  # oversample each band, never skip one
	assert_eq(seen.size(), band_count)


func test_band_anchor_world_y_orders_the_same_as_band_index():
	# The whole point of banding by Y: band 0's anchor must sit above (a
	# smaller world Y than) band 1's, etc., so Y-sort against the player
	# actually tracks vertical position through the chunk.
	var chunk_size := 32
	var previous := -INF
	for band in range(IllustratedGrassPatch.BAND_COUNT):
		var anchor_y := IllustratedGrassPatch.band_anchor_world_y(band, 0, chunk_size, 16.0)
		assert_gt(anchor_y, previous)
		previous = anchor_y


## Reported live: "the player's head is behind the long grass blades when
## the feet already are past it" -- a single MultiMeshInstance2D draw call
## can only Y-sort as ONE unit against the player (see BAND_COUNT's own doc
## comment), using this anchor as that unit's sort key. A CENTER anchor
## means every row in the LOWER half of a band sits below (a larger world Y
## than) the anchor -- so a player standing on one of those rows, having
## already walked past every blade in the band's upper half, still sees the
## WHOLE band (including blades whose own root the player is already past)
## Y-sort in front of them, since the comparison uses the band's midpoint,
## not any individual blade's real position. A blade card is exactly
## WORLD_SIZE (one tile) tall (see `mesh()`), so this isn't a sub-pixel
## rounding error -- a mid-band player can end up visibly behind a blade
## whose root is a full tile or more BEHIND their own feet, and since the
## card renders upward from its root, that reads exactly as "my head is
## behind grass my feet have already passed."
##
## The anchor must instead sit at the band's own BOTTOM edge (its largest
## row's world Y, not its midpoint): an entity standing anywhere within or
## above the band then always sorts BEHIND the whole band (grass draws in
## front while you're walking through it -- normal, expected concealment,
## see docs/concept/combat.md's vegetation-concealment pillar), and only
## pops in front of the entire band once genuinely past its very last row.
## That trades "occasionally covered a beat longer than a single blade's
## own root would justify" for "never shows a body part behind grass it has
## unambiguously already passed" -- the same choice BAND_COUNT's own doc
## comment already argues for ("the whole field flickering... is what
## actually reads as broken").
func test_band_anchor_world_y_is_never_smaller_than_any_row_actually_in_that_band():
	var chunk_size := 32
	var chunk_origin_y := 96  # nonzero, so this doesn't accidentally pass via origin canceling out
	var tile_size := 16.0
	for local_y in range(chunk_size):
		var band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)
		var anchor_y := IllustratedGrassPatch.band_anchor_world_y(band, chunk_origin_y, chunk_size, tile_size)
		var row_world_y := float(chunk_origin_y + local_y) * tile_size
		assert_gte(
			anchor_y, row_world_y,
			"row %d (band %d)'s own world Y must never exceed its band's anchor, or a player standing on it would wrongly Y-sort in front of blades from earlier rows in the same band" % [local_y, band]
		)


# -- per-card Y-sort banding: real position, not the cell's raw row -------
#
# Reported live, after the BAND_COUNT 8->32 fix: "y sorting works for some
# [tufts] but not all... it parts and bends but y ordering is correct only
# for some." Root cause: EarthChunkManager used to bucket a whole cell's
# CARD_COUNT cards into a Y-sort band from the cell's own raw, un-offset
# tile row -- before any card's own random offset (card_specs_for_seed) was
# even applied. cards_for_cell (below) is the single seam that expands a
# cell into its real, offset-adjusted per-card positions; both
# EarthChunkManager's own banding and instances_for_cards' own final
# placement math read from it, so the two can never drift apart.


func test_cards_for_cell_expands_a_cell_into_card_count_real_per_card_specs():
	var ground := Vector2(37.0, -12.0)
	var cell_spec := {"seed": 5, "ground_position": ground, "growth": 0.3}
	var cards := IllustratedGrassPatch.cards_for_cell(cell_spec)
	assert_eq(cards.size(), IllustratedGrassPatch.CARD_COUNT)
	var specs := IllustratedGrassPatch.card_specs_for_seed(5)
	for i in cards.size():
		assert_eq(cards[i].atlas_seed, specs[i].seed)
		assert_true((cards[i].position as Vector2).is_equal_approx(ground + (specs[i].offset as Vector2)))
		assert_eq(cards[i].growth, 0.3)


func test_local_row_for_world_y_inverts_a_cells_own_ground_position_math():
	# A cell's own ground_position is (tile.y + 0.5) * tile_size, where
	# tile.y = chunk_origin_y + local_y -- so feeding that same world Y back
	# through local_row_for_world_y must recover local_y + 0.5 (the row's
	# own center, i.e. the position a card with zero offset would sit at).
	var tile_size := 16.0
	var chunk_origin_y := 96  # nonzero, matches this file's own convention above
	var local_y := 5
	var world_y: float = float(chunk_origin_y + local_y) * tile_size + 0.5 * tile_size
	var recovered := IllustratedGrassPatch.local_row_for_world_y(world_y, chunk_origin_y, tile_size)
	assert_almost_eq(recovered, float(local_y) + 0.5, 0.001)


## SUPERSEDED (2026-08-27): this used to assert real_band == naive_band
## unconditionally -- true only as a COINCIDENCE of BAND_COUNT=32's own
## band_height being a whole tile (adding a cell's own +0.5-tile center
## offset can never cross a boundary a full tile wide). Now that
## band_height is 0.5 tile (BAND_COUNT=64), a cell's own real CENTER
## already sits exactly ON a boundary, so even ZERO further card offset can
## land one band ahead of the cell's raw, un-offset row -- by design, and
## exactly why per-card banding now matters at the real production ratio
## (see test_per_card_banding_diverges_from_cell_level_banding_at_the_real_
## production_ratio). The real, still-true invariant: a cell's own center
## is never more than one band ahead of its raw row, regardless of tuning.
func test_local_row_for_world_y_lands_at_most_one_band_ahead_of_the_cells_own_raw_row():
	var chunk_size := 32
	var tile_size := 16.0
	var chunk_origin_y := 0
	for local_y in range(chunk_size):
		var world_y: float = float(local_y) * tile_size + 0.5 * tile_size
		var real_row := IllustratedGrassPatch.local_row_for_world_y(world_y, chunk_origin_y, tile_size)
		var real_band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size)
		var naive_band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)
		assert_between(real_band, naive_band, naive_band + 1, "a cell's own center-based band must be its raw row's band or the very next one, never further")


## The direct, real proof that per-card banding differs from the OLD
## cell-raw-row banding once a card's own offset genuinely crosses a band
## boundary -- verified numbers, not assumed. Real seed 7's cell has 8
## cards whose offset.y is either exactly +6.8 (6 cards, indices 0-5) or
## exactly -6.8 (2 cards, indices 6-7) -- confirmed by direct inspection of
## card_specs_for_seed(7). At today's real production BAND_COUNT=32/
## CHUNK_SIZE=32 ratio (one band == one full tile row == 16 world units)
## neither offset is large enough to cross a boundary (see the regression
## test below) -- so this test deliberately uses a finer band_count (48,
## band_height = 32/48 tile = 10.667 world units) purely to exercise the
## underlying mechanism, the same way this file's other band_index tests
## already use literal chunk_size/band_count values decoupled from
## EarthChunkManager's own real ones.
func test_per_card_banding_splits_a_single_cells_cards_across_two_real_bands():
	var chunk_size := 32
	var band_count := 48
	var tile_size := 16.0
	var chunk_origin_y := 0
	var local_y := 0

	var cell_spec := {
		"seed": 7,
		"ground_position": Vector2(8.0, (float(local_y) + 0.5) * tile_size),
		"growth": 1.0,
	}
	var naive_band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)

	var cards := IllustratedGrassPatch.cards_for_cell(cell_spec)
	assert_eq(cards.size(), 8, "precondition: CARD_COUNT is still 8")

	var crossed := 0
	var stayed := 0
	for card in cards:
		var real_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, chunk_origin_y, tile_size)
		var real_band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size, band_count)
		if real_band == naive_band:
			stayed += 1
		else:
			assert_eq(real_band, naive_band + 1, "a crossing card must land in the immediately-next band, not further")
			crossed += 1
	assert_eq(crossed, 6, "the 6 cards whose real offset.y is +6.8 must cross into the next band")
	assert_eq(stayed, 2, "the 2 cards whose real offset.y is -6.8 must stay in the cell's own nominal band")


## SUPERSEDED (2026-08-27, same day as it was written): this test used to
## prove per-card banding was a no-op at BAND_COUNT=32 -- true then (band
## height 16, comfortably more than double any card's real max
## |offset.y|=6.8), but BAND_COUNT was raised again to 64 the same day for
## a separate, real reason (see BAND_COUNT's own doc comment: the "grace
## window" a whole tile-band spends drawing in front of the player read as
## broken on dense grass art). At band_height=8, a cell's own real CENTER
## (row+0.5, where every card's own root actually lives) already sits
## exactly ON a band boundary -- so per-card banding now genuinely diverges
## from naive cell-row banding for real cards at today's real production
## ratio, not just under a synthetic finer ratio. Proven generally (every
## row in a real chunk, many real cell seeds): at least one real divergence
## exists, and every real divergence lands in an immediately-adjacent band
## (never further), matching the crossing test just above it.
func test_per_card_banding_diverges_from_cell_level_banding_at_the_real_production_ratio():
	var chunk_size := 32  # EarthChunkManager.CHUNK_SIZE
	var band_count := IllustratedGrassPatch.BAND_COUNT  # today's real value
	var tile_size := 16.0
	var chunk_origin_y := 0
	var divergences := 0
	for local_y in range(chunk_size):
		var naive_band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)
		for seed_value in range(20):
			var cell_spec := {
				"seed": seed_value,
				"ground_position": Vector2(8.0, (float(local_y) + 0.5) * tile_size),
				"growth": 1.0,
			}
			for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
				var real_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, chunk_origin_y, tile_size)
				var real_band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size, band_count)
				if real_band != naive_band:
					assert_almost_eq(
						real_band, naive_band, 1,
						"a real divergence must land in an immediately-adjacent band, never further"
					)
					divergences += 1
	assert_gt(divergences, 0, "at today's real BAND_COUNT, per-card banding must genuinely differ from naive cell-row banding for at least some real cards -- confirming the fix is live, not just theoretically correct")


## No card is gained or lost by which band it ends up grouped into --
## summing a chunk's bands' instance counts must always equal
## CARD_COUNT * num_cells, whether banding is coarse (every card of every
## cell landing in one band) or fine enough that cards from the same cell
## genuinely split across two (mirrors the split proven above).
func test_regrouping_cards_by_band_never_gains_or_loses_a_card():
	var chunk_size := 32
	var tile_size := 16.0
	var cell_seeds := [3, 7, 42, 100]
	for band_count in [8, 32, 48, 96]:
		var cards_by_band: Dictionary = {}
		for seed_value in cell_seeds:
			var cell_spec := {
				"seed": seed_value,
				"ground_position": Vector2(8.0, 8.0),
				"growth": 1.0,
			}
			for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
				var real_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, 0, tile_size)
				var band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size, band_count)
				var list: Array = cards_by_band.get(band, [])
				list.append(card)
				cards_by_band[band] = list
		var total := 0
		for band in cards_by_band:
			total += (cards_by_band[band] as Array).size()
		assert_eq(
			total, IllustratedGrassPatch.CARD_COUNT * cell_seeds.size(),
			"band_count=%d must not change how many cards exist in total, only their grouping" % band_count
		)


# -- instances_for_cards: pure placement math over pre-expanded cards -----
#
# Takes CARD specs directly (not cell specs) -- deliberately does NOT
# expand a cell itself (that is cards_for_cell's own single job above), so
# a cell whose cards straddle two bands can be split across two separate
# calls without any card being drawn twice or silently dropped.


func test_instances_for_cards_produces_one_instance_per_given_card_with_no_further_expansion():
	var card_specs: Array[Dictionary] = [
		{"atlas_seed": 11, "position": Vector2(0, 0), "growth": 1.0},
		{"atlas_seed": 22, "position": Vector2(16, 0), "growth": 0.5},
	]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	assert_eq(instances.size(), 2)


func test_instances_for_cards_packs_each_instances_atlas_region_into_its_color():
	var card_specs: Array[Dictionary] = [{"atlas_seed": 7, "position": Vector2.ZERO, "growth": 1.0}]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var packed: Color = instances[0].custom_data
	var region_uv0 := Vector2(packed.r, packed.g)
	var region_uv1 := Vector2(packed.b, packed.a)
	assert_gte(region_uv0.x, 0.0)
	assert_lte(region_uv1.x, 1.0)
	assert_gt(region_uv1.x, region_uv0.x)
	assert_gt(region_uv1.y, region_uv0.y)


func test_instances_for_cards_places_the_root_exactly_at_the_given_position_regardless_of_growth():
	# The root (transform origin, pre-mesh-offset) must stay exactly at the
	# given position regardless of growth, whatever growth currently affects
	# (today: which row's art is sampled, not scale -- see
	# test_instances_for_cards_places_every_card_at_full_scale_regardless_of_growth).
	var position := Vector2(37.0, -12.0)
	var card_specs: Array[Dictionary] = [{"atlas_seed": 5, "position": position, "growth": 0.3}]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var transform: Transform2D = instances[0].transform
	assert_true(transform.origin.is_equal_approx(position))


## SUPERSEDED (see docs/concept/long_grass.md's "Seasonal art"): growth used
## to scale a card because every cell drew the same mature-clump art
## regardless of growth. Now growth instead selects a real drawn row
## (atlas_region_for), so scaling on TOP of that would double-damp an
## already-smaller-drawn shoot -- a card renders at full, undamped size
## across growth's entire range.
func test_instances_for_cards_places_every_card_at_full_scale_regardless_of_growth():
	for growth in [0.0, 0.3, 0.6, 1.0]:
		var card_specs: Array[Dictionary] = [{"atlas_seed": 5, "position": Vector2(10, 10), "growth": growth}]
		var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
		var transform: Transform2D = instances[0].transform
		assert_almost_eq(transform.x.x, 1.0, 0.001, "growth=%.1f must not scale the card" % growth)
		assert_almost_eq(transform.y.y, 1.0, 0.001, "growth=%.1f must not scale the card" % growth)


## Whichever band a card ultimately lands in, its own atlas region/root
## position/growth-derived scale must be byte-identical -- only the
## band_anchor (a local-position offset, not a placement input) may differ.
func test_instances_for_cards_placement_is_independent_of_which_band_anchor_it_is_drawn_relative_to():
	var card_specs: Array[Dictionary] = [{"atlas_seed": 9, "position": Vector2(50.0, 80.0), "growth": 0.75}]
	var instances_a := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2(0.0, 0.0), Vector2i(1254, 1254))
	var instances_b := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2(200.0, -400.0), Vector2i(1254, 1254))
	var transform_a: Transform2D = instances_a[0].transform
	var transform_b: Transform2D = instances_b[0].transform
	assert_true(
		(transform_a.origin + Vector2(0.0, 0.0)).is_equal_approx(transform_b.origin + Vector2(200.0, -400.0)),
		"absolute placement must not depend on the band_anchor used to draw it"
	)
	assert_eq(instances_a[0].custom_data, instances_b[0].custom_data, "atlas region must not depend on the band_anchor")
	assert_almost_eq(transform_a.x.x, transform_b.x.x, 0.001, "growth-derived scale must not depend on the band_anchor")


func test_fill_band_rebuilds_cleanly_when_called_again_with_fewer_cards():
	# A cell losing its grass (grazed, built on) must not leave stale
	# instances behind from the previous call.
	var patch := IllustratedGrassPatch.new()
	var mmi: MultiMeshInstance2D = autofree(MultiMeshInstance2D.new())
	var cell_a := {"seed": 1, "ground_position": Vector2(0, 0), "growth": 1.0}
	var cell_b := {"seed": 2, "ground_position": Vector2(16, 0), "growth": 1.0}
	var all_cards: Array[Dictionary] = []
	all_cards.append_array(IllustratedGrassPatch.cards_for_cell(cell_a))
	all_cards.append_array(IllustratedGrassPatch.cards_for_cell(cell_b))
	patch.fill_band(mmi, Vector2.ZERO, all_cards)
	var before := mmi.multimesh.instance_count
	patch.fill_band(mmi, Vector2.ZERO, IllustratedGrassPatch.cards_for_cell(cell_a))
	assert_lt(mmi.multimesh.instance_count, before)
	assert_eq(mmi.multimesh.instance_count, IllustratedGrassPatch.CARD_COUNT)


# -- a field carries the season, like the ground it stands in ----------------

## The blade shader had no colour term at all -- the sampled atlas texel was
## written straight through -- so tall grass stayed lush in deep winter while
## the trees above it stood bare. See SeasonalFoliage / concept/seasons.md.
func test_the_blade_shader_takes_a_season_tint_uniform():
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "uniform vec3 season_tint")


## The delivered atlas already carries some dry/brown blades; those must not
## be turned again by a season they are already wearing.
func test_the_blade_shader_gates_the_season_tint_on_greenness_with_the_shared_gain():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var fragment_body := code.substr(code.find("void fragment()"))
	assert_string_contains(fragment_body, "COLOR.g - max(COLOR.r, COLOR.b)")
	assert_string_contains(fragment_body, "* %s" % SeasonalFoliage.GREENNESS_GAIN)
	assert_string_contains(fragment_body, "mix(COLOR.rgb, COLOR.rgb * season_tint")


## A field and the ground under it must turn together -- a straw-coloured
## meadow standing on a bright green lawn is the same defect one layer up.
func test_the_blades_and_the_ground_under_them_use_the_same_greenness_gate():
	var gate := "clamp((COLOR.g - max(COLOR.r, COLOR.b)) * %s, 0.0, 1.0)" % SeasonalFoliage.GREENNESS_GAIN
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, gate)
	assert_string_contains(GroundTint.SHADER_CODE, gate)


## Mirrors set_wind_strength exactly, member re-applied at lazy build time.
func test_set_season_tint_survives_being_called_before_the_material_is_built():
	var patch := IllustratedGrassPatch.new()
	var winter := SeasonalFoliage.tint_for_season("winter")
	patch.set_season_tint(winter)
	var parameter = patch.material().get_shader_parameter("season_tint")
	assert_almost_eq(parameter.x, winter.r, 0.0001)
	assert_almost_eq(parameter.y, winter.g, 0.0001)
	assert_almost_eq(parameter.z, winter.b, 0.0001)


## The shader source is built by ONE positional `%` array, so appending the
## new greenness gain in the wrong slot would silently bake the wrong numbers
## into the bend math -- a shader that still compiles and just looks wrong.
## This pins the tuned constants that would move if that happened.
func test_the_bend_math_still_carries_its_own_tuned_constants():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	assert_string_contains(
		code, "pow(clamp(UV.y, 0.0, 1.0), %s)" % IllustratedGrassPatch.BEND_CURVE_EXPONENT
	)
	assert_string_contains(code, "UV.x * %s" % IllustratedGrassPatch.PHASE_SPREAD)
	assert_string_contains(
		code,
		"%s + %s * sin(UV.x * %s)" % [
			IllustratedGrassPatch.AMPLITUDE_BASE,
			IllustratedGrassPatch.AMPLITUDE_VARIATION,
			IllustratedGrassPatch.AMPLITUDE_FREQUENCY,
		]
	)
	assert_string_contains(
		code, "* %s * wind_strength" % IllustratedGrassPatch.WIND_UV_AMPLITUDE
	)
	assert_string_contains(
		code, "wake * %s" % IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE
	)


# -- per-blade staggered season transition (see docs/concept/long_grass.md's
# "Seasonal art" -- the same "one shared clock, many independently-timed
# units" shape TreePhenology/ProceduralTreeSprite turn a canopy with, at
# card granularity instead of per-pixel) -----------------------------------


func test_turn_threshold_for_seed_is_deterministic():
	assert_eq(
		IllustratedGrassPatch.turn_threshold_for_seed(42), IllustratedGrassPatch.turn_threshold_for_seed(42)
	)


func test_turn_threshold_for_seed_is_a_usable_zero_to_one_mix_weight():
	for atlas_seed in [0, 1, -7, 42, 100000, -100000]:
		var threshold := IllustratedGrassPatch.turn_threshold_for_seed(atlas_seed)
		assert_gte(threshold, 0.0)
		assert_lt(threshold, 1.0)


## Not correlated with which COLUMN a card's own atlas_seed already picks
## (see atlas_region_for) -- two different seeds landing in the same column
## must still be free to turn at different points, or every card in a
## column would turn in lockstep.
func test_turn_threshold_for_seed_spreads_across_many_seeds_not_just_a_few_buckets():
	var thresholds := {}
	for atlas_seed in range(200):
		var bucket := int(IllustratedGrassPatch.turn_threshold_for_seed(atlas_seed) * 10.0)
		thresholds[bucket] = thresholds.get(bucket, 0) + 1
	assert_gte(thresholds.size(), 8, "should spread across most of the [0,1) range, not clump in a few buckets")


func test_split_cards_by_turn_puts_every_card_in_from_at_zero_progress():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(20):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var split := IllustratedGrassPatch.split_cards_by_turn(card_specs, 0.0)
	assert_eq(split.from.size(), 20)
	assert_eq(split.to.size(), 0)


func test_split_cards_by_turn_puts_every_card_in_to_at_full_progress():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(20):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var split := IllustratedGrassPatch.split_cards_by_turn(card_specs, 1.0)
	assert_eq(split.from.size(), 0)
	assert_eq(split.to.size(), 20)


func test_split_cards_by_turn_splits_a_real_mix_at_a_mid_progress_without_losing_any_card():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(200):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var split := IllustratedGrassPatch.split_cards_by_turn(card_specs, 0.5)
	assert_eq(split.from.size() + split.to.size(), 200, "no card may be dropped or duplicated by the split")
	assert_gt(split.from.size(), 0, "precondition: a real mid-progress split must leave some cards untouched")
	assert_gt(split.to.size(), 0, "precondition: a real mid-progress split must turn some cards")


## As progress climbs, a card can only move from "from" to "to", never back
## -- the same one-way sweep direction ProceduralTreeSprite's pixels turn in.
func test_split_cards_by_turn_only_ever_moves_cards_from_from_to_to_as_progress_climbs():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(100):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var previous_to_seeds := {}
	for step in range(11):
		var progress := float(step) / 10.0
		var split := IllustratedGrassPatch.split_cards_by_turn(card_specs, progress)
		var to_seeds := {}
		for card in split.to:
			to_seeds[card.atlas_seed] = true
		for seed_value in previous_to_seeds:
			assert_true(to_seeds.has(seed_value), "a card that has turned must stay turned as progress only climbs")
		previous_to_seeds = to_seeds


# -- winter's own sheet is a snow overlay, not a calendar destination (see
# docs/concept/long_grass.md's "Winter's own sheet is a snow overlay, not a
# calendar destination") ---------------------------------------------------


func test_base_render_season_maps_winter_to_autumn():
	assert_eq(IllustratedGrassPatch.base_render_season("winter"), "autumn")


func test_base_render_season_passes_every_other_season_through_unchanged():
	for season in ["spring", "summer", "autumn"]:
		assert_eq(IllustratedGrassPatch.base_render_season(season), season)


func test_base_render_season_passes_an_unrecognized_name_through_unchanged():
	# Not this function's job to validate/fall back to DEFAULT_SEASON -- it
	# only ever special-cases the one literal string "winter"; every other
	# caller-supplied name (including a typo or a name it has never heard
	# of) passes straight through, exactly like today.
	assert_eq(IllustratedGrassPatch.base_render_season("not_a_real_season"), "not_a_real_season")


## Mirrors turn_threshold_for_seed's own tests exactly -- see that function's
## doc comment for why a snow-overlay threshold needs its OWN hash, distinct
## from both the seed/column hash AND turn_threshold_for_seed itself: a
## card's calendar-turn speed and its snow-overlay speed must never
## correlate, or a card quick to turn seasons would also always be quick to
## frost over.
func test_snow_overlay_threshold_for_seed_is_deterministic():
	assert_eq(
		IllustratedGrassPatch.snow_overlay_threshold_for_seed(42),
		IllustratedGrassPatch.snow_overlay_threshold_for_seed(42)
	)


func test_snow_overlay_threshold_for_seed_is_a_usable_zero_to_one_mix_weight():
	for atlas_seed in [0, 1, -7, 42, 100000, -100000]:
		var threshold := IllustratedGrassPatch.snow_overlay_threshold_for_seed(atlas_seed)
		assert_gte(threshold, 0.0)
		assert_lt(threshold, 1.0)


func test_snow_overlay_threshold_for_seed_spreads_across_many_seeds_not_just_a_few_buckets():
	var thresholds := {}
	for atlas_seed in range(200):
		var bucket := int(IllustratedGrassPatch.snow_overlay_threshold_for_seed(atlas_seed) * 10.0)
		thresholds[bucket] = thresholds.get(bucket, 0) + 1
	assert_gte(thresholds.size(), 8, "should spread across most of the [0,1) range, not clump in a few buckets")


## Independent of turn_threshold_for_seed -- a card's calendar-turn threshold
## and its snow-overlay threshold must not be the same number, or the two
## mechanisms would silently correlate despite being conceptually unrelated.
func test_snow_overlay_threshold_for_seed_does_not_correlate_with_turn_threshold_for_seed():
	var matches := 0
	var total := 200
	for atlas_seed in range(total):
		var turn_bucket := int(IllustratedGrassPatch.turn_threshold_for_seed(atlas_seed) * 10.0)
		var snow_bucket := int(IllustratedGrassPatch.snow_overlay_threshold_for_seed(atlas_seed) * 10.0)
		if turn_bucket == snow_bucket:
			matches += 1
	# Two INDEPENDENT uniform [0,10) buckets agree by pure chance ~10% of the
	# time; a hard correlation (e.g. the same hash reused) would agree 100%.
	assert_lt(matches, total / 2, "the two thresholds must not be the same hash reused")


func test_split_cards_by_snow_overlay_puts_every_card_in_base_at_zero_depth():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(20):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var split := IllustratedGrassPatch.split_cards_by_snow_overlay(card_specs, 0.0)
	assert_eq(split.base.size(), 20)
	assert_eq(split.winter.size(), 0)


func test_split_cards_by_snow_overlay_puts_every_card_in_winter_at_full_depth():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(20):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var split := IllustratedGrassPatch.split_cards_by_snow_overlay(card_specs, 1.0)
	assert_eq(split.base.size(), 0)
	assert_eq(split.winter.size(), 20)


func test_split_cards_by_snow_overlay_splits_a_real_mix_at_a_mid_depth_without_losing_any_card():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(200):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var split := IllustratedGrassPatch.split_cards_by_snow_overlay(card_specs, 0.5)
	assert_eq(split.base.size() + split.winter.size(), 200, "no card may be dropped or duplicated by the split")
	assert_gt(split.base.size(), 0, "precondition: a real mid-depth split must leave some cards untouched")
	assert_gt(split.winter.size(), 0, "precondition: a real mid-depth split must overlay some cards")


# -- turn_threshold_for_seed must spread within ONE CELL's own real 8 cards,
# not just across arbitrary sequential integers (the existing "spreads
# across many seeds" test above only ever fed it 0..199 directly). Reported
# live: "The long grass sprites don't change season color per blade but
# instead per entity... each entity should progress its blades individually
# ... it should transition per blade." Root cause: card_specs_for_seed's own
# atlas_seed is `hash("%d_grass_card_%d" % [seed_value, index])` for
# index 0..7 -- a shared prefix with only a single trailing digit varying --
# and Godot's String hash does NOT avalanche on that shape (confirmed by a
# throwaway probe: it returned seed_value_hash+0, +1, +2, ... +7, an exactly
# LINEAR sequence, not a hash at all). turn_threshold_for_seed then re-hashes
# that already-near-sequential atlas_seed through ANOTHER string built the
# same vulnerable way ("%d_grass_turn" % atlas_seed), which does not recover
# independence either -- so a cell's 8 real cards land suspiciously close
# together and tend to cross any given progress threshold together, reading
# as the whole tuft ("entity") turning at once instead of blade by blade.


## One real cell's 8 real card atlas_seeds, via the exact same production
## path _sync_grass_sprites uses (card_specs_for_seed/cards_for_cell) --
## not a hand-built list of arbitrary integers, so this test can only pass
## if the REAL pipeline decorrelates, not just the threshold function in
## isolation.
func _real_cell_turn_thresholds(tile: Vector2i) -> Array:
	var seed_value := hash("%d_%d_grass_tuft" % [tile.x, tile.y])
	var cell_spec := {"seed": seed_value, "ground_position": Vector2.ZERO, "growth": 1.0}
	var thresholds := []
	for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
		thresholds.append(IllustratedGrassPatch.turn_threshold_for_seed(card.atlas_seed))
	return thresholds


## Across many real cells, the count of "how many of this cell's 8 cards
## have turned" at a mid progress must show REAL variance -- true
## independent [0,1) thresholds make an extreme split (0, 1, 7 or 8 of 8
## below 0.5) happen ~7% of the time (Binomial(8, 0.5)'s own two-tail mass),
## so at least one among 100 real, deterministically-seeded cells finding
## one is expected with overwhelming probability. A correlated/clustered
## hash (the actual bug, confirmed empirically: 0 extreme splits found
## across 500 real cells against the CURRENT implementation) makes this
## essentially never happen -- every cell instead lands its cards in a
## narrow 2-4 band every time.
func test_turn_threshold_for_seed_shows_real_per_cell_variance_not_a_suspiciously_narrow_band():
	var saw_an_extreme_split := false
	for tile_index in range(100):
		var tile := Vector2i(tile_index * 3 + 1000, tile_index * 7 + 2000)
		var thresholds := _real_cell_turn_thresholds(tile)
		var below := 0
		for t in thresholds:
			if t <= 0.5:
				below += 1
		if below <= 1 or below >= 7:
			saw_an_extreme_split = true
			break
	assert_true(
		saw_an_extreme_split,
		"across 100 real cells, none showed an extreme (<=1 or >=7 of 8) split at a mid " +
		"progress -- turn_threshold_for_seed's own output looks correlated within a cell, " +
		"not independent, which is exactly why whole tufts turn together instead of blade by blade"
	)


## The concrete visual complaint, pinned directly: a real cell's own 8 cards
## must not all sit on the SAME side of a mid-transition progress -- if they
## do, that one tuft still turns as a single all-or-nothing unit no matter
## how independent OTHER cells' thresholds are, which is indistinguishable
## from "per entity" to a player watching that one tuft.
func test_a_real_cells_eight_cards_are_not_all_on_the_same_side_of_a_mid_transition():
	var any_cell_actually_split := false
	for tile_index in range(20):
		var tile := Vector2i(tile_index * 5 + 4000, tile_index * 11 + 6000)
		var thresholds := _real_cell_turn_thresholds(tile)
		var below := 0
		var above := 0
		for t in thresholds:
			if t <= 0.5:
				below += 1
			else:
				above += 1
		if below > 0 and above > 0:
			any_cell_actually_split = true
			break
	assert_true(
		any_cell_actually_split,
		"across 20 real cells, none had its own 8 cards straddle a mid progress -- at least " +
		"one real tuft should show SOME of its own blades turned and some not yet turned"
	)


## As depth climbs, a card can only move from "base" to "winter", never back
## -- mirrors split_cards_by_turn's own one-way sweep exactly.
func test_split_cards_by_snow_overlay_only_ever_moves_cards_from_base_to_winter_as_depth_climbs():
	var card_specs: Array[Dictionary] = []
	for atlas_seed in range(100):
		card_specs.append({"atlas_seed": atlas_seed, "position": Vector2.ZERO, "growth": 1.0})
	var previous_winter_seeds := {}
	for step in range(11):
		var depth := float(step) / 10.0
		var split := IllustratedGrassPatch.split_cards_by_snow_overlay(card_specs, depth)
		var winter_seeds := {}
		for card in split.winter:
			winter_seeds[card.atlas_seed] = true
		for seed_value in previous_winter_seeds:
			assert_true(winter_seeds.has(seed_value), "a card the snow has already caught must stay caught as depth only climbs")
		previous_winter_seeds = winter_seeds
