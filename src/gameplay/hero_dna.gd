extends RefCounted

## Player character DNA (see docs/concept/dna.md): a rolled genome that
## drives both the character's VISUAL phenotype (layered onto HeroAppearance,
## unchanged -- the same seed already drives that) and a soft per-archetype
## RESONANCE profile plus small stat modifiers on top of ClassArchetype's
## base numbers.
##
## "DNA and classes should resonate ... so when a player creates a new
## character it will have a random DNA which resonates more or less with
## different classes" (dna.md) -- resonance() gives each archetype an
## affinity score. Per classes.md's resolution, that resonance is
## SOFT/EFFICIENCY-ONLY (faster leveling in a resonant archetype), never a
## content gate.
##
## COMMON and RARE stay balanced: every genome's stat_modifiers net to
## exactly zero raw power (see the power-budget invariant, tested), so a
## rarer genome trades a BIGGER, more dramatic swing between its best and
## worst stat for an EQUAL deficit elsewhere -- "excellent magic attack but
## no defense". LEGENDARY is a deliberate exception (follow-up ask: "add
## legendary dna which is just better in most stats so a real win"): a
## legendary roll is pure upside, no deficit stat at all, net POSITIVE raw
## power across most (3 of 4) stats. It stays balanced at the POPULATION
## level purely through rarity -- only ~3% of rolls ever get it -- not
## through per-genome cancellation like the other two tiers.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")

const RARITY_COMMON := "common"
const RARITY_RARE := "rare"
const RARITY_LEGENDARY := "legendary"

## Rarer DNA is meant to be a genuinely rare, exciting moment (dna.md:
## "common, rare and legendary DNA traits which have a given chance to
## spawn"), not a routine one -- heavily weighted toward common. Cumulative
## cutoffs read legendary-first: a roll under LEGENDARY_CUTOFF is legendary,
## under RARE_CUTOFF is rare, everything else is common.
const LEGENDARY_CUTOFF := 0.03
const RARE_CUTOFF := 0.03 + 0.17

const _STAT_KEYS := ["max_health", "attack_damage", "max_mana", "max_stamina"]

## Total absolute stat swing COMMON/RARE genomes apply, split between one
## BUFFED stat and an equal-magnitude DEFICIT in another -- these two tiers
## always net to zero raw power (see the class doc comment above). Rarity
## changes how big that swing is, not whether it's balanced: a common roll's
## budget is small (barely noticeable jitter); a rare roll spends a bigger
## budget on one dramatic specialist spike.
const _BUDGET_BY_RARITY := {
	RARITY_COMMON: 4.0,
	RARITY_RARE: 14.0,
}

## Total PURE-UPSIDE power a legendary roll spends across 3 of the 4 stats
## (see _legendary_stat_modifiers_for) -- bigger than RARE's balanced swing
## budget, since none of it is offset by a deficit; this is the actual "real
## win" the follow-up asked for.
const LEGENDARY_TOTAL_BUFF := 34.0

## Flavor names for a rare/legendary roll's standout (buffed) stat -- purely
## presentational (the character-creation "you rolled X!" moment), no
## mechanical effect beyond what stat_modifiers already carries.
const _TRAIT_NAME_BY_STAT := {
	"max_health": "Ironblooded",
	"attack_damage": "Battle-Forged",
	"max_mana": "Arcane-Touched",
	"max_stamina": "Windrunner",
}

## How many DNA rerolls a player gets for free before the budget needs a
## real day to refresh (see RESET_INTERVAL_SECONDS) -- dna.md's original "a
## few times (3-5)", tightened by a follow-up ask into a real-world-time
## gate: "rerolls should reset every 24h real world hours so you have to
## wait a whole day if your rerolls are empty forcing the player to make
## wise choices". `has_premium` in can_reroll is a hook for wherever a real
## payment flow eventually plugs in (dna.md's original premium-credits
## idea) -- no such system exists in this project yet.
const MAX_FREE_REROLLS := 4

## A full REAL-WORLD day, in seconds -- the reroll budget's refresh period.
const RESET_INTERVAL_SECONDS := 86400.0


## Deterministic per seed_value -- same seed always rolls the same genome
## (matching this codebase's "identity persists" convention, e.g.
## CreatureInfo/NpcIdentity), and the SAME seed HeroAppearance.appearance_for
## already uses for visuals, so genotype and phenotype are always the one
## same roll, not two independent random draws.
func roll(seed_value: int) -> Dictionary:
	var rarity := _rarity_for(seed_value)
	var stat_modifiers := _stat_modifiers_for(seed_value, rarity)
	return {
		"seed_value": seed_value,
		"rarity": rarity,
		"resonance": _resonance_for(seed_value),
		"stat_modifiers": stat_modifiers,
		"trait_name": _trait_name_for(rarity, stat_modifiers),
	}


## True once `seconds_since_last_reset` (real-world elapsed time -- e.g.
## Time.get_unix_time_from_system() minus a persisted last-reset timestamp)
## covers a full day, meaning the free reroll budget refreshes regardless of
## how many rerolls were already used.
func reroll_budget_has_reset(seconds_since_last_reset: float) -> bool:
	return seconds_since_last_reset >= RESET_INTERVAL_SECONDS


## Whether a `rerolls_used`-th reroll (since the last daily reset) is
## allowed right now.
func can_reroll(rerolls_used: int, seconds_since_last_reset: float, has_premium: bool) -> bool:
	if reroll_budget_has_reset(seconds_since_last_reset):
		return true
	return rerolls_used < MAX_FREE_REROLLS or has_premium


func _rarity_for(seed_value: int) -> String:
	var unit := PixelNoise.unit(seed_value, 9001, 0)
	if unit < LEGENDARY_CUTOFF:
		return RARITY_LEGENDARY
	if unit < RARE_CUTOFF:
		return RARITY_RARE
	return RARITY_COMMON


## A 0..1 affinity score per ClassArchetype archetype -- independently
## rolled per (seed, archetype) so different genomes naturally favor
## different classes, with no single archetype privileged.
func _resonance_for(seed_value: int) -> Dictionary:
	var resonance := {}
	var archetypes := ClassArchetype.new().archetype_names()
	for i in archetypes.size():
		resonance[archetypes[i]] = PixelNoise.unit(seed_value, 9101, i)
	return resonance


func _stat_modifiers_for(seed_value: int, rarity: String) -> Dictionary:
	if rarity == RARITY_LEGENDARY:
		return _legendary_stat_modifiers_for(seed_value)
	return _balanced_stat_modifiers_for(seed_value, rarity)


## COMMON/RARE: picks one BUFFED stat and one (distinct) DEFICIT stat,
## splits this rarity's budget +/- between them, and zeroes the rest --
## always summing to exactly 0.0 raw power.
func _balanced_stat_modifiers_for(seed_value: int, rarity: String) -> Dictionary:
	var budget: float = _BUDGET_BY_RARITY[rarity]
	var buffed_index := int(PixelNoise.unit(seed_value, 9201, 0) * _STAT_KEYS.size())
	var deficit_offset := 1 + int(PixelNoise.unit(seed_value, 9202, 0) * (_STAT_KEYS.size() - 1))
	var deficit_index := (buffed_index + deficit_offset) % _STAT_KEYS.size()

	var modifiers := {}
	for key in _STAT_KEYS:
		modifiers[key] = 0.0
	modifiers[_STAT_KEYS[buffed_index]] = budget
	modifiers[_STAT_KEYS[deficit_index]] = -budget
	return modifiers


## LEGENDARY: spends LEGENDARY_TOTAL_BUFF as pure upside across 3 of the 4
## stats (deterministically, unevenly weighted so it doesn't read as a flat
## +6/+6/+6), leaving exactly one stat untouched at 0.0 -- never negative,
## "just better", not a trade-off (the follow-up's "real win" ask).
func _legendary_stat_modifiers_for(seed_value: int) -> Dictionary:
	var excluded_index := int(PixelNoise.unit(seed_value, 9301, 0) * _STAT_KEYS.size())

	var weights: Array[float] = []
	var weight_total := 0.0
	for i in _STAT_KEYS.size():
		if i == excluded_index:
			weights.append(0.0)
			continue
		# Floor of 0.4 keeps every boosted stat meaningfully above zero --
		# no near-invisible "boost" that's really just noise.
		var w := 0.4 + PixelNoise.unit(seed_value, 9302, i)
		weights.append(w)
		weight_total += w

	var modifiers := {}
	for i in _STAT_KEYS.size():
		var share := (LEGENDARY_TOTAL_BUFF * weights[i] / weight_total) if weight_total > 0.0 else 0.0
		modifiers[_STAT_KEYS[i]] = share
	return modifiers


func _trait_name_for(rarity: String, stat_modifiers: Dictionary) -> String:
	if rarity == RARITY_COMMON:
		return ""
	var buffed_stat := ""
	var best := -INF
	for key in stat_modifiers:
		if stat_modifiers[key] > best:
			best = stat_modifiers[key]
			buffed_stat = key
	var name: String = _TRAIT_NAME_BY_STAT.get(buffed_stat, "Gifted")
	return "Legendary %s" % name if rarity == RARITY_LEGENDARY else name
