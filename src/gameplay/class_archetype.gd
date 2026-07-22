extends RefCounted

## Soft class system (docs/concept/classes.md): archetype is a starting lens,
## not a lock -- stats_for() is a pure snapshot lookup, never mutated state.

const _STAT_KEYS := ["max_health", "attack_damage", "max_mana", "max_stamina"]

## archetype_name -> stat bonus Dictionary. Every entry defines the same keys
## (some 0.0) so callers get a consistent shape regardless of archetype.
const _ARCHETYPES := {
	"warrior": {"max_health": 40.0, "attack_damage": 12.0, "max_mana": 0.0, "max_stamina": 20.0},
	"mage": {"max_health": -15.0, "attack_damage": 0.0, "max_mana": 50.0, "max_stamina": 0.0},
	"ranger": {"max_health": 10.0, "attack_damage": 8.0, "max_mana": 5.0, "max_stamina": 15.0},
	"beastmaster": {"max_health": 15.0, "attack_damage": 3.0, "max_mana": 10.0, "max_stamina": 10.0},
	"artisan": {"max_health": 5.0, "attack_damage": 0.0, "max_mana": 0.0, "max_stamina": 25.0},
	"herbalist": {"max_health": 0.0, "attack_damage": -5.0, "max_mana": 30.0, "max_stamina": 5.0},
	"overseer": {"max_health": 0.0, "attack_damage": 0.0, "max_mana": 15.0, "max_stamina": 0.0},
}


## All defined archetype names, e.g. for a character-creation picker.
func archetype_names() -> Array:
	return _ARCHETYPES.keys()


## Starting stat bonuses for a known archetype, or an all-zero Dictionary
## (with the same keys) for an unknown one -- never null/empty, so callers
## can always index into the result.
func stats_for(archetype_name: String) -> Dictionary:
	if _ARCHETYPES.has(archetype_name):
		return _ARCHETYPES[archetype_name].duplicate()
	var zeroed := {}
	for key in _STAT_KEYS:
		zeroed[key] = 0.0
	return zeroed


func is_known(archetype_name: String) -> bool:
	return _ARCHETYPES.has(archetype_name)


## Free respec (docs/concept/classes.md): switching archetypes has no cost or
## history, so this is a deliberate alias for stats_for() rather than tracking
## any prior-build state.
func respec(archetype_name: String) -> Dictionary:
	return stats_for(archetype_name)
