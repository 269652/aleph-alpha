extends RefCounted

## A small, fixed table of pre-authored capture-device text, parsed,
## compiled and validated once and cached (docs/concept/capture_dsl.md).
## Same role spell_book.gd and device_book.gd play for their DSLs: a real,
## usable set of content while any future device-authoring UI stays unbuilt
## -- ItemCatalog._ITEMS/CraftingRecipeBook's own scoping, applied here.
##
## ## The net is device text (2026-09-05)
##
## A capture device is authored in standard_model.md's `device` grammar --
## the same rules the first capture DSL used, plus real parts -- so the net
## has a bag whose mesh has an `aperture_mm` and whose mouth is its
## `width_cm`, and what it holds is read off those and the subject's body
## (capture_physics.gd), never off a species list or a `tier` guard. The old
## `capture` block kind and capture_parser.gd are retired: the device grammar
## is a strict superset.
##
## Three things happen at load, once, and all of them can refuse loudly:
## DeviceParser parses the text, DeviceCompiler builds the part graph (an
## unmodeled material or a missing dimension comes back with the graph's own
## reason) and exposes every part's facts, and CaptureExecutor.validate
## checks the rules -- in particular that every `confine(in: X)` follows a
## `mesh_holds(mesh: X)` in its own pipeline, so no text in this table can
## confine a subject in a bag its mesh was not shown to hold.
##
## Kept deliberately honest: only devices actually wired end-to-end belong
## here. Today that's just butterfly_net -- the restrain-and-struggle tier
## (lasso/snare/trap/reinforced rope) stays on taming.gd's own mechanism and
## is not expressed as device text yet (see capture_dsl.md's status list).

const DeviceParser = preload("res://src/gameplay/device_parser.gd")
const DeviceCompiler = preload("res://src/gameplay/device_compiler.gd")
const CaptureExecutor = preload("res://src/gameplay/capture_executor.gd")

## The standard net: a 1.2 m wooden handle, a thin iron hoop, and a fibre
## bag 30 cm across the mouth with a coarse 10 mm mesh -- coarse enough that
## a bee or a fly passes it, fine enough to hold a butterfly, a songbird or
## a pond fish (capture_dsl.md's "Mesh physics" verdict table). `on catch`
## has no guard: `mesh_holds` IS the gate, and it says why when it refuses.
const BUTTERFLY_NET := """
	device "Butterfly Net" {
	  part handle: wood haft grip (length_cm: 120, diameter_cm: 2.5)
	  part hoop: iron haft structure (length_cm: 94, diameter_cm: 0.4)
	  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
	  joint ferrule: handle to hoop rigid fit iron
	  joint hem: hoop to bag rigid lashing fiber

	  on catch:
	    mesh_holds(mesh: bag) |> catch_roll(base: 0.65) |> confine(in: bag)
	  on release:
	    free(from: bag)
	  on transfer(glass_bottle):
	    move_captive()
	}
"""

## device_id -> DSL source text.
const _SOURCES := {
	"butterfly_net": BUTTERFLY_NET,
}

var _parser := DeviceParser.new()
var _executor := CaptureExecutor.new()

## Parsing, compiling and validating are pure and the source text never
## changes, so caching across every CaptureBook instance avoids redoing the
## same fixed work -- same static-cache convention as SpellBook._cache and
## DeviceBook's caches.
static var _ast_cache: Dictionary = {}
static var _compile_cache: Dictionary = {}


func has(device_id: String) -> bool:
	return _SOURCES.has(device_id)


func known_ids() -> Array:
	return _SOURCES.keys()


## The parsed, validated AST for `device_id` -- null for an unknown id, or
## for one whose fixed source text fails to parse or whose rules fail
## CaptureExecutor.validate (a loud push_error rather than a silent
## uncatchable device, since this table is authored, not player input).
func ast_for(device_id: String):
	if not _SOURCES.has(device_id):
		return null
	if not _ast_cache.has(device_id):
		var result := _parser.parse(_SOURCES[device_id])
		if not result["ok"]:
			push_error("CaptureBook entry '%s' failed to parse: %s" % [device_id, result["errors"]])
			return null
		var problems: Array = _executor.validate(result["ast"])
		if not problems.is_empty():
			push_error("CaptureBook entry '%s' failed to validate: %s" % [device_id, problems])
			return null
		_ast_cache[device_id] = result["ast"]
	return _ast_cache[device_id]


## The compiled device -- its real part graph, mass and part facts -- for
## `device_id`, cached the same way. null for an unknown id or one that does
## not parse; a compile that fails is returned as-is (its `errors` say why)
## and logged, so a broken entry is visible rather than silently absent.
func compiled_for(device_id: String):
	var ast = ast_for(device_id)
	if ast == null:
		return null
	if not _compile_cache.has(device_id):
		var compiled: Dictionary = DeviceCompiler.compile(ast)
		if not compiled["ok"]:
			push_error("CaptureBook entry '%s' failed to compile: %s" % [device_id, compiled["errors"]])
		_compile_cache[device_id] = compiled
	return _compile_cache[device_id]


## The device's part facts, keyed by part id (`bag.aperture_mm`,
## `bag.width_cm`, ...) -- what Player merges into the catch context so
## `mesh_holds` can read the bag it names. A fresh copy; {} for an unknown
## or broken entry.
func facts_for(device_id: String) -> Dictionary:
	var compiled = compiled_for(device_id)
	if compiled == null or not compiled["ok"]:
		return {}
	return compiled["facts"].duplicate(true)
