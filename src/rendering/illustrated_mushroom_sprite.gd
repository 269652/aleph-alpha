extends RefCounted

## Illustrated mushroom cap art (see docs/concept/mushrooms.md's "No
## illustrated art this pass"). Same "sheet -> SpriteSheetSlicer -> cached
## frames" shape IllustratedAntMoundSprite/IllustratedAnimalSprite use --
## kept deliberately real and tested even with an EMPTY sheet table, so
## MushroomMarker can be written in its final has_variants()-gated form
## from day one, and a real 5x5-per-species sheet (25 variants: 5
## hand-measured row bands, 5 auto-detected columns each, the exact
## IllustratedStoneSprite recipe) can be registered here later with zero
## further code changes -- the same path AntMoundMarker/
## IllustratedAntMoundSprite already proved for ant mounds.
##
## Every species falls straight through to ProceduralMushroomSprite today:
## has_variants() is false for all five roster species until a real sheet
## is registered in _SHEETS.

## species_id -> {"path": String, "row_bands": Array[Vector2i]}. Empty
## today -- see class doc comment.
const _SHEETS := {}


func has_variants(species_id: String) -> bool:
	return _SHEETS.has(species_id)


func frame_count(species_id: String) -> int:
	return _all_frames(species_id).size()


## The seed-picked frame for `species_id`, deterministic per seed the same
## way IllustratedAntMoundSprite.frame_for is -- null if this species has no
## registered sheet, the same has-art-or-doesn't fallback contract every
## illustrated seam in this codebase already uses.
func frame_for(species_id: String, seed_value: int) -> ImageTexture:
	var frames := _all_frames(species_id)
	if frames.is_empty():
		return null
	var pixel_noise = load("res://src/rendering/pixel_noise.gd")
	var index: int = pixel_noise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


## Real slicing (SpriteSheetSlicer.detect_frames/normalize_frames over each
## row band, the same recipe IllustratedAntMoundSprite/IllustratedStoneSprite
## already use) lands here once `_SHEETS` gains a real entry for
## `species_id` -- nothing to slice yet.
func _all_frames(species_id: String) -> Array:
	if not _SHEETS.has(species_id):
		return []
	return []
