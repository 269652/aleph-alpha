extends RefCounted
## Pure logic for the block mechanic: while blocking, incoming damage is
## reduced by a weapon-dependent efficiency (a sword blocks better than an
## axe; unarmed blocks worst).
##
## Blocking costs no stamina -- per docs/concept/survival.md's "Stamina scope:
## movement only, not combat" decision, combat (attacking and blocking) stays
## purely cooldown-based, so this module has no stamina-cost API.

## Fraction of incoming damage absorbed per weapon kind (0..1).
const _EFFICIENCY := {
	"sword": 0.7,
	"axe": 0.4,
	"unarmed": 0.2,
}

## Unknown weapon kinds block as poorly as bare hands.
const _FALLBACK_EFFICIENCY := 0.2


func block_efficiency(weapon_kind: String) -> float:
	return _EFFICIENCY.get(weapon_kind, _FALLBACK_EFFICIENCY)


## Damage that gets through when a hit of `incoming` damage is blocked.
func blocked_damage(incoming: float, weapon_kind: String) -> float:
	return maxf(0.0, incoming) * (1.0 - block_efficiency(weapon_kind))
