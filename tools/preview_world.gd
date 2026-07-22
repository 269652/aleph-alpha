extends SceneTree

## Dev tool: prints an ASCII preview of a generated world so biome plausibility
## can be sanity-checked without opening the editor.
## Usage: godot --headless -s tools/preview_world.gd

const WorldGenerator = preload("res://src/world/world_generator.gd")

const BIOME_CHARS := {
	"ocean": "~",
	"mountain": "^",
	"tundra": ".",
	"forest": "T",
	"grassland": ",",
	"rainforest": "R",
	"desert": "d",
}


func _initialize():
	var generator := WorldGenerator.new()
	var width := 80
	var height := 30
	var chunk := generator.generate_world(
		width, height, 42, generator.recommended_erosion_iterations(width, height)
	)

	for y in chunk.height:
		var line := ""
		for x in chunk.width:
			line += BIOME_CHARS[chunk.biome[y * chunk.width + x]]
		print(line)

	quit()
