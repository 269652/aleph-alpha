extends RefCounted

## One drive vector (docs/concept/ethogram.md §5, slice 3): the single clock
## behind every "rises over time, crosses a threshold, a meal takes it back
## down" need in the game.
##
## Before this, hunger alone was implemented five times -- CreatureNeeds for
## land mammals, NpcNeeds for villagers (a deliberate copy of the first),
## PiscivoreAppetite for the kingfisher, BirdDigestion for songbirds (as
## fullness, the same clock upside down), and SurvivalMeters for the player.
## The four animal ones now run on this, and their numbers are a PROFILE per
## body plan or species in the ethogram (Ethogram.drive_profile) rather than
## constants scattered across modules; the four modules survive as facades
## over this one so their callers and tests are untouched. The player's
## SurvivalMeters stays the player's: it has stamina and fitness this does
## not, and a player is not a species record.
##
## A profile entry per drive:
##   rise_seconds  how long the drive takes to go from 0 (satisfied) to 1
##                 (desperate) -- the world's own units, so a kingfisher's
##                 "two meals a day" and a mammal's 50-second clock are the
##                 same kind of number
##   threshold     the level from which the drive is URGENT (the old
##                 is_hungry boolean), and the level at which its gain is
##                 fully open
##   meal          how much one meal takes off; 1.0 or more resets it
##   start         (optional) the level a fresh individual begins at; a bird
##                 starts empty, a mammal starts fed
##   stagger       (optional) how far into its own cycle a fresh seeded
##                 individual may start, so a herd is not on one clock -- the
##                 same hash CreatureNeeds always used, so every animal keeps
##                 the onset it had
##   onset         (optional) the level at which the gain starts to open;
##                 below the threshold it makes the gain a RAMP, so a
##                 slightly hungry animal is slightly interested. Defaults
##                 to the threshold: a step, which is what every profile's
##                 own tests pin today
##
## Levels are also the behaviour kernel's GAINS: gains() is what the mammal
## adapter feeds it as the drives that gate each wiring. Pure, no engine
## dependency, no RNG.

## drive -> level in [0, 1], 0 satisfied, 1 desperate.
var levels: Dictionary = {}
var _profile: Dictionary = {}


## `seed_value` staggers where this individual begins in each drive's cycle
## (see `stagger` above); 0 means every drive starts exactly at its `start`.
func _init(profile: Dictionary, seed_value: int = 0) -> void:
	_profile = profile
	for drive in profile:
		var entry: Dictionary = profile[drive]
		var level := float(entry.get("start", 0.0))
		if seed_value != 0:
			level += stagger_for(seed_value, drive, float(entry.get("stagger", 0.0)))
		levels[drive] = clampf(level, 0.0, 1.0)


func advance(delta_seconds: float) -> void:
	for drive in levels:
		var entry: Dictionary = _profile[drive]
		levels[drive] = advanced(float(levels[drive]), float(entry.get("rise_seconds", 0.0)), delta_seconds)


func level(drive: String) -> float:
	return float(levels.get(drive, 0.0))


## The old boolean: the drive has crossed its threshold.
func is_urgent(drive: String) -> bool:
	if not _profile.has(drive):
		return false
	return level(drive) >= float(_profile[drive]["threshold"])


## One meal.
func satisfy(drive: String) -> void:
	if not levels.has(drive):
		return
	levels[drive] = after_meal(float(levels[drive]), float(_profile[drive].get("meal", 1.0)))


## This drive as the kernel's gate: 0 closed, 1 open, a ramp between `onset`
## and `threshold` when the profile asks for one.
func gain(drive: String) -> float:
	if not _profile.has(drive):
		return 0.0
	var entry: Dictionary = _profile[drive]
	var threshold := float(entry["threshold"])
	return gain_for(level(drive), threshold, float(entry.get("onset", threshold)))


func gains() -> Dictionary:
	var result := {}
	for drive in levels:
		result[drive] = gain(drive)
	return result


# -- the arithmetic, stateless, for the facades that keep a bare float ---------

static func advanced(level: float, rise_seconds: float, delta_seconds: float) -> float:
	if rise_seconds <= 0.0:
		return clampf(level, 0.0, 1.0)
	return clampf(level + maxf(delta_seconds, 0.0) / rise_seconds, 0.0, 1.0)


static func after_meal(level: float, meal: float) -> float:
	return clampf(level - meal, 0.0, 1.0)


## Hash-derived rather than RandomNumberGenerator, matching the deterministic
## "the same individual always rolls the same" idiom used throughout the
## world sim -- and the exact salt CreatureNeeds/NpcNeeds used, so nothing
## already in the world changes its onset.
static func stagger_for(seed_value: int, drive: String, max_fraction: float) -> float:
	var roll := float(absi(hash("%d_%s_need" % [seed_value, drive])) % 10000) / 10000.0
	return roll * max_fraction


static func gain_for(level: float, threshold: float, onset: float) -> float:
	if level >= threshold:
		return 1.0
	if onset >= threshold or level <= onset:
		return 0.0
	return (level - onset) / (threshold - onset)
