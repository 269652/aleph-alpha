extends RefCounted

## Pure hiring gate for the NPC instruction DSL (docs/concept/
## npc_instructions.md, "Execution / wiring": "hiring_gate.gd is a new
## module answering only 'may this instruction even be assigned to this
## NPC'"). Two independent checks, both fail closed, neither touching a
## live Node or engine object:
##
##   can_hire           -- may an ongoing wage relationship even start:
##                          trust past npc_trust.gd's HIRE_THRESHOLD AND a
##                          wage that clears some minimum, both at once.
##   can_assign_script  -- once hired, how elaborate a script THIS NPC will
##                          tolerate: a caller-supplied script_cost checked
##                          against npc_trust.gd's own
##                          complexity_ceiling_for(trust).
##
## Two checks against the SAME underlying trust value, at two different
## named thresholds -- not one check reused for two purposes, per the
## concept doc's own Design pillar 5 and "Hiring is a separate gate from the
## DSL itself" language: "It gates *whether* instruction_script may be set
## on a given NpcMarker at all; the complexity ceiling above gates *how
## elaborate* a script may be once hiring already succeeded."
##
## `can_assign_script` takes an already-derived `script_cost` (the caller
## supplies npc_instruction_cost.gd's own `script_cost(ast)` output) -- this
## module never re-derives it, only checks it against the ceiling.

const NpcTrust = preload("res://src/world/npc_trust.gd")
const VillageWages = preload("res://src/world/village_wages.gd")


## A reasonable default floor for `minimum_wage`, for a caller with no more
## specific figure of its own. npc.md is explicit an ongoing hire wage is
## "a genuinely new, negotiated payment, NOT VillageWages's existing flat
## subsistence draw" -- so a hired wage must clear more than mere
## subsistence, or there would be no reason for an NPC to accept negotiated
## employment over passive village welfare. Anchored to
## VillageWages.subsistence_wage() (itself anchored to
## VillageMarket.VILLAGE_LOCAL_FOOD_PRICE) rather than a separately
## restated number, so it can never silently drift from what subsistence
## actually pays; doubled here as a real, not merely token, premium above
## it. `can_hire` still takes `minimum_wage` as its own parameter rather
## than reading this directly -- a caller with a real per-NPC negotiated
## figure should pass that; this exists only as a documented fallback.
static func default_minimum_wage() -> float:
	return float(VillageWages.subsistence_wage()) * 2.0


## May an ongoing instruction-hire relationship even start with this NPC, at
## this offered wage? True only if BOTH hold at once: trust clears
## npc_trust.gd's HIRE_THRESHOLD (npc.md: "a stranger won't work for you at
## any price" -- no wage, however large, buys around insufficient trust)
## AND wage_offered meets minimum_wage (however deep trust runs, nobody
## works for nothing).
static func can_hire(trust: float, wage_offered: float, minimum_wage: float) -> bool:
	if not NpcTrust.new().is_hireable(trust):
		return false
	return wage_offered >= minimum_wage


## Once hiring has already succeeded, may a script costing `script_cost`
## (npc_instruction_cost.gd's own script_cost(ast) output, supplied by the
## caller -- this module never re-derives it) be assigned to an NPC at this
## trust? True only if the cost fits under npc_trust.gd's own trust-derived
## complexity_ceiling_for(trust) -- the SAME underlying trust scalar
## can_hire reads, checked at a different, independent threshold.
static func can_assign_script(trust: float, script_cost: float) -> bool:
	var ceiling: float = NpcTrust.new().complexity_ceiling_for(trust)
	return script_cost <= ceiling
