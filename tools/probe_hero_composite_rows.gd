extends SceneTree

## Which of hero_composite.png's eight outfit rows a villager can actually
## be drawn from, and which fall back to the procedural rig.
##
## Reported live with the village in shot: *"Some NPCs look like proper
## chars, others have rectangles as legs"*. _composite_frames refuses a
## WHOLE row whose real band count is not HERO_COMPOSITE_EXPECTED_BAND_COUNT
## -- two touching pieces of art shift every fixed index after the merge
## point onto the wrong content -- and every caller's has-art-then-fallback
## check (`if not textures.is_empty()`) then draws the procedural body and
## legs instead. That is the rectangle.
##
## Prints, per row: the real bands detect_frames finds, whether the row is
## usable, and which parts come back empty.

const IllustratedCharacterSprite = preload("res://src/rendering/illustrated_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")


func _initialize() -> void:
	var sprite := IllustratedCharacterSprite.new()
	print("")
	print("=== hero_composite rows ===")
	print("expected real bands per row: %d" % IllustratedCharacterSprite.HERO_COMPOSITE_EXPECTED_BAND_COUNT)
	var usable: Array = []
	for row in IllustratedCharacterSprite.HERO_COMPOSITE_ROWS:
		var parts: Dictionary = {}
		for part in ["arms", "body", "legs"]:
			parts[part] = sprite._composite_frames(part, row, "front").size()
		var row_usable: bool = int(parts["body"]) > 0
		if row_usable:
			usable.append(row)
		print("   row %d  arms=%d body=%d legs=%d  %s" % [
			row, parts["arms"], parts["body"], parts["legs"],
			"usable" if row_usable else "REFUSED -> procedural rectangle"
		])
	print("")
	print("usable rows: %s  (%d of %d)" % [
		str(usable), usable.size(), IllustratedCharacterSprite.HERO_COMPOSITE_ROWS
	])

	# ...and how often a real villager lands on one. The row a villager
	# wears is HeroAppearance.outfit_variant_for(class, seed).
	var appearance := HeroAppearance.new()
	var rectangles := 0
	var total := 0
	var by_class: Dictionary = {}
	for class_id in HeroAppearance.CLASS_PALETTES.keys():
		var bad := 0
		for seed_value in range(0, 200):
			total += 1
			var row: int = appearance.outfit_variant_for(class_id, seed_value)
			if not usable.has(row):
				rectangles += 1
				bad += 1
		by_class[class_id] = "%d/200" % bad
	print("")
	print("villagers handed a refused row: %d of %d (%.1f%%)" % [
		rectangles, total, 100.0 * float(rectangles) / float(maxi(total, 1))
	])
	print("per class: %s" % str(by_class))
	quit()
