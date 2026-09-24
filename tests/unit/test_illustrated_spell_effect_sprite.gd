extends GutTest

## Real illustrated art for spell atom effects (docs/concept/magic.md's
## "Atom effects render as composite spritemaps" section, docs/concept/
## spell_runtime.md, docs/art/ai_sprite_prompts.md section 8). Same
## two-track pattern every other illustrated-art seam in this codebase
## follows (ProceduralSpellEffectSprite is the fallback this supersedes
## per atom once a real look is registered here).
##
## Delivered as one sheet per shared SHAPE FAMILY (burst/ring/cross+spiral/
## chevron/cloud), not one sheet per atom as magic.md's own brainstorm
## originally described -- each atom still gets its own distinct 6-frame
## row within its family's sheet, just co-located for delivery efficiency
## (see ai_sprite_prompts.md section 8's "one kit per shared shape, not per
## member" batching). See IllustratedSpellEffectSprite's own doc comment.

const IllustratedSpellEffectSprite = preload("res://src/rendering/illustrated_spell_effect_sprite.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

var art: IllustratedSpellEffectSprite
var _catalog := SpellAtomCatalog.new()


func before_each():
	art = IllustratedSpellEffectSprite.new()


## Every real atom in the catalog must have a registered illustrated look --
## a regression guard mirroring test_procedural_spell_effect_sprite.gd's own
## test_every_catalog_atom_has_its_own_registered_look: all 25 atoms were
## delivered across the 5 family sheets in this pass (7 burst + 8 ring + 3
## cross + 3 spiral + 2 chevron + 2 cloud = 25), so none should still be
## falling through to the procedural-only path.
func test_every_catalog_atom_has_a_registered_illustrated_look():
	for atom_id in _catalog.known_ids():
		assert_true(art.has_look(atom_id), "%s should have real illustrated art" % atom_id)


func test_unknown_atom_has_no_illustrated_look():
	assert_false(art.has_look("not_a_real_atom"))


func test_frame_count_is_six_for_a_wired_atom_in_every_family():
	for atom_id in ["fire_damage", "freeze", "minor_heal", "slow", "push", "poison_damage"]:
		assert_eq(art.frame_count(atom_id), 6, "%s should have 6 real frames" % atom_id)


func test_frame_count_is_zero_for_an_unknown_atom():
	assert_eq(art.frame_count("not_a_real_atom"), 0)


func test_frames_for_returns_six_non_null_textures():
	var frames := art.frames_for("fire_damage")
	assert_eq(frames.size(), 6)
	for frame in frames:
		assert_not_null(frame)


func test_frames_for_an_unknown_atom_is_empty():
	assert_eq(art.frames_for("not_a_real_atom").size(), 0)


## Sanity check on the row->atom mapping within one family sheet: two
## different atoms sharing the same shape family (both "ring") must still
## read as visibly different pictures, not accidentally the same row.
func test_different_atoms_in_the_same_family_get_different_art():
	var freeze_frame := art.frames_for("freeze")[0].get_image()
	var root_frame := art.frames_for("root")[0].get_image()
	assert_ne(freeze_frame.get_data(), root_frame.get_data())


## Cross-family sanity check, and confirms cross.png's two co-located
## sub-families (cross rows 1-3, spiral rows 4-6) are both actually reached.
func test_cross_and_spiral_sub_families_both_resolve_from_the_same_sheet():
	assert_true(art.has_look("minor_heal"))
	assert_true(art.has_look("slow"))
	assert_ne(
		art.frames_for("minor_heal")[0].get_image().get_data(),
		art.frames_for("slow")[0].get_image().get_data()
	)


## The chroma-keyed magenta background must not survive into a produced
## frame -- a real regression this codebase has hit before (a stray magenta
## cast reads as a solid pink box around the art instead of transparency).
func test_no_magenta_survives_in_a_produced_frame():
	for atom_id in ["fire_damage", "freeze", "push", "poison_damage", "minor_heal"]:
		var image: Image = art.frames_for(atom_id)[0].get_image()
		for y in image.get_height():
			for x in image.get_width():
				var c: Color = image.get_pixel(x, y)
				if c.a > 0.05:
					var is_magenta: bool = c.r > 0.85 and c.b > 0.85 and c.g < 0.35
					assert_false(is_magenta, "%s frame 0 has a surviving magenta pixel at (%d,%d)" % [atom_id, x, y])


func test_frames_for_caches_the_same_textures_per_atom():
	assert_same(art.frames_for("fire_damage")[0], art.frames_for("fire_damage")[0])
