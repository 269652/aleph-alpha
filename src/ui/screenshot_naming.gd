extends RefCounted

## Pure filename/path formatting for the screenshot feature (see
## docs/concept/screenshots.md). Takes a Time.get_datetime_dict_from_system()
## -shaped Dictionary rather than reading the clock itself, so the exact
## filename a given moment produces is a plain, deterministic unit test --
## no sleeping, no fudging "close enough" on a wall-clock race. Mirrors the
## rest of this codebase's pure/thin-glue split (e.g. EscapeAction /
## World._unhandled_input): ScreenshotCapture is the thin glue that actually
## reads the clock, touches the filesystem, and reads a real viewport.

const DIRECTORY := "screenshots"
const EXTENSION := "webp"


## "DD-MM-YY HH-MM-SS.webp" -- date then time, both zero-padded, hyphens
## throughout. A literal ":" is illegal in a Windows filename, so the time
## portion reuses the date's own separator instead of inventing a second one.
static func filename_for(datetime: Dictionary) -> String:
	return "%02d-%02d-%02d %02d-%02d-%02d.%s" % [
		int(datetime["day"]), int(datetime["month"]), int(datetime["year"]) % 100,
		int(datetime["hour"]), int(datetime["minute"]), int(datetime["second"]),
		EXTENSION,
	]


## The res:// path a screenshot taken at `datetime` would be saved to, with
## no collision handling -- see unique_path_for for the version that actually
## checks.
static func path_for(datetime: Dictionary) -> String:
	return "res://%s/%s" % [DIRECTORY, filename_for(datetime)]


## Same as path_for, but appends " (2)", " (3)", ... before the extension if
## that path is already taken -- two screenshots within the same second must
## not silently overwrite each other. `path_exists` is injected (rather than
## this calling FileAccess.file_exists itself) so the collision search is a
## plain, deterministic unit test with no real filesystem involved.
static func unique_path_for(datetime: Dictionary, path_exists: Callable) -> String:
	var base := path_for(datetime)
	if not path_exists.call(base):
		return base
	var stem := base.get_basename()
	var suffix := 2
	var candidate := "%s (%d).%s" % [stem, suffix, EXTENSION]
	while path_exists.call(candidate):
		suffix += 1
		candidate = "%s (%d).%s" % [stem, suffix, EXTENSION]
	return candidate
