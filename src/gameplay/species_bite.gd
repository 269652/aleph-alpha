extends RefCounted

## One row per species: what it bites for, how long it telegraphs that
## bite, how far it notices you, how fast it runs you down, how far you
## must get to be rid of it, and how hurt it has to be before it quits
## (docs/concept/predator_profiles.md).
##
## Why this exists, measured: CreatureMarker gives EVERY species one
## ATTACK_DAMAGE (6.0) on one ATTACK_COOLDOWN (0.8s) from one SENSE_RADIUS
## (80px) at one HUNT_SPEED (36px/s -- slower than the player's walk, so
## every chase in the game today is lost by the pursuer), and
## CreatureBehavior gives them all one STRONG_HEALTH_FRACTION (0.5). A
## bear, a wolf, a boar and a jackal are four sprites over one stat block,
## which is why the RegionDifficulty gate that keeps bear/lion/
## venomous_snake far from spawn currently changes nothing a player can
## feel. This table is that gate's teeth.
##
## Pure: a RefCounted of static functions over a const table. No scene
## tree, no world, no file access, no singletons -- the wiring into
## CreatureMarker/CreatureBehavior is a separate change (see the doc's
## Status list), in the spirit of errand_delivery.gd and spell_cost.gd.
##
## Almost nothing here is authored. Bite damage and bite rate are derived
## from the species' REAL body mass (CreatureMass, already cited in this
## repo); pursuit speed is derived from its REAL top speed. What is
## authored is four columns -- a real top speed in km/h, a windup, a sense
## radius, a break-off point -- and every one of them is constrained by a
## test in tests/unit/test_species_bite.gd rather than eyeballed.

const CreatureMass = preload("res://src/world/creature_mass.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const Dodge = preload("res://src/gameplay/dodge.gd")

# -- anchors read off the live game -------------------------------------
#
# These four are the engine's own current numbers, copied here as
# constants rather than preloaded, because their homes (CreatureMarker is
# a Sprite2D, Player is a CharacterBody2D) are scene-tree scripts this
# module must not depend on. Each is pinned against its real source by
# test_species_bite.gd, so the copy cannot silently drift.

## CreatureMarker.ATTACK_DAMAGE / ATTACK_COOLDOWN: today's universal bite,
## kept here as the REFERENCE_SPECIES' bite. This table re-scales the
## roster AROUND the number the game already shipped instead of inflating
## it -- the wolf is the one animal whose bite this doc does not change.
const REFERENCE_BITE_DAMAGE := 6.0
const REFERENCE_BITE_COOLDOWN := 0.8
## A 40kg cursorial pack canid: the middle of the roster by mass, and the
## species the retired "predator" placeholder was always drawn as.
const REFERENCE_SPECIES := "wolf"

## Player.BASE_SPEED (40px/s) and Player.SPRINT_SPEED (80px/s) over
## TerrainRenderer.TILE_SIZE (16px). Every pursuit speed in the table is
## expressed against these two, because "can I get away" is the only
## question a chase asks.
const PLAYER_WALK_TILES_PER_SECOND := 2.5
const PLAYER_SPRINT_TILES_PER_SECOND := 5.0

## scenes/player.gd's `@export var max_health := 100.0` (and the same
## 100.0 base in apply_class). Used ONLY as the reference the table's own
## fairness math is authored against -- required_windup_seconds() takes
## the LIVE max health as a parameter, so a class, a level or a keystone
## that moves it re-derives the requirement rather than inheriting this.
const PLAYER_REFERENCE_MAX_HEALTH := 100.0

## CreatureMarker.FLEE_RELEASE_RADIUS / CreatureMarker.SENSE_RADIUS
## (120/80): the Schmitt-trigger hysteresis the engine ALREADY uses so a
## fleeing animal does not dither in and out of fleeing at one shared
## threshold. Pursuit gets the same treatment for the same reason -- and
## it is what makes backing off one step fail to break a chase.
const RELEASE_DISTANCE_RATIO := 1.5

## A chase must also open by at least a whole tile, not just by a ratio:
## a 1-tile-sense ambusher scaled by RELEASE_DISTANCE_RATIO alone would
## release half a tile out, which is not a decision, it is a step. Applied
## as a floor inside release_distance_tiles_for(), so the invariant holds
## for a sense radius nobody has authored yet rather than happening to
## hold for the ones that exist today.
const MIN_RELEASE_HYSTERESIS_TILES := 1.0

## CreatureMarker.CAUTION_RADIUS (160px) in tiles. Nothing senses further:
## past this the engine's own avoidance bias has already stopped
## considering the player at all, so an animal that reacted out here would
## be reacting to someone the rest of the AI has forgotten.
const MAX_SENSE_RADIUS_TILES := 10.0

# -- fairness -----------------------------------------------------------

## The smallest telegraph in the world is exactly as long as the
## invulnerability window the player's OWN dodge grants: see the tell,
## dodge on the frame it starts, and the whole bite passes through you.
const BASE_WINDUP_SECONDS := Dodge.INVINCIBLE_DURATION

## A bite that would kill a full-health player outright must be
## telegraphed for at least a whole dodge cooldown -- a player who has
## just dodged something else must never be killed by a bite they could
## not possibly have avoided.
const LETHAL_WINDUP_SECONDS := Dodge.COOLDOWN_DURATION

## The slice today's universal 6.0 bite takes out of the player's 100
## health. A bite no worse than the one the game already ships needs no
## more warning than the base telegraph; everything above it pays.
const FAIR_BITE_HEALTH_FRACTION := REFERENCE_BITE_DAMAGE / PLAYER_REFERENCE_MAX_HEALTH

## Computed, never authored: the slope that joins the two anchors above.
const WINDUP_SECONDS_PER_HEALTH_FRACTION := (
	(LETHAL_WINDUP_SECONDS - BASE_WINDUP_SECONDS) / (1.0 - FAIR_BITE_HEALTH_FRACTION)
)

## However hard it bites, an animal may not take a full-health player from
## alive to dead faster than this. Below it there is no "you are in
## trouble" phase to read, only a death -- which is the difference between
## stakes and a cheap shot. Roughly half today's uniform 13.3s.
const MINIMUM_TIME_TO_KILL_SECONDS := 5.0

# -- speed --------------------------------------------------------------

## A chase decided by less than this is decided by frame timing, not by a
## decision the player made. Used both as the escape test (is_outrun_by)
## and as how far past a sprint the fastest animal in the world sits.
const OUTRUN_MARGIN := 1.10

## The slowest animal in the roster moves at four fifths of a walk: it is
## outwalked by a clear 20%, comfortably more than OUTRUN_MARGIN, so the
## floor of the band is never a borderline case.
const SLOWEST_PURSUIT_FRACTION := 0.8

## The band every real top speed is compressed onto. Used literally, a
## real lion (80km/h) crosses 15 tiles a second and the game is
## unplayable; so the real ORDER is kept and the real RANGE is squeezed
## between "comfortably outwalked" and "cannot be outsprinted".
const SLOWEST_PURSUIT_TILES_PER_SECOND := PLAYER_WALK_TILES_PER_SECOND * SLOWEST_PURSUIT_FRACTION
const FASTEST_PURSUIT_TILES_PER_SECOND := PLAYER_SPRINT_TILES_PER_SECOND * OUTRUN_MARGIN

## The real range the band is mapped from -- the slowest and fastest cited
## top speeds in the table below. Pinned against the table itself by test,
## so both ends of the band are actually reached by a real animal.
const SLOWEST_REAL_TOP_SPEED_KMH := 9.0
const FASTEST_REAL_TOP_SPEED_KMH := 80.0

# -- allometry ----------------------------------------------------------

## Muscle force follows the CROSS-SECTION of the muscle, which follows the
## square of a linear dimension, which follows mass^(2/3) -- the same
## physical reasoning CreatureMass.linear_scale_for_mass_ratio already
## uses in the other direction (mass^(1/3), for footprint size). So a
## 300kg bear does not bite for 7.5x a 40kg wolf; it bites for 7.5^(2/3)
## ~ 3.8x. That one exponent is why a bear is frightening without being a
## one-shot, and why a 3.5kg arctic fox is an irritation.
const BITE_DAMAGE_MASS_EXPONENT := 2.0 / 3.0

## Jaw and limb cycle time follows the square root of a linear dimension
## (a pendulum's period -- the standard allometric approximation for gait
## and chewing frequency), i.e. mass^(1/6). Big jaws close slowly.
const BITE_COOLDOWN_MASS_EXPONENT := 1.0 / 6.0

## What one bite of venom is really worth: one DebuffStack stack, ticking
## for its whole duration (VenomModel). Delayed damage, deliberately NOT
## counted toward the windup requirement -- the strike is fast precisely
## because the strike is not what kills you.
const VENOM_DAMAGE_PER_BITE := (
	VenomModel.DAMAGE_PER_SECOND_PER_STACK * VenomModel.DURATION_SECONDS
)

## Mirrors CreatureMarker.VENOMOUS_SPECIES -- the one species whose bite
## injects venom.
const VENOMOUS_SPECIES := {"venomous_snake": true}

## A harder region must not be MARGINALLY harder: the least dangerous
## species gated to a tier must clear the most dangerous species of the
## tier below by this factor, or the gate is a casting decision again.
const TIER_THREAT_MARGIN := 1.25

# -- the authored table -------------------------------------------------

## Four authored columns per species, and nothing else:
##
## `real_top_speed_kmh` -- a commonly-cited real top speed for that real
##   animal, never an invented number (same discipline as
##   CreatureMass._REAL_MASS_KG). Compressed onto the pursuit band by
##   pursuit_speed_for_real_top_speed(); the world's speed ORDER is
##   nature's.
## `windup_seconds` -- the telegraph before the bite lands, authored per
##   species from how the real animal actually attacks (a bear rears up, a
##   viper strikes in a blink) and then REQUIRED to clear
##   required_windup_seconds() for its own damage. Authored independently
##   of the requirement on purpose: that is what makes the fairness test a
##   constraint on real data rather than a restatement of a formula.
## `sense_radius_tiles` -- how far it notices the player. Prey are the
##   wary ones (deer 9) and ambushers are not (lynx 6); a bear's nose is
##   the roster's best and sits exactly at MAX_SENSE_RADIUS_TILES.
## `tenacity` -- the health fraction at or below which it breaks off. A
##   solitary cat that is injured cannot hunt, and a lost hunt is
##   starvation, so the cats are risk-averse (0.40); a brown bear has
##   almost nothing that can make it quit (0.10); a viper cannot flee
##   anything, so the strike IS its defence (0.15); a jackal lives by not
##   fighting (0.45) and the 3.5kg arctic fox quits earliest of all (0.50
##   -- exactly today's universal STRONG_HEALTH_FRACTION, which survives
##   here as the behaviour of the most cowardly predator in the roster
##   rather than as everyone's rule). A species that cannot bite at all
##   gets 1.00: there is no health at which it stands.
##
## Every species the real spawn pools can produce has a row (see
## CreatureRenderer's HERBIVORE_SPECIES_POOL_BY_BIOME /
## PREDATOR_SPECIES_POOL_BY_BIOME and the generic fallback pools),
## drift-tested in both directions.
const PROFILES := {
	# -- predators, by what they do rather than what they look like -----
	"bear": {"real_top_speed_kmh": 56.0, "windup_seconds": 0.90, "sense_radius_tiles": 10.0, "tenacity": 0.10},
	"lion": {"real_top_speed_kmh": 80.0, "windup_seconds": 0.60, "sense_radius_tiles": 9.0, "tenacity": 0.20},
	"venomous_snake": {"real_top_speed_kmh": 11.0, "windup_seconds": 0.25, "sense_radius_tiles": 3.0, "tenacity": 0.15},
	"jaguar": {"real_top_speed_kmh": 65.0, "windup_seconds": 0.45, "sense_radius_tiles": 6.0, "tenacity": 0.40},
	# The Curupira (docs/concept/monsters.md): it senses further than any
	# animal because it is not tracking you, it has already decided about
	# you -- at the engine caution radius itself, the furthest anything in
	# the game may sense (test_nothing_senses_further_than_the_engines_
	# caution_radius); and it holds on past the health a hunting animal quits at,
	# because a grievance is not hunger.
	"curupira": {"real_top_speed_kmh": 45.0, "windup_seconds": 0.50, "sense_radius_tiles": 10.0, "tenacity": 0.08},
	"mountain_lion": {"real_top_speed_kmh": 80.0, "windup_seconds": 0.45, "sense_radius_tiles": 6.0, "tenacity": 0.40},
	"wolf": {"real_top_speed_kmh": 50.0, "windup_seconds": 0.40, "sense_radius_tiles": 9.0, "tenacity": 0.25},
	"lynx": {"real_top_speed_kmh": 64.0, "windup_seconds": 0.35, "sense_radius_tiles": 6.0, "tenacity": 0.40},
	"jackal": {"real_top_speed_kmh": 56.0, "windup_seconds": 0.30, "sense_radius_tiles": 8.0, "tenacity": 0.45},
	"arctic_fox": {"real_top_speed_kmh": 50.0, "windup_seconds": 0.30, "sense_radius_tiles": 7.0, "tenacity": 0.50},
	# A wild boar is herbivore-ROLE but aggressive (CreatureInfo): it does
	# not hunt you, it objects to you, at 40km/h and 90kg.
	"boar": {"real_top_speed_kmh": 40.0, "windup_seconds": 0.55, "sense_radius_tiles": 7.0, "tenacity": 0.30},
	# -- grazers: no bite, so no windup and no health at which they stand
	"deer": {"real_top_speed_kmh": 60.0, "windup_seconds": 0.0, "sense_radius_tiles": 9.0, "tenacity": 1.0},
	"reindeer": {"real_top_speed_kmh": 78.0, "windup_seconds": 0.0, "sense_radius_tiles": 8.0, "tenacity": 1.0},
	"horse": {"real_top_speed_kmh": 70.0, "windup_seconds": 0.0, "sense_radius_tiles": 8.0, "tenacity": 1.0},
	"camel": {"real_top_speed_kmh": 65.0, "windup_seconds": 0.0, "sense_radius_tiles": 7.0, "tenacity": 1.0},
	"tapir": {"real_top_speed_kmh": 48.0, "windup_seconds": 0.0, "sense_radius_tiles": 6.0, "tenacity": 1.0},
	"alpaca": {"real_top_speed_kmh": 35.0, "windup_seconds": 0.0, "sense_radius_tiles": 7.0, "tenacity": 1.0},
	"goat": {"real_top_speed_kmh": 26.0, "windup_seconds": 0.0, "sense_radius_tiles": 7.0, "tenacity": 1.0},
	"sheep": {"real_top_speed_kmh": 25.0, "windup_seconds": 0.0, "sense_radius_tiles": 6.0, "tenacity": 1.0},
	"squirrel": {"real_top_speed_kmh": 20.0, "windup_seconds": 0.0, "sense_radius_tiles": 5.0, "tenacity": 1.0},
	"mouse": {"real_top_speed_kmh": 13.0, "windup_seconds": 0.0, "sense_radius_tiles": 3.0, "tenacity": 1.0},
	"nonvenomous_snake": {"real_top_speed_kmh": 9.0, "windup_seconds": 0.0, "sense_radius_tiles": 3.0, "tenacity": 1.0},
}

## What a species with no row of its own gets: the world boss, the
## easter-egg cameo, anything a later roster adds before this table
## catches up. Every value is today's live engine behaviour
## (CreatureMarker.ATTACK_DAMAGE / ATTACK_COOLDOWN / SENSE_RADIUS /
## FLEE_RELEASE_RADIUS / HUNT_SPEED, CreatureBehavior
## .STRONG_HEALTH_FRACTION), so wiring this module in can never regress a
## creature it does not know about. The ONE number it does not copy from
## today's engine is the windup, because today's engine has none at all --
## that absence is the bug this module exists to fix.
const FALLBACK_SENSE_RADIUS_TILES := 5.0
const FALLBACK_PURSUIT_TILES_PER_SECOND := 2.25
const FALLBACK_TENACITY := 0.5


## How far the player must get before this animal gives up, from how far
## it senses them: the engine's own flee hysteresis ratio, never less than
## a whole tile of it.
static func release_distance_tiles_for(sense_radius_tiles: float) -> float:
	return maxf(
		sense_radius_tiles * RELEASE_DISTANCE_RATIO,
		sense_radius_tiles + MIN_RELEASE_HYSTERESIS_TILES
	)


static func has_profile(species: String) -> bool:
	return PROFILES.has(species)


## Every species with a row, sorted so callers and tests iterate in a
## stable order.
static func species_list() -> Array[String]:
	var names: Array[String] = []
	for species in PROFILES:
		names.append(species)
	names.sort()
	return names


## The commonly-cited real top speed the species' pursuit speed is
## compressed from. 0.0 for a species with no row (see profile_for).
static func real_top_speed_kmh(species: String) -> float:
	if not PROFILES.has(species):
		return 0.0
	var row: Dictionary = PROFILES[species]
	return float(row["real_top_speed_kmh"])


## Only an aggressive species bites at all -- CreatureInfo's temperament
## table is the roster's existing single source of truth for who fights,
## and this module deliberately does not hold a second opinion.
static func bite_damage_for(species: String) -> float:
	if CreatureInfo.TEMPERAMENT_BY_SPECIES.get(species, "calm") != "aggressive":
		return 0.0
	var mass_ratio := CreatureMass.mass_kg_for(species) / CreatureMass.mass_kg_for(REFERENCE_SPECIES)
	return REFERENCE_BITE_DAMAGE * pow(mass_ratio, BITE_DAMAGE_MASS_EXPONENT)


## Recovery between bites. Zero for a species that has no bite: a grazer's
## bite rate is not a small number, it is a meaningless one.
static func bite_cooldown_seconds_for(species: String) -> float:
	if bite_damage_for(species) <= 0.0:
		return 0.0
	var mass_ratio := CreatureMass.mass_kg_for(species) / CreatureMass.mass_kg_for(REFERENCE_SPECIES)
	return REFERENCE_BITE_COOLDOWN * pow(mass_ratio, BITE_COOLDOWN_MASS_EXPONENT)


## The real speed range, linearly compressed onto the playable band. Real
## order in, real order out.
static func pursuit_speed_for_real_top_speed(kmh: float) -> float:
	var span := FASTEST_REAL_TOP_SPEED_KMH - SLOWEST_REAL_TOP_SPEED_KMH
	if span <= 0.0:
		return SLOWEST_PURSUIT_TILES_PER_SECOND
	var t := clampf((kmh - SLOWEST_REAL_TOP_SPEED_KMH) / span, 0.0, 1.0)
	return (
		SLOWEST_PURSUIT_TILES_PER_SECOND
		+ t * (FASTEST_PURSUIT_TILES_PER_SECOND - SLOWEST_PURSUIT_TILES_PER_SECOND)
	)


## The whole row, derived columns and all. A species with no row of its
## own gets today's engine animal (see FALLBACK_*).
static func profile_for(species: String) -> Dictionary:
	if not PROFILES.has(species):
		return {
			"bite_damage": REFERENCE_BITE_DAMAGE,
			"venom_damage": 0.0,
			"bite_cooldown_seconds": REFERENCE_BITE_COOLDOWN,
			"windup_seconds": BASE_WINDUP_SECONDS,
			"sense_radius_tiles": FALLBACK_SENSE_RADIUS_TILES,
			"pursuit_speed_tiles_per_second": FALLBACK_PURSUIT_TILES_PER_SECOND,
			"release_distance_tiles": release_distance_tiles_for(FALLBACK_SENSE_RADIUS_TILES),
			"tenacity": FALLBACK_TENACITY,
		}
	var row: Dictionary = PROFILES[species]
	var damage := bite_damage_for(species)
	var sense := float(row["sense_radius_tiles"])
	return {
		"bite_damage": damage,
		"venom_damage": VENOM_DAMAGE_PER_BITE if VENOMOUS_SPECIES.has(species) else 0.0,
		"bite_cooldown_seconds": bite_cooldown_seconds_for(species),
		"windup_seconds": float(row["windup_seconds"]),
		"sense_radius_tiles": sense,
		"pursuit_speed_tiles_per_second": pursuit_speed_for_real_top_speed(
			float(row["real_top_speed_kmh"])
		),
		"release_distance_tiles": release_distance_tiles_for(sense),
		"tenacity": float(row["tenacity"]),
	}


## Fairness, as a function rather than as an intention: the harder a bite
## hits THIS player, the longer it must be telegraphed first. Flat at
## BASE_WINDUP_SECONDS up to the bite the game already ships, then rising
## to LETHAL_WINDUP_SECONDS for a bite that would kill outright. Takes the
## LIVE max health, so a frail character is warned more, not less.
static func required_windup_seconds(bite_damage: float, player_max_health: float) -> float:
	# No bite, no telegraph: a grazer is not owed a windup it has nothing
	# to spend. (Found by the table-wide fairness test, which asserts over
	# EVERY row rather than only over the ones that bite.)
	if bite_damage <= 0.0:
		return 0.0
	if player_max_health <= 0.0:
		return LETHAL_WINDUP_SECONDS
	var fraction := bite_damage / player_max_health
	var over := maxf(0.0, fraction - FAIR_BITE_HEALTH_FRACTION)
	return BASE_WINDUP_SECONDS + over * WINDUP_SECONDS_PER_HEALTH_FRACTION


## What the caller should actually use: the authored telegraph is a FLOOR,
## and the fairness requirement wins whenever this player is frail enough
## for it to. A 20-health character faces a longer bear rear-up than a
## 100-health one without anybody authoring a second table.
static func windup_seconds_for(species: String, player_max_health: float) -> float:
	var profile := profile_for(species)
	return maxf(
		float(profile["windup_seconds"]),
		required_windup_seconds(float(profile["bite_damage"]), player_max_health)
	)


## Health the profile takes per second of contact, venom included -- one
## bite (plus what that bite's venom is worth) per windup-and-recovery
## cycle. Zero for anything that cannot bite.
static func sustained_damage_per_second(profile: Dictionary) -> float:
	var damage := float(profile.get("bite_damage", 0.0)) + float(profile.get("venom_damage", 0.0))
	if damage <= 0.0:
		return 0.0
	var cycle := (
		float(profile.get("windup_seconds", 0.0))
		+ float(profile.get("bite_cooldown_seconds", 0.0))
	)
	if cycle <= 0.0:
		return 0.0
	return damage / cycle


## How long a player at full health survives while this stays on them.
## INF for a species that cannot bite -- it never kills you, rather than
## killing you in zero seconds.
static func seconds_to_kill(profile: Dictionary, player_max_health: float) -> float:
	var dps := sustained_damage_per_second(profile)
	if dps <= 0.0:
		return INF
	return player_max_health / dps


## The single number the world's order is checked against. Three things
## make an animal dangerous and all three are in here: how fast it takes
## your health, how much of ITSELF it will spend taking it (1 - tenacity,
## the fraction of its health it will burn before breaking off), and
## whether you can leave. A ranking device, not a damage simulation.
static func threat_score(profile: Dictionary) -> float:
	var commitment := 1.0 - float(profile.get("tenacity", 1.0))
	return (
		sustained_damage_per_second(profile)
		* maxf(0.0, commitment)
		* float(profile.get("pursuit_speed_tiles_per_second", 0.0))
	)


## Whether a player moving at `player_speed_tiles_per_second` really gets
## away -- by OUTRUN_MARGIN, not by a hair. A chase won by 1% is won by
## frame timing, and the player cannot feel the difference between that
## and losing.
static func is_outrun_by(
	pursuit_speed_tiles_per_second: float, player_speed_tiles_per_second: float
) -> bool:
	return pursuit_speed_tiles_per_second <= player_speed_tiles_per_second / OUTRUN_MARGIN


## Whether this species breaks off at this health fraction. Replaces
## CreatureBehavior's single STRONG_HEALTH_FRACTION (0.5) for every
## species alike -- a bear does not quit at half health, and a grazer
## (tenacity 1.0) never stands at all.
static func flees_at(species: String, health_fraction: float) -> bool:
	return health_fraction <= float(profile_for(species)["tenacity"])
