extends Sprite2D

## An item lying on the ground: a visible, procedurally-drawn sprite holding an
## ItemStack, with a clickable name label floating above it (Path-of-Exile
## style) -- click the label (or the icon) to pick it up. There is
## deliberately no proximity auto-pickup; walking past a dropped item leaves
## it alone until the player actually clicks it. Picking up merges the stack
## into the player's inventory and frees this node; if the inventory has no
## room the node stays (with whatever didn't fit).

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

const GROUP_NAME := "dropped_item"
## Un-picked-up items despawn after this many seconds so the ground doesn't
## fill up with forage over a long session.
const LIFETIME := 90.0

## The clickable area covers both the icon and the name label above it, not
## just the icon -- "click the name to pick it up" needs the label itself to
## be a real click target.
const CLICK_AREA_SIZE := Vector2(64.0, 32.0)
const CLICK_AREA_OFFSET_Y := -8.0
const NAME_LABEL_OFFSET_Y := -20.0

static var _sprite_generator := ProceduralItemSprite.new()

var item_stack
var _age := 0.0
var _name_label: Label


func _ready() -> void:
	add_to_group(GROUP_NAME)
	if item_stack != null and texture == null:
		texture = _sprite_generator.generate_texture(item_stack.item.id)
		# Item art is authored DETAIL_MULTIPLIER times oversized; scaling it
		# back keeps a dropped item the same size on the ground as before
		# (see docs/concept/art_resolution.md).
		scale = Vector2.ONE * ArtResolution.SPRITE_SCALE

	var click_area := Area2D.new()
	var collision_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = CLICK_AREA_SIZE
	collision_shape.shape = shape
	collision_shape.position = Vector2(0, CLICK_AREA_OFFSET_Y)
	click_area.add_child(collision_shape)
	click_area.input_event.connect(_on_input_event)
	add_child(click_area)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(-CLICK_AREA_SIZE.x / 2.0, NAME_LABEL_OFFSET_Y)
	_name_label.size = Vector2(CLICK_AREA_SIZE.x, 14.0)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks go to click_area below
	add_child(_name_label)
	_update_name_label()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()


## Merges this stack into the picker's inventory. Frees the node if it all fit;
## if the inventory was full, leaves the node on the ground with the
## remainder (and its label updated to match). Returns whether anything at
## all was picked up.
func pick_up(picker) -> bool:
	if item_stack == null or picker.inventory == null:
		return false
	var overflow: int = picker.inventory.add(item_stack.item, item_stack.count)
	if overflow == item_stack.count:
		return false  # nothing fit
	item_stack.count = overflow
	if item_stack.count <= 0:
		queue_free()
	else:
		_update_name_label()
	return true


func _update_name_label() -> void:
	if item_stack == null or _name_label == null:
		return
	_name_label.text = (
		"%s x%d" % [item_stack.item.display_name, item_stack.count]
		if item_stack.count > 1
		else item_stack.item.display_name
	)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			pick_up(players[0])
