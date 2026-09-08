extends SceneTree

## Real-render verification for the per-blade turn-threshold fix (docs/
## concept/long_grass.md's "Seasonal art" -- staggered per-blade turn).
## Per this codebase's own established discipline, a code trace/headless
## test is not enough evidence for "what does this actually look like" --
## needs a REAL GPU window, not --headless. Run:
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_grass_per_blade_turn.gd
##
## Renders ONE real cell's own 8 cards (the exact production path:
## cards_for_cell) split by split_cards_by_turn at several progress steps
## (summer->autumn) as two MultiMeshInstance2Ds sharing one viewport -- if
## the fix works, the tuft should show a real MIX of green (summer) and
## orange/red (autumn) blades scattered through the same clump at every
## intermediate step, not a clean block of one color.
##
## CONFIRMED (2026-09-08): before the fix (turn_threshold_for_seed hashing a
## shared-prefix STRING salt), a real cell's 8 cards landed at suspiciously
## close thresholds (Godot's String hash does not avalanche on "prefix_
## smallint" -- see turn_threshold_for_seed's own doc comment for the full
## finding) and tended to cross a given progress together -- the whole tuft
## read as flipping as one "entity" instead of blade by blade, exactly the
## live report: "The long grass sprites don't change season color per blade
## but instead per entity." After the fix (hashing atlas_seed as an INT with
## a salt constant, which DOES avalanche), the SAME real cell/seed used here
## shows real per-card thresholds spread across the full range (0.272,
## 0.360, 0.450, 0.459, 0.469, 0.656, 0.831, 0.870) and the rendered clump
## visibly shows a genuine mix of green and orange/red blades at 33%, 50%
## and 67% progress -- not a hard snap between one uniform color and another.

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")

const OUT_DIR := "res://tools/grass_turn_renders"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = Vector2i(80, 80)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.5, 0.5, 0.5, 1.0)
	backdrop.size = Vector2(80, 80)
	viewport.add_child(backdrop)

	var grass := IllustratedGrassPatch.new()

	# A real cell seed, same shape _sync_grass_sprites actually produces.
	var tile := Vector2i(1000, 2000)
	var seed_value := hash("%d_%d_grass_tuft" % [tile.x, tile.y])
	var cell_spec := {
		"seed": seed_value,
		"ground_position": Vector2(40, 60),
		"growth": 1.0,
	}
	var cards := IllustratedGrassPatch.cards_for_cell(cell_spec)
	print("cell seed=", seed_value, " card count=", cards.size())
	for card in cards:
		print("  atlas_seed=", card.atlas_seed, " turn_threshold=",
			"%.3f" % IllustratedGrassPatch.turn_threshold_for_seed(card.atlas_seed))

	var band_anchor := Vector2(40, 60)
	for progress in [0.0, 0.33, 0.5, 0.67, 1.0]:
		for child in viewport.get_children():
			if child is MultiMeshInstance2D:
				child.queue_free()
		await process_frame

		var split := IllustratedGrassPatch.split_cards_by_turn(cards, progress)
		print("progress=", progress, " from(summer)=", split.from.size(), " to(autumn)=", split.to.size())

		var from_mmi := MultiMeshInstance2D.new()
		# fill_band does NOT set this itself -- band_anchor only computes
		# each INSTANCE's relative offset; the caller (here and in
		# _sync_grass_sprites) sets the node's own position separately.
		from_mmi.position = band_anchor
		viewport.add_child(from_mmi)
		grass.fill_band(from_mmi, band_anchor, split.from, "summer")

		var to_mmi := MultiMeshInstance2D.new()
		to_mmi.position = band_anchor
		viewport.add_child(to_mmi)
		grass.fill_band(to_mmi, band_anchor, split.to, "autumn")

		RenderingServer.force_draw()
		await process_frame
		RenderingServer.force_draw()
		var img: Image = viewport.get_texture().get_image()
		img.resize(img.get_width() * 6, img.get_height() * 6, Image.INTERPOLATE_NEAREST)
		var path := "%s/turn_progress_%d.png" % [OUT_DIR, int(progress * 100)]
		img.save_png(path)
		print("saved ", path)

	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()
