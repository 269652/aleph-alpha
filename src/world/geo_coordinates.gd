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
