extends Sprite2D

## An item lying on the ground: a visible, procedurally-drawn sprite holding an
## ItemStack. Its name only shows on mouse hover, via World's shared hover
## tooltip (see HoverTargetFinder/get_display_name/get_hover_actions) -- it
## used to float an always-on name label above every dropped item
## (Path-of-Exile style), which cluttered the ground with labels for every
## windfall and pebble lying around. Click the icon to pick it up. There is
## deliberately no proximity auto-pickup; walking past a dropped item leaves
## it alone until the player actually clicks it. Picking up merges the stack
## into the player's inventory and frees this node; if the inventory has no
## room the node stays (with whatever didn't fit).

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")

const GROUP_NAME := "dropped_item"
## Un-picked-up items despawn after this many seconds so the ground doesn't
## fill up with forage over a long session.
const LIFETIME := 90.0

## How long THIS item lasts before it goes.
##
## Food overrides it with a real shelf life (see FruitSpoilage): a windfall
## should be worth walking back for and then be gone, and a nut in its shell
## should still be there long after the cherries beside it have rotted.
## Anything that is not food keeps the flat despawn, which is a tidiness rule
## rather than a spoilage one.
var spoil_seconds := LIFETIME

## Whether this item ages on WORLD time rather than wall-clock time.
##
## Food does. Rot is a thing the seasons do, so it has to run on the same clock
## as the seasons -- otherwise a run of /ecotest sweeps a year past a windfall
## that has aged ninety seconds, and fruit that should have rotted in autumn is
## still sitting there in spring.
var ages_on_world_time := false

const CLICK_AREA_SIZE := Vector2(64.0, 32.0)
const CLICK_AREA_OFFSET_Y := -8.0

static var _sprite_generator := ProceduralItemSprite.new()
static var _crop_sprite_generator := IllustratedCropSprite.new()

var item_stack
var _age := 0.0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	if item_stack != null and texture == null:
		# A pulled wild carrot/potato uses the real illustrated root art (see
		# docs/concept/wild_crops.md) -- the same texture the player just
		# watched rise out of the ground during the pull, not a different
		# fallback sprite once it lands. Checked first, ahead of the generic
		# procedural path every other item still uses.
		if _crop_sprite_generator.has_crop(item_stack.item.id):
			texture = _crop_sprite_generator.root_texture(item_stack.item.id, 0)
			scale = Vector2.ONE * _crop_sprite_generator.root_world_scale(item_stack.item.id)
		else:
			texture = _sprite_generator.texture_for(item_stack.item.id)
			# Item art is authored DETAIL_MULTIPLIER times oversized; scaling
			# it back keeps a dropped item the right size on the ground (see
			# docs/concept/art_resolution.md). Tree fruit additionally has its
			# own per-species world width, because at the shared scale a
			# fallen cherry was as wide as the tile it lay on -- see
			# ProceduralItemSprite.world_scale_for.
			scale = Vector2.ONE * _sprite_generator.world_scale_for(item_stack.item.id)

	var click_area := Area2D.new()
	var collision_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = CLICK_AREA_SIZE
	collision_shape.shape = shape
	collision_shape.position = Vector2(0, CLICK_AREA_OFFSET_Y)
	click_area.add_child(collision_shape)
	click_area.input_event.connect(_on_input_event)
	add_child(click_area)


func _process(delta: float) -> void:
	# World-time items are aged by the ecology step instead (see advance).
	if ages_on_world_time:
		return
	advance(delta)


## Ages this item by `delta` seconds and removes it once it is past keeping.
func advance(delta: float) -> void:
	_age += delta
	if _age >= spoil_seconds:
		queue_free()


## How rotten this item is, 0 fresh to 1 gone -- for callers that want to show
## it or refuse to eat it.
func spoilage() -> float:
	if spoil_seconds <= 0.0:
		return 1.0
	return clampf(_age / spoil_seconds, 0.0, 1.0)


## Merges this stack into the picker's inventory. Frees the node if it all fit;
## if the inventory was full, leaves the node on the ground with the
## remainder. Returns whether anything at all was picked up.
func pick_up(picker) -> bool:
	if item_stack == null or picker.inventory == null:
		return false
	var overflow: int = picker.inventory.add(item_stack.item, item_stack.count)
	if overflow == item_stack.count:
		return false  # nothing fit
	item_stack.count = overflow
	if item_stack.count <= 0:
		queue_free()
	return true


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	if item_stack == null:
		return ""
	return (
		"%s x%d" % [item_stack.item.display_name, item_stack.count]
		if item_stack.count > 1
		else item_stack.item.display_name
	)


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_hover_actions() -> Array:
	return [{"verb": "Pick Up", "action": "pickup"}]


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			pick_up(players[0])
