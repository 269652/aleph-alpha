extends Node2D

## A single wild-crop patch cell in the world -- soil mound, growth-staged
## leaves, and (once pulled) the harvested root, composited exactly per
## docs/concept/wild_crops.md / ai_sprite_prompts.md section 2's "genuinely
## composite" kit. Deliberately NOT responsible for its own growth or
## simulation state (see WildCropPatch) -- the renderer pushes growth in via
## `growth` (mirroring ChoppableTree.set_age's "the sim/renderer decides,
## the node just draws" split), and `on_harvested` is how a completed pull
## reports back to remove this cell from its owning sim, so this marker
## itself never needs to know WildCropPatch's own API.
##
## Same no-per-frame-cost-until-needed shape as ChoppableTree/SmashableStone/
## MinableOre: _process only does real work while a pull is actually in
## progress.

const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")
const CropPull = preload("res://src/gameplay/crop_pull.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

const GROUP_NAME := "wild_crop"

## How much Root Vigor scales a specimen's REAL mass, at either end of
## vigor's 0..1 range -- a real, ordinary garden root crop's own
## specimen-to-specimen size spread (a small carrot/potato from a mixed
## harvest running noticeably lighter than a prize one, not a freak
## outlier), not an eyeballed number: symmetric around 1.0 so the
## population's own mean vigor (0.5, see WildCropPatch.get_vigor's default)
## reproduces exactly the pre-vigor reference mass every existing caller
## already expects (see test_default_vigor_renders_leaves_at_their_
## ordinary_base_scale / _finish_pull). Pinned by
## test_vigor_mass_multiplier_is_the_identity_at_the_populations_own_mean.
const MIN_VIGOR_MASS_MULTIPLIER := 0.7
const MAX_VIGOR_MASS_MULTIPLIER := 1.3

## Root Vigor's effect on a specimen's real mass, 0..1 -> the multiplier
## range above. Static + public: _finish_pull uses this on the actual
## harvested mass, and _apply_vigor_scale derives the LEAVES' visual scale
## from the same number (a real vegetable that masses more is bigger, not
## a second, independently-tuned "how much do bigger vigor leaves look
## bigger" figure).
static func vigor_mass_multiplier(vigor: float) -> float:
	return lerpf(MIN_VIGOR_MASS_MULTIPLIER, MAX_VIGOR_MASS_MULTIPLIER, vigor)

## What share of the seeding distribution counts as a "Prize" specimen --
## the top (1 - PRIZE_VIGOR_PERCENTILE) share of WildCropPatch's own
## seeding formula (the average of two salted-hash draws, VIGOR_BELL_HALVES
## in wild_crop_patch.gd -- a triangular distribution on [0, 1], NOT flat).
## PRIZE_VIGOR_THRESHOLD is the closed-form value that makes this true: for
## that triangular distribution, P(X <= x) = 1 - 2*(1-x)^2 for x >= 0.5, so
## solving 1 - 2*(1-x)^2 == PRIZE_VIGOR_PERCENTILE for x gives the formula
## below. Verified against an empirical sample of the real seeding formula
## (not just the algebra) by
## test_prize_threshold_actually_selects_about_the_top_decile_of_seeded_vigor.
const PRIZE_VIGOR_PERCENTILE := 0.9
const PRIZE_VIGOR_THRESHOLD := 0.7763932022500211  # 1.0 - sqrt((1.0 - PRIZE_VIGOR_PERCENTILE) / 2.0)

## "carrot" or "potato" -- which sheet/item this cell grows. Set before
## add_child, same convention as LiftableStone.diameter_cm/stone_seed.
var crop_id := ""
## Deterministic per-cell seed, picking which root/tuber color variant this
## particular plant yields.
var sprite_seed := 0

## How grown this plant is, 0..1 -- pushed in by the renderer on its own
## refresh cadence (see EarthChunkManager.step_wild_crops), not read live
## from a sim reference this node holds itself.
var growth: float = 0.0:
	set(value):
		growth = value
		_redraw_leaves()

## The season's tint on this plant's LEAVES (see SeasonalFoliage) -- pushed in
## by the renderer on the same refresh cadence `growth` is, never read live
## from a clock this node holds itself. A root crop's TOPS are what the season
## touches; the tuber underground is unchanged, which is why the root sprite
## is deliberately left alone and a mature crop stays pullable all winter (see
## docs/concept/wild_crops.md "The season"). Identity by default, so a caller
## that never mentions the season renders exactly today's picture.
var season_tint := Color.WHITE:
	set(value):
		season_tint = value
		_apply_season_tint()

## Root Vigor (see docs/concept/wild_crops.md's "Root Vigor" section and
## WildCropPatch.get_vigor) -- a heritable size/quality trait, pushed in by
## the renderer at spawn time exactly the way `growth`/`season_tint` are,
## never read live from a sim reference this node holds itself. Defaults to
## 0.5 (the population's own mean) so a hand-built marker in a test/diorama
## draws and harvests at the population's average size, not an accidental
## runt or giant.
var vigor: float = 0.5:
	set(value):
		vigor = value
		_apply_vigor_scale()

## Invoked once, right before this marker frees itself, so whatever spawned
## it (WildCropRenderer) can remove this cell from its owning WildCropPatch.
## Left unset (a no-op) for isolated tests/callers that don't need it.
var on_harvested: Callable

static var _illustrated := IllustratedCropSprite.new()
static var _item_catalog := ItemCatalog.new()

var _soil: Sprite2D
var _lift: Node2D
var _leaves: Sprite2D
var _root: Sprite2D
var _drawn_stage := -1  # -1 == never drawn, so the first set always redraws

var _pulling := false
var _pull_elapsed := 0.0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	# A crop that is not being pulled has nothing to do per frame, and there
	# are ~700 of them loaded at once: the engine's ~7 us of dispatch into
	# an early-returning _process, times that many, every frame, was ~5 ms
	# of every frame (FPS regression round 13). Frames are switched on for
	# the pull animation only (begin_pull) and off again when it finishes.
	set_process(false)

	_soil = Sprite2D.new()
	_soil.texture = ProceduralSoilSprite.new().generate_texture(false)
	_soil.scale = Vector2.ONE * ProceduralSoilSprite.SOIL_WORLD_SCALE
	# Hidden while the plant is simply GROWING. A tilled mound is a farming
	# artifact and this is a WILD plant -- reported live: "the potatoes and
	# carrots still render a brown blob which is not supposed to be there".
	# Two earlier passes read that as a sizing bug and shrank the mound; the
	# mound itself was the problem, since a wild carrot in a meadow grows
	# straight out of the grass (wild_crops.md is explicit that player-tilled
	# farming does not exist yet). Kept as a real child rather than dropped
	# outright because the PULL earns it: yanking a root really does tear up
	# the earth, and that swap is the harvest animation's own ground-level
	# feedback (see begin_pull).
	_soil.visible = false
	add_child(_soil)

	_lift = Node2D.new()
	add_child(_lift)

	_leaves = Sprite2D.new()
	_lift.add_child(_leaves)

	# Leaves+root are assembled as ONE entity from the start, not built
	# lazily at begin_pull() -- the root's full art is already loaded, just
	# entirely clipped away (region_rect height 0) so nothing of it shows
	# while planted (reported live: the root was visible even before being
	# pulled). A region_rect that grows from 0 up to the full art height,
	# revealing from the TOP of the canvas down (see IllustratedCropSprite's
	# normalize_frames convention: content is baseline-anchored near the
	# canvas bottom, so the top-down reveal order is crown-first,
	# tip-last -- physically correct for something being drawn up out of
	# the ground), is what actually shows it emerging as CropPull's rise
	# progresses (see _reveal_root) -- not a hard instant visible/invisible
	# flip at the moment the swing lands.
	_root = Sprite2D.new()
	_root.texture = _illustrated.root_texture(crop_id, sprite_seed)
	_root.scale = Vector2.ONE * _illustrated.root_world_scale(crop_id)
	_root.region_enabled = true
	# NOT centered: see _reveal_root's own doc comment -- the grown region
	# has to stay pinned to the ground line by its own BOTTOM edge, not
	# straddle the marker's origin the way a centered growing rect would.
	_root.centered = false
	# Horizontal centering only, set ONCE -- see CropPull.root_reveal_offset's
	# own doc comment for why this must NOT depend on progress (the actual
	# "huge blob behind the leaves" bug: a per-frame vertical shift here
	# used to push the crown away from the leaves as more of the root
	# revealed).
	_root.offset = CropPull.root_reveal_offset(IllustratedCropSprite.ROOT_CANVAS_SIZE)
	_lift.add_child(_root)
	_reveal_root(0.0)

	_redraw_leaves()
	# Catches up a season/vigor set before this node was in the tree (the
	# renderer sets crop_id/growth/vigor/season_tint before add_child),
	# exactly the way _redraw_leaves above catches up a growth set the same
	# way.
	_apply_season_tint()
	_apply_vigor_scale()


func _process(delta: float) -> void:
	if not _pulling:
		return
	_pull_elapsed += delta
	var progress := CropPull.progress_at(_pull_elapsed)
	_lift.position = CropPull.rise_offset_at(_pull_elapsed)
	_reveal_root(progress)
	if CropPull.is_complete(_pull_elapsed):
		_finish_pull()


## How much of the root's art is currently uncovered, 0 (nothing, still
## fully buried) to 1 (the whole root, fully clear of the ground).
##
## Reported live, twice: first "potato fruits are still rendered above soil
## and not buried" (fixed by pinning the growing region to `centered =
## false` -- see _ready), then "carrots/potatoes render a huge blob behind
## the leaves" -- that first fix's own offset ALSO shifted vertically by
## `-revealed_height` every frame, which correctly pinned the region's
## bottom edge to the ground at any single instant, but meant the crown's
## own drawn position climbed steadily higher as revealed_height grew,
## since a taller revealed slice needs a bigger upward shift to keep its
## bottom at y=0. The crown -- where the root attaches to the leaves --
## ended up floating further and further from the leaf cluster as the pull
## progressed instead of staying anchored to it. See
## CropPull.root_reveal_rect/root_reveal_offset: offset is now set ONCE in
## _ready (horizontal centering only), and only the region_rect grows here,
## so the crown never moves -- the root now visibly hangs below the leaves
## it's still attached to, growing more visible from that fixed point.
func _reveal_root(progress: float) -> void:
	_root.region_rect = CropPull.root_reveal_rect(IllustratedCropSprite.ROOT_CANVAS_SIZE, progress)


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	var label := crop_id.capitalize()
	match IllustratedCropSprite.growth_stage_index(growth):
		0:
			return "%s Sprout" % label
		1:
			return "%s Plant" % label
		_:
			if vigor >= PRIZE_VIGOR_THRESHOLD:
				return "Prize %s" % label
			return label


## For World's mouse-hover tooltip (see HoverTargetFinder). Only a mature,
## not-already-pulling patch offers anything -- pulling a seedling does
## nothing, same "young shoots tear uselessly" rule harvest_grass_near
## already applies to immature grass.
func get_hover_actions() -> Array:
	if not is_mature():
		return []
	return [{"verb": "Pull", "action": "attack"}]


func is_mature() -> bool:
	return growth >= 1.0 and not _pulling


## Starts the pull: swaps the soil to its disturbed look and begins the
## CropPull rise + root reveal (see _process). Returns whether a pull
## actually started -- false for an immature patch or one already mid-pull.
func begin_pull() -> bool:
	if not is_mature():
		return false
	_pulling = true
	_pull_elapsed = 0.0
	set_process(true)
	# The ground only shows once something has actually been yanked out of
	# it -- see _ready for why it stays hidden while the plant just grows.
	_soil.visible = true
	_soil.texture = ProceduralSoilSprite.new().generate_texture(true)
	return true


## Nudges the LEAVES' scale by vigor (see vigor_mass_multiplier) -- a bigger
## real vegetable comes from a visibly bigger plant. Mass scales with
## VOLUME, so the LINEAR scale a Sprite2D draws at only needs the cube root
## of the mass multiplier -- a real physical relationship, not a second
## independently-eyeballed visual range. The root's own scale is left alone
## on purpose: it is drawn at art scale, not vigor scale, matching this
## marker's existing convention that the root's art (unlike the leaves) is
## never touched by anything but the pull reveal itself.
func _apply_vigor_scale() -> void:
	if _leaves == null:
		return  # not _ready() yet -- the end of _ready() catches up
	var linear_multiplier := pow(vigor_mass_multiplier(vigor), 1.0 / 3.0)
	_leaves.scale = Vector2.ONE * _illustrated.leaf_world_scale(crop_id) * linear_multiplier


func _apply_season_tint() -> void:
	if _leaves == null:
		return  # not _ready() yet -- the end of _ready() catches up
	_leaves.modulate = season_tint


func _redraw_leaves() -> void:
	if _leaves == null:
		return  # not _ready() yet -- the end of _ready() catches up
	var stage := IllustratedCropSprite.growth_stage_index(growth)
	if stage == _drawn_stage:
		return
	_drawn_stage = stage
	_leaves.texture = _illustrated.leaf_texture(crop_id, stage)


## The rise completes: the harvested root becomes a real ground item (see
## WorldItemBus/World._on_item_dropped, the same path a felled tree's wood
## or a mined boulder's ore already uses) carrying the illustrated root
## texture the player just watched rise out of the ground (see
## DroppedItem._ready()'s own has_crop preference) -- not an instant
## straight-to-inventory grant.
func _finish_pull() -> void:
	if on_harvested.is_valid():
		on_harvested.call()
	var item: Item
	if _item_catalog.has(crop_id):
		# _mass_kg_for (which resolves crop_id's real reference mass, e.g.
		# carrot 0.07kg / potato 0.17kg) is private to ItemCatalog -- make()
		# is the public way to get at that reference Item, whose own
		# mass_kg field is public (see Item.mass_kg). Root Vigor scales
		# THAT real reference mass, then make_with_mass carries the result
		# into a real Item the same way EarthChunkManager.catch_nearest_fish
		# already does for a caught fish's own individually-known mass.
		var reference := _item_catalog.make(crop_id)
		item = _item_catalog.make_with_mass(crop_id, reference.mass_kg * vigor_mass_multiplier(vigor))
	else:
		item = Item.new(crop_id, crop_id.capitalize(), "food", 20)
	WorldItemBus.item_dropped.emit(ItemStack.new(item, 1), position)
	set_process(false)
	queue_free()
