extends Node2D

## The honeybee queen's own real, minimal visual presence at her hive --
## see docs/concept/bees.md's "The queen" section, reported live: "Also
## added honeybee_queen sprite add a honeybee queen and wire it... give
## her a real place in the ecosystem."
##
## Deliberately NOT a BeeForagerMarker: a real queen never forages, she
## stays in the hive her entire life (see BeeColony.has_queen_at's own
## doc comment for the real mechanical state this marker only ever
## DISPLAYS, never drives), so this has no scout/approach/return state
## machine at all -- it shows the one real static pose
## (IllustratedBeeSprite.generate_queen_texture, the "walk" band's frame
## 0, since she has no flight cycle to play either) and hides itself
## entirely whenever her hive has genuinely lost her (BeeColony.
## has_queen_at false -- swarmed away with the new colony, mid-
## requeening) rather than playing a "dying" pose that would have to sit
## there, misleadingly, for the whole real multi-week requeening window
## (see BeeColony.REQUEENING_DAYS).
##
## A child of BeeHiveMarker (see that class's own _ready), not a sibling
## with a hover/panel contract of its own: her presence is reported
## through the hive's OWN existing tooltip (BeeHiveMarker.
## get_display_name), the same "one real observable consequence through
## an existing contract" reasoning that keeps this addition honestly
## scoped rather than growing a second, parallel hoverable entity for one
## static sprite.

const IllustratedBeeSprite = preload("res://src/rendering/illustrated_bee_sprite.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")

## How far from the hive marker's own origin to draw her -- offset
## rather than dead-centered on the hive structure sprite, so she reads
## as a distinct figure AT the hive rather than hidden inside/behind it.
## No precedent to mirror here (an ant queen is deliberately never drawn
## at all -- see soil_fauna.md), so this is a plain, real "beside the
## entrance" placement, not a value ported from anywhere else.
const OFFSET_PX := Vector2(10.0, 4.0)

## How often to re-check the colony's real queen state -- presence/
## requeening move over simulated DAYS (see BeeColony.advance), so
## anything faster than a handful of real seconds spends per-frame cost
## on a state that is, for all practical purposes, motionless between
## checks. Mirrors BeeHiveMarker.RESIZE_INTERVAL_SECONDS exactly.
const REFRESH_INTERVAL_SECONDS := 5.0

var _colony: BeeColony = null
var _cell := Vector2i.ZERO
var _sprite: Sprite2D
var _refresh_accumulator := 0.0

static var _generator := IllustratedBeeSprite.new()


## `colony`/`cell` -- the real hive this queen belongs to. Call before
## add_child, the same convention every other marker's setup() follows.
func setup(colony: BeeColony, cell: Vector2i) -> void:
	_colony = colony
	_cell = cell


func _ready() -> void:
	position = OFFSET_PX
	_sprite = Sprite2D.new()
	_sprite.texture = _generator.generate_queen_texture()
	_sprite.scale = Vector2.ONE * _generator.queen_world_scale()
	add_child(_sprite)
	_refresh_visibility()


func _process(delta: float) -> void:
	if _colony == null:
		return
	_refresh_accumulator += delta
	if _refresh_accumulator < REFRESH_INTERVAL_SECONDS:
		return
	_refresh_accumulator = 0.0
	_refresh_visibility()


## The one real, observable consequence of BeeColony.has_queen_at: her
## own sprite simply is not there while the hive is genuinely queenless.
## See this class's own header comment for why that reads more honestly
## than parking a "dying" frame for a real multi-week window.
func _refresh_visibility() -> void:
	visible = _colony != null and _colony.has_queen_at(_cell)
