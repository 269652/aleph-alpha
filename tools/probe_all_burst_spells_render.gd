extends SceneTree

## Renders ALL SEVEN burst-family atoms through the REAL in-game path
## (SpellEffectMarker.play, not a bare Sprite2D) over a checkerboard test
## background, and saves one PNG per atom -- extending the single-atom
## check in probe_spell_distortion_render.gd to the full gated list, per a
## direct follow-up request after that fix ("can you test the other burst
## spells too"). Exercises the real illustrated-art loading, the real
## shader wiring, and the real progress tween together, not just the
## distortion shader in isolation.
##
## Run: xvfb-run -a <godot> --path . --rendering-driver opengl3 -s tools/probe_all_burst_spells_render.gd

const SpellEffectMarker = preload("res://src/rendering/spell_effect_marker.gd")
const SpellImpactDistortionShader = preload("res://src/rendering/spell_impact_distortion_shader.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

const OUT_DIR := "res://tools/spell_distortion_renders"

## The documented seven -- cross-checked against the catalog below rather
## than assumed, so a future roster change that silently drops or adds a
## burst atom shows up here too.
const BURST_ATOMS := [
	"fire_damage", "frost_damage", "shock_damage", "ignite",
	"induce_mutation", "illuminate", "fear",
]


func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	var catalog := SpellAtomCatalog.new()
	for atom_id in BURST_ATOMS:
		if not SpellImpactDistortionShader.atom_gets_distortion(atom_id):
			print("UNEXPECTED: %s is not gated to distortion -- roster drifted" % atom_id)
		if not catalog.known_ids().has(atom_id):
			print("UNEXPECTED: %s is not a known catalog atom" % atom_id)
		await _render_one(atom_id)

	print("DONE")
	quit()


func _capture(viewport: SubViewport) -> Image:
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	return viewport.get_texture().get_image()


func _render_one(atom_id: String):
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 200)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.6, 0.2)
	bg.size = Vector2(200, 200)
	viewport.add_child(bg)
	for y in 4:
		for x in 4:
			if (x + y) % 2 == 0:
				continue
			var tile := ColorRect.new()
			tile.color = Color(0.9, 0.9, 0.1)
			tile.size = Vector2(25, 25)
			tile.position = Vector2(x * 50, y * 50)
			viewport.add_child(tile)

	var marker := SpellEffectMarker.new()
	marker.position = Vector2(100, 100)
	viewport.add_child(marker)
	marker.play(atom_id)

	# Partway into grow -> hold, where distortion strength and the glow halo
	# are both well past zero (GROW_DURATION=0.12, HOLD_DURATION=0.15) --
	# the beat's own most active window, not its very first or last frame.
	await create_timer(0.18).timeout
	var img: Image = await _capture(viewport)
	img.save_png("%s/burst_%s.png" % [OUT_DIR, atom_id])
	print("saved burst_%s.png" % atom_id)

	viewport.queue_free()
