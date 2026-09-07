extends Node2D

## The visible marker over one WildBeePatch nest hole -- see
## ProceduralWildBeeNestSprite, docs/concept/bees.md's "Wild bee nests".
## Mirrors AntMoundMarker's own shape: never player-interactive, no
## `_world` reference needed at all -- relocation, unlike BeeHiveMarker's
## own harvest-triggered one, is driven entirely externally by
## EarthChunkManager checking WildBeePatch.should_relocate_at on its own
## periodic cadence (the same "colony owns the economy, EarthChunkManager
## owns the real ground/site-search and marker teardown/respawn" split
## AntColony's own budding already uses).
##
## Unlike AntMoundMarker/BeeHiveMarker, there is NO growth-fraction
## sizing at all: a nest hole is a fixed physical feature of existing
## deadwood (see ProceduralWildBeeNestSprite's own doc comment), so this
## marker never resizes and needs no periodic re-check, no _process
## override beyond the inherited no-op.
##
## Deliberately offers no get_hover_actions()/panel_state()/animal_state()
## at all -- a wild nest is hoverable (a name, and nothing else) but
## never panel-worthy or interactive, matching its own much lighter
## mechanism (see bees.md: no honey, no harvest, real biology, not an
## arbitrary omission).

const ProceduralWildBeeNestSprite = preload("res://src/rendering/procedural_wild_bee_nest_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")

const GROUP_NAME := "wild_bee_nest"

## The real WildBeePatch this nest belongs to, and which cell within it
## -- optional, the same "graceful no-op without a patch" contract
## AntMoundMarker's own `_colony` already has.
var _patch: WildBeePatch = null
var _cell := Vector2i.ZERO

var _sprite: Sprite2D

static var _generator := ProceduralWildBeeNestSprite.new()


## `patch`/`cell` -- the real nest this marker represents. Mirrors
## AntMoundMarker.setup's own shape exactly (a lighter marker than
## BeeHiveMarker's own setup, since this one never needs a `_world`
## reference at all). Call before add_child, same convention as every
## other marker's setup().
func setup(patch: WildBeePatch, cell: Vector2i) -> void:
	_patch = patch
	_cell = cell


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	_sprite.texture = _generator.generate_texture()
	_sprite.scale = Vector2.ONE * ProceduralWildBeeNestSprite.WORLD_SCALE
	add_child(_sprite)


## A deliberate, explicit no-op -- unlike AntMoundMarker/BeeHiveMarker,
## a nest hole never resizes (see this file's own header doc comment),
## so there is nothing to re-check on any cadence. Kept as a real
## override (rather than just relying on Node's own built-in no-op)
## purely so a caller/test can invoke _process directly without a
## "nonexistent function" engine error -- GDScript's virtual dispatch
## only resolves a direct call against what the SCRIPT itself defines.
func _process(_delta: float) -> void:
	pass


## Mirrors AntMoundMarker.get_display_name's own shape, minus any honey
## figure at all -- see bees.md's own "Tooltip distinction": the absence
## itself is part of what makes the two structures read as genuinely
## different animals, not a reskin of one mechanic.
func get_display_name() -> String:
	if _patch == null:
		return "Wild Bee Nest"
	return "Wild Bee Nest (%d resident%s)" % [
		int(round(_patch.residents_at(_cell))),
		"" if int(round(_patch.residents_at(_cell))) == 1 else "s",
	]
