extends RefCounted
## How long a fight has to last (docs/concept/combat.md, "The reference
## exchange").
##
## One rule:
##
##   An animal that stands and trades must live long enough to land two
##   bites.
##
## A telegraph you see once is a surprise; a telegraph you see twice is a
## pattern. A fight that ends inside one cycle cannot teach the animal that
## is in it -- and measured before this module existed, none of them did:
## the reference character felled a wolf in three swings, 1.5 s, against a
## `Dodge.COOLDOWN_DURATION` of 1.5 s and a bear rear-up of 0.90 s. The
## telegraph, the windup freeze, the i-frames and the reach asymmetry were
## all real, all tested, and none of them ever got a turn.
##
## Pure: RefCounted, static functions, no world, no player, no scene tree.
## Every number it is asked about is passed in, so a test can walk the rule
## without playing the game.

const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const NightMare = preload("res://src/gameplay/night_mare.gd")

## How many bites an animal that stands and trades must get to land. Two,
## for the reason in the doc: one telegraph is a surprise, two is a
## pattern.
const BITES_TO_LAND := 2

## The uniform multiplier on a creature's rolled `max_health`, applied in
## `CreatureInfo._init` -- the instance, never the table, so `Taming`'s
## health-derived `PREDATOR_BREAK_FREE_MULTIPLIER` and every `health /
## max_health` fraction in the game stay exactly where they were.
##
## NOT eyeballed. It is the smallest tenth for which every bound species
## satisfies the rule against the real reference character, and
## `test_combat_pacing.gd` pins it from both sides: at this value every
## bound species passes, and at one tenth less at least one fails.
##
## Measured, the binding species is the BOAR -- it needs 2.02 s to land two
## bites and carries only 28 base health, so it is felled fastest relative
## to what its own clock asks for. Every other bound species is satisfied
## between 1.3 (curupira) and 1.9 (wolf); the boar alone demands 2.5.
const EXCHANGE_HEALTH_SCALE := 2.5


## How long the animal needs to LAND `count` bites, counted the way its own
## clock actually runs: it telegraphs, it bites, it recovers, it telegraphs
## again. So `count` windups and `count - 1` recoveries -- the recovery
## after the last bite is time the fight does not need.
##
## Stated this way rather than as "count * (windup + cooldown)", which
## charges the fight for a recovery nobody waits through and demands about
## a fifth more health than the rule actually needs.
##
## `target_max_health` is the thing being bitten, because
## `windup_seconds_for` scales the tell by how much of you the bite would
## take -- a frailer character is warned for longer.
static func seconds_to_land_bites(species: String, target_max_health: float, count: int) -> float:
	if not SpeciesBite.has_profile(species) or count <= 0:
		return 0.0
	var windup := SpeciesBite.windup_seconds_for(species, target_max_health)
	var recovery := SpeciesBite.bite_cooldown_seconds_for(species)
	return count * windup + (count - 1) * recovery


## How many swings it takes to fell `health` at `damage_per_swing`. The
## ceiling, because a half-landed swing is not a thing: the last one is
## whole even when it overkills.
static func swings_to_fell(health: float, damage_per_swing: float) -> int:
	if damage_per_swing <= 0.0:
		return 0
	return int(ceil(health / damage_per_swing))


## How long those swings take. The FIRST one lands immediately, so the
## exchange is the cooldowns BETWEEN swings, not one per swing -- counting
## the leading cooldown would credit the rule with half a second nobody
## spends.
static func exchange_seconds(swings: int, attack_cooldown: float) -> float:
	return maxf(0, swings - 1) * attack_cooldown


## Whether this animal stands and trades, and so is bound by the rule.
##
## Both exemptions key on a property the code already owns rather than on a
## name in a list here:
##
## - The Alp never strikes at all (it presses a sleeper's chest), so its
##   `windup_seconds` column is fiction and "land two bites" is a
##   requirement about something that never happens.
## - A venomous animal is a glass cannon whose threat is what it leaves
##   behind, not what it survives. Binding the snake would demand 41 health
##   of it -- tougher than a jackal -- to protect a telegraph nobody is
##   meant to trade blows through.
static func stands_and_trades(species: String) -> bool:
	if not SpeciesBite.has_profile(species):
		return false
	if SpeciesBite.bite_damage_for(species) <= 0.0:
		return false
	if NightMare.presses_instead_of_striking(species):
		return false
	if SpeciesBite.VENOMOUS_SPECIES.has(species):
		return false
	return true


## The rule itself, asked of one animal against one character.
static func lasts_long_enough(
	species: String,
	creature_health: float,
	damage_per_swing: float,
	attack_cooldown: float,
	target_max_health: float
) -> bool:
	if not stands_and_trades(species):
		return true
	var lasts := exchange_seconds(
		swings_to_fell(creature_health, damage_per_swing), attack_cooldown
	)
	return lasts >= seconds_to_land_bites(species, target_max_health, BITES_TO_LAND)
