extends CharacterBody2D
class_name InteriorAvatar

## The player's own local, non-networked stand-in while indoors (see
## HouseInteriorView's own doc comment, World._build_interior_view). The
## real Player node never moves or renders while indoors -- it stays
## parked outdoors at the real doorstep the whole visit, keeping chunk
## streaming/NPC schedules anchored exactly where they already were (see
## docs/concept/building.md "Entering"). This is what actually walks
## around inside the isolated interior SubViewport, colliding with
## HouseInteriorView's own real wall/furniture/threshold bodies on
## INTERIOR_COLLISION_LAYER. Reads input directly rather than going
## through Player's whole authority/proxy/RPC machinery: it only ever
## exists locally, for the one person currently standing in their own
## house, so none of that applies. A simple placeholder square, not the
## real CharacterView -- matching the player's exact outdoor appearance
## indoors is a named, deliberately deferred follow-up (see
## docs/progress.md), not something this pass needs to get right.

const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")

const RADIUS := 6.0
const _VISUAL_COLOR := Color(0.85, 0.7, 0.5)

## Player.BASE_SPEED is the outdoor walking speed -- reused rather than a
## second, separately-tuned number, so indoor movement doesn't feel like a
## different game. Player is a global class_name (scenes/player.gd), so
## this reads it directly rather than preloading that script by path --
## Player itself references InteriorAvatar the same way, and an explicit
## two-way preload between the two would be a real circular-preload risk.
const SPEED := Player.BASE_SPEED


func _ready() -> void:
	collision_layer = 0
	collision_mask = HouseInteriorView.INTERIOR_COLLISION_LAYER

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	var visual := ColorRect.new()
	visual.color = _VISUAL_COLOR
	visual.size = Vector2.ONE * RADIUS * 2.0
	visual.position = -visual.size * 0.5
	visual.z_index = HouseInteriorView.INTERIOR_OCCUPANT_Z_INDEX
	add_child(visual)


func _physics_process(_delta: float) -> void:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction * SPEED
	move_and_slide()
