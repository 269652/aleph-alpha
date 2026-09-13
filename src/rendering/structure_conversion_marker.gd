extends Node2D

## A structure worker who turns the building's OWN stock into its product
## (docs/concept/milling_and_baking.md): the Mill's Miller (wheat -> flour,
## see mill_marker.gd) and the Bakery's Baker (flour -> bread, see
## bakery_marker.gd). "An NPC moves in" the moment the building stands, one
## per structure tile, exactly the LumberjackMarker/FarmerMarker shape
## (EarthChunkManager's _conversion_workers wiring) -- and, like those,
## deliberately NOT the full NpcMarker AI stack: a worker whose whole job
## is to stand at one building and work it is the wrong shape for that
## machinery.
##
## The one real difference from the Sägewerk: its logs live in its
## Lumberjack's private production state, credited only by the
## Lumberjack's own fell/carry loop, so nothing external can ever feed it.
## A Mill grinds whatever wheat has reached its real StructureStock -- a
## logistics hauler can feed it (see EarthChunkManager's consumer legs) --
## and credits flour back to the SAME stock, where the next hauler picks
## it up. Production is StockConversionProduction's pure advance() every
## frame this marker exists; the marker's presence itself IS "staffed"
## (the Lumberjack's own rule).

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const GROUP_NAME := "structure_worker"

## Where this worker's building stands -- its own tile, whose StructureStock
## is both the hopper it draws from and the shelf it fills.
var home := Vector2.ZERO

## Late-bound world reference, set by EarthChunkManager itself when it
## spawns this worker (the SAME pattern the Farmer/Lumberjack use; see
## test_earth_chunk_manager_structure_workers.gd for why it must never be
## forgotten) -- without it, nothing is read or credited anywhere.
var earth = null

## What this worker consumes and produces, and the pure production model
## that decides how fast -- set by the concrete subclass.
var input_item_id := ""
var output_item_id := ""
var display_name := "Worker"
var _production = null

## Work banked toward the next unit -- the only state the worker itself
## keeps; the stock lives in the building.
var _progress := 0.0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	var sprite := Sprite2D.new()
	# The same procedural worker figure the Lumberjack/Farmer already wear --
	# real illustrated art per trade is a named follow-up in the concept doc.
	sprite.texture = ProceduralLumberjackSprite.new().generate_texture()
	add_child(sprite)


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	return display_name


## An autonomous worker, not something you click on to command (mirrors
## LumberjackMarker/FarmerMarker offering none either).
func get_hover_actions() -> Array:
	return []


func _process(delta: float) -> void:
	_step_production(delta)


## One tick of the building's own conversion off its own real stock: read
## how much input the StructureStock holds right now, advance the pure
## production model against it, then apply exactly what it consumed and
## produced back to that stock -- input withdrawn only as units actually
## complete, output credited the same tick. No-op if `earth` was never set
## (a marker not spawned through EarthChunkManager).
func _step_production(delta: float) -> void:
	if earth == null or _production == null:
		return
	var home_tile := _tile_for(home)
	var available: int = earth.structure_stock_at(home_tile.x, home_tile.y, input_item_id)
	var result: Dictionary = _production.advance({"input_stock": float(available), "progress": _progress}, delta, true)
	_progress = result["progress"]
	var consumed := available - int(result["input_stock"])
	if consumed > 0:
		earth.withdraw_from_structure_at(home_tile.x, home_tile.y, input_item_id, consumed)
	var output: int = result["output"]
	if output > 0:
		earth.deposit_to_structure_at(home_tile.x, home_tile.y, output_item_id, output)


## Recovers the global tile coordinate a pixel position falls in -- mirrors
## LumberjackMarker/FarmerMarker's own helper.
func _tile_for(pixel_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(pixel_position.x / TerrainRenderer.TILE_SIZE), floori(pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
