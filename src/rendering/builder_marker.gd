extends Node2D

## The Builder worker -- the piece docs/concept/timber_construction.md's own
## NPC construction section names as the last missing loop stage: the
## Lumberjack's own loop stops at DEPOSIT; this is CARRY_MATERIAL/PLACE_PIECE,
## an NPC actually building a structure piece by piece. Deliberately NOT built
## on the full NpcMarker/CreatureMarker AI stack, mirroring LumberjackMarker/
## LogisticsMarker's own reasoning for the same choice: a small,
## purpose-built walker, not the full daily-schedule stack.
##
## SEEKING (pick the next real unplaced piece from `target_pieces`, round-
## robin so a refused piece doesn't starve every OTHER piece's own turn) ->
## WITHDRAWING (walk to the nearest real Storage, then withdraw the SPECIFIC
## piece's own real BuildingPiece.cost_of material via
## EarthChunkManager.nearest_structure_position/withdraw_from_structure_at --
## the SAME real accessor Player._collect_step/LogisticsMarker already use)
## -> CARRYING (walk to the build site) -> PLACING (a timed placement of
## exactly one piece, validated against BuildingPlacement.can_place before
## ever calling the real EarthChunkManager.build_at_global -- which itself
## re-syncs the real statics graph exactly the way every other real
## placement does, so nothing here bypasses that mechanism either; a refused
## piece is never force-placed, its withdrawn material is returned to
## Storage, and it stays unplaced for a later SEEKING round to retry) -> back
## to SEEKING, until every real piece across `target_pieces` (ground),
## `target_upper_pieces` (a two-story house's own real second storey) and
## `target_roof_pieces` (the roof) is placed -- strictly in that order, one
## whole layer at a time (see _step_seeking), the same real order a house
## actually goes up in.
##
## `target_project`/`target_pieces`/`project_store`/`household_store`/`earth`
## are all injected by whatever spawns this worker -- the SAME "caller
## assigns what to do" pattern LogisticsMarker's own source_structure_id/
## item_id already establishes (see that file's own class doc comment).
## `target_pieces` is a real piece layout (Vector2i local cell -> piece_id,
## the same Vector2i-cell-keyed shape RoomDetector/BuildingStatics already
## use), footprint-relative to `target_project`'s own site
## (chunk_coord + origin) -- the SAME "origin_tile + local_cell" convention
## EarthChunkManager.stamp_structure_at_global's own doc comment already
## establishes for turning a footprint-relative piece dict into real global
## tile coordinates.
##
## `target_upper_pieces` (docs/concept/housing.md's "Two-story houses"
## section) is the SAME shape, one layer up -- optional (defaults to `{}`,
## so every existing single-story hire is completely unaffected), placed
## into EarthChunkManager.upper_floor_modifications via build_upper_floor_
## at_global rather than build_at_global. Deliberately built only AFTER
## every real ground piece is placed (see _step_seeking) -- the same
## real-world order a building actually goes up in, and it means a house's
## own ground floor is never left half-built while material gets spent
## upstairs instead.
##
## `target_roof_pieces` closes this file's own long-standing "roof pieces
## out of scope" gap (see below) -- optional (defaults to `{}`), built
## LAST, once every real ground AND upper piece is placed: a roof caps
## whichever floor is topmost, so it can never legitimately go up before
## the walls it rests on. Placed via the new EarthChunkManager.build_roof_
## at_global, checked against BuildingPlacement's own real "a roof needs a
## floor beneath it" rule (see _attempt_place).
##
## Deliberately does NOT auto-wire itself to any ConstructionProject lookup
## or spawn-per-structure trigger -- there is no real caller yet that decides
## a Builder should exist for a given project (see docs/concept/
## timber_construction.md's own Status entry for this gap). A bare, real,
## tested BuilderMarker/BuilderBehavior a FUTURE caller can inject a
## project/piece-dict into is this pass's own honest scope, matching how
## LogisticsMarker itself shipped real and tested before EarthChunkManager
## auto-spawned it in a later pass.
##
## `_buildable_ground` and roof pieces were BOTH originally out of scope
## here (`_buildable_ground` a permissive stand-in always answering true;
## `CATEGORY_ROOF` living in a SEPARATE `roof_modifications` layer only
## `stamp_structure_at_global` wrote to) -- both gaps are closed now:
## `_buildable_ground` calls the real EarthChunkManager.is_buildable_
## terrain_at (see that function's own doc comment), and roofs are real
## via `target_roof_pieces` above.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const BuildingPlacement = preload("res://src/gameplay/building_placement.gd")
const BuilderBehavior = preload("res://src/gameplay/builder_behavior.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")

const GROUP_NAME := "builder"

const WALK_SPEED := 28.0
const ARRIVE_DISTANCE_PX := 4.0

## Mirrors EarthChunkManager.CHUNK_SIZE's own exact value -- duplicated
## rather than preloading that whole large, engine-dependent singleton file
## here, the same reasoning `earth` itself being a late-bound, untyped
## reference already models (LogisticsMarker/LumberjackMarker avoid a hard
## static dependency on it too). Cross-checked directly against the real
## EarthChunkManager.CHUNK_SIZE by
## test_builder_marker.gd's own test_chunk_size_matches_earth_chunk_manager,
## so drift would fail loudly rather than silently misplacing every piece.
const CHUNK_SIZE := 32

var storage_structure_id := "storage"
var search_radius_tiles := 20

## Injected by the caller -- see this file's own header.
var target_project = null
var target_pieces: Dictionary = {}
var target_upper_pieces: Dictionary = {}
var target_roof_pieces: Dictionary = {}
var project_store = null
var household_store = null

## Late-bound world reference, the same pattern LogisticsMarker/
## LumberjackMarker already use for their own EarthChunkManager access.
var earth = null

var _behavior := BuilderBehavior.new()
var _building_placement := BuildingPlacement.new()

## Which of the three real layers (see this file's own header) the
## currently-committed piece belongs to -- decides which grid _attempt_
## place validates against and which real EarthChunkManager setter places
## it. Set once per commit in _step_seeking, read in _attempt_place and
## nowhere else.
const LAYER_GROUND := "ground"
const LAYER_UPPER := "upper"
const LAYER_ROOF := "roof"

var _next_cell_index := 0
var _next_upper_cell_index := 0
var _next_roof_cell_index := 0
var _current_local_cell := Vector2i.ZERO
var _current_piece_id := ""
var _current_layer := LAYER_GROUND
var _current_cost: Dictionary = {}
var _storage_target_position := Vector2.ZERO
var _arrived_at_storage := false


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	# No dedicated Builder art yet -- reusing Storage's own tile art at marker
	# scale is a placeholder, the SAME stand-in LogisticsMarker's own sprite
	# already uses for the identical reason (a dedicated worker sprite is a
	# follow-up, not this pass's scope).
	sprite.texture = ProceduralStructureSprite.new().generate_texture("storage")
	sprite.scale = Vector2.ONE * 0.5
	add_child(sprite)


func _process(delta: float) -> void:
	match _behavior.phase:
		BuilderBehavior.Phase.SEEKING:
			_step_seeking(delta)
		BuilderBehavior.Phase.WITHDRAWING:
			_step_withdrawing(delta)
		BuilderBehavior.Phase.CARRYING:
			_step_carrying(delta)
		BuilderBehavior.Phase.PLACING:
			_step_placing(delta)


func _step_seeking(delta: float) -> void:
	_behavior.advance(delta)  # no-op outside SEEKING's own rehunt clock
	if not _behavior.can_commit():
		return
	if earth == null or target_project == null or project_store == null:
		return
	if target_pieces.is_empty() and target_upper_pieces.is_empty() and target_roof_pieces.is_empty():
		return
	var layer := LAYER_GROUND
	var candidate = _next_unplaced_piece()
	if candidate == null:
		# The ground floor is fully placed (or there never was one) -- only
		# THEN does a real house get its own upper storey started, the same
		# real-world build order this file's own header documents.
		candidate = _next_unplaced_upper_piece()
		layer = LAYER_UPPER
	if candidate == null:
		# Both floors are fully placed (or a single-story house never had an
		# upper one) -- only THEN does the roof go up, since it caps
		# whichever floor is topmost and can't legitimately exist before it.
		candidate = _next_unplaced_roof_piece()
		layer = LAYER_ROOF
	if candidate == null:
		return  # every real piece across all three layers is already placed
	var storage_position = earth.nearest_structure_position(
		position, storage_structure_id, float(search_radius_tiles) * TerrainRenderer.TILE_SIZE
	)
	if storage_position == null:
		return  # nowhere to withdraw from yet -- retry once the rehunt clock allows

	_current_local_cell = candidate["local_cell"]
	_current_piece_id = candidate["piece_id"]
	_current_layer = layer
	_current_cost = BuildingPiece.cost_of(_current_piece_id)
	_storage_target_position = storage_position
	_arrived_at_storage = false
	_behavior.begin_withdraw()


func _step_withdrawing(delta: float) -> void:
	if not _arrived_at_storage:
		var to_storage: Vector2 = _storage_target_position - position
		if to_storage.length() <= ARRIVE_DISTANCE_PX:
			_arrived_at_storage = true
		else:
			position += to_storage.normalized() * WALK_SPEED * delta
			return
	if not _behavior.advance_withdraw(delta):
		return
	if not _withdraw_current_cost():
		_behavior.abort()
		return
	_behavior.start_carry()


func _step_carrying(delta: float) -> void:
	var site_position := _site_pixel_position()
	var to_site: Vector2 = site_position - position
	if to_site.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive_at_site()
		return
	position += to_site.normalized() * WALK_SPEED * delta


func _step_placing(delta: float) -> void:
	if not _behavior.advance_place(delta):
		return
	if _attempt_place():
		_credit_labor_for_current_piece()
	else:
		_return_current_cost_to_storage()
	_behavior.finish_place()


## The next real unplaced piece in `target_pieces`, round-robin from wherever
## the last attempt left off -- so a piece that gets refused at PLACING time
## doesn't starve every OTHER piece's own turn (see this file's own header).
## Verifies each cell's OWN real placed state via earth.modification_at_global
## rather than trusting a separately-tracked "done" set, per this pass's own
## "each real placed cell verified, not just a count" brief. Returns null if
## every real piece is already placed.
func _next_unplaced_piece():
	var sorted_cells := _sorted_local_cells()
	var count := sorted_cells.size()
	if count == 0:
		return null
	for offset in range(count):
		var index := (_next_cell_index + offset) % count
		var local_cell: Vector2i = sorted_cells[index]
		var piece_id: String = target_pieces[local_cell]
		var global_cell := _global_cell_for(local_cell)
		if earth.modification_at_global(global_cell.x, global_cell.y) == piece_id:
			continue  # already really placed
		_next_cell_index = (index + 1) % count
		return {"local_cell": local_cell, "piece_id": piece_id}
	return null


## `target_pieces`' own keys, deterministically sorted (y then x, the SAME
## convention BuildingStatics._cell_before already uses) -- so round-robin
## order is stable/reproducible regardless of Dictionary insertion order.
func _sorted_local_cells() -> Array:
	var cells: Array = target_pieces.keys()
	cells.sort_custom(_cell_before)
	return cells


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## The upper-storey twin of _next_unplaced_piece, one layer up -- the SAME
## round-robin/"verify against the real world, not a tracked done set"
## contract, mirrored against target_upper_pieces/earth.upper_floor_at_
## global instead of target_pieces/earth.modification_at_global. Only ever
## reached once _next_unplaced_piece itself returns null (see _step_seeking)
## -- a house's ground floor finishes before its own upper storey starts.
func _next_unplaced_upper_piece():
	var sorted_cells := _sorted_upper_local_cells()
	var count := sorted_cells.size()
	if count == 0:
		return null
	for offset in range(count):
		var index := (_next_upper_cell_index + offset) % count
		var local_cell: Vector2i = sorted_cells[index]
		var piece_id: String = target_upper_pieces[local_cell]
		var global_cell := _global_cell_for(local_cell)
		if earth.upper_floor_at_global(global_cell.x, global_cell.y) == piece_id:
			continue  # already really placed
		_next_upper_cell_index = (index + 1) % count
		return {"local_cell": local_cell, "piece_id": piece_id}
	return null


func _sorted_upper_local_cells() -> Array:
	var cells: Array = target_upper_pieces.keys()
	cells.sort_custom(_cell_before)
	return cells


## The roof's own twin of _next_unplaced_piece/_next_unplaced_upper_piece --
## the SAME round-robin/"verify against the real world" contract, mirrored
## against target_roof_pieces/earth.roof_at_global. Only ever reached once
## BOTH _next_unplaced_piece and _next_unplaced_upper_piece return null
## (see _step_seeking) -- the roof caps whichever floor is topmost, so it
## goes up last, never before the walls it rests on.
func _next_unplaced_roof_piece():
	var sorted_cells := _sorted_roof_local_cells()
	var count := sorted_cells.size()
	if count == 0:
		return null
	for offset in range(count):
		var index := (_next_roof_cell_index + offset) % count
		var local_cell: Vector2i = sorted_cells[index]
		var piece_id: String = target_roof_pieces[local_cell]
		var global_cell := _global_cell_for(local_cell)
		if earth.roof_at_global(global_cell.x, global_cell.y) == piece_id:
			continue  # already really placed
		_next_roof_cell_index = (index + 1) % count
		return {"local_cell": local_cell, "piece_id": piece_id}
	return null


func _sorted_roof_local_cells() -> Array:
	var cells: Array = target_roof_pieces.keys()
	cells.sort_custom(_cell_before)
	return cells


## Withdraws EVERY real item_id/count in `_current_cost` from the currently-
## targeted Storage, all-or-nothing across the WHOLE cost (not just per
## item) -- checks every item's real available stock first so a multi-item
## cost (e.g. stone_door's stone+wood) never withdraws SOME of its items and
## leaves the rest short. Returns false (nothing withdrawn) if any one item
## is short.
func _withdraw_current_cost() -> bool:
	var storage_tile := _tile_for(_storage_target_position)
	for item_id in _current_cost:
		if earth.structure_stock_at(storage_tile.x, storage_tile.y, item_id) < int(_current_cost[item_id]):
			return false
	for item_id in _current_cost:
		earth.withdraw_from_structure_at(storage_tile.x, storage_tile.y, item_id, int(_current_cost[item_id]))
	return true


## A refused placement's material goes straight back to the SAME Storage it
## came from -- mirroring LogisticsMarker's own "put it back" discipline when
## a delivery can't complete, so a refusal never just silently destroys real
## withdrawn stock.
func _return_current_cost_to_storage() -> void:
	var storage_tile := _tile_for(_storage_target_position)
	for item_id in _current_cost:
		earth.deposit_to_structure_at(storage_tile.x, storage_tile.y, item_id, int(_current_cost[item_id]))


## The real placement attempt: BuildingPlacement.can_place first (a refused
## piece is never force-placed -- build_at_global is never even called on
## that branch), THEN the real EarthChunkManager.build_at_global -- which
## itself re-syncs the real statics support graph exactly the way every
## other real placement (player, village generator) already does, so nothing
## here bypasses that mechanism either. Returns whether the piece actually
## landed.
##
## Branches on _current_layer (see _step_seeking) to place against the
## UPPER floor or the ROOF instead -- each its own grid snapshot and its
## own real EarthChunkManager setter, never the ground ones, so a piece's
## own adjacency is always judged against the layer it actually belongs to
## (the floors can legitimately differ at the same cell -- see
## EarthChunkManager.UPPER_FLOOR_COLLISION_LAYER's own doc comment for why).
##
## The roof branch reads its OWN "is there a floor beneath this cell"
## check off the GROUND grid, not the upper one, even for a two-story
## house: every real two-story shape in HouseBlueprint shares an IDENTICAL
## floor/wall footprint between its ground and upper layers (no notches --
## see TWO_STORY_BLUEPRINT_IDS' own doc comment), so the two grids always
## agree on which cells are floor. Reusing the already-real ground snapshot
## is correct, not a shortcut, for every real catalog shape today.
func _attempt_place() -> bool:
	var global_cell := _global_cell_for(_current_local_cell)
	if _current_layer == LAYER_ROOF:
		var grid := _local_grid_snapshot(global_cell)
		var roofs := _roof_snapshot(global_cell)
		if not _building_placement.can_place(_current_piece_id, global_cell, grid, _buildable_ground, roofs):
			return false
		earth.build_roof_at_global(global_cell.x, global_cell.y, _current_piece_id)
		return true
	if _current_layer == LAYER_UPPER:
		var upper_grid := _upper_local_grid_snapshot(global_cell)
		if not _building_placement.can_place(_current_piece_id, global_cell, upper_grid, _buildable_ground):
			return false
		earth.build_upper_floor_at_global(global_cell.x, global_cell.y, _current_piece_id)
		return true
	var grid := _local_grid_snapshot(global_cell)
	if not _building_placement.can_place(_current_piece_id, global_cell, grid, _buildable_ground):
		return false
	earth.build_at_global(global_cell.x, global_cell.y, _current_piece_id)
	return true


## A minimal, single-cell roof snapshot for BuildingPlacement's own
## `roofs` parameter -- unlike the 5-cell ground/upper snapshots, its own
## refusal_reason only ever checks `roofs.has(cell)` for the EXACT target
## cell (see building_placement.gd), never a neighbor.
func _roof_snapshot(global_cell: Vector2i) -> Dictionary:
	var roof_id: String = earth.roof_at_global(global_cell.x, global_cell.y)
	return {global_cell: roof_id} if roof_id != "" else {}


## A minimal real grid snapshot -- just `global_cell` and its 4 orthogonal
## neighbors -- read live via earth.modification_at_global. BuildingPlacement
## only ever looks at the target cell itself and its immediate neighbors
## (see its own _touches_floor), so this is sufficient without needing a
## whole-chunk grid accessor. Keyed in GLOBAL tile coordinates throughout --
## self-consistent with `global_cell` itself, which is all BuildingPlacement
## actually requires (it never assumes an absolute-vs-relative frame).
func _local_grid_snapshot(global_cell: Vector2i) -> Dictionary:
	var grid := {}
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for offset in offsets:
		var cell := global_cell + offset
		var tile_id: String = earth.modification_at_global(cell.x, cell.y)
		if BuildingPiece.has_piece(tile_id):
			grid[cell] = tile_id
	return grid


## The upper-storey twin of _local_grid_snapshot, reading earth.upper_
## floor_at_global instead of earth.modification_at_global.
func _upper_local_grid_snapshot(global_cell: Vector2i) -> Dictionary:
	var grid := {}
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for offset in offsets:
		var cell := global_cell + offset
		var tile_id: String = earth.upper_floor_at_global(cell.x, cell.y)
		if BuildingPiece.has_piece(tile_id):
			grid[cell] = tile_id
	return grid


## Real terrain buildability (docs/concept/building.md): no water, no
## forest, and no standing tree still in the way -- the SAME real
## EarthChunkManager.is_buildable_terrain_at the player's own
## can_build_house_from_blueprint now checks, so a hired house is refused
## on identical terms to a self-built one. Previously a permissive
## stand-in (`return true`) -- named and documented as a real, honest gap
## rather than silently assumed; that gap is closed now.
func _buildable_ground(cell: Vector2i) -> bool:
	return earth.is_buildable_terrain_at(cell.x, cell.y)


## Credits this piece's own real labor-hours onto the real project, and
## completes it via ConstructionProjectStore once every real piece's worth
## has accumulated -- see ConstructionProjectStore.advance_project_labor_for
## _piece's own doc comment for the full contract.
##
## `required` sums ALL THREE layers' own real totals (target_upper_pieces/
## target_roof_pieces are both {} for whatever a hire doesn't have -- a
## single-story hire's target_upper_pieces is always {}, and either one
## being {} contributes exactly 0.0 via labor_hours_required_for_pieces --
## so this stays identical to before two-story houses/roofs existed for
## any caller that never sets them) -- a project only ever reaches COMPLETE
## once every real piece across every real layer it actually has has been
## placed.
func _credit_labor_for_current_piece() -> void:
	var required := (
		ConstructionLabor.labor_hours_required_for_pieces(target_pieces)
		+ ConstructionLabor.labor_hours_required_for_pieces(target_upper_pieces)
		+ ConstructionLabor.labor_hours_required_for_pieces(target_roof_pieces)
	)
	project_store.advance_project_labor_for_piece(
		target_project.id, _current_piece_id, required, household_store
	)


## `local_cell` (footprint-relative to target_project's own site) -> a real
## global tile coordinate, the SAME "origin_tile + local_cell" convention
## EarthChunkManager.stamp_structure_at_global's own doc comment establishes.
func _global_cell_for(local_cell: Vector2i) -> Vector2i:
	return target_project.chunk_coord * CHUNK_SIZE + target_project.origin + local_cell


func _site_pixel_position() -> Vector2:
	var global_cell := _global_cell_for(_current_local_cell)
	return (Vector2(global_cell) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE


## Recovers the global tile coordinate a tile-center pixel position
## (nearest_structure_position's own return shape) came from -- mirrors
## LogisticsMarker's own identical _tile_for helper.
func _tile_for(tile_center_pixel: Vector2) -> Vector2i:
	return Vector2i(
		floori(tile_center_pixel.x / TerrainRenderer.TILE_SIZE), floori(tile_center_pixel.y / TerrainRenderer.TILE_SIZE)
	)
