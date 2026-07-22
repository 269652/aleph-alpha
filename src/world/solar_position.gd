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
	var local_solar_time := utc_hour + longitude_deg / 15.0
	var hour_angle_deg := 15.0 * (local_solar_time - 12.0)

	var lat_rad := deg_to_rad(latitude_deg)
	var decl_rad := deg_to_rad(declination_deg)
	var hour_rad := deg_to_rad(hour_angle_deg)

	var sin_elevation := sin(lat_rad) * sin(decl_rad) + cos(lat_rad) * cos(decl_rad) * cos(hour_rad)
	return rad_to_deg(asin(clampf(sin_elevation, -1.0, 1.0)))


## Maps solar elevation to a normalized sunlight intensity [0.0, 1.0]: zero at
## and below the horizon, rising to 1.0 with the sun directly overhead.
func sunlight_intensity(elevation_deg: float) -> float:
	return clampf(sin(deg_to_rad(elevation_deg)), 0.0, 1.0)


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
