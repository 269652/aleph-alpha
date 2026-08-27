extends GutTest

## A single wild-crop patch cell in the world (see docs/concept/wild_crops.md,
## CropPull, IllustratedCropSprite, ProceduralSoilSprite). Growth is read-only
## from the marker's own perspective (the renderer pushes it in via
## set_growth, mirroring ChoppableTree.set_age's "the sim/renderer decides,
## the node just draws" split) -- only begin_pull mutates anything, and only
## once the harvest actually completes (see on_harvested).

const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")
const CropPull = preload("res://src/gameplay/crop_pull.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")

var marker: WildCropMarker
var _drops: Array = []
var _harvested_count := 0


func before_each():
	marker = WildCropMarker.new()
	marker.crop_id = "carrot"
	marker.sprite_seed = 3
	_drops = []
	_harvested_count = 0
	WorldItemBus.item_dropped.connect(_record_drop)


func after_each():
	if is_instance_valid(marker):
		marker.free()
	if WorldItemBus.item_dropped.is_connected(_record_drop):
		WorldItemBus.item_dropped.disconnect(_record_drop)


func _record_drop(stack, _position) -> void:
	_drops.append(stack)


func test_joins_the_group_and_dropped_item_hoverable_group():
	add_child_autofree(marker)
	assert_true(marker.is_in_group(WildCropMarker.GROUP_NAME))
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


# -- name reflects growth stage ----------------------------------------------

func test_display_name_seedling():
	marker.growth = 0.0
	add_child_autofree(marker)
	assert_eq(marker.get_display_name(), "Carrot Sprout")


func test_display_name_vegetative():
	marker.growth = 0.5
	add_child_autofree(marker)
	assert_eq(marker.get_display_name(), "Carrot Plant")


func test_display_name_mature():
	marker.growth = 1.0
	add_child_autofree(marker)
	assert_eq(marker.get_display_name(), "Carrot")


func test_display_name_for_potato():
	marker.crop_id = "potato"
	marker.growth = 1.0
	add_child_autofree(marker)
	assert_eq(marker.get_display_name(), "Potato")


# -- only a mature, not-already-pulling patch is pullable --------------------

func test_immature_patch_offers_no_actions():
	marker.growth = 0.5
	add_child_autofree(marker)
	assert_eq(marker.get_hover_actions().size(), 0)


func test_mature_patch_offers_pull_bound_to_attack():
	marker.growth = 1.0
	add_child_autofree(marker)
	var actions := marker.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["verb"], "Pull")
	assert_eq(actions[0]["action"], "attack")


func test_is_mature_true_only_at_full_growth():
	marker.growth = 0.99
	add_child_autofree(marker)
	assert_false(marker.is_mature())
	marker.growth = 1.0
	assert_true(marker.is_mature())


func test_begin_pull_fails_on_an_immature_patch():
	marker.growth = 0.5
	add_child_autofree(marker)
	assert_false(marker.begin_pull())


func test_begin_pull_succeeds_on_a_mature_patch():
	marker.growth = 1.0
	add_child_autofree(marker)
	assert_true(marker.begin_pull())


func test_a_second_begin_pull_while_already_pulling_fails():
	marker.growth = 1.0
	add_child_autofree(marker)
	assert_true(marker.begin_pull())
	assert_false(marker.begin_pull())


func test_pulling_removes_its_own_hover_actions():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	assert_eq(marker.get_hover_actions().size(), 0)


# -- the pull itself: a real animated duration, then a real dropped item ----

func test_pull_does_not_finish_before_crop_pull_duration_elapses():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.5)
	assert_false(marker.is_queued_for_deletion())
	assert_eq(_drops.size(), 0)


func test_pull_finishes_and_drops_the_harvested_item():
	marker.growth = 1.0
	marker.position = Vector2(200, 300)
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS + 0.01)
	assert_eq(_drops.size(), 1)
	assert_eq(_drops[0].item.id, "carrot")
	assert_true(marker.is_queued_for_deletion())


func test_pull_finishing_calls_on_harvested_before_freeing():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.on_harvested = func(): _harvested_count += 1
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS + 0.01)
	assert_eq(_harvested_count, 1)


func test_process_is_a_no_op_when_not_pulling():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker._process(1000.0)
	assert_false(marker.is_queued_for_deletion())
	assert_eq(_drops.size(), 0)


# -- soil sizing + the "buried, then gradually revealed" composition --------
#
# Reported live: the soil mound rendered at ~1.5 tiles wide (no scale
# applied at all), and the root/tuber was visible even while still planted
# (should be entirely hidden underground, only leaves showing). Fixed by
# assembling leaves+root as one entity from _ready() -- not lazily built at
# begin_pull() -- with the root's reveal driven by a region_rect that grows
# from nothing to the full root art exactly as CropPull's rise progresses,
# so it visibly emerges from the ground as it's pulled rather than popping
## instantly visible the moment the swing lands.

func test_soil_is_scaled_to_its_declared_world_width():
	marker.growth = 1.0
	add_child_autofree(marker)
	assert_almost_eq(marker._soil.scale.x, ProceduralSoilSprite.SOIL_WORLD_SCALE, 0.0001)


func test_root_is_assembled_from_the_start_but_fully_hidden():
	marker.growth = 0.5  # even immature -- the root art exists, just clipped away
	add_child_autofree(marker)
	assert_not_null(marker._root.texture, "the root should be composed in from the start")
	assert_true(marker._root.region_enabled)
	assert_eq(marker._root.region_rect.size.y, 0.0, "nothing of the root shows while planted")


func test_pull_partway_reveals_part_of_the_root():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	var elapsed := CropPull.DURATION_SECONDS * 0.5
	marker._process(elapsed)
	var expected_height: float = CropPull.progress_at(elapsed) * IllustratedCropSprite.ROOT_CANVAS_SIZE.y
	assert_almost_eq(marker._root.region_rect.size.y, expected_height, 0.01)
	assert_gt(marker._root.region_rect.size.y, 0.0)
	assert_lt(marker._root.region_rect.size.y, float(IllustratedCropSprite.ROOT_CANVAS_SIZE.y))


func test_pull_reveals_the_full_root_by_the_time_it_completes():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.999)  # not yet finalized/freed
	assert_almost_eq(
		marker._root.region_rect.size.y, float(IllustratedCropSprite.ROOT_CANVAS_SIZE.y), 0.5
	)


# -- the root's CROWN stays anchored to the leaves, not centred on the ------
# -- marker and not drifting away as more of it reveals ---------------------
#
# Two live reports, in sequence, on the same growing region_rect:
#
# 1. "potato fruits are still rendered above soil and not buried" --
#    Sprite2D defaults to `centered = true`, so the growing region straddled
#    the marker's own origin, half below ground, half above. Fixed by turning
#    `centered` off.
# 2. "carrots/potatoes render a huge blob behind the leaves" -- the first
#    fix's own offset ALSO shifted vertically by `-revealed_height` every
#    frame to keep the region's BOTTOM edge pinned at the ground line. That
#    correctly avoided straddling at any single instant, but it moved the
#    CROWN itself (texture y=0, where the root attaches to the leaves --
#    see IllustratedCropSprite's baseline-anchoring convention and
#    CropPull.root_reveal_rect's own doc comment) further from the leaf
#    cluster the more of the root became revealed, since a taller revealed
#    slice needs a bigger upward shift to keep ITS bottom fixed. The crown
#    should never move -- it is still attached to the leaves throughout the
#    whole pull. Fixed by pinning the OFFSET once (see CropPull.
#    root_reveal_offset), so the region's TOP edge -- the crown -- stays at
#    the marker's local origin, and only the newly-revealed shaft/tip
#    extends downward from that fixed point as the region grows.

func test_root_sprite_is_not_centered():
	add_child_autofree(marker)
	assert_false(
		marker._root.centered, "centered=true would straddle the ground line instead of growing off it"
	)


func test_freshly_planted_roots_crown_sits_exactly_on_the_ground_line():
	marker.growth = 1.0
	add_child_autofree(marker)
	# Nothing revealed yet (region height 0) -- the crown-pinning offset
	# should already sit at the ground line, not wherever centering would
	# have put a zero-height rect.
	assert_eq(marker._root.offset.y, 0.0)


func test_partly_revealed_roots_crown_stays_on_the_ground_line():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.5)
	# The drawn quad spans [offset.y, offset.y + region_rect.size.y] in the
	# root's own local space -- its TOP edge (offset.y) -- the crown -- must
	# stay exactly at the marker's ground line (0), for every crop, every
	# progress value, not just the one carrot happened to look acceptable at.
	assert_almost_eq(marker._root.offset.y, 0.0, 0.01)


func test_fully_revealed_roots_crown_still_stays_on_the_ground_line():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.999)
	assert_almost_eq(marker._root.offset.y, 0.0, 0.01)


## The exact regression this test guards against: at full reveal, the
## crown must NOT have drifted away from the ground line by the whole
## scaled canvas height (the actual "huge blob behind the leaves" bug).
func test_root_offset_does_not_drift_as_more_of_it_is_revealed():
	marker.growth = 1.0
	add_child_autofree(marker)
	var offset_before_pull := marker._root.offset.y
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.999)
	assert_eq(marker._root.offset.y, offset_before_pull)


func test_root_offset_stays_horizontally_centred_on_the_soil():
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.5)
	assert_almost_eq(marker._root.offset.x, -float(IllustratedCropSprite.ROOT_CANVAS_SIZE.x) / 2.0, 0.01)


## Same ground-anchoring invariant, but for potato specifically -- the crop
## actually reported broken, so the fix must hold for it, not just carrot.
func test_potato_roots_crown_also_stays_on_the_ground_line():
	marker.crop_id = "potato"
	marker.growth = 1.0
	add_child_autofree(marker)
	marker.begin_pull()
	marker._process(CropPull.DURATION_SECONDS * 0.5)
	assert_almost_eq(marker._root.offset.y, 0.0, 0.01)


# -- the tops carry the season, the root does not ----------------------------

## A wild carrot used to stand bright green-topped in deep winter under a
## tree that had correctly gone bare. The LEAVES take the same SeasonalFoliage
## tint the grass around them and the ground under them wear; the root does
## not, because a stored tuber underground is not what the frost reaches
## (see docs/concept/wild_crops.md "The season").
func test_the_leaves_wear_the_seasons_tint_and_the_pulled_root_does_not():
	add_child_autofree(marker)
	var winter := SeasonalFoliage.tint_for_season("winter")
	marker.season_tint = winter
	assert_eq(marker._leaves.modulate, winter, "the tops go over")
	assert_eq(marker._root.modulate, Color.WHITE, "the tuber underground does not")


## Same "set before the node is in the tree" convention `growth`/`crop_id`
## already use -- the renderer sets everything before add_child.
func test_a_season_set_before_ready_still_lands_on_the_leaves():
	var autumn := SeasonalFoliage.tint_for_season("autumn")
	marker.season_tint = autumn
	add_child_autofree(marker)
	assert_eq(marker._leaves.modulate, autumn)


## Untouched by default, so nothing that never pushes a season renders
## differently than it does today.
func test_a_marker_nobody_told_about_the_season_renders_exactly_as_before():
	add_child_autofree(marker)
	assert_eq(marker.season_tint, Color.WHITE)
	assert_eq(marker._leaves.modulate, Color.WHITE)
