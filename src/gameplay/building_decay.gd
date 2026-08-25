extends RefCounted

## Withering: decay as a bounded, closed-form catch-up (see
## docs/concept/timber_construction.md#withering-decay-as-a-bounded-closed-
## form-catch-up). Every placed piece carries a `condition` value (1.0 =
## new), decaying toward 0.0 at a rate keyed to its material's own
## MaterialProperties.decay_rate, modulated by how exposed the piece is.
##
## Reuses chunk_ecology_catchup.gd's EXACT closed-form exponential-approach
## shape (`new_vegetation := 1.0 - (1.0 - vegetation) * exp(-rate * days)`),
## just decaying TOWARD zero instead of growing toward one:
##
##   new_condition := condition * exp(-decay_rate * exposure_multiplier * elapsed_days)
##
## Pure, deterministic, no mutation of any argument -- a large elapsed_days
## jump is safe and bounded in ONE call, matching ChunkEcologyCatchup's own
## "no need to iterate day by day" property: exp(-x) for x >= 0 is always in
## (0, 1], so this can never overshoot below 0 or need clamping, and a
## century-long jump is exactly as cheap as a one-second one.

const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## A roofed piece, or one belonging to an inhabited/maintained property,
## decays at a damped fraction of its material's base rate; anything else is
## fully EXPOSED (multiplier 1.0 -- the material's own undamped decay_rate).
## An unrecognized exposure string falls back to EXPOSED, the "assume the
## worst" direction -- mirrors BuildingPiece.is_load_bearing's own
## "unknown answers false" convention: a caller typo must never silently make
## a piece decay-immune.
const EXPOSURE_SHELTERED := "sheltered"
const EXPOSURE_EXPOSED := "exposed"

## Grounded in the doc's own "ground-contact/post-rot" reasoning: keeping
## wood dry, off bare earth, and out of standing weather (a roof overhang, a
## stone footing) measurably slows rot in real vernacular construction --
## surveys of untreated wood service life commonly put a properly sheltered,
## elevated member at several times (roughly 5x) the life of the same wood
## left in continuous ground contact/full weather exposure. It does not stop
## decay outright (a roofed but wholly untended structure still ages, just
## slowly) -- 0.2 (a fifth of the exposed rate) is that "slowed, not
## stopped" real-world ratio, not an eyeballed number. Pinned by
## test_exposure_multiplier_values_are_pinned.
const EXPOSURE_MULTIPLIER := {
	EXPOSURE_SHELTERED: 0.2,
	EXPOSURE_EXPOSED: 1.0,
}

## Exponential decay is asymptotic -- exp(-x) never reaches exactly 0.0 for
## any finite x, so "condition crossing zero" (this doc's own collapse
## trigger language) cannot mean literal zero without waiting an unbounded
## number of days. A piece retaining under 5% of its own original condition
## is, in real terms, no longer a standing structure -- negligible
## structural integrity, the "recognizable low ruin" Worked Example D and
## the doc's own "how real ruins decay" grounding describe, not a piece
## worth continuing to track. This is the real, honest collapse threshold
## BuildingDecay uses in place of unreachable literal zero. Pinned by
## test_ruined_condition_threshold_is_pinned.
const RUINED_CONDITION_THRESHOLD := 0.05

var _materials := MaterialProperties.new()


## The single closed-form step: `condition` (1.0 = new; values are assumed
## already in [0, 1]) after `elapsed_days` of decay for a piece made of
## `material`, under `exposure` (EXPOSURE_SHELTERED/EXPOSURE_EXPOSED).
## Monotonically non-increasing in elapsed_days and always in (0, condition]
## for finite input -- exp() itself guarantees this, no clamping needed.
## Negative elapsed_days (should never happen, but mirrors
## ChunkEcologyCatchup.advance's own maxf(0.0, ...) defensiveness) is
## treated as zero.
func advance_condition(condition: float, material: String, exposure: String, elapsed_days: float) -> float:
	var days := maxf(0.0, elapsed_days)
	var decay_rate := _materials.property_value(material, "decay_rate")
	var multiplier: float = EXPOSURE_MULTIPLIER.get(exposure, EXPOSURE_MULTIPLIER[EXPOSURE_EXPOSED])
	return condition * exp(-decay_rate * multiplier * days)


## Is a piece's condition low enough to treat as fully decayed -- see
## RUINED_CONDITION_THRESHOLD's own doc comment for why this, not a literal
## `<= 0.0`, is the real collapse trigger.
func is_ruined(condition: float) -> bool:
	return condition <= RUINED_CONDITION_THRESHOLD


## Which exposure state a piece is actually in, per the doc's own mechanism
## section: a roofed piece (caller answers this via
## RoomDetector.is_indoors(cell, grid)) OR a piece belonging to an
## inhabited/maintained property (caller answers this via
## HouseholdStore.owner_of(property_id) != "") is SHELTERED -- either
## condition alone is enough (a roofed but unclaimed ruin still keeps rain
## off; an owned-but-unroofed yard fence still gets tended). Neither ->
## EXPOSED, the fastest-decaying case. Pure boolean logic -- this module
## never talks to RoomDetector/HouseholdStore itself, matching
## BuildingStatics' own "caller decides what 'grounded' means" split.
func exposure_for(is_roofed: bool, owner_id: String) -> String:
	if is_roofed or owner_id != "":
		return EXPOSURE_SHELTERED
	return EXPOSURE_EXPOSED
