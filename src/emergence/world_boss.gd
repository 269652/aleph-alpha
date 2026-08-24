extends RefCounted

## A promoted world-boss-tier individual (see
## src/gameplay/world_boss_fitness.gd's own fitness/promotion math,
## docs/concept/worldbosses.md "World bosses: emergent apex predators").
##
## Pure data -- WorldBossStore owns assigning `id` and driving `status`, the
## same split Contract/Institution already use. `phases` stays a plain,
## untyped Array (not Array[Dictionary]) -- assigning a bare array/duplicate
## into a TYPED array field fails at RUNTIME, not parse time, in this
## engine version (see project memory on the gotcha); untyped sidesteps it
## entirely rather than routing every assignment through a typed local.

const ACTIVE := "active"
const DEFEATED := "defeated"
const STATUSES := [ACTIVE, DEFEATED]

## Assigned by WorldBossStore.promote; empty until then.
var id := ""

## The real creature entity this boss IS -- an EntityRef, the same
## deterministic-key idiom every other entity in this substrate uses.
var individual_id: String
var species: String
## The fitness_score that crossed the threshold, and the threshold itself
## -- both kept so /why can show a real margin, not just a pass/fail.
var score: float
var threshold: float
## Telegraphed encounter phases baked in once, at promotion time, from
## exactly one WorldBossFitness.PhaseGenerator call (docs/concept/
## worldbosses.md "Encounter design") -- never regenerated afterward.
var phases: Array = []
var status: String
var created_at: float


func _init(
	an_individual_id: String, a_species: String, a_score: float, a_threshold: float,
	a_phases: Array, a_created_at: float
) -> void:
	individual_id = an_individual_id
	species = a_species
	score = a_score
	threshold = a_threshold
	for phase in a_phases:
		phases.append(phase)
	created_at = a_created_at
	status = ACTIVE
