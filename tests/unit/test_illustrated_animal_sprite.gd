extends GutTest

## IllustratedAnimalSprite: real hand/AI-illustrated sprite-sheet animation
## for species with art in assets/sprites/ (see docs/concept/... and
## SpriteSheetSlicer), replacing ProceduralAnimalSprite's primitive-shape
## generation for just those species. Species without a registered sheet
## keep using the procedural generator entirely -- see CreatureMarker.
## _animation_step, which checks has_species() first and falls back.

const IllustratedAnimalSprite = preload("res://src/rendering/illustrated_animal_sprite.gd")

var sprite: IllustratedAnimalSprite


func before_each():
	sprite = IllustratedAnimalSprite.new()


func test_has_species_true_for_a_registered_species():
	assert_true(sprite.has_species("horse"))
	assert_true(sprite.has_species("deer"))
	assert_true(sprite.has_species("boar"))


func test_has_species_false_for_an_unregistered_species():
	assert_false(sprite.has_species("mouse"))
	assert_false(sprite.has_species("totally_unknown_species"))


func test_has_action_true_for_walk_and_eat_on_a_registered_species():
	assert_true(sprite.has_action("deer", "walk"))
	assert_true(sprite.has_action("deer", "eat"))
	assert_true(sprite.has_action("deer", "idle"))


## Horse's current sheet has dedicated idle art of its own (not synthesized
## from an eat cycle's frame 0 like deer/boar) -- see has_action's own doc
## comment.
func test_has_action_true_for_walk_and_idle_on_horse():
	assert_true(sprite.has_action("horse", "walk"))
	assert_true(sprite.has_action("horse", "idle"))


## No dedicated attack art exists for any illustrated species (none of the
## three are predators), and attack's own lunge pose isn't well approximated
## by walk or idle the way swim/drink are (see the fallback tests below) --
## so it's the one action left with no illustrated fallback at all.
## CreatureMarker falls back to ProceduralAnimalAnimation for it, rather
## than crashing or showing nothing.
func test_attack_is_covered_by_illustrated_art():
	assert_true(sprite.has_action("horse", "attack"))


## Swimming has no dedicated art of its own on any sheet, but reuses the
## WALK cycle rather than falling all the way through to the procedural
## generator -- a moving illustrated body reads far closer to swimming than
## switching art style entirely does (reported: "when swimming the
## procedural generated horse shape is rendered instead of the illustrated
## one"). Applies to every registered species, not just horse.
func test_has_action_true_for_swim_via_walk_fallback():
	assert_true(sprite.has_action("horse", "swim"))
	assert_true(sprite.has_action("deer", "swim"))
	assert_true(sprite.has_action("boar", "swim"))


## Drinking has no dedicated art either, but reuses whatever "idle" itself
## resolves to -- a creature drinking is standing still, same as idle,
## whether that's real idle art (horse) or the synthesized eat-frame-0
## fallback (deer/boar).
func test_has_action_true_for_drink_via_idle_fallback():
	assert_true(sprite.has_action("horse", "drink"))
	assert_true(sprite.has_action("deer", "drink"))
	assert_true(sprite.has_action("boar", "drink"))


## Horse's current sheet has no eat/graze row at all (its idle/walk/trot/
## sit-hurt-death rows are all it has) -- unlike deer/boar, there's no eat
## cycle to even synthesize an idle frame from, so this is a real, honest
## gap: CreatureMarker falls back to ProceduralAnimalAnimation for a
## grazing horse.
func test_horse_has_dedicated_eat_art():
	assert_true(sprite.has_action("horse", "eat"))


func test_has_action_false_for_an_unregistered_species():
	assert_false(sprite.has_action("mouse", "walk"))


func test_generate_textures_returns_eight_walk_frames_for_horse():
	var textures := sprite.generate_textures("horse", "walk")
	assert_eq(textures.size(), 8)
	for texture in textures:
		assert_true(texture is ImageTexture)


## Horse's current sheet is a single walking row -- no idle row, no eat row.
## Idle synthesizes from the walk cycle's own frame 0 (the last link in the
## idle fallback chain: dedicated idle_bands, then eat frame 0, then walk
## frame 0) rather than regressing a standing horse to procedural art.
func test_generate_textures_returns_one_idle_frame_synthesized_from_walk_for_horse():
	assert_eq(sprite.generate_textures("horse", "idle").size(), 1)


## has_action already rejects "eat" for horse (see
## test_has_action_false_for_eat_on_horse) -- generate_textures must honor
## that and return nothing to animate, not throw digging for a missing key.
func test_generate_textures_returns_eight_eat_frames_for_horse():
	assert_eq(sprite.generate_textures("horse", "eat").size(), 8)


func test_generate_textures_returns_the_walk_frames_for_swim():
	assert_eq(sprite.generate_textures("horse", "swim").size(), sprite.generate_textures("horse", "walk").size())


## Drink resolves through whatever "idle" itself resolves to -- horse's own
## real 4-frame idle cycle here, not the single synthesized deer/boar pose
## (see test_generate_textures_returns_four_real_idle_frames_for_horse).
func test_generate_textures_returns_the_idle_frames_for_drink():
	assert_eq(sprite.generate_textures("horse", "drink").size(), sprite.generate_textures("horse", "idle").size())


func test_generate_textures_returns_the_synthesized_idle_frame_for_drink_when_no_real_idle_art_exists():
	assert_eq(sprite.generate_textures("deer", "drink").size(), 1)


func test_generate_textures_returns_eight_walk_frames_for_deer():
	assert_eq(sprite.generate_textures("deer", "walk").size(), 8)


func test_generate_textures_returns_eight_eat_frames_for_deer():
	assert_eq(sprite.generate_textures("deer", "eat").size(), 8)


func test_generate_textures_returns_eight_walk_frames_for_boar():
	assert_eq(sprite.generate_textures("boar", "walk").size(), 8)


func test_generate_textures_returns_six_eat_frames_for_boar():
	assert_eq(sprite.generate_textures("boar", "eat").size(), 8)


## For a species with no dedicated idle art (deer, boar), idle reuses a
## single frame (the eat cycle's own head-up/alert pose) rather than needing
## its own row -- see ProceduralAnimalAnimation's own "idle" precedent (a
## single static neutral pose for a creature that isn't moving). Horse has
## real idle art instead -- see
## test_generate_textures_returns_four_real_idle_frames_for_horse.
func test_deer_idle_is_a_single_held_pose():
	assert_eq(sprite.generate_textures("deer", "idle").size(), 1)


## Every frame comes back the same canvas size, regardless of which action or
## how much the source content's own bounding box varied -- CreatureMarker
## just swaps `texture` every animation tick and expects a stable frame size.
func test_every_frame_shares_the_same_canvas_size():
	var walk := sprite.generate_textures("horse", "walk")
	var idle := sprite.generate_textures("horse", "idle")
	var expected_size := walk[0].get_size()
	for texture in walk + idle:
		assert_eq(texture.get_size(), expected_size)


## Repeated calls must not re-load and re-slice the source image from disk
## every time -- see the class doc comment: many creature markers of the
## same species all want the exact same fixed frames.
func test_generate_textures_returns_the_same_cached_instance_on_repeated_calls():
	var first := sprite.generate_textures("horse", "walk")
	var second := sprite.generate_textures("horse", "walk")
	assert_eq(first[0], second[0])


## The baseline sits below the canvas's own vertical center (feet are lower
## on the canvas than its middle, matching every frame's own padding above
## the figure) -- and every registered species shares the exact same value,
## since they all share one canvas/baseline convention (see the class doc
## comment): this is one constant, not something computed per species.
func test_ground_offset_y_is_below_canvas_center_and_shared_across_species():
	var offset := sprite.ground_offset_y()
	assert_gt(offset, 0.0, "the ground/feet row should sit below the canvas's own vertical center")
	assert_eq(sprite.ground_offset_y(), offset, "the same fixed offset regardless of which species asks")


## Where the water surface sits for a swimming creature, as a local-space Y
## offset from the marker's own origin -- the DRAWN body's own vertical
## centre, so "half submerged" falls out of the art itself rather than a
## hand-tuned fraction (the same reasoning as the player's own waterline,
## see CharacterView). Must land strictly between the top of the art and
## the feet, or the creature would render either fully dry or fully drowned.
func test_waterline_offset_sits_between_the_top_of_the_body_and_the_feet():
	var offset := sprite.waterline_offset_y("horse")
	var feet := sprite.ground_offset_y()
	var canvas_top := -float(IllustratedAnimalSprite.CANVAS_SIZE.y) * 0.5
	assert_lt(offset, feet, "the waterline must be above the feet, not below them")
	assert_gt(offset, canvas_top, "the waterline must be below the top of the canvas")


func test_marker_scale_is_positive():
	assert_gt(sprite.marker_scale("horse", "walk"), 0.0)
	assert_gt(sprite.marker_scale("deer", "walk"), 0.0)


## An action can come from its OWN file at its OWN resolution: horse's idle
## art is a separate 1536x1024 sprite whose animal is ~1110px wide, against
## the walk sheet's ~263px. A single per-species scale would balloon the
## horse ~4x the instant it stopped moving. Scale is therefore measured per
## ACTION, so every action of a species renders at the same apparent size no
## matter what resolution its source art happens to be.
func test_idle_and_walk_render_at_the_same_apparent_size():
	var idle := _content_width(sprite.generate_textures("horse", "idle")[0]) * sprite.marker_scale("horse", "idle")
	var walk := _content_width(sprite.generate_textures("horse", "walk")[0]) * sprite.marker_scale("horse", "walk")
	assert_almost_eq(idle, walk, walk * 0.02, "a horse must not change size when it stops walking")


## Species whose actions all come from one sheet must be unaffected.
func test_per_action_scaling_leaves_a_single_sheet_species_consistent():
	var idle := _content_width(sprite.generate_textures("deer", "idle")[0]) * sprite.marker_scale("deer", "idle")
	var walk := _content_width(sprite.generate_textures("deer", "walk")[0]) * sprite.marker_scale("deer", "walk")
	assert_almost_eq(idle, walk, walk * 0.02)


## marker_scale's own formula (BASE_WORLD_WIDTH * world_scale /
## reference_content_width) makes a species' actual rendered content width
## -- reference_content_width times marker_scale -- work out to exactly
## BASE_WORLD_WIDTH * world_scale, with reference_content_width canceling
## out entirely (see marker_scale's own doc comment). That means raw
## marker_scale VALUES themselves are NOT comparable across species with
## different sheets: a sheet with a narrower reference frame needs a
## bigger raw multiplier to reach the same on-screen size, an artifact of
## that sheet's own pixel density, not of how big the species actually is
## (this bit a real comparison here once before: horse's own sheet swap
## changed its reference_content_width enough to flip a same-shaped raw-
## marker_scale check even though horse still renders visibly bigger).
## What's actually comparable is the real rendered content width once
## marker_scale is applied -- measured here from each species' own frame's
## opaque-pixel extent, not assumed from the formula.
func test_marker_scale_produces_a_bigger_on_screen_width_for_a_bigger_species():
	var horse_width := _content_width(sprite.generate_textures("horse", "idle")[0]) * sprite.marker_scale("horse")
	var deer_width := _content_width(sprite.generate_textures("deer", "walk")[0]) * sprite.marker_scale("deer")
	assert_gt(horse_width, deer_width, "a horse should render visibly wider on screen than a deer")


func _content_width(texture: ImageTexture) -> float:
	var image := texture.get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return float(max_x - min_x + 1)


# -- boar: dedicated walk/idle/eat art, and no procedural swap on attack ----

func test_boar_uses_its_own_dedicated_art_for_walk_idle_and_eat():
	assert_eq(sprite.generate_textures("boar", "walk").size(), 8)
	assert_eq(sprite.generate_textures("boar", "eat").size(), 8)
	assert_eq(sprite.generate_textures("boar", "idle").size(), 1)


func test_horse_now_has_its_own_eat_art():
	assert_true(sprite.has_action("horse", "eat"))
	assert_eq(sprite.generate_textures("horse", "eat").size(), 8)


## Attack was the last action still dropping an illustrated species back to
## ProceduralAnimalSprite, so a charging boar visibly changed art style
## mid-lunge (reported: "when the boar is attacking it switches to old
## procedural sprite"). There is no dedicated attack art, but a charge is a
## fast run -- reusing the walk cycle keeps the creature ITSELF on screen,
## which beats swapping to a different rendering of a different animal.
## Same reasoning as swim's walk fallback.
func test_attack_falls_back_to_illustrated_walk_rather_than_procedural():
	for species in ["boar", "horse", "deer"]:
		assert_true(sprite.has_action(species, "attack"), "%s must not fall back to procedural art" % species)
		assert_eq(
			sprite.generate_textures(species, "attack").size(),
			sprite.generate_textures(species, "walk").size()
		)


## Every action of a species renders at the same apparent size even though
## boar's idle art is a separate, much larger file (1536x1024) than its
## walk/eat sheets -- see marker_scale's per-action measurement.
func test_boar_actions_all_render_at_the_same_apparent_size():
	var idle := _content_width(sprite.generate_textures("boar", "idle")[0]) * sprite.marker_scale("boar", "idle")
	var walk := _content_width(sprite.generate_textures("boar", "walk")[0]) * sprite.marker_scale("boar", "walk")
	var eat := _content_width(sprite.generate_textures("boar", "eat")[0]) * sprite.marker_scale("boar", "eat")
	assert_almost_eq(idle, walk, walk * 0.02, "a boar must not change size when it stops walking")
	assert_almost_eq(eat, walk, walk * 0.02, "nor when it starts eating")


## Which way a sheet is DRAWN is a property of the supplied asset, and it has
## changed under us before: boar's new per-action sheets face left where the
## single boar.png they replaced faced right. Declaring it wrong renders the
## creature mirrored, so it walks backwards in every direction (the horse
## shipped that way). Pinned per species so a future art swap that flips
## facing fails loudly here instead of silently in game.
func test_each_sheets_declared_facing_matches_its_art():
	assert_true(sprite.faces_left("horse"), "horse art is drawn facing left")
	assert_true(sprite.faces_left("boar"), "boar's new sheets are drawn facing left")
	assert_true(sprite.faces_left("deer"), "deer's new sheets are drawn facing left")


## Deer now has per-action files too, at three different resolutions
## (1774x887 walk, 1536x1024 idle portrait, 2172x724 eat) -- the per-action
## scale measurement must keep them all the same apparent size.
func test_deer_actions_all_render_at_the_same_apparent_size():
	var idle := _content_width(sprite.generate_textures("deer", "idle")[0]) * sprite.marker_scale("deer", "idle")
	var walk := _content_width(sprite.generate_textures("deer", "walk")[0]) * sprite.marker_scale("deer", "walk")
	var eat := _content_width(sprite.generate_textures("deer", "eat")[0]) * sprite.marker_scale("deer", "eat")
	assert_almost_eq(idle, walk, walk * 0.02)
	assert_almost_eq(eat, walk, walk * 0.02)


## Every illustrated species now has dedicated walk/idle/eat art of its own.
func test_all_three_species_have_dedicated_walk_idle_and_eat_art():
	for species in ["horse", "boar", "deer"]:
		for action in ["walk", "idle", "eat"]:
			assert_gt(
				sprite.generate_textures(species, action).size(), 0,
				"%s should have real %s art" % [species, action]
			)
