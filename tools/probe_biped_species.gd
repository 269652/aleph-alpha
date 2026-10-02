extends SceneTree

## Renders REAL procedural sprites for Goblin and Nachzehrer (the roster's
## first biped body plan -- docs/concept/monsters.md entries 10-11) next to
## an ordinary quadruped (wolf) for scale/contrast, and saves a PNG -- the
## same "code tracing alone is not enough evidence, go look at the pixels"
## technique probe_spell_distortion_render.gd established. Unlike that
## probe, no shader/viewport/GPU is involved here (generate_image is a
## plain CPU-side Image build -- see ProceduralAnimalSprite.generate_image),
## so this runs under ordinary --headless, no xvfb-run needed:
##   <godot> --headless --path . -s tools/probe_biped_species.gd

const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")

const OUT_DIR := "res://tools/biped_species_renders"
const SCALE := 10
const SPECIES := ["wolf", "goblin", "nachzehrer"]


func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var generator := ProceduralAnimalSprite.new()

	var tile_w := ProceduralAnimalSprite.WIDTH * SCALE
	var tile_h := ProceduralAnimalSprite.HEIGHT * SCALE
	var sheet := Image.create(tile_w * SPECIES.size(), tile_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.18))

	for i in SPECIES.size():
		var species: String = SPECIES[i]
		var frame := generator.generate_image(species, 1, 0.0)
		frame.resize(tile_w, tile_h, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(i * tile_w, 0))
		# Also saved individually -- easier to eyeball one species at a time
		# than to pick it out of the combined strip.
		frame.save_png("%s/%s.png" % [OUT_DIR, species])
		print("saved %s.png" % species)

	sheet.save_png("%s/wolf_goblin_nachzehrer_strip.png" % OUT_DIR)
	print("saved wolf_goblin_nachzehrer_strip.png")
	print("DONE")
	quit()
