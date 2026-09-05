extends RefCounted

## docs/concept/capture_dsl.md: derives a capture attempt's real success
## chance from a device's own tuned base rate plus real target biology --
## never authored directly per attempt, the same "derive, don't hand-tune
## per situation" discipline spell_cost.gd holds itself to for spell price.
##
## Pure and engine-free, like the rest of the DSL's logic modules: no RNG
## held here. The actual roll is the caller's job (see capture_executor.gd's
## own doc comment on why), this only turns a base rate + an individual's
## boldness into the legal probability that roll is checked against.

const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")

## How much a target's boldness shifts the odds either way. Tuned and
## pinned by test (CLAUDE.md: never an eyeballed number), not per-device:
## at FlyerPersonality.MIDDLING_BOLDNESS (the "unremarkable middle" a
## personality-less target -- a hand-placed fixture, an older save -- is
## already taken to be everywhere else boldness is read) a target gets
## exactly the device's own `base` chance; the boldest real individual gets
## base + BOLDNESS_WEIGHT/2, the shyest gets base - BOLDNESS_WEIGHT/2.
const BOLDNESS_WEIGHT := 0.3


## A capture attempt's real odds, clamped to a legal probability.
func catch_chance(base: float, boldness: float = FlyerPersonality.MIDDLING_BOLDNESS) -> float:
	var shift := (boldness - FlyerPersonality.MIDDLING_BOLDNESS) * BOLDNESS_WEIGHT
	return clampf(base + shift, 0.0, 1.0)


# --- mesh physics: what a net holds (capture_dsl.md, 2026-09-05) -------------
#
# Two comparisons over a subject's sorted body extents (body_dimensions.gd)
# and a bag's real geometry. A body passes a square opening when its two
# smaller extents both do, and the larger of those two -- the MIDDLE extent
# -- is the one that binds. It has to go through the mouth before it turns,
# so the LARGEST extent is what the mouth is compared against. The bag's
# depth does not enter: a bag deeper than its mouth always has room for what
# fit the mouth (a stated simplification in the concept doc).
#
# Both are monotone by construction -- a finer mesh never releases what a
# coarser one held, a wider mouth never refuses what a narrower one took --
# and test_capture_physics.gd pins that over every measured species.

## The three ways a verdict can refuse, for a caller that phrases the reason
## around its subject (the executor says "the bee slips through ...").
const CODE_UNMEASURED := "unmeasured"
const CODE_SLIPS_THROUGH := "slips_through"
const CODE_TOO_BIG := "too_big"


## Does a body with these extents pass through a mesh of `aperture_mm`?
## False for an unmeasured body ([]): the physics cannot claim a thing slips
## through when it does not know how big it is.
func slips_through(extents_mm: Array, aperture_mm: float) -> bool:
	var sorted := _sorted(extents_mm)
	if sorted.size() < 3:
		return false
	return float(sorted[1]) < aperture_mm


## Does a body with these extents go through a mouth `mouth_mm` wide?
## False for an unmeasured body, for the same reason.
func fits_mouth(extents_mm: Array, mouth_mm: float) -> bool:
	var sorted := _sorted(extents_mm)
	if sorted.size() < 3:
		return false
	return float(sorted[0]) <= mouth_mm


## Whether the bag holds the subject, and if not, why -- in words a player
## can act on ("slips through the 10 mm mesh" says weave a finer bag; "too
## big for the 30 cm mouth" says build a bigger one). An unmeasured subject
## is refused with its own reason rather than guessed at.
func mesh_verdict(extents_mm: Array, aperture_mm: float, mouth_mm: float) -> Dictionary:
	if _sorted(extents_mm).size() < 3:
		return {"holds": false, "code": CODE_UNMEASURED, "reason": "the net has no measure of its size"}
	if slips_through(extents_mm, aperture_mm):
		return {"holds": false, "code": CODE_SLIPS_THROUGH, "reason": "slips through the %s mm mesh" % _plain(aperture_mm)}
	if not fits_mouth(extents_mm, mouth_mm):
		return {"holds": false, "code": CODE_TOO_BIG, "reason": "too big for the %s cm mouth" % _plain(mouth_mm / 10.0)}
	return {"holds": true, "code": "", "reason": ""}


func _sorted(extents_mm: Array) -> Array:
	var sorted: Array = []
	for value in extents_mm:
		sorted.append(float(value))
	sorted.sort()
	sorted.reverse()
	return sorted


## 10.0 reads as "10", 2.5 as "2.5" -- a reason is prose, not a float dump.
func _plain(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
