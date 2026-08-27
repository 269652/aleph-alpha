extends RefCounted

## Approximate solar position, accurate enough for day/night lighting (not
## navigation): no equation-of-time correction, and declination is a simple
## sinusoidal approximation rather than a full orbital calculation.

## Returns the sun's elevation in degrees above the horizon (negative when
## below it) for a given latitude/longitude at a UTC moment.
## day_of_year is 1-366 (day 80 ~ March equinox, day 172 ~ June solstice).
## utc_hour is hours since UTC midnight, may be fractional (e.g. 13.5 = 13:30).
func elevation_degrees(
	latitude_deg: float, longitude_deg: float, day_of_year: int, utc_hour: float
) -> float:
	var declination_deg := -23.44 * cos(deg_to_rad((360.0 / 365.0) * (day_of_year + 10)))
	var hour_angle_deg := 15.0 * (local_hour(utc_hour, longitude_deg) - 12.0)

	var lat_rad := deg_to_rad(latitude_deg)
	var decl_rad := deg_to_rad(declination_deg)
	var hour_rad := deg_to_rad(hour_angle_deg)

	var sin_elevation := sin(lat_rad) * sin(decl_rad) + cos(lat_rad) * cos(decl_rad) * cos(hour_rad)
	return rad_to_deg(asin(clampf(sin_elevation, -1.0, 1.0)))


## Local solar time at `longitude_deg`, for a given UTC hour -- the same
## astronomically-grounded formula elevation_degrees already uses internally
## for lighting (local_solar_time := utc_hour + longitude_deg / 15.0, 15
## degrees of longitude per hour of Earth's rotation), exposed here as its
## own function so anything that wants "what time is it HERE" (the displayed
## clock, NPC schedules, ...) shares the exact same source of truth as
## lighting does, rather than every caller either duplicating the formula or
## quietly showing raw UTC regardless of where the character actually is
## (reported: "if a player from Japan has his character in Berlin, it's
## still GMT+2 for him" -- the clock ignored in-game longitude entirely).
##
## Deliberately LONGITUDE-based solar time, not real political timezone
## boundaries: this game already grounds lighting in real astronomy rather
## than a timezone database (a far messier, separately-maintained dataset,
## and one that has nothing to do with the sun's actual position) -- keeping
## the displayed clock on the same real-astronomy basis as the sun overhead
## is the honest, internally-consistent choice, even though it won't always
## match a real place's actual civil clock exactly.
##
## Wraps into a real 0..24 clock face (never prints "25:00" or "-1:00").
func local_hour(utc_hour: float, longitude_deg: float) -> float:
	return fposmod(utc_hour + longitude_deg / 15.0, 24.0)


## The UTC hour that puts the local solar clock at `local_hour_value` here --
## the exact inverse of local_hour just above, on the same 15-degrees-of
## -longitude-per-hour relation.
##
## Exposed so the /time <hh:mm> console command can pin what the player reads
## on the clock -- and therefore what the sun does, since elevation_degrees
## and azimuth_degrees both go through local_hour -- without a caller
## re-deriving the relation for itself and drifting away from it. Wraps into
## a real 0..24 clock face, same as local_hour.
func utc_hour_for_local(local_hour_value: float, longitude_deg: float) -> float:
	return fposmod(local_hour_value - longitude_deg / 15.0, 24.0)


## Maps solar elevation to a normalized sunlight intensity [0.0, 1.0]: zero at
## and below the horizon, rising to 1.0 with the sun directly overhead.
func sunlight_intensity(elevation_deg: float) -> float:
	return clampf(sin(deg_to_rad(elevation_deg)), 0.0, 1.0)


## Sun azimuth in degrees (compass bearing, 0=north, 90=east, 180=south,
## 270=west, clockwise) -- the sun's compass DIRECTION, as opposed to
## elevation_degrees' angle above the horizon. Needed for real hillshading
## (see terrain_relief.gd, docs/concept/terrain_relief.md), which has to
## know not just how bright the sun is but which way a slope has to face to
## catch it. Same real astronomical inputs and same accuracy caveats as
## elevation_degrees (no equation-of-time correction, sinusoidal
## declination approximation) -- deliberately NOT merged into one combined
## function, so elevation_degrees (already driving live day/night lighting)
## stays completely untouched by this addition.
##
## Standard real solar-position formula:
## cos(azimuth) = (sin(declination) - sin(elevation)*sin(latitude)) /
## (cos(elevation)*cos(latitude)), disambiguated between the eastern and
## western half of the sky by the sign of the hour angle (negative =
## morning, sun still rising toward the meridian; positive = afternoon, sun
## past it).
func azimuth_degrees(
	latitude_deg: float, longitude_deg: float, day_of_year: int, utc_hour: float
) -> float:
	var declination_deg := -23.44 * cos(deg_to_rad((360.0 / 365.0) * (day_of_year + 10)))
	var hour_angle_deg := 15.0 * (local_hour(utc_hour, longitude_deg) - 12.0)
	var elevation_deg := elevation_degrees(latitude_deg, longitude_deg, day_of_year, utc_hour)

	var lat_rad := deg_to_rad(latitude_deg)
	var decl_rad := deg_to_rad(declination_deg)
	var elevation_rad := deg_to_rad(elevation_deg)

	# Sun at the zenith, or an observer at a pole -- azimuth is genuinely
	# undefined (every compass direction is simultaneously correct). 0.0 is
	# an arbitrary but harmless fallback: this is a rare, fleeting real
	# geometry, not a common case worth a separate sentinel value the way
	# terrain_relief.gd's flat-ground aspect uses -1.
	var denom := cos(elevation_rad) * cos(lat_rad)
	if absf(denom) < 0.0001:
		return 0.0

	var cos_azimuth := clampf((sin(decl_rad) - sin(elevation_rad) * sin(lat_rad)) / denom, -1.0, 1.0)
	var azimuth_deg := rad_to_deg(acos(cos_azimuth))
	if hour_angle_deg > 0.0:
		azimuth_deg = 360.0 - azimuth_deg
	return azimuth_deg


## Cumulative days before the 1st of each month (index 0) through December
## (index 11), in a non-leap year.
const DAYS_BEFORE_MONTH := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]


## Day of year (1-366) for a calendar date, accounting for leap years.
func day_of_year(year: int, month: int, day: int) -> int:
	var cumulative: int = DAYS_BEFORE_MONTH[month - 1]
	var is_leap := (year % 4 == 0) and (year % 100 != 0 or year % 400 == 0)
	if is_leap and month > 2:
		cumulative += 1
	return cumulative + day
