extends GutTest

## IllustratedMushroomSprite (see docs/concept/mushrooms.md's "No
## illustrated art this pass"). A real, tested class with an EMPTY sheet
## table -- MushroomMarker can be written in its final has_variants()-gated
## form from day one, and a real 5x5-per-species sheet can be registered
## later with zero further code changes, the same path AntMoundMarker/
## IllustratedAntMoundSprite already proved for ant mounds.

const IllustratedMushroomSprite = preload("res://src/rendering/illustrated_mushroom_sprite.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")

var _sprite: IllustratedMushroomSprite


func before_each():
	_sprite = IllustratedMushroomSprite.new()


func test_no_species_has_real_art_yet():
	for id in MushroomSpecies.IDS:
		assert_false(_sprite.has_variants(id), "%s should have no illustrated art this pass" % id)


func test_frame_count_is_zero_for_every_species():
	for id in MushroomSpecies.IDS:
		assert_eq(_sprite.frame_count(id), 0)


func test_frame_for_returns_null_when_there_is_no_art():
	assert_null(_sprite.frame_for("fly_agaric", 42))


func test_an_unknown_species_also_has_no_art():
	assert_false(_sprite.has_variants("portobello"))
	assert_null(_sprite.frame_for("portobello", 1))
