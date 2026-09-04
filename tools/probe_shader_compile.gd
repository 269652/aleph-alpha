extends SceneTree

## Dev tool: puts RiverFlowShader.SHADER_CODE through Godot's own shader
## PARSER and reports whether it survived.
##
## The render smoke test cannot answer this under --headless (no rendering
## device, so nothing is ever compiled), and the string assertions in
## test_river_flow_shader.gd only prove the source says what we think it
## says -- not that it is valid GLSL. A shader that fails to parse renders
## nothing at all, which has already happened once in this feature's life
## (a GDScript `##` comment left inside the shader string).
##
## Godot's parser runs on the CPU, so setting `code` reports errors here
## even with no GPU. A parsed shader exposes its uniforms; a broken one
## exposes none.
##
## Usage: godot --headless --path . -s tools/probe_shader_compile.gd

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")


func _initialize() -> void:
	var shader := Shader.new()
	shader.code = RiverFlowShader.SHADER_CODE
	var uniforms := shader.get_shader_uniform_list()
	print("uniforms exposed: %d" % uniforms.size())
	if uniforms.is_empty():
		print("SHADER DID NOT PARSE -- see the errors above")
		quit(1)
		return
	var names := []
	for uniform in uniforms:
		names.append(uniform["name"])
	# The uniforms this pass introduced or depends on, by name.
	for required in ["smear_curvature", "smear_spacing", "flow_across_map", "flow_scale_map"]:
		print("   %-18s %s" % [required, "present" if required in names else "MISSING"])
	# And the material the game actually builds, with its defaults applied.
	var material: ShaderMaterial = RiverFlowShader.new().make_material()
	print("material smear_curvature = %s" % str(material.get_shader_parameter("smear_curvature")))
	print("SHADER PARSED")
	quit()
