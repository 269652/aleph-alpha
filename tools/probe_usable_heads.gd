extends SceneTree

## How many of the illustrated faces can a villager actually wear?
##
## Reported live with a villager in shot: *"It's a rough sketch with a square
## as head and poor resolution"*. CharacterView._apply_head draws the
## illustrated face only when IllustratedCharacterSprite.has_usable_head says
## the cell is usable, and otherwise falls back to
## ProceduralCharacterSprite's own ART_HEAD_SIZE (24x24) head -- a flat square
## on an otherwise illustrated body, which is exactly what was reported.
##
## HeroAppearance rolls "head" uniformly over option_count("head"), so every
## unusable cell in that range is a villager with a square for a head. This
## counts them.

const IllustratedCharacterSprite = preload("res://src/rendering/illustrated_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")


func _initialize() -> void:
	var sprite := IllustratedCharacterSprite.new()
	var hero := HeroAppearance.new()
	var options := hero.option_count("head")
	print("RESULT head_options=%d has_head=%s" % [options, sprite.has_head()])

	# the real skin tones a villager can roll
	var tones: Array = HeroAppearance.SKIN_TONES
	var unusable_any: Array[int] = []
	var usable_all := 0
	for cell in range(options):
		var ok_count := 0
		for tone in tones:
			if sprite.has_usable_head(cell, tone):
				ok_count += 1
		if ok_count == tones.size():
			usable_all += 1
		elif ok_count == 0:
			unusable_any.append(cell)
	print("RESULT cells=%d usable_for_every_tone=%d unusable_for_every_tone=%d"
		% [options, usable_all, unusable_any.size()])
	print("RESULT unusable_cells=%s" % str(unusable_any.slice(0, 40)))
	print("RESULT square_head_rate=%.3f" % (1.0 - float(usable_all) / float(maxi(options, 1))))
	quit()
