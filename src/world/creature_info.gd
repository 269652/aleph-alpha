extends RefCounted

## Identity/personality/stats data for a promoted creature marker, shown in
## its HUD panel (see CreaturePanel/World._update_creature_panels) and
## driving its behavior (see CreatureBehavior). health is a real damageable
## stat (Phase 3 combat); temperament + is_predator decide how the creature
## reacts to threats and prey around it. level is a deterministic
## per-individual flavor stat derived from its spawn seed and scales up
## max_health (see LEVEL_HEALTH_SCALE) so higher-level individuals are
## visibly tougher, not just a cosmetic number; stamina/mana are flavor
## stats for now (not yet consumed by any ability -- no stamina-cost
## actions or spellcasting exist).
##
## boar and lynx are variety within the herbivore/predator roles rather than
## new roles of their own (see CreatureRenderer's species pools): a boar is
## a herbivore-role individual (is_predator false, so it doesn't hunt and
## still counts toward EcosystemSimulation's herbivore population) that
## fights back when threatened instead of always fleeing; a lynx is a
## predator-role individual with its own stats/color. Both reuse
## CreatureBehavior's existing temperament/is_predator-driven decision tree
## unchanged.
##
## 8 more species (camel/jackal/reindeer/arctic_fox/tapir/jaguar/goat/
## mountain_lion) exist for the same reason, one per non-grassland/forest
## biome (see CreatureRenderer's HERBIVORE_SPECIES_POOL_BY_BIOME/
## PREDATOR_SPECIES_POOL_BY_BIOME) so different biomes actually look
## ecologically distinct instead of drawing from the same global 4-species
## pool. Each is its own species entry here (own stats/diet), independent of
## which of the 4 hand-drawn shape families it happens to render with.

## The 8 biome-specific species below (see CreatureRenderer's per-biome
## species pools -- desert/tundra/rainforest/mountain each get their own
## herbivore+predator pair) reuse one of the original 4's shape families for
## art (ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY) but are independent
## entries here: stats/diet/temperament/role are set per species, not
## inherited from whichever shape they happen to look like.
## Mouse is deliberately the smallest/frailest species (it's a mouse); horse
## the highest-stamina herbivore-role species (real horses are known for
## endurance) -- both real-world-grounded, not arbitrary, see
## docs/concept/ecosystem_dynamics.md's Species roster section.
const MAX_HEALTH_BY_SPECIES := {
	"herbivore": 20.0,
	"boar": 28.0,
	"predator": 35.0,
	"lynx": 26.0,
	"camel": 26.0,
	"jackal": 27.0,
	"reindeer": 24.0,
	"arctic_fox": 24.0,
	"tapir": 27.0,
	"jaguar": 34.0,
	"goat": 20.0,
	"sheep": 18.0,
	"mountain_lion": 32.0,
	"horse": 32.0,
	"mouse": 6.0,
	"deer": 24.0,
	"bear": 50.0,
	"lion": 45.0,
	"nonvenomous_snake": 10.0,
	"venomous_snake": 14.0,
	# -- Germany-region world bosses (docs/concept/worldbosses.md) ----------
	# Debug/test-spawn stats, not this doc's real design -- see this file's
	# GERMANY_BOSS_SPECIES-adjacent test for why these are hand-authored
	# placeholders rather than fitness-derived. All above this roster's
	# current toughest ordinary predator (bear, 50.0).
	"lindwurm": 140.0,
	"rubezahl": 110.0,
	"nyx": 95.0,
	"krampus": 120.0,
	# -- Easter-egg cameo creatures (docs/concept/easter_eggs.md) -----------
	# Debug/first-pass stats, same "hand-authored row" precedent as the
	# Germany bosses just above -- but deliberately NOT at that roster's
	# scale (95-140): the doc is explicit that Squallmaw "does nothing a
	# real creature doesn't already do (fight, flee, be tamed)", an
	# ordinary creature encounter, not a boss fight. Squallmaw reads as a
	# strong apex predator (above bear, this roster's toughest ordinary
	# predator at 50) without reaching world-boss stakes. Coilnecca and
	# Champ are calm/skittish cameos, not combat encounters, so they sit at
	# an ordinary-herbivore scale instead.
	"squallmaw": 58.0,
	"coilnecca": 24.0,
	"champ": 21.0,
}
const MAX_STAMINA_BY_SPECIES := {
	"herbivore": 30.0,
	"boar": 25.0,
	"predator": 25.0,
	"lynx": 30.0,
	"camel": 30.0,
	"jackal": 25.0,
	"reindeer": 30.0,
	"arctic_fox": 30.0,
	"tapir": 25.0,
	"jaguar": 25.0,
	"goat": 30.0,
	"sheep": 22.0,
	"mountain_lion": 25.0,
	"horse": 40.0,
	"mouse": 20.0,
	"deer": 32.0,
	"bear": 28.0,
	"lion": 30.0,
	"nonvenomous_snake": 15.0,
	"venomous_snake": 15.0,
	"lindwurm": 30.0,
	"rubezahl": 35.0,
	"nyx": 30.0,
	"krampus": 35.0,
	# Squallmaw is a strong swimmer (high stamina); Coilnecca/Champ are
	# unhurried lake dwellers, ordinary-herbivore-scale.
	"squallmaw": 32.0,
	"coilnecca": 26.0,
	"champ": 26.0,
}
const MAX_MANA_BY_SPECIES := {
	"herbivore": 5.0,
	"boar": 5.0,
	"predator": 10.0,
	"lynx": 10.0,
	"camel": 5.0,
	"jackal": 10.0,
	"reindeer": 5.0,
	"arctic_fox": 10.0,
	"tapir": 5.0,
	"jaguar": 10.0,
	"goat": 5.0,
	"sheep": 5.0,
	"mountain_lion": 10.0,
	"horse": 5.0,
	"mouse": 5.0,
	"deer": 5.0,
	"bear": 5.0,
	"lion": 10.0,
	"nonvenomous_snake": 5.0,
	"venomous_snake": 5.0,
	"lindwurm": 10.0,
	"rubezahl": 10.0,
	"nyx": 10.0,
	"krampus": 10.0,
	"squallmaw": 10.0,
	"coilnecca": 5.0,
	"champ": 5.0,
}
const DIET_BY_SPECIES := {
	"herbivore": "Grazer",
	"boar": "Omnivore",
	"predator": "Hunter",
	"lynx": "Hunter",
	"camel": "Grazer",
	"jackal": "Hunter",
	"reindeer": "Grazer",
	"arctic_fox": "Hunter",
	"tapir": "Grazer",
	"jaguar": "Hunter",
	"goat": "Grazer",
	"sheep": "Grazer",
	"mountain_lion": "Hunter",
	"horse": "Grazer",
	"mouse": "Forager",
	"deer": "Grazer",
	"bear": "Omnivore",
	"lion": "Hunter",
	"nonvenomous_snake": "Small-Prey Hunter",
	"venomous_snake": "Venomous Hunter",
	"lindwurm": "Apex Hunter",
	"rubezahl": "Apex Hunter",
	"nyx": "Apex Hunter",
	"krampus": "Apex Hunter",
	"squallmaw": "Apex Hunter",
	"coilnecca": "Forager",
	"champ": "Forager",
}
## Herbivores are calm (always flee threats); boars/predators/lynx are
## aggressive (fight when strong, flee when weak). See CreatureBehavior for
## how this is used -- fighting back only needs "aggressive" temperament, not
## is_predator, so a boar fights without hunting other creatures for food.
## tapir deliberately stays "calm" despite sharing boar's shape family --
## temperament is independent of shape and set directly per species.
const TEMPERAMENT_BY_SPECIES := {
	"herbivore": "calm",
	"boar": "aggressive",
	"predator": "aggressive",
	"lynx": "aggressive",
	"camel": "calm",
	"jackal": "aggressive",
	"reindeer": "calm",
	"arctic_fox": "aggressive",
	"tapir": "calm",
	"jaguar": "aggressive",
	"goat": "calm",
	"sheep": "calm",
	"mountain_lion": "aggressive",
	"horse": "calm",
	"mouse": "calm",
	"deer": "calm",
	"bear": "aggressive",
	"lion": "aggressive",
	"nonvenomous_snake": "calm",
	"venomous_snake": "aggressive",
	"lindwurm": "aggressive",
	"rubezahl": "aggressive",
	"nyx": "aggressive",
	"krampus": "aggressive",
	# Squallmaw is furious-looking and can fight (docs/concept/
	# easter_eggs.md: "does nothing a real creature doesn't already do
	# (fight, flee, be tamed)") -- an ordinary aggressive predator, not a
	# world boss (see WORLD_BOSS_SPECIES below, which it deliberately does
	# not join). Coilnecca is explicitly calm ("Deliberately calm-
	# temperament (not aggressive like the mythology roster's kelpie)").
	# Champ is deliberately "skittish rather than placid" in the doc's own
	# words -- NOT a reskin of Coilnecca's calm despite the family
	# resemblance. "skittish" is a new temperament value: CreatureBehavior
	# only special-cases "aggressive" (see _will_fight), so anything else,
	# including this new label, already flees exactly like "calm" does --
	# see test_creature_behavior.gd's regression test for that. The
	# distinct label exists so Champ never reads as a mechanical duplicate
	# of Coilnecca, even though both currently behave the same way in
	# CreatureBehavior (a real per-species flee-detection-radius
	# difference, matching the doc's "visible only from a real distance"
	# flavor more precisely, is a documented follow-up -- see
	# docs/progress.md).
	"squallmaw": "aggressive",
	"coilnecca": "calm",
	"champ": "skittish",
}
## Only true predators (hunt herbivores/boars for food) go here -- a boar is
## aggressive but not a predator (see TEMPERAMENT_BY_SPECIES doc above).
## camel/tapir/etc are likewise herbivore-role even where calm/aggressive
## temperament might suggest otherwise; only the 4 dedicated predator species
## added alongside boar/lynx go here.
const PREDATOR_SPECIES := {
	"predator": true,
	"lynx": true,
	"jackal": true,
	"arctic_fox": true,
	"jaguar": true,
	"mountain_lion": true,
	"bear": true,
	"lion": true,
	"venomous_snake": true,
	"lindwurm": true,
	"rubezahl": true,
	"nyx": true,
	"krampus": true,
	"squallmaw": true,
}

## Gates the aggro-provocation rule (docs/concept/worldbosses.md, see
## BossAggro/CreatureBehavior._perceives_threats): a world boss doesn't
## proactively attack (or flee) a nearby player at all until a real hit
## lands, unlike every other species' proximity-based reaction. Currently
## just the Germany-region roster; a future regional boss joins this table
## the same way it joins PREDATOR_SPECIES above.
const WORLD_BOSS_SPECIES := {
	"lindwurm": true,
	"rubezahl": true,
	"nyx": true,
	"krampus": true,
}

## Levels roll in [1, LEVEL_RANGE] from the individual's seed -- a cheap,
## deterministic source of "some creatures are tougher than others" variety
## without a full leveling/XP system.
const LEVEL_RANGE := 5

## Each level above 1 adds this fraction of the species' base max_health --
## e.g. 0.25 means a level-5 individual (the max) has double the base HP.
const LEVEL_HEALTH_SCALE := 0.25

var species: String
var display_name: String
var diet: String
var temperament: String
var is_predator: bool
## See WORLD_BOSS_SPECIES above.
var is_world_boss: bool
## Per-individual state, not per-species data -- always starts false
## regardless of species; BossAggro/CreatureMarker.take_damage flips it on
## the first hit that clears the real-damage threshold. Meaningless (and
## unread) for a non-boss creature.
var is_aggroed: bool = false
var level: int
var max_health: float
var health: float
var max_stamina: float
var stamina: float
var max_mana: float
var mana: float


func _init(a_species: String, seed_value: int = 0) -> void:
	species = a_species
	display_name = a_species.capitalize()
	diet = DIET_BY_SPECIES.get(a_species, "Unknown")
	temperament = TEMPERAMENT_BY_SPECIES.get(a_species, "calm")
	is_predator = PREDATOR_SPECIES.get(a_species, false)
	is_world_boss = WORLD_BOSS_SPECIES.get(a_species, false)
	level = 1 + (absi(seed_value) % LEVEL_RANGE)
	var base_max_health: float = MAX_HEALTH_BY_SPECIES.get(a_species, 10.0)
	max_health = base_max_health * (1.0 + (level - 1) * LEVEL_HEALTH_SCALE)
	health = max_health
	max_stamina = MAX_STAMINA_BY_SPECIES.get(a_species, 10.0)
	stamina = max_stamina
	max_mana = MAX_MANA_BY_SPECIES.get(a_species, 5.0)
	mana = max_mana
