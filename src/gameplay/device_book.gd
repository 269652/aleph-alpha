extends RefCounted

## A small, fixed table of pre-authored device text, parsed and compiled
## once and cached (docs/concept/standard_model.md, "Worked examples"). Same
## role capture_book.gd and spell_book.gd play for their DSLs: real, usable
## content while any device-authoring UI and any world placement of a device
## stay unbuilt -- ItemCatalog._ITEMS / CraftingRecipeBook's own scoping,
## applied here.
##
## Kept deliberately honest: only devices that parse, compile AND solve end
## to end belong here, and test_device_book.gd walks every entry to check.
## Nothing in live gameplay reads this table yet -- the same position
## ItemCompiler is in, named in the concept doc's Status list.

const DeviceParser = preload("res://src/gameplay/device_parser.gd")
const DeviceCompiler = preload("res://src/gameplay/device_compiler.gd")

## Worked example A. Read what is NOT in it: no wattage for the bulb, no
## ohms for the wire, no torque for the wheel. The river's push is momentum
## flux on half a square metre of paddle in a 1.5 m/s current; the wheel's
## ratio is its own metre of radius; the wire's resistance is copper's
## published conductivity over ten metres of 3 mm wire; the filament's is
## graphite's over two centimetres of a tenth of a millimetre.
##
## The gear train is the lesson: a water wheel turns at about a radian and a
## half a second, far too slow to generate from directly, and the same
## device without `gears` (MILL_RACE_LIGHT_WITHOUT_GEARS, below) puts under a
## watt into the filament. Real mills geared up by ten or more for exactly
## this reason. Here it is a consequence the solver reports, not a rule.
const MILL_RACE_LIGHT := """
	device "Mill Race Light" {
	  part wheel: wood face working (width_cm: 200, height_cm: 200, thickness_cm: 4)
	  part axle: iron haft structure (length_cm: 60, diameter_cm: 4)
	  part wire: copper haft structure (length_cm: 1000, diameter_cm: 0.3)
	  part filament: carbon haft working (length_cm: 2, diameter_cm: 0.01)
	  joint hub: wheel to axle rigid fit iron

	  law river: source(domain: translation, fluid: water, area_m2: 0.5, velocity: 1.5)
	  law wheel: transform(in: translation, out: rotation, part: wheel)
	  law gears: transform(in: rotation, out: rotation, ratio: 0.1)
	  law dynamo: gyrate(in: rotation, out: electrical, magnet_tesla: 0.5, turns: 200, area_m2: 0.02)
	  law wire: resist(domain: electrical, part: wire)
	  law filament: resist(domain: electrical, part: filament)

	  loop river |> wheel |> gears |> dynamo |> wire |> filament

	  on step when filament.power >= 1: shine(target: filament)
	}
"""

## The same light with the gear train left out -- NOT a book entry, because
## it does not work, and that is the point. Pinned by
## test_without_a_gear_train_the_same_wheel_lights_nothing.
const MILL_RACE_LIGHT_WITHOUT_GEARS := """
	device "Mill Race Light (ungeared)" {
	  part wheel: wood face working (width_cm: 200, height_cm: 200, thickness_cm: 4)
	  part axle: iron haft structure (length_cm: 60, diameter_cm: 4)
	  part wire: copper haft structure (length_cm: 1000, diameter_cm: 0.3)
	  part filament: carbon haft working (length_cm: 2, diameter_cm: 0.01)
	  joint hub: wheel to axle rigid fit iron

	  law river: source(domain: translation, fluid: water, area_m2: 0.5, velocity: 1.5)
	  law wheel: transform(in: translation, out: rotation, part: wheel)
	  law dynamo: gyrate(in: rotation, out: electrical, magnet_tesla: 0.5, turns: 200, area_m2: 0.02)
	  law wire: resist(domain: electrical, part: wire)
	  law filament: resist(domain: electrical, part: filament)

	  loop river |> wheel |> dynamo |> wire |> filament

	  on step when filament.power >= 1: shine(target: filament)
	}
"""

## Worked example B: a mill is a light with the gyrator left out and a
## different fluid. Ten square metres of sail in an 8 m/s wind, a four-metre
## sail radius, a 1:5 step-up to the stone, and the stone's grinding load as
## a rotational resistance. No new law, no new module.
const WINDMILL_MILL := """
	device "Post Mill" {
	  law wind: source(domain: translation, fluid: air, area_m2: 10, velocity: 8)
	  law sails: transform(in: translation, out: rotation, ratio: 4)
	  law gears: transform(in: rotation, out: rotation, ratio: 0.2)
	  law stone: resist(domain: rotation, resistance: 20)

	  loop wind |> sails |> gears |> stone

	  on step when stone.power >= 100: grind(target: stone)
	}
"""

## device_id -> DSL source text, in a fixed order.
const _SOURCES := {
	"mill_race_light": MILL_RACE_LIGHT,
	"windmill_mill": WINDMILL_MILL,
}
const _IDS: Array[String] = ["mill_race_light", "windmill_mill"]

var _parser := DeviceParser.new()

## Parsing and compiling are pure and the source text never changes, so
## caching across every DeviceBook instance avoids redoing the same fixed
## work -- the static-cache convention SpellBook._cache and CaptureBook.
## _cache already use.
static var _ast_cache: Dictionary = {}
static var _compile_cache: Dictionary = {}


func has(device_id: String) -> bool:
	return _SOURCES.has(device_id)


func known_ids() -> Array:
	return _IDS.duplicate()


## The parsed AST for `device_id` -- null for an unknown id, or for one
## whose fixed source text somehow fails to parse (a loud push_error rather
## than a silent unbuildable device, since this table is authored, not
## player input).
func ast_for(device_id: String):
	if not _SOURCES.has(device_id):
		return null
	if not _ast_cache.has(device_id):
		var result := _parser.parse(_SOURCES[device_id])
		if not result["ok"]:
			push_error("DeviceBook entry '%s' failed to parse: %s" % [device_id, result["errors"]])
			return null
		_ast_cache[device_id] = result["ast"]
	return _ast_cache[device_id]


## The compiled device (graph + chain) for `device_id`, cached the same way.
## null for an unknown id or one that does not parse; a compile that fails
## is returned as-is (its `errors` say why) and logged, so a broken entry is
## visible rather than silently absent.
func compiled_for(device_id: String):
	var ast = ast_for(device_id)
	if ast == null:
		return null
	if not _compile_cache.has(device_id):
		var compiled: Dictionary = DeviceCompiler.compile(ast)
		if not compiled["ok"]:
			push_error("DeviceBook entry '%s' failed to compile: %s" % [device_id, compiled["errors"]])
		_compile_cache[device_id] = compiled
	return _compile_cache[device_id]
