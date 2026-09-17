extends SceneTree

## What a bending grass card actually looks like, for every generation of the
## bend this system has had (docs/concept/long_grass.md, "Where a bent blade
## actually goes" and History #15-#17). Per this codebase's own discipline, a
## headless test is not evidence for "what does this look like" -- it needs a
## real GPU context, not --headless. Run:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_grass_bend_clipping.gd
##
## Draws ONE real cell's own cards once per generation, all in the SAME frame
## so every panel sees the identical TIME and therefore the identical wind,
## with a walker standing right beside each clump so the push term is at its
## full WALKER_PUSH_UV_AMPLITUDE. Every superseded generation is derived from
## the SHIPPED shader by swapping one block, so they cannot rot as the rest of
## the shader moves on.
##
## It also MEASURES the furthest blade pixel from its own root, which is the
## number two of the three live reports were about. Deliberately a REACH and
## not a height: a shear preserves blade height by construction and cannot be
## seen in it at all -- what grows is the diagonal.
##
## CONFIRMED (2026-09-17), under xvfb + Mesa software GL, which is a real
## rasterizer as far as the shader is concerned. A card is 16px tall and the
## resting tuft reaches 17.9px from the cell's own centre:
##
##   sampling only   17.7px   the bend never left the quad -- it CUT the
##                            blade off at the card's edge instead
##                            ("clipped on the left and right")
##   shear           31.4px   nearly double: a leaning blade drawn as a
##                            longer diagonal ("elongate and stretch")
##   column arc      24.0px   better, still stretched: the diagonal leaves
##                            this atlas is full of swing out while their
##                            bases stay put ("still super elongated")
##   rotation        20.1px   the shipped one. What is over 17.9 is one
##                            offset card leaning away from the cell centre
##                            the measurement is taken from, not a blade
##                            growing.

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")

const OUT_DIR := "res://tools/grass_bend_renders"
const PANEL := 80
const GROUND_Y := 68.0
const SHIPPED := "rotation (shipped)"

## The shipped shader's own vertex block, which every superseded generation
## below is derived from by replacement.
const _SHIPPED_BLOCK := """	float radius = length(VERTEX);
	if (radius > 0.0001) {
		float lean = asin(clamp(v_geometry_bend * 16.0 / radius, -1.0, 1.0));
		// Clamped at the horizon per POINT: a leaf that already points up and
		// to the side reaches flat before the ones above it, and would carry
		// on below the ground its roots stand on, folding the card under
		// itself. A blade lies flat; it does not grow into the ground.
		float from_upright = clamp(
			atan(VERTEX.x, -VERTEX.y) + lean, -radians(90.0), radians(90.0)
		);
		VERTEX = vec2(radius * sin(from_upright), -radius * cos(from_upright));
	}"""


## Every generation of the bend, oldest first, as the vertex block that
## produced it. SHIPPED is the shader exactly as it stands.
static func generations() -> Array:
	return [
		{"label": "sampling only", "block": "", "sample_whole_bend": true},
		{"label": "shear", "block": "	VERTEX.x += v_geometry_bend * 16.0;"},
		{
			"label": "column arc",
			"block": """	float along = -VERTEX.y;
	float sideways = clamp(v_geometry_bend * 16.0, -along, along);
	VERTEX.x += sideways;
	VERTEX.y = -sqrt(max(along * along - sideways * sideways, 0.0));""",
		},
		{
			"label": "free rotation",
			"block": """	float radius = length(VERTEX);
	if (radius > 0.0001) {
		float lean = asin(clamp(v_geometry_bend * 16.0 / radius, -1.0, 1.0));
		float from_upright = atan(VERTEX.x, -VERTEX.y) + lean;
		VERTEX = vec2(radius * sin(from_upright), -radius * cos(from_upright));
	}""",
		},
		{"label": SHIPPED, "block": _SHIPPED_BLOCK},
	]


static func shader_for(generation: Dictionary) -> Shader:
	var code: String = IllustratedGrassPatch.SHADER_CODE.replace(_SHIPPED_BLOCK, generation["block"])
	if generation.get("sample_whole_bend", false):
		# Before any of this moved geometry, fragment() carried the WHOLE
		# bend in the sampled UV rather than the sliver the mesh could not.
		code = code.replace("bend_offset_at(UV, v_root) - v_geometry_bend", "bend_offset_at(UV, v_root)")
	var shader := Shader.new()
	shader.code = code
	return shader


## How far BELOW its own base a panel draws -- the fold reported as "it still
## stretches when it's bent below the base of the grass entity". A blade lies
## flat at worst, so this should be zero however hard it is pushed.
static func below_base(image: Image, root: Vector2, from_x: int, to_x: int) -> float:
	var lowest := 0.0
	for y in image.get_height():
		for x in range(from_x, to_x):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.05 and pixel.v > 0.2:
				lowest = maxf(lowest, float(y) - root.y)
	return lowest


## How far the furthest blade pixel in this panel is from the root its cards
## grow from. See the header for why this is a reach and not a height.
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

	var panels := generations()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PANEL * panels.size(), 80)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.1, 0.1, 0.12, 1.0)
	backdrop.size = Vector2(viewport.size)
	viewport.add_child(backdrop)

	var grass := IllustratedGrassPatch.new()
	var seed_value := hash("%d_%d_grass_tuft" % [1000, 2000])
	for i in panels.size():
		panels[i]["ground"] = Vector2(PANEL * i + PANEL * 0.5, GROUND_Y)
		# ONE card per panel, planted exactly at the panel's own ground point.
		# A whole cell's CARD_COUNT cards are scattered up to +/-6.8 units
		# around their cell, which swamps this measurement: the furthest pixel
		# then belongs to whichever card is offset furthest, not to a stretched
		# blade, and two generations that differ a lot read as differing by
		# 0.2px. One card measured against its OWN root is the question.
		var cell_cards := IllustratedGrassPatch.cards_for_cell(
			{"seed": seed_value, "ground_position": panels[i]["ground"], "growth": 1.0}
		)
		panels[i]["cards"] = [{
			"atlas_seed": cell_cards[0]["atlas_seed"],
			"position": panels[i]["ground"],
			"growth": 1.0,
		}]
		var material := ShaderMaterial.new()
		material.shader = shader_for(panels[i])
		panels[i]["material"] = material

	# "nearby" is what a player standing a tile and a half off actually does
	# to a tuft -- the case a screenshot is usually of. "walker" is a boot
	# in the clump, the worst case the amplitudes allow.
	for push_label in ["calm", "nearby", "walker"]:
		for child in viewport.get_children():
			if child is MultiMeshInstance2D:
				child.queue_free()
		await process_frame

		for panel in panels:
			var mmi := MultiMeshInstance2D.new()
			mmi.position = panel["ground"]
			viewport.add_child(mmi)
			grass.fill_band(mmi, panel["ground"], panel["cards"], "summer")
			# fill_band binds the one shared material; each panel needs its own.
			mmi.material = panel["material"]
			var walker := Vector2(-100000.0, -100000.0)
			if push_label == "nearby":
				walker = panel["ground"] - Vector2(24.0, 0.0)
			elif push_label == "walker":
				walker = panel["ground"] - Vector2(1.0, 0.0)
			panel["material"].set_shader_parameter("player_world_position", walker)
			panel["material"].set_shader_parameter("wind_strength", 1.0)

		RenderingServer.force_draw()
		await process_frame
		RenderingServer.force_draw()
		var img: Image = viewport.get_texture().get_image()
		var reaches: Array[String] = []
		for i in panels.size():
			reaches.append("%s %.1f/%.1f" % [
				panels[i]["label"],
				blade_reach(img, panels[i]["ground"], PANEL * i, PANEL * (i + 1)),
				below_base(img, panels[i]["ground"], PANEL * i, PANEL * (i + 1)),
			])
		print("%s: reach / below-base, px -- %s  (a card is %.0fpx tall; both should stay put)" % [
			push_label, " | ".join(reaches), IllustratedGrassPatch.WORLD_SIZE
		])
		img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
		var path := "%s/bend_%s.png" % [OUT_DIR, push_label]
		img.save_png(path)
		print("saved ", path, "  (left to right: %s)" % ", ".join(panels.map(func(p): return p["label"])))

	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()
