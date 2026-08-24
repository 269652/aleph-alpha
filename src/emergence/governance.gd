extends RefCounted

## A settlement's governance form and legitimacy, both derived from real
## flows (see docs/concept/governance.md, docs/emergence/01-society-and-
## institutions.md "Governance": "Governance emerges from... historical
## precedent" and "Legitimacy": "Legitimacy derives from... food
## security").
##
## Deliberately narrow, same "don't invent what isn't grounded" discipline
## as every prior phase: of the docs' own named governance forms (council,
## hereditary leadership, merchant oligarchy, clan leadership, priesthood,
## military rule, cooperative administration, representative governance),
## only three have a real, already-tracked institution TYPE behind them
## (Institution.TYPES, Emergence Phase 6). Of legitimacy's eight named
## inputs (protection, food security, justice, tradition, wealth
## distribution, religious authority, military success, popular trust),
## only food security has real, already-live data (SettlementState, Phase
## 7) -- the rest wait on systems (crime, currency, trust/reputation,
## combat outcomes) that don't exist yet.

const SettlementState = preload("res://src/emergence/settlement_state.gd")

const NONE := "none"
const MILITARY_RULE := "military rule"
const MERCHANT_OLIGARCHY := "merchant oligarchy"
const COOPERATIVE_ADMINISTRATION := "cooperative administration"
const FORMS := [NONE, MILITARY_RULE, MERCHANT_OLIGARCHY, COOPERATIVE_ADMINISTRATION]

## `guild`'s real-world overlap with oligarchic economic power is closer
## than any other listed form -- deliberately mapped alongside
## `merchant_company` rather than given its own form. `criminal_group` is
## deliberately UNMAPPED: a purely criminal presence has coercive power,
## not legitimate authority (docs/emergence/01's own invariant: "No
## authority without legitimacy or coercion") -- this first slice does not
## yet model coercion-based rule separately from legitimate governance.
const _FORM_BY_INSTITUTION_TYPE := {
	"militia": MILITARY_RULE,
	"merchant_company": MERCHANT_OLIGARCHY,
	"guild": MERCHANT_OLIGARCHY,
	"cooperative": COOPERATIVE_ADMINISTRATION,
}

## The reverse of the mapping above -- what a NEW automatic institution
## formation attempts, given the settlement's current governance form. A
## settlement with no governance history yet defaults to "cooperative",
## unchanged from before this phase existed, so an ungoverned settlement's
## automatic formation behaves exactly as it always has.
const _NEW_FORMATION_TYPE_BY_FORM := {
	NONE: "cooperative",
	MILITARY_RULE: "militia",
	MERCHANT_OLIGARCHY: "merchant_company",
	COOPERATIVE_ADMINISTRATION: "cooperative",
}

const HIGH := "high"
const STABLE_LEGITIMACY := "stable"
const LOW := "low"
const LEGITIMACY_LEVELS := [HIGH, STABLE_LEGITIMACY, LOW]


## A settlement's dominant governance form, derived from which institution
## TYPE it has formed most across its real history (active or dissolved --
## a settlement's political character persists through a specific
## institution's failure). A tie breaks toward whichever type sorts first,
## deterministic rather than depending on Dictionary iteration order. NONE
## for a settlement with no institution history yet, or whose dominant
## type has no mapped form (criminal_group).
static func form_for(institution_type_counts: Dictionary) -> String:
	var types := institution_type_counts.keys()
	types.sort()
	var best_type := ""
	var best_count := 0
	for type in types:
		var count: int = institution_type_counts[type]
		if count > best_count:
			best_count = count
			best_type = type
	return _FORM_BY_INSTITUTION_TYPE.get(best_type, NONE)


## Legitimacy read directly off SettlementState's own real status -- the
## exact same underlying signal (food security) viewed through a
## different lens, not a second number to keep in sync with it.
static func legitimacy_for(settlement_status: String) -> String:
	if settlement_status == SettlementState.GROWING:
		return HIGH
	if settlement_status == SettlementState.DECLINING:
		return LOW
	return STABLE_LEGITIMACY


## What governance actually changes (this doc's own third design pillar,
## docs/emergence/07's own exit language: "Governance changes actual
## decisions and resource flows."): which institution type a settlement's
## own automatic formation attempts next.
static func institution_type_for_new_formation(governance_form: String) -> String:
	return _NEW_FORMATION_TYPE_BY_FORM.get(governance_form, "cooperative")
