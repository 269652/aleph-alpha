extends RefCounted

## A small, fixed table of pre-authored example spells, parsed once and
## cached (docs/concept/spell_runtime.md's "fixed example spellbook, not a
## spell-authoring UI" section). There is no spell-editor UI and no
## skill-tree atom-unlock gate yet (skills.md's own status section names
## this as a still-open gap), so this plays exactly the role
## ItemCatalog._ITEMS/CraftingRecipeBook played before any crafting UI
## existed: a real, castable set of content while the authoring layer above
## it stays unbuilt. Every spell here is castable by anyone with enough
## mana -- the same "authoring/access depth is a later layer" scoping
## ItemCatalog itself already established for crafting.

const SpellParser = preload("res://src/gameplay/spell_parser.gd")

## spell_id -> DSL source text. `on cast(DELIVERY) when wielder.mana >=
## @cost: pipeline` is the shape every entry follows -- see spell_runtime.md
## on why delivery rides the parser's existing event_arg slot.
const _SOURCES := {
	"fire_bolt": (
		'spell "Fire Bolt" { on cast(touch) when wielder.mana >= @cost: '
		+ "fire_damage(magnitude: 8) }"
	),
	"frost_lance": (
		'spell "Frost Lance" { on cast(projectile) when wielder.mana >= @cost: '
		+ "frost_damage(magnitude: 6) |> slow(duration: 3) }"
	),
	"minor_heal": (
		'spell "Minor Heal" { on cast(self) when wielder.mana >= @cost: '
		+ "minor_heal(magnitude: 6) }"
	),
}

var _parser := SpellParser.new()

## Parsing is pure and the source text never changes, so caching across
## every SpellBook instance (not just this one) avoids re-parsing the same
## fixed text repeatedly -- same static-cache convention as
## ProceduralItemSprite._texture_cache.
static var _cache: Dictionary = {}


func has(spell_id: String) -> bool:
	return _SOURCES.has(spell_id)


func known_ids() -> Array:
	return _SOURCES.keys()


## The parsed AST for `spell_id` -- null for an unknown id, or for one whose
## fixed source text somehow fails to parse (a loud push_error rather than a
## silent uncastable spell, since this table is authored, not player input).
func ast_for(spell_id: String):
	if not _SOURCES.has(spell_id):
		return null
	if not _cache.has(spell_id):
		var result := _parser.parse(_SOURCES[spell_id])
		if not result["ok"]:
			push_error("SpellBook entry '%s' failed to parse: %s" % [spell_id, result["errors"]])
			return null
		_cache[spell_id] = result["ast"]
	return _cache[spell_id]
