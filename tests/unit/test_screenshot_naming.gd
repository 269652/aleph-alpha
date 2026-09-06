extends GutTest

## ScreenshotNaming is pure filename/path formatting (see docs/concept/
## screenshots.md) -- takes a Time.get_datetime_dict_from_system()-shaped
## Dictionary rather than reading the clock itself, so an exact filename for
## a given moment is a plain, deterministic assertion, not a wall-clock race.

const ScreenshotNaming = preload("res://src/ui/screenshot_naming.gd")


func _dt(year: int, month: int, day: int, hour: int, minute: int, second: int) -> Dictionary:
	return {"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second}


func test_filename_pads_every_field_to_two_digits():
	assert_eq(ScreenshotNaming.filename_for(_dt(2026, 9, 6, 8, 3, 9)), "06-09-26 08-03-09.webp")


func test_filename_does_not_pad_fields_already_two_digits():
	assert_eq(ScreenshotNaming.filename_for(_dt(2026, 12, 25, 23, 59, 41)), "25-12-26 23-59-41.webp")


func test_filename_takes_only_the_last_two_digits_of_the_year():
	assert_eq(ScreenshotNaming.filename_for(_dt(1999, 1, 1, 0, 0, 0)), "01-01-99 00-00-00.webp")


func test_filename_uses_hyphens_not_colons_in_the_time_portion():
	# A literal ":" is illegal in a Windows filename.
	assert_false(ScreenshotNaming.filename_for(_dt(2026, 9, 6, 8, 3, 9)).contains(":"))


func test_path_for_is_under_the_screenshots_directory():
	assert_eq(ScreenshotNaming.path_for(_dt(2026, 9, 6, 8, 3, 9)), "res://screenshots/06-09-26 08-03-09.webp")


func test_unique_path_for_returns_the_plain_path_when_nothing_exists():
	var path := ScreenshotNaming.unique_path_for(_dt(2026, 9, 6, 8, 3, 9), func(_p): return false)
	assert_eq(path, "res://screenshots/06-09-26 08-03-09.webp")


func test_unique_path_for_appends_2_when_the_plain_path_is_taken():
	var taken := {"res://screenshots/06-09-26 08-03-09.webp": true}
	var path := ScreenshotNaming.unique_path_for(_dt(2026, 9, 6, 8, 3, 9), func(p): return taken.has(p))
	assert_eq(path, "res://screenshots/06-09-26 08-03-09 (2).webp")


func test_unique_path_for_keeps_incrementing_past_multiple_collisions():
	var taken := {
		"res://screenshots/06-09-26 08-03-09.webp": true,
		"res://screenshots/06-09-26 08-03-09 (2).webp": true,
		"res://screenshots/06-09-26 08-03-09 (3).webp": true,
	}
	var path := ScreenshotNaming.unique_path_for(_dt(2026, 9, 6, 8, 3, 9), func(p): return taken.has(p))
	assert_eq(path, "res://screenshots/06-09-26 08-03-09 (4).webp")
