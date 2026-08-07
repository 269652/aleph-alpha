extends RefCounted

## GPU micro-blade field: the individual 1px grass blades the baked tile
## frames could never truly animate (4 frames of a 1px pixel reads as
## flicker, not wind). Each grassland cell gets BLADES_PER_CELL tiny quad
## blades in ONE MultiMeshInstance2D per chunk -- thousands of blades, one
## draw call, zero per-frame script. A vertex shader bends each blade from
## its root with a per-blade phase (INSTANCE_CUSTOM), so the meadow rolls
## organically instead of bobbing in lockstep.

const BLADES_PER_CELL := 2
const BLADE_WIDTH_PX := 1.0
const BLADE_HEIGHT_PX := 4.0
const AMPLITUDE_PX := 1.6
const WIND_SPEED := 3.0

const SHADER_CODE := """
shader_type canvas_item;

uniform float amplitude_px = 1.6;
uniform float wind_speed = 3.0;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float top_weight = 1.0 - UV.y;
	VERTEX.x += sin(TIME * wind_speed + phase) * amplitude_px * top_weight;
}
"""

const _BLADE_GREENS := [
	Color(0.24, 0.5, 0.15), Color(0.3, 0.6, 0.18), Color(0.45, 0.62, 0.2),
]

var _material: ShaderMaterial


## One swaying blade field covering `chunk_biome`'s grassland cells, placed
## at chunk-local pixel coordinates (caller positions the node at the chunk
## origin). Returns null when the chunk has no grassland at all.
func build_field(chunk_biome: PackedStringArray, width: int, height: int, tile_size: int, seed_value: int) -> MultiMeshInstance2D:
	var placements: Array[Transform2D] = []
	var phases: Array[float] = []
	var colors: Array[Color] = []
	for y in height:
		for x in width:
			if chunk_biome[y * width + x] != "grassland":
				continue
			for i in BLADES_PER_CELL:
				var h := absi(hash("%d_%d_%d_blade_%d" % [seed_value, x, y, i]))
				var px := x * tile_size + 1 + h % (tile_size - 2)
				var py := y * tile_size + 2 + (h / 97) % (tile_size - 3)
				placements.append(Transform2D(0.0, Vector2(px, py - BLADE_HEIGHT_PX / 2.0)))
				phases.append(float((h / 811) % 100) / 100.0)
				colors.append(_BLADE_GREENS[(h / 3271) % _BLADE_GREENS.size()])
	if placements.is_empty():
		return null

	var multimesh := MultiMesh.new()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(BLADE_WIDTH_PX, BLADE_HEIGHT_PX)
	multimesh.mesh = quad
	multimesh.instance_count = placements.size()
	for i in placements.size():
		multimesh.set_instance_transform_2d(i, placements[i])
		multimesh.set_instance_color(i, colors[i])
		multimesh.set_instance_custom_data(i, Color(phases[i], 0, 0, 0))

	var node := MultiMeshInstance2D.new()
	node.multimesh = multimesh
	node.material = _blade_material()
	return node


func _blade_material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("amplitude_px", AMPLITUDE_PX)
		_material.set_shader_parameter("wind_speed", WIND_SPEED)
	return _material
