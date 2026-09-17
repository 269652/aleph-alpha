extends SceneTree

## Reported in play, from a real screenshot at lat 48.6 lon 12.7: "Some
## villages have no houses" -- a village with paved streets, a market stall
## and a sawmill standing, and not one house.
##
## VillageLayout lays its plaza and its street BEFORE it tries to fit a
## single house, so a village whose street frontage will not take a
## building still gets its roads, and _place_industry_if_missing still
## raises its sawmill. The result reads as a village that forgot to build
## itself.
##
## This measures how often that happens against real chunks, real
## settlements and the real layout, and -- for the misses -- WHY: how much
## of the street's own frontage is unbuildable, how much is already
## occupied, and how many of the houses the village wanted actually landed.
## Same discipline probe_village_industry.gd uses ("for the misses, how far
## the nearest forest cell was").
##
## Pure modules only, so this can run in _init (see
## tools/probe_village_hunting.gd's own doc comment for why a probe that
## spawns real NODES cannot).

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

const CHUNK_SIZE := 32
## The reported spot: lat 48.6, lon 12.7 (Bavaria).
const LAT := 48.6
const LON := 12.7
const SPAN := 22

## Water blocks a build; everything else -- forest included -- is clearable
## (the user's own call: "Sure why not build houses on forest biome if they
## are cleared"). Mirrors VillageRenderer._is_buildable_local's real first
## branch exactly.
static func _is_water(biome: String) -> bool:
	return biome == "ocean" or biome == "lake" or biome == "river"


func _init() -> void:
	var generator := EarthChunkGenerator.new()
	var settlements := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var geo := GeoCoordinates.new()
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)

	var scanned := 0
	var housed := 0
	var houseless := 0
	var with_plaza := 0
	var placed_counts: Array = []
	var houseless_frontage_water: Array = []
	var houseless_wanted: Array = []
	var layout := VillageLayout.new()

	for dy in range(-SPAN, SPAN + 1):
		for dx in range(-SPAN, SPAN + 1):
			var coord := centre + Vector2i(dx, dy)
			if not settlements.has_settlement_at(coord, "grassland"):
				continue
			var chunk := generator.generate_chunk(coord, CHUNK_SIZE)
			var biome := classifier.dominant_biome(chunk.biome)
			if not settlements.has_settlement_at(coord, biome):
				continue
			scanned += 1

			var is_buildable := func(cell: Vector2i) -> bool:
				if cell.x < 0 or cell.y < 0 or cell.x >= CHUNK_SIZE or cell.y >= CHUNK_SIZE:
					return false
				return not _is_water(chunk.biome[cell.y * CHUNK_SIZE + cell.x])
			# A first load: nothing is built yet, exactly what
			# VillageRenderer._place_new_village runs against.
			var never_occupied := func(_cell: Vector2i) -> bool: return false

			var settlement := settlements.generate_settlement(
				coord, coord * CHUNK_SIZE, CHUNK_SIZE, 16
			)
			var building_ids: Array = []
			for i in settlement.npcs.size():
				var seed_value := hash("%d_%d_house_%d" % [coord.x, coord.y, i])
				building_ids.append(
					BuildingCatalog.choose_house_id(
						settlement.npcs[i].occupation, settlement.npcs[i].genome, seed_value
					)
				)

			var result: Dictionary = layout.layout(
				building_ids, CHUNK_SIZE, VillageLayout.seed_for(coord), is_buildable, never_occupied
			)
			var plots: Array = result["plots"]
			placed_counts.append(plots.size())
			if not (result["plaza"] as Rect2i).size == Vector2i.ZERO:
				with_plaza += 1
			if plots.is_empty():
				houseless += 1
				houseless_wanted.append(building_ids.size())
				houseless_frontage_water.append(_street_frontage_water_fraction(chunk, coord))
			else:
				housed += 1

	print("-- do real villages near lat %.1f lon %.1f actually build houses? --" % [LAT, LON])
	print("settlement chunks scanned:               %d" % scanned)
	if scanned == 0:
		quit()
		return
	print(
		"villages with NO house at all:           %d (%.1f%%)"
		% [houseless, 100.0 * float(houseless) / float(scanned)]
	)
	print("villages that got a plaza:               %d" % with_plaza)
	placed_counts.sort()
	print(
		"houses placed per village:               min %d  median %d  max %d"
		% [placed_counts[0], placed_counts[placed_counts.size() / 2], placed_counts[placed_counts.size() - 1]]
	)
	if not houseless_frontage_water.is_empty():
		houseless_frontage_water.sort()
		print(
			"for the houseless: street frontage that is WATER  min %.0f%%  median %.0f%%  max %.0f%%"
			% [
				100.0 * houseless_frontage_water[0],
				100.0 * houseless_frontage_water[houseless_frontage_water.size() / 2],
				100.0 * houseless_frontage_water[houseless_frontage_water.size() - 1],
			]
		)
		var wanted_total := 0
		for w in houseless_wanted:
			wanted_total += w
		print("for the houseless: houses they wanted    %d across %d villages" % [wanted_total, houseless])
	quit()


## How much of the strip a house would stand on -- the rows just north of
## the main street, across its whole length -- is water.
func _street_frontage_water_fraction(chunk, coord: Vector2i) -> float:
	var bones := VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))
	var street_y: int = bones["street_y"]
	var total := 0
	var water := 0
	for x in range(bones["street_x0"], bones["street_x1"] + 1):
		for dy in range(1, 4):
			var y := street_y - dy
			if y < 0:
				continue
			total += 1
			if _is_water(chunk.biome[y * CHUNK_SIZE + x]):
				water += 1
	return float(water) / float(total) if total > 0 else 0.0
