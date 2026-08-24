extends RefCounted

## Maps between game-world tile coordinates and real-world latitude/longitude,
## assuming an equirectangular layout: x wraps east-west (longitude), y spans
## pole-to-pole (latitude). Shared by real-time day/night (SolarPosition) and,
## eventually, real elevation-data sampling.


## Latitude in degrees for a tile row: +90 (north pole) at row 0, -90 (south
## pole) at the last row.
func latitude_for_tile(tile_y: int, world_height: int) -> float:
	var t := float(tile_y) / float(world_height - 1)
	return 90.0 - t * 180.0


## Longitude in degrees for a tile column: -180 (date line) at column 0,
## increasing eastward, wrapping back at column world_width.
func longitude_for_tile(tile_x: int, world_width: int) -> float:
	var t := float(tile_x) / float(world_width)
	return -180.0 + t * 360.0


## Inverse of latitude_for_tile: the tile row containing a given latitude.
func tile_for_latitude(latitude_deg: float, world_height: int) -> int:
	var t := (90.0 - latitude_deg) / 180.0
	return roundi(t * float(world_height - 1))


## Inverse of longitude_for_tile: the tile column containing a given longitude.
func tile_for_longitude(longitude_deg: float, world_width: int) -> int:
	var t := (longitude_deg + 180.0) / 360.0
	return roundi(t * float(world_width))


## --- Reverse lookup with radius ---
## Shared infrastructure for hand-placed, real-coordinate-triggered content
## (docs/concept/easter_eggs.md's real-coordinate cameos, and the regional-
## mythology roster worldbosses.md describes) -- "is the player's tile near
## this real-world point" needs both a single-tile reverse lookup and a
## radius, on top of the plain tile_for_latitude/tile_for_longitude above.

## Real-world kilometers per degree of latitude/longitude -- the same ~111
## km/degree approximation EarthChunkGenerator's own TILES_PER_DEGREE
## comment documents for this world's real-Earth scale (~1km/tile at the
## game's actual WORLD_WIDTH_TILES/WORLD_HEIGHT_TILES). Used only to convert
## a real-world radius into tile space; latitude_for_tile/longitude_for_tile
## above don't depend on it, since they work in degrees directly.
const KM_PER_DEGREE := 111.0


## The tile a real-world (latitude_deg, longitude_deg) corresponds to on a
## world_width x world_height grid -- tile_for_longitude and tile_for_latitude
## combined into the one reverse lookup callers actually want.
func tile_for_coordinate(
	latitude_deg: float, longitude_deg: float, world_width: int, world_height: int
) -> Vector2i:
	return Vector2i(
		tile_for_longitude(longitude_deg, world_width), tile_for_latitude(latitude_deg, world_height)
	)


## A real-world radius_km converted into tile space, on a world_width x
## world_height grid. Uses latitude's tile density (uniform pole-to-pole,
## unlike longitude which compresses near the poles) as the conversion
## basis -- correct at the equator and a reasonable approximation elsewhere,
## which is exactly the same equirectangular-projection tradeoff
## latitude_for_tile/longitude_for_tile already make.
func radius_in_tiles(radius_km: float, world_height: int) -> float:
	var tiles_per_degree := float(world_height - 1) / 180.0
	return (radius_km / KM_PER_DEGREE) * tiles_per_degree


## True if tile (tile_x, tile_y) falls within radius_km of a real-world
## (latitude_deg, longitude_deg), on a world_width x world_height grid. The
## actual "given a target lat/lon + a small radius, which tile(s) does that
## correspond to" query, expressed as a membership test rather than an
## enumeration -- what every coordinate-triggered Easter egg actually needs
## ("is the player standing here") rather than a list of every tile in range.
func tile_is_within_radius(
	tile_x: int,
	tile_y: int,
	latitude_deg: float,
	longitude_deg: float,
	radius_km: float,
	world_width: int,
	world_height: int
) -> bool:
	var target := tile_for_coordinate(latitude_deg, longitude_deg, world_width, world_height)
	var distance := Vector2(tile_x, tile_y).distance_to(Vector2(target.x, target.y))
	return distance <= radius_in_tiles(radius_km, world_height)
