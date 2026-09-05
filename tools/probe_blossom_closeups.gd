extends SceneTree

## Dev tool: measures every fruit_region landing in each species' own
## CANOPY_BLOSSOM column (see IllustratedTree._CANOPY_FRAME_BY_SEASON),
## the same real-measurement step _FOLIAGE_GREEN_HUE_MIN_DEGREES/
## _FOLIAGE_ORANGE_HUE_MIN_DEGREES etc. were presumably grounded in for
## summer/autumn -- before adding a "spring" entry to
## IllustratedTree._foliage_closeups, need real fill/hue/saturation/area
## numbers for the blossom-column candidates across all 6 species, to know
## whether the existing filter shape (max-fill, on-tree exclusion,
## smallest-region-wins) already picks a sensible loose-petal/flower
## closeup without a hue band, or needs one.
##
## Headless-safe: pure Image/CompositeSheetSlicer work, no GPU/viewport.
##
## Usage: godot --headless --path . -s tools/probe_blossom_closeups.gd

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const CompositeSheetSlicer = preload("res://src/rendering/composite_sheet_slicer.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const CANOPY_BLOSSOM := 1


func _initialize() -> void:
	var tree := IllustratedTree.new()
	for species in TreeSpecies.IDS:
		print("=== %s ===" % species)
		var path: String = IllustratedTree.composite_path_for(species)
		var sheet := Image.load_from_file(ProjectSettings.globalize_path(path))
		if sheet == null:
			print("  (no composite sheet, skipping)")
			continue
		var regions := CompositeSheetSlicer.regions_in(sheet)
		var below: Array[Rect2i] = []
		var canopy_x_centers: Array = []
		if regions.is_empty():
			print("  (no regions found)")
			continue
		var band_bottom: int = regions[0].position.y + regions[0].size.y
		for region in regions:
			if region.position.y < band_bottom:
				canopy_x_centers.append(region.position.x + region.size.x / 2.0)
			else:
				below.append(region)

		var trunk_row := IllustratedTree._trunk_row(below)
		var fruit_regions: Array[Rect2i] = []
		for index in below.size():
			if trunk_row.has(index):
				continue
			fruit_regions.append(below[index])
		var on_tree_regions: Array = IllustratedTree._on_tree_row(fruit_regions, canopy_x_centers, sheet)

		print("  canopy_x_centers=%s" % [canopy_x_centers])
		for region in fruit_regions:
			var rect: Rect2i = region
			var column := IllustratedTree._nearest_canopy_column(rect, canopy_x_centers)
			var fill := IllustratedTree._fill_fraction(sheet, rect)
			var hue_sat := IllustratedTree._mean_hue_saturation(sheet, rect)
			var area := rect.size.x * rect.size.y
			var is_on_tree := on_tree_regions.has(rect)
			var trusted := IllustratedTree._is_trusted_real_fruit(sheet, rect, on_tree_regions)
			var tag := ""
			if column == CANOPY_BLOSSOM:
				tag = "  <-- BLOSSOM COLUMN"
			print(
				"  col=%d rect=%s area=%d fill=%.3f hue=%.1f sat=%.3f on_tree=%s trusted_fruit=%s%s"
				% [column, rect, area, fill, hue_sat.x, hue_sat.y, is_on_tree, trusted, tag]
			)
	quit()
