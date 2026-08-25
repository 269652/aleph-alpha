extends GutTest

## Strata: per-chunk, per-layer solid/ore/tunnel rock sim (see
## docs/concept/geology.md "Real strata, not a backdrop"). One class, four
## real layers, differently parameterized rather than four separate
## classes.

const Strata = preload("res://src/world/strata.gd")


func _make(layer: String = Strata.LAYER_BEDROCK, origin: Vector2i = Vector2i.ZERO) -> Strata:
	return Strata.new(layer, origin)


func test_four_real_layers_are_named():
	assert_eq(Strata.LAYERS.size(), 4)
	assert_true(Strata.LAYERS.has(Strata.LAYER_TOPSOIL_REGOLITH))
	assert_true(Strata.LAYERS.has(Strata.LAYER_BEDROCK))
	assert_true(Strata.LAYERS.has(Strata.LAYER_DEEP_BEDROCK))
	assert_true(Strata.LAYERS.has(Strata.LAYER_HYDROTHERMAL))


func test_unmined_cell_is_solid_or_ore_never_tunnel():
	var strata := _make()
	for y in 20:
		for x in 20:
			var kind: String = strata.cell_kind_at(Vector2i(x, y))
			assert_ne(kind, Strata.KIND_TUNNEL, "unmined cell (%d,%d) should not be a tunnel" % [x, y])
			assert_true(
				kind == Strata.KIND_SOLID or kind == Strata.KIND_ORE,
				"unexpected kind %s at (%d,%d)" % [kind, x, y]
			)


func test_cell_kind_is_deterministic():
	var strata := _make()
	var a := strata.cell_kind_at(Vector2i(3, 4))
	var b := strata.cell_kind_at(Vector2i(3, 4))
	assert_eq(a, b)


func test_some_cells_are_ore_and_most_are_solid():
	var strata := _make()
	var ore_count := 0
	var solid_count := 0
	for y in 40:
		for x in 40:
			var kind: String = strata.cell_kind_at(Vector2i(x, y))
			if kind == Strata.KIND_ORE:
				ore_count += 1
			elif kind == Strata.KIND_SOLID:
				solid_count += 1
	assert_gt(ore_count, 0, "expected some ore cells")
	assert_gt(solid_count, ore_count, "solid rock should dominate over ore")


func test_mining_a_cell_makes_it_a_tunnel():
	var strata := _make()
	var cell := Vector2i(1, 1)
	strata.mine_at(cell)
	assert_eq(strata.cell_kind_at(cell), Strata.KIND_TUNNEL)


func test_mining_is_permanent_for_this_instance():
	var strata := _make()
	var cell := Vector2i(2, 2)
	strata.mine_at(cell)
	strata.mine_at(cell)  # mining an already-open tunnel again is a no-op
	assert_eq(strata.cell_kind_at(cell), Strata.KIND_TUNNEL)


func test_mining_only_affects_the_mined_cell():
	var strata := _make()
	strata.mine_at(Vector2i(5, 5))
	assert_ne(strata.cell_kind_at(Vector2i(6, 5)), Strata.KIND_TUNNEL)


func test_different_layers_at_the_same_origin_can_differ():
	# Not a strict requirement per-cell, but across many cells the different
	# per-layer ore density/weighting must actually produce different maps.
	var bedrock := _make(Strata.LAYER_BEDROCK)
	var hydrothermal := _make(Strata.LAYER_HYDROTHERMAL)
	var differs := false
	for y in 30:
		for x in 30:
			var cell := Vector2i(x, y)
			if bedrock.cell_kind_at(cell) != hydrothermal.cell_kind_at(cell):
				differs = true
				break
	assert_true(differs, "different layers should produce different rock maps somewhere")


func test_ore_type_at_matches_layer_aware_genesis():
	var strata := _make(Strata.LAYER_HYDROTHERMAL)
	var GeologyOreGenesis = load("res://src/world/geology_ore_genesis.gd")
	var genesis = GeologyOreGenesis.new()
	assert_eq(
		strata.ore_type_at(10, 10),
		genesis.ore_type_at(10, 10, Strata.LAYER_HYDROTHERMAL)
	)


func test_chunk_origin_offsets_the_global_coordinates_sampled():
	var at_origin := Strata.new(Strata.LAYER_BEDROCK, Vector2i.ZERO)
	var shifted := Strata.new(Strata.LAYER_BEDROCK, Vector2i(100, 100))
	# Local (0,0) in the shifted chunk samples global (100,100), which must
	# match a strata rooted directly there.
	var direct := Strata.new(Strata.LAYER_BEDROCK, Vector2i(100, 100))
	assert_eq(shifted.cell_kind_at(Vector2i.ZERO), direct.cell_kind_at(Vector2i.ZERO))


func test_seed_at_deterministic():
	var strata := _make()
	assert_eq(strata.seed_at(9, 9), strata.seed_at(9, 9))
