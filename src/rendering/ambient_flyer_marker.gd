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
	if perched:
		_animate_wings()
		return  # sitting still: no drift, no beat

	var before := position
	position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	var moved := position - before
	if moved.length() > 0.001:
		face_travel(moved, delta)
	_animate_wings()


## How much horizontal travel is needed before the sprite mirrors. Without
## a deadzone, a near-vertical drift jitters either side of zero and the
## bird strobes between facings.
const FACING_DEADZONE := 0.05

## The bird must want to turn for this long before it actually does.
##
## A deadzone alone was not enough: the wander's horizontal component
## crosses zero constantly, so the sprite still mirrored several times a
## second and read as two overlapping birds. A real bird BANKS slowly and
## flaps fast -- the wings are the quick part, the heading is not. Holding
## a facing until the flyer has genuinely been travelling the other way for
## this long separates those two rates.
const FACING_TURN_DELAY := 1.4

## How long the flyer has continuously wanted to face the other way.
var _contrary_travel_time := 0.0


## Points the flyer the way it is travelling by MIRRORING it, never by
## rotating. Setting `rotation = moved.angle()` (as this did) spun the
## sprite a full 180 degrees whenever the wander reversed, rendering the
## bird upside-down -- reported as "birds appear doubled as they rotate 180
## degree with every wing flap". The art is drawn facing right, so facing
## left is a horizontal flip.
func face_travel(direction: Vector2, delta: float = 0.0) -> void:
	if absf(direction.x) < FACING_DEADZONE:
		return  # too vertical to imply a facing -- keep the current one
	var wants_flip := direction.x < 0.0
	if wants_flip == flip_h:
		_contrary_travel_time = 0.0
		return
	# Only commit to the turn once the flyer has meant it for a while.
	_contrary_travel_time += delta
	if _contrary_travel_time >= FACING_TURN_DELAY or delta <= 0.0:
		flip_h = wants_flip
		_contrary_travel_time = 0.0


## Wing-beat frames for this flyer, and how fast they cycle. Birds beat
## several times a second -- fast, unlike the slow banking of FACING_TURN_
## DELAY. The two rates are deliberately far apart: "they should change
## direction slowly, only their wings should flap fast".
var flap_frames: Array = []
## The folded-wing sprite shown while perched (see ProceduralBirdSprite.
## generate_perched_texture).
var perched_frame: Texture2D = null
## True while the flyer is sitting rather than flying.
var perched := false
const FLAP_SECONDS_PER_FRAME := 0.09


## Advances the wing-beat. Separate from the movement step so a flyer
## animates even while hovering.
func _animate_wings() -> void:
	# A perched bird holds still. Flapping while sitting on a branch reads
	# as a glitch, not as a bird.
	if perched:
		if perched_frame != null:
			texture = perched_frame
		return
	if flap_frames.is_empty():
		return
	var index := int(_elapsed_time / FLAP_SECONDS_PER_FRAME) % flap_frames.size()
	texture = flap_frames[index]
