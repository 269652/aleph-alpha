extends RefCounted

## A small, fixed table of pre-authored capture-device text, parsed once and
## cached (docs/concept/capture_dsl.md). Same role spell_book.gd plays for
## magic: a real, usable set of content while any future device-authoring UI
## stays unbuilt -- ItemCatalog._ITEMS/CraftingRecipeBook's own scoping,
## applied here.
##
## Kept deliberately honest: only devices actually wired end-to-end belong
## here. Today that's just butterfly_net -- the restrain-and-struggle tier
## (lasso/snare/trap/reinforced rope) stays on taming.gd's own mechanism and
## is not expressed as capture text yet (see capture_dsl.md's status list).

const CaptureParser = preload("res://src/gameplay/capture_parser.gd")

## device_id -> DSL source text. `on catch when target.tier == "...": ...`
## for the roll; `on release` to empty the tool; `on transfer(CONTAINER)`
## reusing the event-arg slot to name which container a rule handles, the
## same reuse trick spell text already makes of it for delivery method.
const _SOURCES := {
	"butterfly_net": (
		'capture "Butterfly Net" { '
		+ 'on catch when target.tier == "flyer": catch_roll(base: 0.65) |> hold_captive() '
		+ "on release: release_captive() "
		+ "on transfer(glass_bottle): move_captive() }"
	),
}

var _parser := CaptureParser.new()

## Parsing is pure and the source text never changes, so caching across
## every CaptureBook instance avoids re-parsing the same fixed text
## repeatedly -- same static-cache convention as SpellBook._cache.
static var _cache: Dictionary = {}


func has(device_id: String) -> bool:
	return _SOURCES.has(device_id)


func known_ids() -> Array:
	return _SOURCES.keys()


## The parsed AST for `device_id` -- null for an unknown id, or for one
## whose fixed source text somehow fails to parse (a loud push_error rather
## than a silent uncatchable device, since this table is authored, not
## player input).
func ast_for(device_id: String):
	if not _SOURCES.has(device_id):
		return null
	if not _cache.has(device_id):
		var result := _parser.parse(_SOURCES[device_id])
		if not result["ok"]:
			push_error("CaptureBook entry '%s' failed to parse: %s" % [device_id, result["errors"]])
			return null
		_cache[device_id] = result["ast"]
	return _cache[device_id]
