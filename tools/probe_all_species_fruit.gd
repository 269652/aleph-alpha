extends SceneTree

## Diagnostic: for every illustrated species, dumps what fruit_for(ripe=true/
## false) actually returns today, plus the full on_tree/harvest row counts,
## to individual PNGs for visual inspection.
##
## Usage: godot --headless -s tools/probe_all_species_fruit.gd

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")

const OUT_DIR := "res://../probe_out2"


func _initialize():
	var dir_abs := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	var tree := IllustratedTree.new()

	for species in IllustratedTree.SPECIES_WITH_ART:
		print("\n=== %s ===" % species)
		var on_tree := tree.on_tree_frames_for(species)
		var harvest := tree.harvest_frames_for(species)
		print("  on_tree: %d frames, harvest: %d frames" % [on_tree.size(), harvest.size()])
		for i in on_tree.size():
			_save(on_tree[i], "%s_on_tree_%d" % [species, i])
		for i in harvest.size():
			_save(harvest[i], "%s_harvest_%d" % [species, i])
		var ripe := tree.fruit_for(species, true)
		var unripe := tree.fruit_for(species, false)
		if ripe:
			print("  fruit_for(ripe) size=%s" % ripe.get_size())
			_save(ripe, "%s_fruit_ripe" % species)
		if unripe:
			print("  fruit_for(unripe) size=%s" % unripe.get_size())
			_save(unripe, "%s_fruit_unripe" % species)

	quit()


func _save(tex: Texture2D, name: String) -> void:
	var img := tex.get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
