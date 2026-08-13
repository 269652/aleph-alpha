extends Sprite2D

## A butterfly/songbird ambient wildlife marker -- pure decorative presence
## (see docs/concept/ecosystem_dynamics.md's Species roster), driven by
## AmbientFlyerMovement's idle-flight drift. Deliberately lighter than
## FishMarker/CreatureMarker: no needs/perception/behavior AI, no water
## confinement (flyers roam freely over both land and water), and no
## population simulation behind it -- a fixed, capped, decorative presence
## like the game's original static tree/grass-tuft layers.

const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")

## For World's mouse-hover animal-name tooltip (see CreatureMarker.HOVERABLE_GROUP).
const HOVERABLE_GROUP := "hoverable_animal"

var home := Vector2.ZERO
var wander_seed := 0
var species := "sparrow"

var _movement: AmbientFlyerMovement
var _elapsed_time := 0.0


## `movement` (an AmbientFlyerMovement tuned per species-category -- see
## AmbientFlyerRenderer) drives this marker's flight; left unset (default
## null), it stays still, the same isolated-test fallback other markers use.
func _ready() -> void:
	add_to_group(HOVERABLE_GROUP)


func setup(movement: AmbientFlyerMovement) -> void:
	_movement = movement


## For World's mouse-hover animal-name tooltip.
func get_display_name() -> String:
	return species.capitalize()


func _process(delta: float) -> void:
	_elapsed_time += delta
	if _movement == null:
		return
	var before := position
	position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	var moved := position - before
	if moved.length() > 0.001:
		face_travel(moved)


## How much horizontal travel is needed before the sprite mirrors. Without
## a deadzone, a near-vertical drift jitters either side of zero and the
## bird strobes between facings.
const FACING_DEADZONE := 0.05


## Points the flyer the way it is travelling by MIRRORING it, never by
## rotating. Setting `rotation = moved.angle()` (as this did) spun the
## sprite a full 180 degrees whenever the wander reversed, rendering the
## bird upside-down -- reported as "birds appear doubled as they rotate 180
## degree with every wing flap". The art is drawn facing right, so facing
## left is a horizontal flip.
func face_travel(direction: Vector2) -> void:
	if absf(direction.x) < FACING_DEADZONE:
		return  # too vertical to imply a facing -- keep the current one
	flip_h = direction.x < 0.0
