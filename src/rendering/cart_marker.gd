extends Node2D

## The Bollerwagen (docs/concept/village_warehouse.md, Mechanism 5): a real
## cart on the map that HOLDS the load, follows whoever is pulling it, and
## turns to face the way it is going.
##
## Asked directly: *"it should be so that the ressources are actually loaded
## inside the wagon which has an inventory; so if the worker leaves it
## somewhere it's actually full of ressources... once in the warehouse he
## unloads"*. The goods live here, on the cart's own node -- a cart standing
## in a field is a cart with the timber still in it.
##
## Deliberately NOT built on NpcMarker/CreatureMarker, the same reasoning
## LogisticsMarker and DecomposerMarker already give: a thing that is pulled
## needs no sense/perceive/act stack. What it is worth and what fits is
## CartLoad's (pure); this owns only where it stands and what it draws.

const CartLoad = preload("res://src/gameplay/cart_load.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

const GROUP_NAME := "cart"

const SHEET_PATH := "res://assets/sprites/vehicles/cart.png"

## The sheet's own magenta-divided grid, MEASURED off the real file rather
## than detected: the generic band scan reads this sheet's own canvas frames
## as extra dividers, the same case illustrated_structure_sprite.gd's
## explicit_frame_image was added for. Four rows are the four views; the five
## columns are a roll cycle (measured: the difference from column 0 grows
## monotonically across the row, which is an animation rather than five
## unrelated variants).
const ROW_BANDS := [Vector2i(37, 214), Vector2i(292, 464), Vector2i(538, 712), Vector2i(763, 947)]
const COLUMN_BANDS := [
	Vector2i(63, 246), Vector2i(372, 553), Vector2i(677, 863),
	Vector2i(981, 1167), Vector2i(1285, 1478),
]

## Which row of the sheet is which view.
const ROW_REAR := 0    # going away from the camera
const ROW_EAST := 1    # the shaft points right
const ROW_WEST := 2    # the shaft points left
const ROW_FRONT := 3   # coming toward the camera

## How wide the cart is drawn, in tiles. A hand-cart is about a tile and a
## half of road -- wider than the porter pulling it, narrower than the
## buildings it serves.
const WIDTH_TILES := 1.5

## How far behind its puller a cart trails, in pixels. A cart is PULLED, so
## it never stands on top of the person pulling it.
const TRAIL_DISTANCE_PX := 10.0

## How fast a cart closes that gap. Comfortably above LogisticsMarker's own
## WALK_SPEED so a cart keeps up with a walking porter rather than being
## dragged further and further behind.
const FOLLOW_SPEED := 48.0

## Real seconds of rolling per turn of the wheel.
const ROLL_SECONDS_PER_FRAME := 0.18

## What this cart is carrying: item_id -> whole units, the real store (see
## CartLoad). Left on the cart, never moved onto the puller.
var stock: Dictionary = {}

## Where the puller is right now (Vector2), or null when nobody is pulling
## -- a cart nobody is pulling stays exactly where it was left.
var pulled_toward = null

## Whoever has the shaft (a Node2D), or null when the cart is parked
## (docs/concept/village_warehouse.md, Mechanism 6). `pulled_toward` follows
## them for as long as they hold it, so nothing has to drive the low-level
## field by hand.
##
## Asked directly: *"the player should also be able to grab/pull it"*.
var held_by = null

## What stops you walking through it. The same ground-floor collision layer
## every wall piece and the village well already use
## (EarthChunkManager.GROUND_FLOOR_COLLISION_LAYER), named here rather than
## imported so a cart does not have to preload the whole chunk manager to
## know one number.
const GROUND_FLOOR_COLLISION_LAYER := 1

## How much of the drawn frame the hitbox covers. A hand-cart is mostly
## air -- a box the full size of the art would stop you a wheel's width
## away from something you can plainly walk past.
const SOLID_FOOTPRINT_FRACTION := Vector2(0.7, 0.45)

var _sprite: Sprite2D
var _view_row := ROW_FRONT
var _rolled_seconds := 0.0
var _drawn: Vector2i = Vector2i(-1, -1)
static var _frames: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_NAME)
	# Answers the cursor like every other interactable in the world -- a
	# name, and one thing to do with it (Mechanism 6).
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_redraw()
	add_child(_solid_body())


## The body that stops you walking into a parked cart. A child of the cart
## itself, so it moves with it and is freed with it -- the cart IS the thing
## in the way, and a separately-tracked body would be one more thing to keep
## in step (the same shape VillageRenderer._solid_body_for already uses for
## the well).
##
## Sized in WORLD units off the cart's own drawn width, not off the art's raw
## pixels: the sheet is authored many times oversized and the sprite is
## scaled back to WIDTH_TILES of road, so raw numbers would be a wall several
## tiles across.
func _solid_body() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "CartCollision"
	body.collision_layer = GROUND_FLOOR_COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var drawn := WIDTH_TILES * float(TerrainRenderer.TILE_SIZE)
	rect.size = Vector2(drawn, drawn) * SOLID_FOOTPRINT_FRACTION
	shape.shape = rect
	# A cart stands on its own wheels, so what stops you is the box at its
	# foot rather than a column of air over it.
	shape.position = Vector2(0, -rect.size.y * 0.5)
	body.add_child(shape)
	return body


## What the hover tooltip calls it. An empty cart and a loaded one are
## different things to walk up to, so the name says which.
func get_display_name() -> String:
	if is_empty():
		return "Handcart"
	return "Handcart (%d)" % CartLoad.total(stock)


## The one thing there is to do with a cart, on the primary context slot --
## which is exactly what that slot is for: what it does is decided by
## whatever is under the cursor and the state it is in.
func get_hover_actions() -> Array:
	if held_by != null and is_instance_valid(held_by):
		return [{"verb": "Let Go", "action": "primary_action"}]
	return [{"verb": "Take Hold", "action": "primary_action"}]


## What a click on the cart shows, in the shape HousePanel already reads --
## it is a pure consumer of a Dictionary, so a cart hands it one rather than
## growing a second panel that would draw the same rows a different way.
##
## A SNAPSHOT of the load, never the cart's own store: a panel holding the
## live dictionary could edit the load by drawing it.
func report() -> Dictionary:
	return {
		"title": get_display_name(),
		"subtitle": _holder_line(),
		"is_home": false,
		"stock": stock.duplicate(),
		"storage_capacity": CartLoad.CAPACITY,
	}


func _holder_line() -> String:
	if held_by == null or not is_instance_valid(held_by):
		return "Parked"
	if held_by.has_method("get_display_name"):
		return "Pulled by %s" % held_by.get_display_name()
	return "Being pulled"


## Takes the shaft. Fails when somebody else already has it, so two carters
## never fight over one wagon -- unless `force`, which the player's own grab
## passes: a villager is not going to wrestle them for it, and being refused
## by an NPC's claim reads as a bug.
func take_hold(who, force := false) -> bool:
	if who == null:
		return false
	if held_by != null and is_instance_valid(held_by) and held_by != who and not force:
		return false
	held_by = who
	return true


## Lets go, but only if `who` really has it -- otherwise anybody walking past
## could park somebody else's cart.
func let_go(who) -> void:
	if held_by == who:
		held_by = null
		pulled_toward = null


func is_held_by(who) -> bool:
	return who != null and held_by == who and is_instance_valid(who)


## Loads up to `count` of `item_id` on, and reports what really went on. What
## will not fit is left for the caller to put back -- a full cart never
## swallows the rest.
func load_on(item_id: String, count: int) -> int:
	var result: Dictionary = CartLoad.load_into(stock, item_id, count)
	stock = result["stock"]
	return int(result["loaded"])


## How much more this cart will take -- what one trip is worth to the porter
## pulling it.
func room_left() -> int:
	return CartLoad.room_left(stock)


func is_empty() -> bool:
	return CartLoad.total(stock) <= 0


## Everything on the cart, handed over at once, leaving it empty -- what
## happens at the warehouse door.
func unload_all() -> Dictionary:
	var taken := stock.duplicate()
	stock = {}
	return taken


func _process(delta: float) -> void:
	# A holder that has been freed is not a holder: a cart whose carter's
	# chunk unloaded is parked, not chasing a dangling reference.
	if held_by != null and not is_instance_valid(held_by):
		held_by = null
		pulled_toward = null
	elif held_by != null:
		pulled_toward = held_by.position
	if pulled_toward == null:
		_redraw()
		return
	var to_puller: Vector2 = (pulled_toward as Vector2) - position
	var gap := to_puller.length()
	if gap > TRAIL_DISTANCE_PX:
		var step: float = minf(FOLLOW_SPEED * delta, gap - TRAIL_DISTANCE_PX)
		position += to_puller.normalized() * step
		_view_row = view_row_for(to_puller, _view_row)
		_rolled_seconds += delta
	_redraw()


## Which view faces `heading`. A cart standing still (a heading of no length)
## keeps the way it was last pointed rather than snapping to a default.
static func view_row_for(heading: Vector2, current := ROW_FRONT) -> int:
	if heading.length() <= 0.0:
		return current
	if absf(heading.x) >= absf(heading.y):
		return ROW_EAST if heading.x >= 0.0 else ROW_WEST
	return ROW_FRONT if heading.y >= 0.0 else ROW_REAR


## Which turn of the wheel to draw after `rolled_seconds` of real rolling.
## Only rolling counts: a parked cart with spinning wheels is worse than one
## that does not animate at all.
static func roll_frame_for(rolled_seconds: float, columns: float, seconds_per_frame: float) -> int:
	if rolled_seconds <= 0.0 or seconds_per_frame <= 0.0 or columns < 1.0:
		return 0
	return int(floor(rolled_seconds / seconds_per_frame)) % int(columns)


func _redraw() -> void:
	var column := roll_frame_for(_rolled_seconds, float(COLUMN_BANDS.size()), ROLL_SECONDS_PER_FRAME)
	var cell := Vector2i(column, _view_row)
	if cell == _drawn or _sprite == null:
		return
	_drawn = cell
	var texture := _frame_texture(_view_row, column)
	if texture == null:
		return
	_sprite.texture = texture
	_sprite.scale = Vector2.ONE * (WIDTH_TILES * TerrainRenderer.TILE_SIZE / float(texture.get_width()))
	# Anchored at its own wheels, like every other thing standing on the
	# ground here, so a cart sorts against the ground it is on.
	_sprite.offset = Vector2(0, -float(texture.get_height()) * 0.5)


## Shared across every cart in the world: the sheet is 1.5 MB and its frames
## are identical for all of them, so slicing one per cart would pay for the
## same twenty images over and over (the same reason IllustratedGrassPatch
## shares its atlas).
static func _frame_texture(row: int, column: int) -> ImageTexture:
	var key := "%d_%d" % [row, column]
	if _frames.has(key):
		return _frames[key]
	var image: Image = IllustratedStructureSprite.new().explicit_frame_image(
		SHEET_PATH, ROW_BANDS, COLUMN_BANDS, row, column
	)
	var texture: ImageTexture = null if image == null else ImageTexture.create_from_image(image)
	_frames[key] = texture
	return texture
