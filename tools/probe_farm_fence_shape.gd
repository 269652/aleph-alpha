extends SceneTree

## What does a farmhouse's field and its fence actually LOOK like on the
## grid? Reported in play with the ring circled in a screenshot: "The
## fencing system does not yet work... The fence should enclose a 2x3 or 3x2
## area ... the side walls of the fence should be moved outwards and corner
## pieces added so it doesn't look that broken".
##
## Prints the farmhouse (H), its beds (#) and every rail with the piece it
## is drawn as (^ north, v south, > east, < west, + corner), so the frame is
## LOOKED AT rather than assumed from a passing test.

func _initialize() -> void:
	var VillageFarm = load("res://src/gameplay/village_farm.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var origin := Vector2i(6, 4)
	var footprint: Vector2i = BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)

	for blocked_name in ["open ground", "a rock east of the door", "water below"]:
		var is_free: Callable
		match blocked_name:
			"a rock east of the door":
				is_free = func(cell: Vector2i) -> bool: return cell != Vector2i(7, 6)
			"water below":
				is_free = func(cell: Vector2i) -> bool: return cell.y < 8
			_:
				is_free = func(_cell: Vector2i) -> bool: return true

		var rect = VillageFarm.field_rect(origin, VillageFarm.FARM_BUILDING_ID, is_free)
		print("== ", blocked_name, " -> ", rect)
		if rect == null:
			print("   no field fits")
			continue
		var beds: Array = []
		for y in range((rect as Rect2i).position.y, (rect as Rect2i).end.y):
			for x in range((rect as Rect2i).position.x, (rect as Rect2i).end.x):
				beds.append(Vector2i(x, y))
		var glyphs := {}
		for cell in beds:
			glyphs[cell] = "#"
		for y in footprint.y:
			for x in footprint.x:
				glyphs[origin + Vector2i(x, y)] = "H"
		var rails := 0
		for rail in VillageFarm.fence_cells(beds, origin, VillageFarm.FARM_BUILDING_ID):
			var facing: String = VillageFarm.fence_facing(rail, beds)
			rails += 1
			glyphs[rail] = {
				"north": "^", "south": "v", "east": ">", "west": "<",
				"corner_west": "+", "corner_east": "+", "": "?",
			}[facing]
		for y in range(origin.y - 2, origin.y + 8):
			var row := "   "
			for x in range(origin.x - 5, origin.x + 8):
				row += glyphs.get(Vector2i(x, y), ".")
			print(row)
		print("   beds ", beds.size(), "  rails ", rails)
	quit()
