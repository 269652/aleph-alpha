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

	_soil = Sprite2D.new()
	_soil.texture = ProceduralSoilSprite.new().generate_texture(false)
	_soil.scale = Vector2.ONE * ProceduralSoilSprite.SOIL_WORLD_SCALE
	add_child(_soil)

	_lift = Node2D.new()
	add_child(_lift)

	_leaves = Sprite2D.new()
	_leaves.scale = Vector2.ONE * IllustratedCropSprite.LEAF_WORLD_SCALE
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
	_root.scale = Vector2.ONE * IllustratedCropSprite.ROOT_WORLD_SCALE
	_root.region_enabled = true
	_lift.add_child(_root)
	_reveal_root(0.0)

	_redraw_leaves()


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
func _reveal_root(progress: float) -> void:
	var revealed_height := progress * float(IllustratedCropSprite.ROOT_CANVAS_SIZE.y)
	_root.region_rect = Rect2(Vector2.ZERO, Vector2(IllustratedCropSprite.ROOT_CANVAS_SIZE.x, revealed_height))


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	var label := crop_id.capitalize()
	match IllustratedCropSprite.growth_stage_index(growth):
		0:
			return "%s Sprout" % label
		1:
			return "%s Plant" % label
		_:
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
	_soil.texture = ProceduralSoilSprite.new().generate_texture(true)
	return true


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
	var item := (
		_item_catalog.make(crop_id) if _item_catalog.has(crop_id)
		else Item.new(crop_id, crop_id.capitalize(), "food", 20)
	)
	WorldItemBus.item_dropped.emit(ItemStack.new(item, 1), position)
	queue_free()
