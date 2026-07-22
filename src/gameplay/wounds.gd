extends RefCounted

## Stacking wound/bleed severity: deals damage over time proportional to
## severity, heals slowly on its own, and heals a large chunk instantly when
## bandaged. Severity is uncapped -- nothing in the design calls for a max,
## and callers can already reason about "wounded" via is_wounded().

const BLEED_RATE_PER_SEVERITY := 0.1
const NATURAL_HEAL_PER_SECOND := 0.5
const BANDAGE_HEAL_PER_AMOUNT := 5.0

var severity := 0.0


func add_wound(amount: float) -> void:
	severity += amount


func bleed_damage_per_second() -> float:
	return severity * BLEED_RATE_PER_SEVERITY


## Applies this tick's bleed damage (computed from severity BEFORE natural
## healing below is applied, so a lethal-looking tick isn't softened by the
## same tick's healing) then reduces severity via natural healing.
func advance(delta: float) -> float:
	var damage := bleed_damage_per_second() * delta
	severity = maxf(severity - NATURAL_HEAL_PER_SECOND * delta, 0.0)
	return damage


func bandage(amount: float) -> void:
	severity = maxf(severity - BANDAGE_HEAL_PER_AMOUNT * amount, 0.0)


func is_wounded() -> bool:
	return severity > 0.0
