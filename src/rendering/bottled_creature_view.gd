extends Node2D

## The sandwiched view of a bottled catch (docs/concept/capture_dsl.md's
## "Rendering a bottled catch"): a back sprite, a live creature animated by
## bottled_creature_wander.gd, and a front sprite drawn on top -- the
## composite sheet's own real, painted-in translucent glass is what lets
## the creature show through both layers, not a shader trick here.
##
## Reuses ProceduralButterflySprite's existing flap/settled frame
## generators and WingbeatBounce's real-physics bob wholesale -- nothing
## here draws a new creature frame from scratch. Falls back to the bottle
## alone (no creature child at all) for any species ProceduralButterflySprite
## does not cover (today: birds) -- an honest, named simplification (see the
## concept doc), not an oversight.
##
## Deliberately much simpler than AmbientFlyerMarker's open-world animation:
## no courtship, no nectaring, no perched-bird logic -- nothing in a sealed
## bottle forages or courts.

const IllustratedGlassBottleSprite = preload("res://src/rendering/illustrated_glass_bottle_sprite.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const BottledCreatureWander = preload("res://src/gameplay/bottled_creature_wander.gd")
const WingbeatBounce = preload("res://src/rendering/wingbeat_bounce.gd")

## Where inside the sheet cell the creature is free to wander, in local
## pixels -- the bottle's own drawn body, not the whole cell (which also
## carries the neck and a transparent margin).
const INTERIOR_BOUNDS := Rect2(Vector2(-40, -60), Vector2(80, 90))

const FLAP_SECONDS_PER_FRAME := 0.09

## The sheet's cells are authored at icon/portrait resolution (measured:
## 512px), not ArtResolution's ordinary entity-sprite convention -- drawing
## them at that convention's scale would size a dropped bottle bigger than
## a whole tile. A held tool's own world footprint (lasso/climbing_rope,
## the same scale class this bottle actually is) sits in this range; a
## reasoned starting point, not yet visually confirmed against the real
## art in a live screenshot -- the same honest gap item_illustrations.md
## itself names for the armor slots.
const TARGET_WORLD_WIDTH_PX := 16.0

static var _bottle_sprite := IllustratedGlassBottleSprite.new()
static var _butterfly_sprite := ProceduralButterflySprite.new()


## The scale that shrinks a `source_width_px`-wide sheet cell down to
## TARGET_WORLD_WIDTH_PX -- the same "icon pixels aren't world pixels"
## conversion ProceduralItemSprite.world_scale_for already does for every
## other dropped item.
static func world_scale_for(source_width_px: float) -> float:
	if source_width_px <= 0.0:
		return 1.0
	return TARGET_WORLD_WIDTH_PX / source_width_px

## Set by the caller (e.g. DroppedItem) before this enters the tree.
var species := ""
var wander_seed := 0
var condition := "pristine"

var _back: Sprite2D
var _creature: Sprite2D
var _front: Sprite2D
var _flap_frames: Array = []
var _settled_frames: Array = []
var _elapsed := 0.0


func _ready() -> void:
	_back = Sprite2D.new()
	_back.texture = _bottle_sprite.back_texture_for(condition)
	add_child(_back)

	if ProceduralButterflySprite.SPECIES_IDS.has(species):
		_flap_frames = _butterfly_sprite.generate_flap_textures(species, wander_seed)
		_settled_frames = _butterfly_sprite.generate_settled_textures(species, wander_seed)
		_creature = Sprite2D.new()
		add_child(_creature)
		_animate_creature()

	_front = Sprite2D.new()
	_front.texture = _bottle_sprite.front_texture_for(condition)
	add_child(_front)


func _process(delta: float) -> void:
	_elapsed += delta
	_animate_creature()


## Advances the creature's position/pose to `_elapsed`. A no-op if this
## species has no creature layer at all (see _ready).
func _animate_creature() -> void:
	if _creature == null:
		return
	_creature.position = BottledCreatureWander.position_in(INTERIOR_BOUNDS, _elapsed, wander_seed)
	if BottledCreatureWander.is_resting(_elapsed, wander_seed) and not _settled_frames.is_empty():
		# Nothing is beating, so there is no lift pulse to bob on (see
		# WingbeatBounce) -- the same "settled means still" reasoning
		# AmbientFlyerMarker._animate_wings already applies.
		_creature.offset.y = 0.0
		_creature.texture = _settled_frames[0]
		return
	if _flap_frames.is_empty():
		return
	var frame_count := _flap_frames.size()
	var index := int(_elapsed / FLAP_SECONDS_PER_FRAME) % frame_count
	_creature.texture = _flap_frames[absi(index)]
	_creature.offset.y = WingbeatBounce.bounce_offset(
		species, _elapsed, FLAP_SECONDS_PER_FRAME, frame_count, float(_creature.texture.get_height())
	)
