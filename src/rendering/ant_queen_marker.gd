extends Node2D

## The ant queen's own real, minimal visual presence at her mound --
## requested live, directly after the honeybee queen shipped: "give ants
## a real queen as well". Mirrors BeeQueenMarker's shape as closely as
## the underlying biology allows (see that class's own doc comment, and
## docs/concept/soil_fauna.md's "A real ant queen, and why she cannot
## requeen like a bee" for the real-world grounding on why ants and bees
## genuinely differ here) -- deliberately NOT an AntForagerMarker: a real
## queen never forages and never leaves the mound at all (see
## AntColony.has_queen_at's own doc comment for the real mechanical state
## this marker only ever DISPLAYS, never drives), so this has no
## scout/approach/return state machine whatsoever.
##
## No real ant queen art has been delivered (only ant.png/ant_mound.png
## exist under assets/sprites/animals/ -- unlike bees, which got a real,
## delivered honeybee_queen.png), so this falls back to a real, distinct
## PROCEDURAL silhouette (ProceduralDecomposerSprite's new "queen"
## species -- larger overall, with a far more pronounced abdomen than a
## worker, the real anatomical tell of a real egg-laying ant queen), the
## same has_species()/has_action()-gated "real art where it exists,
## honest procedural fallback otherwise" convention every other optional
## illustrated-art seam in this codebase already uses
## (IllustratedDecomposerSprite.has_action("queen", "walk") is false
## today; real queen art, if ever delivered, slots in for free behind
## that exact gate, the same seam ANT_WORLD_WIDTH/BUG_WORLD_WIDTH already
## sit behind).
##
## A child of AntMoundMarker (see that class's own _ready), not a sibling
## with a hover/panel contract of its own: her presence is reported
## through the mound's OWN existing tooltip (AntMoundMarker.
## get_display_name), mirroring BeeHiveMarker's identical choice, rather
## than growing a second, parallel hoverable entity for one static
## sprite.

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const AntColony = preload("res://src/world/ant_colony.gd")

## How far from the mound marker's own origin to draw her -- offset
## rather than dead-centered on the mound sprite, mirroring
## BeeQueenMarker.OFFSET_PX's own "beside the entrance, not buried inside
## the structure" placement. Smaller than the bee's own (10.0, 4.0): an
## ant mound's own founding size (ProceduralAntMoundSprite.
## MOUND_WORLD_WIDTH_MIN, 4.0 world-px) is far smaller than a beehive
## structure, so a beehive-scale offset would visibly detach her from a
## young mound entirely.
const OFFSET_PX := Vector2(4.0, 2.0)

## Mirrors AntMoundMarker.RESIZE_INTERVAL_SECONDS / BeeQueenMarker.
## REFRESH_INTERVAL_SECONDS exactly -- her presence moves over simulated
## DAYS (see AntColony.advance), so anything faster than a handful of
## real seconds spends per-frame cost on a state that is, for all
## practical purposes, motionless between checks.
const REFRESH_INTERVAL_SECONDS := 5.0

var _colony: AntColony = null
var _cell := Vector2i.ZERO
var _sprite: Sprite2D
var _refresh_accumulator := 0.0

static var _procedural_generator := ProceduralDecomposerSprite.new()
static var _illustrated_generator := IllustratedDecomposerSprite.new()


## `colony`/`cell` -- the real mound this queen belongs to. Call before
## add_child, the same convention every other marker's setup() follows.
func setup(colony: AntColony, cell: Vector2i) -> void:
	_colony = colony
	_cell = cell


func _ready() -> void:
	position = OFFSET_PX
	_sprite = Sprite2D.new()
	if _illustrated_generator.has_action("queen", "walk"):
		_sprite.texture = _illustrated_generator.generate_textures("queen", "walk")[0]
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale("queen", "walk")
	else:
		_sprite.texture = _procedural_generator.generate_texture("queen")
		_sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
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


## The one real, observable consequence of AntColony.has_queen_at: her
## own sprite simply is not there while the mound has genuinely collapsed
## to zero population (see that function's own doc comment for why this
## is the ONLY real queenless state ants have -- unlike bees' own
## multi-week declining-but-still-populated window, there is no partial
## queenless state to show a "dying" or "requeening" pose for here).
func _refresh_visibility() -> void:
	visible = _colony != null and _colony.has_queen_at(_cell)
