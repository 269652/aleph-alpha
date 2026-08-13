extends GutTest

## World's small pure helpers for docs/concept/persistence.md's Load Game
## path -- World itself has no direct unit tests (its role is orchestration
## glue over already-tested pieces: Player.apply_save_dict, PlayerSave,
## WorldReset, EarthChunkManager -- see MainMenu's own "purely glue" framing),
## but a genuinely pure, dependency-free helper still gets one.

const World = preload("res://scenes/world.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var world: World


func before_each():
	# Deliberately NOT add_child()'d -- _tile_for_position only touches a
	# plain (non-@onready) field, so it doesn't need the real scene tree.
	world = World.new()


func after_each():
	world.free()


func test_tile_for_position_matches_players_own_pixel_to_tile_conversion():
	var pixel_position := Vector2(4 * TerrainRenderer.TILE_SIZE + 3, 9 * TerrainRenderer.TILE_SIZE + 7)
	assert_eq(world._tile_for_position(pixel_position), Vector2i(4, 9))


func test_tile_for_position_wraps_a_negative_position_into_world_bounds():
	var tile := world._tile_for_position(Vector2(-TerrainRenderer.TILE_SIZE, 0))
	assert_eq(tile.x, EarthChunkGenerator.WORLD_WIDTH_TILES - 1)


## Regression: the player used to spawn at a tile's top-left CORNER while
## every other placed entity (trees, creatures, structures -- see
## EarthChunkManager's `(cell + 0.5) * TILE_SIZE` convention) sits at its
## tile's CENTER. Since a sprite draws centered on its position, that put
## the hero straddling the corner between four tiles instead of standing in
## one -- reported as "the player is offset by half a tile" once tile edges
## got sharp enough to see it.
func test_spawn_position_for_tile_is_centered_in_the_tile():
	var centered := world._spawn_position_for_tile(Vector2i(3, 5))
	assert_almost_eq(centered.x, 3.5 * TerrainRenderer.TILE_SIZE, 0.001)
	assert_almost_eq(centered.y, 5.5 * TerrainRenderer.TILE_SIZE, 0.001)


## The centered spawn must still resolve back to the tile it was derived
## from -- centering is a rendering-alignment fix, not a relocation.
func test_spawn_position_still_resolves_back_to_its_own_tile():
	var tile := Vector2i(7, 2)
	assert_eq(world._tile_for_position(world._spawn_position_for_tile(tile)), tile)
