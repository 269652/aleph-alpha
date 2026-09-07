extends GutTest

## The visible marker over one WildBeePatch nest hole -- see
## ProceduralWildBeeNestSprite, docs/concept/bees.md's "Wild bee nests".
## Mirrors AntMoundMarker's own shape (never player-interactive, no
## `_world` reference needed at all -- relocation, unlike BeeHiveMarker's
## own harvest-triggered one, is driven entirely externally by
## EarthChunkManager checking WildBeePatch.should_relocate_at on its own
## periodic cadence, the same "colony owns the economy, EarthChunkManager
## owns the real ground/site-search and marker teardown/respawn" split
## budding already uses). Unlike AntMoundMarker/BeeHiveMarker, there is
## NO growth-fraction sizing at all: a nest hole is a fixed physical
## feature (see ProceduralWildBeeNestSprite's own doc comment), so this
## marker never resizes and needs no periodic re-check.

const WildBeeNestMarker = preload("res://src/rendering/wild_bee_nest_marker.gd")
const ProceduralWildBeeNestSprite = preload("res://src/rendering/procedural_wild_bee_nest_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")

const WIDTH := 16
const HEIGHT := 16


func _all_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "grassland"
	return biome


func _patch_with_one_nest() -> WildBeePatch:
	for seed_value in range(1, 200):
		var patch := WildBeePatch.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		if patch.nest_cells().size() > 0:
			return patch
	fail_test("no seed in [1, 200) placed a single nest")
	return null


var marker: WildBeeNestMarker


func before_each():
	marker = WildBeeNestMarker.new()
	marker.position = Vector2(120, 80)
	add_child_autofree(marker)


func test_joins_the_wild_bee_nest_group():
	assert_true(marker.is_in_group(WildBeeNestMarker.GROUP_NAME))


func test_joins_the_hoverable_group():
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_stays_exactly_where_placed():
	assert_eq(marker.position, Vector2(120, 80))


## No "harvest" verb at all -- there is nothing to take from a wild
## nest (see bees.md's own real-world grounding: solitary bees produce
## no harvestable surplus). Falls back to no hover actions, the same
## non-interactive shape AntForagerMarker/AntMoundMarker already have.
func test_offers_no_hover_actions():
	assert_false(marker.has_method("get_hover_actions"))


## The tooltip distinction bees.md itself names directly: a wild nest's
## own text never mentions honey at all, unlike BeeHiveMarker's.
func test_get_display_name_never_mentions_honey():
	assert_false(marker.get_display_name().to_lower().contains("honey"))


func test_get_display_name_with_no_patch_reads_as_a_plain_wild_bee_nest():
	assert_eq(marker.get_display_name(), "Wild Bee Nest")


func test_get_display_name_reports_the_real_resident_count_once_a_patch_is_set_up():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	var linked := WildBeeNestMarker.new()
	linked.setup(patch, cell)
	add_child_autofree(linked)
	assert_string_contains(linked.get_display_name(), str(int(round(patch.residents_at(cell)))))


## No panel_state()/animal_state() at all -- a wild nest is neither a
## creature nor panel-worthy the way a honeybee hive's own real honey
## bar is (see bees.md: hoverable, nothing more).
func test_has_no_panel_state():
	assert_false(marker.has_method("panel_state"))
	assert_false(marker.has_method("animal_state"))


# -- fixed size, never grows (see ProceduralWildBeeNestSprite's own -----
# -- doc comment: a hole is a fixed physical feature) --------------------

func test_has_a_real_sprite_texture_at_the_fixed_world_size():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_almost_eq(sprite.scale.x, ProceduralWildBeeNestSprite.WORLD_SCALE, 0.0001)


func test_size_never_changes_regardless_of_resident_count():
	var patch := _patch_with_one_nest()
	var cell: Vector2i = patch.nest_cells()[0]
	var linked := WildBeeNestMarker.new()
	linked.setup(patch, cell)
	add_child_autofree(linked)
	var sprite := linked.get_child(0) as Sprite2D
	var before := sprite.scale.x
	for i in 4000:
		patch.record_forage_result(cell, true)
		patch.advance(WildBeePatch.SECONDS_PER_SIMULATED_DAY)
	linked._process(1.0)
	assert_almost_eq(sprite.scale.x, before, 0.0001, "a nest hole's own physical size never changes")


func test_process_with_no_patch_set_up_does_not_crash():
	marker._process(1.0)
	assert_not_null(marker)
