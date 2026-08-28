extends GutTest

## Spawns/despawns WildCropMarker nodes to match a WildCropPatch sim's
## current cells -- the individual-Node2D-per-cell counterpart of what
## _sync_grass_sprites does with MultiMesh bands, appropriate here because
## wild crop patches are sparse and each cell needs its own hover/pull
## identity (see docs/concept/wild_crops.md).

const WildCropRenderer = preload("res://src/rendering/wild_crop_renderer.gd")
const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")
const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")

const TILE_SIZE := 16.0
const CHUNK_ORIGIN := Vector2i(100, 200)
const WIDTH := 16
const HEIGHT := 16

var renderer: WildCropRenderer
var parent: Node2D


func before_each():
	renderer = WildCropRenderer.new()
	# WildCropMarker's own children (soil/leaves/root) are built in _ready(),
	# which only fires once a node is genuinely in the live SceneTree -- a
	# bare, never-added Node2D parent (StoneRenderer's own test convention,
	# which happens not to need _ready() for what it asserts) isn't enough
	# here, since begin_pull() touches those child sprites directly.
	parent = Node2D.new()
	add_child_autofree(parent)


func _biome_all_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill("grassland")
	return biome


func test_spawn_markers_makes_one_marker_per_patch_cell():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(markers.size(), sim.get_patch_cells().size())
	assert_eq(parent.get_child_count(), markers.size())
	assert_gt(markers.size(), 0, "precondition: this seed/biome produced at least one patch")


func test_spawned_markers_are_positioned_at_their_tile_center():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	for cell in markers:
		var marker: WildCropMarker = markers[cell]
		var expected := Vector2(
			(CHUNK_ORIGIN.x + cell.x + 0.5) * TILE_SIZE, (CHUNK_ORIGIN.y + cell.y + 0.5) * TILE_SIZE
		)
		assert_eq(marker.position, expected)


func test_spawned_markers_carry_the_crop_id_and_current_growth():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	for cell in markers:
		var marker: WildCropMarker = markers[cell]
		assert_eq(marker.crop_id, "carrot")
		assert_eq(marker.growth, sim.get_growth(cell))


## Retries several spread ticks rather than assuming one tick lands a new
## cell -- each tick's single pick (WildCropPatch.SPREAD_PER_TICK == 1) can
## land on an already-occupied neighbor and do nothing that round, same as
## real spread's own throttled, sometimes-a-no-op nature.
func _advance_until_a_new_cell_appears(sim, max_ticks: int = 50) -> void:
	var before: int = sim.get_patch_cells().size()
	for i in max_ticks:
		sim.advance(WildCropPatch.SPREAD_INTERVAL, 1.0)
		if sim.get_patch_cells().size() > before:
			return


func test_sync_markers_adds_a_marker_for_a_newly_spread_cell():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	var before := markers.size()
	_advance_until_a_new_cell_appears(sim)
	assert_gt(sim.get_patch_cells().size(), before, "precondition: spread actually added a cell")
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_eq(markers.size(), sim.get_patch_cells().size())


func test_sync_markers_updates_growth_on_an_existing_marker():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	_advance_until_a_new_cell_appears(sim)
	var immature_cell := Vector2i(-1, -1)
	for cell in sim.get_patch_cells():
		if sim.get_growth(cell) < 1.0:
			immature_cell = cell
	assert_ne(immature_cell, Vector2i(-1, -1), "precondition: spread produced an immature cell")
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers)
	sim.advance(1.0, 1.0)
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers)
	var marker: WildCropMarker = markers[immature_cell]
	assert_eq(marker.growth, sim.get_growth(immature_cell))


func test_sync_markers_frees_and_removes_a_marker_whose_cell_was_harvested():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	var cell: Vector2i = markers.keys()[0]
	var marker: WildCropMarker = markers[cell]
	sim.graze(cell)
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_false(markers.has(cell))
	assert_true(marker.is_queued_for_deletion())


## A marker that is still mid-pull-animation must not be torn down by a
## sync tick just because it hasn't finished yet -- its cell is still
## genuinely present in the sim until the pull actually completes (see
## WildCropMarker._finish_pull).
func test_sync_markers_leaves_a_mid_pull_marker_alone():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	var cell: Vector2i = markers.keys()[0]
	var marker: WildCropMarker = markers[cell]
	marker.begin_pull()
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_true(markers.has(cell))
	assert_false(marker.is_queued_for_deletion())


# -- the season reaches the markers this renderer owns -----------------------

## Same shape `growth` already uses: the renderer pushes the season in on its
## own refresh cadence, the marker never reads a clock itself.
func test_markers_are_spawned_wearing_the_current_season():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var winter := SeasonalFoliage.tint_for_season("winter")
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, winter)
	assert_gt(markers.size(), 0, "precondition: something got spawned")
	for cell in markers:
		assert_eq(markers[cell].season_tint, winter)


## A chunk loaded in summer is still on screen when autumn arrives, so the
## season has to reach markers that already exist, not just new ones.
func test_syncing_pushes_a_changed_season_onto_every_live_marker():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(markers.size(), 0, "precondition: something got spawned")
	var autumn := SeasonalFoliage.tint_for_season("autumn")
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers, autumn)
	for cell in markers:
		assert_eq(markers[cell].season_tint, autumn)


## Every caller that has not been taught about the season yet must keep
## seeing exactly today's picture.
func test_a_caller_that_never_mentions_the_season_gets_untinted_markers():
	var sim := WildCropPatch.new("carrot", 1, WIDTH, HEIGHT, _biome_all_grassland())
	var markers := renderer.spawn_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE)
	renderer.sync_markers(parent, sim, "carrot", CHUNK_ORIGIN, TILE_SIZE, markers)
	for cell in markers:
		assert_eq(markers[cell].season_tint, Color.WHITE)
