extends Node2D

## Enterable house interiors (docs/concept/building.md "Entering"): the
## real scene an "Enter" prompt swaps the player into -- built once per
## Enter, freed on Leave, as the content of an ISOLATED SubViewport (see
## World._build_interior_view, the same real "another scene, not a paint-
## over" pattern this codebase already proves out for the character
## creator's diorama -- main_menu.gd's _build_diorama_view). A TileMapLayer
## sharing the MAIN terrain tile set (the exact illustrated wall/floor/
## furniture tiles the rest of the world already draws with -- no second
## art pipeline), real StaticBody2D collision on every wall AND every
## "blocking" furniture piece, plus an always-present threshold body one
## cell past the door so the only way past it is the real Leave action,
## and this view's own Camera2D fit to the room's own size (see
## _build_camera) rather than reusing the outdoor world's fixed 4x zoom.
##
## Deliberately NOT the real Player node, and not positioned at the
## house's real world coordinates at all any more (an earlier version was
## both, and reportedly still showed the real outside world bleeding in
## around a small patch of floor -- no backdrop sized to only the room's
## own grid can out-cover a camera that is bigger than every room). The
## real Player stays exactly where it is outdoors, at the real doorstep,
## for the whole visit -- see scenes/player.gd's indoors state -- so chunk
## streaming, NPC schedules and the clock all keep running unaffected.
## Movement inside is InteriorAvatar's job, a small local-only stand-in
## that lives only inside this same SubViewport.

const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")

## A new collision layer, not layers 1/2 (EarthChunkManager.
## GROUND_FLOOR_COLLISION_LAYER/UPPER_FLOOR_COLLISION_LAYER) -- an interior
## is never simultaneously walkable with either outdoor floor, so it needs
## its own bit rather than reusing one.
const INTERIOR_COLLISION_LAYER := 4

## Above every real world z-index today (UpperFloor/UpperFloorFurniture = 2,
## Player.UPPER_FLOOR_OCCUPANT_Z_INDEX = 4 -- see EarthChunkManager) --
## an interior must always draw over the whole outdoor world, the same
## "one number higher than the current ceiling" reasoning the two-story
## pass itself already used.
const INTERIOR_Z_INDEX := 10
const INTERIOR_OCCUPANT_Z_INDEX := 11

const _WALL_PIECE_ID := "wood_wall"
const _WINDOW_PIECE_ID := "wood_window"
const _FLOOR_PIECE_ID := "wood_floor"
const _DOOR_PIECE_ID := "wood_door"

## Furniture that blocks movement, by real BuildingPiece.CATEGORY_FURNITURE
## id (docs/concept/building.md "Entering": "its walls and blocking
## furniture (bed, table, bookshelf, couch)... chair/rug/frame don't") --
## the OPPOSITE of BuildingPiece.is_walkable's own blanket-true-for-every-
## furniture-id rule (see that file's own doc comment on why furniture
## never blocks OUTDOORS): an interior room is small and meant to be
## navigated around its own furniture, unlike a sprawling exterior plot.
## The v2 workshop/storage pieces are solid things you walk around; a
## candle is not.
const _BLOCKING_FURNITURE_IDS := {
	"wood_bed": true, "wood_table": true, "wood_bookshelf": true, "couch": true,
	"hearth": true, "workbench": true, "anvil": true, "barrel": true,
	"crate": true, "chest": true, "cupboard": true,
}

## A candle's glow: the same additive TorchGlow material the player's own
## torch uses (docs/concept/lighting.md), one quad per light cell, sized to
## light a room's corner rather than the outdoor torch's 7.5 m -- tuned by
## eye once and pinned, like every other radius here.
const INTERIOR_LIGHT_RADIUS_TILES := 3.0
const TorchGlow = preload("res://src/rendering/torch_glow.gd")
const InteriorResident = preload("res://src/rendering/interior_resident.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

## door_cell/size mirror InteriorTemplates.furnish's own output exactly,
## exposed here for callers that need to reason about the room's shape
## without re-deriving it.
var door_cell: Vector2i
var size: Vector2i
## The occupation this room was furnished for (see InteriorTemplates.
## furnish) -- the resident's real one from the building record, or the
## seed-derived fallback for a house nobody was recorded for.
var occupation: String = ""
## Where the resident stands when they're home (InteriorTemplates' own
## `@` cell -- always open floor).
var resident_cell: Vector2i

var _tile_map_layer: TileMapLayer
var _backdrop: ColorRect
var _camera: Camera2D
var _collision_bodies: Dictionary = {}  # local Vector2i -> StaticBody2D
var _light_glows: Array = []  # MeshInstance2D per light cell, in template order
var _tile_size := 16
var _torch_glow := TorchGlow.new()
## The villager standing in this room, or null when nobody is home (see
## place_resident) -- a child of this view, so it is freed with it. Always
## _occupants[0] when there is a group (see place_occupants), so the indoor
## Talk verb and World's own prompt keep reading one field.
var _resident: Node2D = null
## Everybody standing in this room, in the order they were placed. A house
## holds exactly one (place_resident); a mage guild holds several
## (docs/concept/mage_guild.md -- "multiple mages hang around inside").
var _occupants: Array = []
## What stands on each cell right now: local cell -> furniture id, both the
## template's own pieces and whatever the player placed (see set_furniture)
## -- what furniture_at answers.
var _furniture: Dictionary = {}
## Every cell that can hold furniture -- the plan's own floor (anything
## that is not wall, window or door), the exact cells InteriorTemplates.
## piece_grid reports as wood_floor. A placement anywhere else is ignored.
var _floor_cells: Dictionary = {}
var _terrain_renderer: TerrainRenderer

## A little room in front of the walls so they never touch the screen
## edge -- purely cosmetic now (the SubViewport itself is what actually
## bounds what's visible; this used to have to out-grow the outdoor
## camera's own view just to hide the real world behind it, which is why
## it used to need to be enormous -- see visible_world_size_px's own
## removal). Two tiles reads as a comfortable margin without being showy.
const _BACKDROP_MARGIN_TILES := 2.0

## Leaves a little air around the room instead of touching the screen
## edge exactly -- the same reasoning DIORAMA_VIEW_SIZE's own fit-camera
## comment gives, tuned by eye once and then pinned here rather than
## re-eyeballed.
const _CAMERA_FIT_MARGIN := 0.85


## Builds the whole interior scene as children of `self`, positioned near
## local (0,0) -- NOT at the house's real world doorstep any more (see
## this file's own doc comment on why: this view lives inside an isolated
## SubViewport, not the outdoor world, so there is no outdoor coordinate
## for it to align to). `shared_tile_set`: the SAME TileSet the main
## terrain TileMapLayer already built (see TerrainRenderer.build_tile_set
## / EarthChunkManager's own `_tile_map_layer.tile_set = _terrain_renderer.
## build_tile_set()`) -- reused directly, never rebuilt, the same
## convention every sibling overlay layer (roof/furniture/upper floor)
## already follows. `placed_furniture`: what the player put in this house
## (EarthChunkManager.interior_furniture_of -- local cell -> furniture id,
## docs/concept/housing.md "Decorating an entered interior"), laid over
## the plan's floor cells after the template's own pieces; an entry on a
## wall/window/door cell is ignored.
func build(
	interior_family: String, for_occupation: String, seed_value: int,
	shared_tile_set: TileSet, tile_size: int, terrain_renderer: TerrainRenderer,
	placed_furniture: Dictionary = {}
) -> void:
	var result := InteriorTemplates.furnish(interior_family, for_occupation, seed_value)
	occupation = for_occupation
	size = result["size"]
	door_cell = result["door_cell"]
	resident_cell = result["resident_cell"]
	var cells: Dictionary = result["cells"]
	_tile_size = tile_size
	_terrain_renderer = terrain_renderer
	var room_size_px := Vector2(size) * tile_size

	var margin := _BACKDROP_MARGIN_TILES * tile_size
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.04, 0.03)
	_backdrop.position = -Vector2.ONE * margin
	_backdrop.size = room_size_px + Vector2.ONE * margin * 2.0
	_backdrop.z_index = -2
	add_child(_backdrop)

	_tile_map_layer = TileMapLayer.new()
	_tile_map_layer.tile_set = shared_tile_set
	_tile_map_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	add_child(_tile_map_layer)

	for local: Vector2i in cells:
		var value: String = cells[local]
		if value == "wall" or value == "window" or value == "door":
			_tile_map_layer.set_cell(local, 0, terrain_renderer.atlas_coords_for_modification(_piece_id_for(value)))
			if value != "door":
				_add_collision_at(local)
			continue
		_floor_cells[local] = true
		_tile_map_layer.set_cell(local, 0, terrain_renderer.atlas_coords_for_modification(_FLOOR_PIECE_ID))
		if value != "floor":
			set_furniture(local, value)  # the plan's own piece for this resident
	for local: Vector2i in placed_furniture:
		if _floor_cells.has(local) and not _furniture.has(local):
			set_furniture(local, placed_furniture[local])

	# One additive glow per candle (see INTERIOR_LIGHT_RADIUS_TILES) -- the
	# outdoor torch's own material and quad shape (World._update_torch_glow),
	# so a lit room reads the same way a lit night does.
	for light_cell: Vector2i in result["light_cells"]:
		_light_glows.append(_add_glow_at(light_cell))

	# A real physical stop one cell past the door, always present (not
	# part of InteriorTemplates' own grid -- every template ends its grid
	# AT the door row on purpose). Reported live: without this, nothing
	# stopped a player from just walking through the door and on past it
	# without ever pressing the real Leave action -- the door tile itself
	# is deliberately walkable (see _piece_id_for/_BLOCKING_FURNITURE_IDS),
	# so it alone was never a boundary.
	_add_collision_at(door_cell + Vector2i(0, 1))

	_camera = _build_camera(room_size_px)
	add_child(_camera)
	# No explicit `.current = true` -- Godot activates the first Camera2D
	# added to a Viewport with no camera current yet automatically (the
	# same reasoning main_menu.gd's own diorama camera relies on, which
	# never sets it either); this view's camera is always the only one in
	# its own isolated SubViewport, so there's never any ambiguity to
	# resolve. An explicit assignment here throws in a bare --headless
	# test context ("Invalid assignment of property... on Camera2D") --
	# the property setter expects an active rendering surface this early
	# that a real windowed run already has by the time a house is entered.

	z_index = INTERIOR_Z_INDEX


## Frames the WHOLE room, however small -- the outdoor world's fixed 4x
## zoom is what forced the old backdrop to cover a 320x180 world-px view
## no authored room actually fills (reported live as a "huge black
## margin" once the backdrop itself was fixed to really cover that view).
## Fit-to-content, the same shape main_menu.gd's own diorama camera uses
## (zoom = target size / content size, the smaller axis wins so neither
## edge crops), against DisplayScaling's design resolution -- the
## SubViewport this view is built into is always sized to exactly that
## (see World._build_interior_view), so the fit is exact regardless of
## the real window's own size.
func _build_camera(room_size_px: Vector2) -> Camera2D:
	var camera := Camera2D.new()
	camera.position = room_size_px * 0.5
	var target := Vector2(DisplayScaling.DESIGN_WIDTH, DisplayScaling.DESIGN_HEIGHT)
	var fit := minf(target.x / room_size_px.x, target.y / room_size_px.y) * _CAMERA_FIT_MARGIN
	camera.zoom = Vector2.ONE * fit
	return camera


func tile_map_layer() -> TileMapLayer:
	return _tile_map_layer


func backdrop() -> ColorRect:
	return _backdrop


func camera() -> Camera2D:
	return _camera


func collision_body_at(local: Vector2i) -> StaticBody2D:
	return _collision_bodies.get(local)


## Whether `local_position` (this view's OWN local coordinates, i.e. the
## interior avatar's own `position` -- see InteriorAvatar) is close enough
## to the room's own door cell to leave from -- World's own "Leave" prompt
## check. Deliberately SMALLER than one tile (16px): InteriorAvatar spawns
## one full cell north of the door (see World._enter_building_view), and
## this must stay false there -- a player who has just walked in must not
## immediately see (or be able to trigger) "Leave" again before ever
## really being in the room. Standing back at the door cell itself (0px
## away) always counts.
const _EXIT_RADIUS_PX := 10.0

func is_on_exit(local_position: Vector2) -> bool:
	var door_center := (Vector2(door_cell) + Vector2(0.5, 0.5)) * _tile_size
	return local_position.distance_to(door_center) <= _EXIT_RADIUS_PX


func light_glows() -> Array:
	return _light_glows


## Stands the house's own villager on the template's resident cell
## (docs/concept/building.md "Residents inside") -- called by the player's
## enter step only when EarthChunkManager.resident_marker_for says that
## villager is actually at home right now (NpcMarker.is_at_home), so an
## empty house stays honestly empty. Freed with the view on exit, like
## every other child here; the outdoor NpcMarker is never touched.
func place_resident(identity: NpcIdentity) -> Node2D:
	var resident := InteriorResident.new()
	resident.position = (Vector2(resident_cell) + Vector2(0.5, 0.5)) * _tile_size
	resident.z_index = INTERIOR_OCCUPANT_Z_INDEX
	add_child(resident)
	resident.present(identity, INTERIOR_COLLISION_LAYER)
	_resident = resident
	# Kept in the group too, so occupant_identities/occupant_positions
	# answer for a one-villager house exactly as they do for a guild, and
	# a later place_occupants clears this one rather than leaving a ghost
	# standing in the room.
	_occupants = [resident]
	return resident


## Every cell somebody may stand on: open floor with nothing standing on
## it, and never the doorway -- the door has to stay clear or there is no
## way back out. Sorted, so a room always seats a group the same way.
##
## Read off _floor_cells/_furniture rather than from a second table, so a
## piece the player drops on a cell takes that cell out of circulation for
## free.
func standing_cells() -> Array:
	var cells: Array = []
	for local in _floor_cells:
		if local == door_cell or _furniture.has(local):
			continue
		cells.append(local)
	cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	return cells


## Stands a whole group up at once, replacing whoever was standing here.
##
## The FIRST of them takes the template's own resident cell and becomes
## this room's `_resident`, so every existing single-occupant reader --
## resident_identity, resident_position, the indoor Talk verb, World's
## prompt -- keeps working with no knowledge that a group exists at all.
## The rest are spread across the remaining standing cells rather than
## bunched by the door: evenly spaced through the sorted list, so three
## masters occupy a room instead of queueing in it.
##
## A group larger than the room stands up only as many as fit. Returns the
## nodes actually placed.
func place_occupants(identities: Array) -> Array:
	for occupant in _occupants:
		occupant.queue_free()
	_occupants = []
	_resident = null
	if identities.is_empty():
		return []

	var free_cells := standing_cells()
	if free_cells.is_empty():
		return []
	var wanted: int = mini(identities.size(), free_cells.size())

	# The resident cell first if it is free, then the rest of the room
	# sampled evenly -- index i of n walks the whole list instead of its
	# first n entries.
	var chosen: Array = []
	if free_cells.has(resident_cell):
		chosen.append(resident_cell)
	var remaining: Array = []
	for cell in free_cells:
		if not chosen.has(cell):
			remaining.append(cell)
	var still_needed: int = wanted - chosen.size()
	for i in still_needed:
		var index: int = int(floor(float(i) * float(remaining.size()) / float(maxi(still_needed, 1))))
		chosen.append(remaining[clampi(index, 0, remaining.size() - 1)])

	var placed: Array = []
	for i in wanted:
		var occupant := InteriorResident.new()
		occupant.position = (Vector2(chosen[i]) + Vector2(0.5, 0.5)) * _tile_size
		occupant.z_index = INTERIOR_OCCUPANT_Z_INDEX
		add_child(occupant)
		occupant.present(identities[i], INTERIOR_COLLISION_LAYER)
		_occupants.append(occupant)
		placed.append(occupant)
	_resident = _occupants[0]
	return placed


## Everybody standing in this room, in placement order.
func occupant_identities() -> Array:
	var identities: Array = []
	for occupant in _occupants:
		identities.append(occupant.identity)
	return identities


## Where each of them is standing, in this view's own coordinates (the same
## space as InteriorAvatar.position), in placement order.
func occupant_positions() -> Array:
	var positions: Array = []
	for occupant in _occupants:
		positions.append(occupant.position)
	return positions


## Who is home: the placed resident's NpcIdentity, or null when the room is
## empty -- the indoor Talk verb (Player._talk_step) and World's indoors
## prompt read this before ever asking resident_position.
func resident_identity() -> NpcIdentity:
	if _resident == null:
		return null
	return _resident.identity


## The resident's own local position (this view's coordinates, i.e. the
## same space as InteriorAvatar.position, so a plain distance_to between
## the two is the indoor talk range). Vector2.INF when nobody is home --
## infinitely far from everything, so a distance check against it is
## always "out of range" rather than a real corner of the room.
func resident_position() -> Vector2:
	if _resident == null:
		return Vector2.INF
	return _resident.position


## The furniture standing on `local` -- the plan's own piece or one the
## player placed -- or "" for bare floor, a wall, a window or the door.
func furniture_at(local: Vector2i) -> String:
	return _furniture.get(local, "")


## Puts `piece_id` on a floor cell right now -- repainted at once, solid
## if the piece blocks (see _BLOCKING_FURNITURE_IDS) -- the live half of
## decorating (Player._decorate_step): the persisted half is
## EarthChunkManager.place_interior_furniture, which the caller has
## already cleared this placement with. Replaces whatever was on the cell.
## Ignored on a cell that is not floor.
func set_furniture(local: Vector2i, piece_id: String) -> void:
	if not _floor_cells.has(local):
		return
	clear_furniture(local)
	_furniture[local] = piece_id
	_tile_map_layer.set_cell(local, 0, _terrain_renderer.atlas_coords_for_modification(piece_id))
	if _BLOCKING_FURNITURE_IDS.has(piece_id):
		_add_collision_at(local)


## Takes whatever stands on `local` away again: bare floor, no body. A
## no-op on an empty cell.
func clear_furniture(local: Vector2i) -> void:
	if not _furniture.has(local):
		return
	_furniture.erase(local)
	_tile_map_layer.set_cell(local, 0, _terrain_renderer.atlas_coords_for_modification(_FLOOR_PIECE_ID))
	var body: StaticBody2D = _collision_bodies.get(local)
	if body != null:
		_collision_bodies.erase(local)
		body.queue_free()


func _piece_id_for(cell_value: String) -> String:
	if cell_value == "wall":
		return _WALL_PIECE_ID
	if cell_value == "window":
		return _WINDOW_PIECE_ID
	if cell_value == "floor":
		return _FLOOR_PIECE_ID
	if cell_value == "door":
		return _DOOR_PIECE_ID
	return cell_value  # already a real furniture id


func _add_glow_at(local: Vector2i) -> MeshInstance2D:
	var radius_px := INTERIOR_LIGHT_RADIUS_TILES * _tile_size
	var quad := QuadMesh.new()
	quad.size = Vector2(radius_px, radius_px) * 2.0
	var glow := MeshInstance2D.new()
	glow.mesh = quad
	glow.material = _torch_glow.material()
	glow.position = (Vector2(local) + Vector2(0.5, 0.5)) * _tile_size
	glow.z_index = 1  # over the floor and furniture, under the occupant
	add_child(glow)
	return glow


func _add_collision_at(local: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.name = "InteriorCollision_%d_%d" % [local.x, local.y]
	body.collision_layer = INTERIOR_COLLISION_LAYER
	body.position = (Vector2(local) + Vector2(0.5, 0.5)) * _tile_size
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_tile_size, _tile_size)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	_collision_bodies[local] = body
