extends RefCounted

## Whether an incoming hit against a world boss counts as real provocation
## (docs/concept/worldbosses.md's Krampus encounter-design brainstorm):
## "bosses should not attack low-level players on their own, even if they
## attack -- only if they deal actual damage do they pull aggro."
##
## The threshold is a FRACTION OF THE BOSS'S OWN max_health, not a flat
## number and not a new player-level-vs-creature-level comparison system --
## neither exists anywhere else in this codebase, and a level comparison
## would need its own infrastructure. Damage dealt is already the natural,
## existing proxy for "how equipped/leveled is this attacker" (weapon tier,
## class/skill attack bonuses all feed into it -- see MeleeAttack.
## attack_damage/MaterialDamage.effective_damage), so gating on the VALUE
## already flowing through the existing damage pipeline needs no new
## comparison axis. Self-scaling per boss (a tougher boss needs a bigger
## hit to register) rather than one shared flat number, so a future,
## tougher regional boss doesn't need its own hand-tuned threshold.

## First-pass placeholder, not a calibrated-against-real-playtesting number
## (this project has no live damage-scaling-by-level data yet to calibrate
## against -- see docs/concept/worldbosses.md's own open questions). Pinned
## here, not eyeballed inline, so a future numeric-design pass has one
## constant to revise rather than a scattered magic number.
const MIN_DAMAGE_FRACTION_OF_MAX_HEALTH := 0.02


## The minimum single-hit damage that counts as "real" against a boss with
## this max_health.
func min_damage_to_aggro(max_health: float) -> float:
	return max_health * MIN_DAMAGE_FRACTION_OF_MAX_HEALTH


## Whether `incoming_damage` clears that threshold for a boss with this
## max_health -- true means the hit both applies and provokes the boss;
## false means it should bounce off entirely (no damage, no aggro).
func deals_real_damage(incoming_damage: float, max_health: float) -> bool:
	return incoming_damage >= min_damage_to_aggro(max_health)
