extends SceneTree

## Real-render before/after for the bend-clipping fix (docs/concept/
## long_grass.md's "Where a bent blade actually goes"). Per this codebase's
## own discipline, a headless test is not evidence for "what does this
## actually look like" -- needs a real GPU context, not --headless. Run:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_grass_bend_clipping.gd
##
## Draws ONE real cell's own cards twice in the SAME frame (so both see the
## identical TIME, and therefore the identical wind): left with the OLD
## sampling-only bend on a plain quad, right with the shipped geometry bend
## on the subdivided one. A walker stands right beside each clump, so the
## push term is at its full WALKER_PUSH_UV_AMPLITUDE.
##
## CONFIRMED (2026-09-17), rendered under xvfb + Mesa (software GL), which is
## a real GPU pipeline as far as the shader is concerned:
##  - bend_calm.png (no walker anywhere): the two clumps are pixel-alike, so
##    the fix genuinely changes nothing about an unbent card.
##  - bend_walker.png: the OLD clump is visibly CUT -- a squat stub with its
##    leaning half missing, exactly the reported "clipped on the left and
##    right". The NEW clump instead LEANS: blades sweep out well past the
##    card's own upright footprint, parting to both sides of the walker
##    (cards left of them push left, cards right of them push right), with
##    roots still planted at the same ground line.
##
## EXTENDED (2026-09-17, same day) with a third panel after the next live
## report -- "the grassblades elongate and stretch instead of only bending"
## -- so all three generations stand side by side: sampling-only, the pure
## SHEAR that stretched them, and the shipped arc. It now also MEASURES the
## furthest blade pixel from its own root, which is the number that report
## is about: a shear cannot be seen in blade HEIGHT at all, since it
## preserves height by construction -- what grows is the diagonal. Under a
## walker: sampling-only 17.7px, shear 31.4px, arc 20.1px, on a card 16px
## tall that reaches 17.9px at rest.

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")

const OUT_DIR := "res://tools/grass_bend_renders"
const VIEW := Vector2i(240, 80)
const OLD_GROUND := Vector2(40, 68)
const SHEAR_GROUND := Vector2(120, 68)
const NEW_GROUND := Vector2(200, 68)


## The shader exactly as it was before the fix: the whole bend lives in
## fragment(), displacing the SAMPLED column inside a quad that never moves.
static func old_shader_code() -> String:
	return """
shader_type canvas_item;
uniform vec2 player_world_position = vec2(-100000.0);
uniform float walker_radius = 22.0;
uniform float wind_speed = 1.6;
uniform float wind_strength = 1.0;
uniform vec3 season_tint = vec3(1.0);

varying vec2 v_root;
varying vec4 v_region;

void vertex() {
	v_root = (MODEL_MATRIX * vec4(vec2(0.0), 0.0, 1.0)).xy;
	v_region = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 region_uv0 = v_region.rg;
	vec2 region_uv1 = v_region.ba;
	vec2 region_size = max(region_uv1 - region_uv0, vec2(0.0001));

	float bend = pow(clamp(UV.y, 0.0, 1.0), %s);
	float phase = UV.x * %s;
	float amplitude_scale = %s + %s * sin(UV.x * %s);

	vec2 from_walker = v_root - player_world_position;
	float distance_to_walker = length(from_walker);
	vec2 away = from_walker / max(distance_to_walker, 0.001);
	float wake = 1.0 - smoothstep(0.0, walker_radius, distance_to_walker);

	float wind = sin(TIME * wind_speed + v_root.x * 0.071 + v_root.y * 0.043 + phase) * %s * wind_strength * amplitude_scale;
	float push = away.x * wake * %s;
	float bend_offset = (wind + push) * bend;

	float raw_local_x = UV.x - bend_offset;
	float local_x = clamp(raw_local_x, 0.0, 1.0);
	vec2 atlas_uv = region_uv0 + vec2(local_x, 1.0 - UV.y) * region_size;
	COLOR = texture(TEXTURE, atlas_uv);
	if (raw_local_x < 0.0 || raw_local_x > 1.0) {
		COLOR.a = 0.0;
	}
}
""" % [
		IllustratedGrassPatch.BEND_CURVE_EXPONENT, IllustratedGrassPatch.PHASE_SPREAD,
		IllustratedGrassPatch.AMPLITUDE_BASE, IllustratedGrassPatch.AMPLITUDE_VARIATION,
		IllustratedGrassPatch.AMPLITUDE_FREQUENCY, IllustratedGrassPatch.WIND_UV_AMPLITUDE,
		IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE,
	]


## The geometry bend as it FIRST shipped: vertex() displaced VERTEX.x and
## nothing else. A shear leaves every row at the height it started at, so a
## leaning blade draws longer than a standing one -- reported live as "the
## grassblades elongate and stretch instead of only bending".
static func shear_shader_code() -> String:
	return IllustratedGrassPatch.SHADER_CODE.replace(
		"""	float along = -VERTEX.y;
	float sideways = clamp(v_geometry_bend * 16.0, -along, along);
	VERTEX.x += sideways;
	VERTEX.y = -sqrt(max(along * along - sideways * sideways, 0.0));""",
		"	VERTEX.x += v_geometry_bend * 16.0;"
	)


## How far the furthest blade pixel in this panel is from the root it grows
## from -- the number that actually says whether a bent blade got LONGER.
## Deliberately a REACH and not a height: a shear leaves every row at the
## height it started at, so height alone cannot see the stretch at all; what
## grows is the diagonal.
static func blade_reach(image: Image, root: Vector2, from_x: int, to_x: int) -> float:
	var furthest := 0.0
	for y in image.get_height():
		for x in range(from_x, to_x):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.05 and pixel.v > 0.2:
				furthest = maxf(furthest, Vector2(float(x), float(y)).distance_to(root))
	return furthest


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = VIEW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.1, 0.1, 0.12, 1.0)
	backdrop.size = Vector2(VIEW)
	viewport.add_child(backdrop)

	var grass := IllustratedGrassPatch.new()
	var seed_value := hash("%d_%d_grass_tuft" % [1000, 2000])
	var cards_old := IllustratedGrassPatch.cards_for_cell(
		{"seed": seed_value, "ground_position": OLD_GROUND, "growth": 1.0}
	)
	var cards_shear := IllustratedGrassPatch.cards_for_cell(
		{"seed": seed_value, "ground_position": SHEAR_GROUND, "growth": 1.0}
	)
	var cards_new := IllustratedGrassPatch.cards_for_cell(
		{"seed": seed_value, "ground_position": NEW_GROUND, "growth": 1.0}
	)

	var old_shader := Shader.new()
	old_shader.code = old_shader_code()
	var old_material := ShaderMaterial.new()
	old_material.shader = old_shader

	var shear_shader := Shader.new()
	shear_shader.code = shear_shader_code()
	var shear_material := ShaderMaterial.new()
	shear_material.shader = shear_shader

	var old_mesh := QuadMesh.new()
	old_mesh.size = Vector2(IllustratedGrassPatch.WORLD_SIZE, IllustratedGrassPatch.WORLD_SIZE)
	old_mesh.center_offset = Vector3(0.0, -IllustratedGrassPatch.WORLD_SIZE * 0.5, 0.0)

	for push_label in ["calm", "walker"]:
		for child in viewport.get_children():
			if child is MultiMeshInstance2D:
				child.queue_free()
		await process_frame

		var old_mmi := MultiMeshInstance2D.new()
		old_mmi.position = OLD_GROUND
		viewport.add_child(old_mmi)
		grass.fill_band(old_mmi, OLD_GROUND, cards_old, "summer")
		# Swap in the pre-fix pair: plain quad + sampling-only bend.
		old_mmi.material = old_material
		old_mmi.multimesh.mesh = old_mesh

		var shear_mmi := MultiMeshInstance2D.new()
		shear_mmi.position = SHEAR_GROUND
		viewport.add_child(shear_mmi)
		grass.fill_band(shear_mmi, SHEAR_GROUND, cards_shear, "summer")
		shear_mmi.material = shear_material

		var new_mmi := MultiMeshInstance2D.new()
		new_mmi.position = NEW_GROUND
		viewport.add_child(new_mmi)
		grass.fill_band(new_mmi, NEW_GROUND, cards_new, "summer")

		var far_away := Vector2(-100000.0, -100000.0)
		var old_walker: Vector2 = far_away if push_label == "calm" else OLD_GROUND - Vector2(1.0, 0.0)
		var shear_walker: Vector2 = far_away if push_label == "calm" else SHEAR_GROUND - Vector2(1.0, 0.0)
		var new_walker: Vector2 = far_away if push_label == "calm" else NEW_GROUND - Vector2(1.0, 0.0)
		old_material.set_shader_parameter("player_world_position", old_walker)
		old_material.set_shader_parameter("wind_strength", 1.0)
		shear_material.set_shader_parameter("player_world_position", shear_walker)
		shear_material.set_shader_parameter("wind_strength", 1.0)
		grass.set_walker_position(new_walker)
		grass.set_wind_strength(1.0)

		RenderingServer.force_draw()
		await process_frame
		RenderingServer.force_draw()
		var img: Image = viewport.get_texture().get_image()
		print(
			"%s: furthest blade pixel from its own root -- sampling-only %.1fpx | shear %.1fpx | arc %.1fpx  (a card is %.0fpx tall; a bend must not make a blade LONGER)"
			% [
				push_label,
				blade_reach(img, OLD_GROUND, 0, 80),
				blade_reach(img, SHEAR_GROUND, 80, 160),
				blade_reach(img, NEW_GROUND, 160, 240),
				IllustratedGrassPatch.WORLD_SIZE,
			]
		)
		img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
		var path := "%s/bend_%s.png" % [OUT_DIR, push_label]
		img.save_png(path)
		print("saved ", path, "  (left = sampling-only, middle = shear, right = shipped arc bend)")

	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()
