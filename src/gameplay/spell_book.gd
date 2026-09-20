extends RefCounted

## The world's catalogue of spells: a fixed table of pre-authored spells,
## parsed once and cached (docs/concept/spell_runtime.md's "fixed example
## spellbook, not a spell-authoring UI" section). There is no spell-editor
## UI yet, so this plays exactly the role ItemCatalog._ITEMS/
## CraftingRecipeBook played before any crafting UI existed: a real,
## castable body of content while the authoring layer above it stays
## unbuilt.
##
## **This is the catalogue, not anybody's known set.** `has()` answers
## "does this spell exist in the world", never "can you cast it" -- see
## spell_tuition.gd for the per-caster known set and docs/concept/
## mage_guild.md for who teaches what.
##
## **One spell per school per depth, roughly.** The table is laid out by
## spell_schools.gd's ten traditions rather than as a flat list, because
## mage_guild.md's pillar 2 -- who came to a guild decides what can be
## learned there -- is only interesting if a master's school and depth
## actually narrow the offer. A book of three fire spells would make every
## master either everything or nothing. Depth follows the atom catalog's
## own tiers: a spell is as deep as its deepest verb, so the tier-3 entries
## here are the ones only an archmage can pass on.

const SpellParser = preload("res://src/gameplay/spell_parser.gd")

## spell_id -> DSL source text. `on cast(DELIVERY) when wielder.mana >=
## @cost: pipeline` is the shape every entry follows -- see spell_runtime.md
## on why delivery rides the parser's existing event_arg slot.
const _SOURCES := {
	# -- pyromancy (fire_damage, ignite) -- no atom in this school runs
	# deeper than tier 1, so a pyromancer's whole trade is teachable by any
	# adept of it. Not every tradition has depth to offer.
	"fire_bolt": (
		'spell "Fire Bolt" { on cast(touch) when wielder.mana >= @cost: '
		+ "fire_damage(magnitude: 8) }"
	),
	"cinder_lash": (
		'spell "Cinder Lash" { on cast(projectile) when wielder.mana >= @cost: '
		+ "fire_damage(magnitude: 6) |> ignite(duration: 4) }"
	),

	# -- cryomancy (frost_damage, freeze, slow)
	"frost_lance": (
		'spell "Frost Lance" { on cast(projectile) when wielder.mana >= @cost: '
		+ "frost_damage(magnitude: 6) |> slow(duration: 3) }"
	),
	"glacial_bind": (
		'spell "Glacial Bind" { on cast(projectile) when wielder.mana >= @cost: '
		+ "frost_damage(magnitude: 5) |> freeze(duration: 3) }"
	),

	# -- galvanism (shock_damage, illuminate): the bolt and the lamp are
	# one trade.
	"spark": (
		'spell "Spark" { on cast(projectile) when wielder.mana >= @cost: '
		+ "shock_damage(magnitude: 7) }"
	),
	"lantern_light": (
		'spell "Lantern Light" { on cast(self) when wielder.mana >= @cost: '
		+ "illuminate(duration: 20) }"
	),

	# -- venefice (poison_damage, blight): the slow trades.
	"venom_dart": (
		'spell "Venom Dart" { on cast(projectile) when wielder.mana >= @cost: '
		+ "poison_damage(magnitude: 5) }"
	),
	"withering": (
		'spell "Withering" { on cast(touch) when wielder.mana >= @cost: '
		+ "blight(duration: 8) }"
	),

	# -- mending (minor_heal, major_heal, shield)
	"minor_heal": (
		'spell "Minor Heal" { on cast(self) when wielder.mana >= @cost: '
		+ "minor_heal(magnitude: 6) }"
	),
	"greater_mending": (
		'spell "Greater Mending" { on cast(self) when wielder.mana >= @cost: '
		+ "major_heal(magnitude: 18) }"
	),
	"warding_skin": (
		'spell "Warding Skin" { on cast(self) when wielder.mana >= @cost: '
		+ "shield(magnitude: 12, duration: 6) }"
	),

	# -- kinetics (push, pull, root, gravity_shift): force on a body.
	"shove": (
		'spell "Shove" { on cast(touch) when wielder.mana >= @cost: '
		+ "push(magnitude: 12) }"
	),
	"beckon": (
		'spell "Beckon" { on cast(projectile) when wielder.mana >= @cost: '
		+ "pull(magnitude: 12) }"
	),
	"snare": (
		'spell "Snare" { on cast(projectile) when wielder.mana >= @cost: '
		+ "root(duration: 3) }"
	),
	"heavy_air": (
		'spell "Heavy Air" { on cast(area) when wielder.mana >= @cost: '
		+ "gravity_shift(magnitude: 5, duration: 4) }"
	),

	# -- wayfaring (teleport, portal, reveal): going and seeing at a
	# distance.
	"farsight": (
		'spell "Farsight" { on cast(self) when wielder.mana >= @cost: '
		+ "reveal(duration: 12) }"
	),
	"blink": (
		'spell "Blink" { on cast(self) when wielder.mana >= @cost: '
		+ "teleport(magnitude: 8) }"
	),
	"gateway": (
		'spell "Gateway" { on cast(self) when wielder.mana >= @cost: '
		+ "portal(duration: 10) }"
	),

	# -- mentalism (calm, fear): minds rather than bodies.
	"soothe": (
		'spell "Soothe" { on cast(touch) when wielder.mana >= @cost: '
		+ "calm(duration: 6) }"
	),
	"dread": (
		'spell "Dread" { on cast(projectile) when wielder.mana >= @cost: '
		+ "fear(duration: 6) }"
	),

	# -- vivimancy (accelerate_growth, suppress_mutation, induce_mutation):
	# life itself, which is its own trade and a feared one.
	"quickening": (
		'spell "Quickening" { on cast(touch) when wielder.mana >= @cost: '
		+ "accelerate_growth(magnitude: 6) }"
	),
	"stillblood": (
		'spell "Stillblood" { on cast(touch) when wielder.mana >= @cost: '
		+ "suppress_mutation(duration: 10) }"
	),
	"graft": (
		'spell "Graft" { on cast(touch) when wielder.mana >= @cost: '
		+ "induce_mutation(magnitude: 3) }"
	),

	# -- conjury (summon_wisp): calling a thing into being. One atom, one
	# spell, and the deepest band there is.
	"call_wisp": (
		'spell "Call Wisp" { on cast(self) when wielder.mana >= @cost: '
		+ "summon_wisp(duration: 10) }"
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
