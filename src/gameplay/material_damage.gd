extends RefCounted

## Material-aware weapon damage model. Pure logic.
##
## Maps (weapon_kind, target material) -> damage multiplier. An axe excels
## against wood (chopping trees), a sword is the flesh weapon of choice.
## Unknown pairs fall back to DEFAULT_MULTIPLIER. All values are tested
## constants (see tests/unit/test_material_damage.gd).

const DEFAULT_MULTIPLIER: float = 1.0

const MULTIPLIERS: Dictionary = {
	"axe": {
		"wood": 3.0,
		"flesh": 0.8,
	},
	"sword": {
		"wood": 0.5,
		"flesh": 1.0,
	},
	"unarmed": {
		"wood": 0.25,
		"flesh": 0.5,
	},
}


func damage_multiplier(weapon_kind: String, material: String) -> float:
	var by_material: Dictionary = MULTIPLIERS.get(weapon_kind, {})
	return by_material.get(material, DEFAULT_MULTIPLIER)


func effective_damage(base_damage: float, weapon_kind: String, material: String) -> float:
	return maxf(0.0, base_damage * damage_multiplier(weapon_kind, material))
