extends RefCounted

## Spawns cave-entrance markers on the surface, and reveals a real
## Strata-sourced diggable-rock chamber the moment the player is near one
## -- the underground counterpart of TreeRenderer/StoneRenderer, deliberately
## reusing RoomDetector/paint_roofs' reveal-on-entry shape one layer down
## (see docs/concept/geology.md "Reveal-on-entry, reused recursively").
##
## Two independent responsibilities, kept in one file because they're two
## halves of the same mechanism: `spawn_entrance_markers`/`entrances_in_chunk`
## place the visible cave mouth (chunk-load-lifetime, like trees/stones),
## and `reveal_chamber` spawns/despawns the actual diggable cells
## (entry-lifetime, like paint_roofs' hidden_cells) -- the caller
## (EarthChunkManager) owns tracking which is currently revealed, the same
## split it already keeps for hidden-roof state.

const CaveEntrancePlacement = preload("res://src/world/cave_entrance_placement.gd")
const GeologyChamber = preload("res://src/world/geology_chamber.gd")
const Strata = preload("res://src/world/strata.gd")
const DiggableRock = preload("res://src/rendering/diggable_rock.gd")
const CaveEntranceMarker = preload("res://src/rendering/cave_entrance_marker.gd")
const ProceduralCaveEntranceSprite = preload("res://src/rendering/procedural_cave_entrance_sprite.gd")
const ProceduralStoneSprite = preload("res://src/rendering/procedural_stone_sprite.gd")
const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

var _placement := CaveEntrancePlacement.new()
var _entrance_sprite_generator := ProceduralCaveEntranceSprite.new()
var _stone_sprite_generator := ProceduralStoneSprite.new()
var _ore_sprite_generator := ProceduralOreSprite.new()


## Local cell positions (within a `width` x `height` chunk biome grid at
## `chunk_origin_tiles`) that carry a cave entrance -- same shape as
## StonePlacement.stones_in_chunk.
func entrances_in_chunk(
	chunk_origin_tiles: Vector2i, biome: Array, width: int, height: int
) -> Array[Vector2i]:
	var entrances: Array[Vector2i] = []
	for y in height:
		for x in width:
			var biome_name: String = biome[y * width + x]
			var global_x := chunk_origin_tiles.x + x
			var global_y := chunk_origin_tiles.y + y
			if _placement.has_entrance_at(global_x, global_y, biome_name):
				entrances.append(Vector2i(x, y))
	return entrances


## Spawns a walkable CaveEntranceMarker (as a child of `parent`) for every
## cave entrance in the chunk. Chunk-load lifetime -- the caller frees these
## on chunk unload, same as spawn_trees/spawn_stones.
func spawn_entrance_markers(
	parent: Node2D, chunk_origin_tiles: Vector2i, biome: Array, width: int, height: int, tile_size: float
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for cell in entrances_in_chunk(chunk_origin_tiles, biome, width, height):
		var global_x := chunk_origin_tiles.x + cell.x
		var global_y := chunk_origin_tiles.y + cell.y
		var marker := CaveEntranceMarker.new()
		marker.position = Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
		var sprite := Sprite2D.new()
		sprite.texture = _entrance_sprite_generator.generate_texture(_placement.seed_at(global_x, global_y))
		sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
		marker.add_child(sprite)
		parent.add_child(marker)
		spawned.append(marker)
	return spawned


## Reveals the real diggable-rock chamber around `entrance_local_cell` (see
## GeologyChamber.cells_for): spawns one DiggableRock per chamber cell that
## `strata` doesn't already report as a mined-out TUNNEL, wired straight
## back to that same Strata instance so mining one permanently updates it.
## Entry-lifetime -- the caller frees these the moment the player leaves
## the entrance's vicinity, same as paint_roofs' hidden-room repaint, but
## `strata`'s own mined-cell bookkeeping outlives the nodes, so a chamber
## re-revealed later still shows its real tunnels rather than resetting.
func reveal_chamber(
	parent: Node2D, strata: Strata, entrance_local_cell: Vector2i, chunk_origin_tiles: Vector2i, tile_size: float
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for cell in GeologyChamber.cells_for(entrance_local_cell):
		var kind := strata.cell_kind_at(cell)
		if kind == Strata.KIND_TUNNEL:
			continue  # already dug out -- nothing to spawn, walk straight through
		var rock := DiggableRock.new()
		rock.strata = strata
		rock.local_cell = cell
		rock.kind = kind
		var global := chunk_origin_tiles + cell
		var seed_value := strata.seed_at(cell.x, cell.y)
		if kind == Strata.KIND_ORE:
			rock.ore_type = strata.ore_type_at(cell.x, cell.y)
			rock.ore_seed = seed_value
			_attach_sprite(rock, _ore_sprite_generator.generate_texture(rock.ore_type, seed_value))
		else:
			_attach_sprite(rock, _stone_sprite_generator.generate_texture(seed_value))
		rock.position = Vector2((global.x + 0.5) * tile_size, (global.y + 0.5) * tile_size)
		parent.add_child(rock)
		spawned.append(rock)
	return spawned


func _attach_sprite(rock: DiggableRock, texture: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	rock.add_child(sprite)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(ProceduralStoneSprite.SIZE) * ArtResolution.SPRITE_SCALE * 0.6
	collision.shape = shape
	rock.add_child(collision)
