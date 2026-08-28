extends GutTest

## Deterministic in-engine pixel-art for spell atom effects (docs/concept/
## magic.md's atom-effects section, docs/concept/spell_runtime.md) -- the
## procedural-first fallback every atom must render correctly from before
## any illustrated sheet exists, same two-track pattern ProceduralItemSprite
## already established for items. Mirrors that file's own test shape.

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

var generator: ProceduralSpellEffectSprite
var _catalog := SpellAtomCatalog.new()


func before_each():
	generator = ProceduralSpellEffectSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("fire_damage")
	assert_eq(image.get_width(), ProceduralSpellEffectSprite.SIZE)
	assert_eq(image.get_height(), ProceduralSpellEffectSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image("fire_damage")
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralSpellEffectSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_not_a_single_flat_color():
	var image := generator.generate_image("shield")
	var distinct := {}
	for y in ProceduralSpellEffectSprite.SIZE:
		for x in ProceduralSpellEffectSprite.SIZE:
			distinct[image.get_pixel(x, y)] = true
	assert_gt(distinct.size(), 1)


## Every real atom in the catalog must render something valid -- a real
## regression guard: if a future atom is added to spell_atom_catalog.gd and
## nobody registers a look for it here, this fails loudly instead of the
## atom silently falling back to a generic shape forever.
func test_every_catalog_atom_has_its_own_registered_look():
	for atom_id in _catalog.known_ids():
		assert_true(
			generator.has_look(atom_id), "%s should have its own registered {color, shape}" % atom_id
		)


func test_unknown_atom_falls_back_to_a_generic_shape_rather_than_crashing():
	var image := generator.generate_image("not_a_real_atom")
	assert_eq(image.get_width(), ProceduralSpellEffectSprite.SIZE)


func test_different_damage_atoms_get_different_colors():
	# The four damage atoms are mechanically identical today (see
	# spell_runtime.md) -- color is the ONLY thing that currently
	# distinguishes them, so it must actually differ.
	var colors := {}
	for atom_id in ["fire_damage", "frost_damage", "shock_damage", "poison_damage"]:
		colors[ProceduralSpellEffectSprite.color_for(atom_id)] = true
	assert_eq(colors.size(), 4, "all four damage atoms must have visibly distinct colors")


func test_texture_for_caches_the_same_texture_per_atom():
	assert_same(generator.texture_for("fire_damage"), generator.texture_for("fire_damage"))


func test_texture_for_differs_between_atoms():
	assert_ne(
		generator.texture_for("fire_damage").get_image().get_data(),
		generator.texture_for("frost_damage").get_image().get_data()
	)
