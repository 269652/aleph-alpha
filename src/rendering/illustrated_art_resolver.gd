extends RefCounted

## Resolves a REQUESTED illustrated-art address (context/season/state/
## animation, for one subject) into the address that actually exists, per
## docs/concept/illustrated_art_addressing.md's "Resolution: the fallback
## lattice". Pure logic: `address_exists` is caller-injected --
## Callable(context, season, state, animation) -> bool -- so this never
## touches a real file itself and stays headlessly testable against a
## fixture set of placeholder addresses (see test_illustrated_art_
## resolver.gd's own `_fixture` helper), matching this codebase's
## established "inject the check" convention (LeafLitterField.
## set_current_probe, AntColony's seeded rolls, etc.).
##
## ## The algorithm: a lattice search, not an ordered cascade
##
## Four axes can each be relaxed to the subject's own declared fallback
## value: season -> entry.base_season, state -> entry.base_state,
## context -> "icon", animation -> "still" (subject itself falling back to
## the caller's procedural sprite is the caller's job once is_procedural
## comes back true -- this resolver only ever deals in the 4 file-address
## axes). Every one of the 16 combinations of {requested, relaxed} across
## those 4 axes is a candidate address; this tries them in order of FEWEST
## axes relaxed first, and among candidates that relax the same NUMBER of
## axes, in the fixed priority order season, then state, then context,
## then animation -- returning the first candidate address_exists confirms.
## Implemented as a straight bitmask walk (mask bit 0=season, 1=state,
## 2=context, 3=animation; sorted by (popcount(mask), mask) ascending,
## which is exactly "fewest relaxed axes first, ties broken by the fixed
## per-axis priority" without needing to hand-enumerate combinations).
##
## **Why a lattice search, not simply walking the doc's own 5-item
## numbered list in order:** the doc's list order (animation, season,
## state, context, subject) does not actually match its OWN worked
## example. "`worn/attack` resolves to `pristine/attack` (state -> base
## state)" requires preferring a STATE-only relaxation (pristine/attack,
## an exact animation match) over an ANIMATION-only relaxation (worn/
## still, an exact state match) -- both are real, single-axis-relaxed
## candidates that exist for the pilot's actual file set, so which one
## wins is a genuine tie the numbered list (animation listed first) gets
## backwards. This resolver follows the concrete, specifically-justified
## worked example ("a worn club still swings using the pristine frames")
## over the abstract list where the two disagree -- see
## test_a_missing_state_specific_animation_prefers_relaxing_state_over_
## animation, the load-bearing test for this. Season-before-state is
## unambiguous either way and both sources agree (the doc gives an
## explicit reason: "a state carries gameplay meaning ... a season
## carries dressing"), which is why season keeps priority 1 here despite
## the reordering.
##
## **Also NOT implemented**: the doc's own worked-example aside that
## `wooden_club`'s missing `icon` context would fall back to reusing
## `held`'s still frame. That is the OPPOSITE direction from the doc's
## own stated rule 4 ("ground and held reuse the icon by default") and
## does not generalize to any other subject in the doc (campfire's icon
## context is real, independent art) -- treated as a one-off aside about
## a not-yet-authored file, not a second, conflicting context-fallback
## rule, rather than silently implementing an unstated special case.
##
## **Also NOT implemented (left for whoever wires the real loader)**:
## normalizing a non-seasonal context's season to "any" before the search
## runs (a context's own `seasonal: false` declaration should make season
## a no-op axis for it, rather than something a caller must remember to
## pass "any" for themselves).
static func resolve(
	context: String, season: String, state: String, animation: String,
	entry: Dictionary, address_exists: Callable
) -> Dictionary:
	var base_season: String = entry.get("base_season", "any")
	var base_state: String = entry.get("base_state", "")
	var candidates := _ordered_masks()
	for mask in candidates:
		var candidate_season := base_season if mask & 1 else season
		var candidate_state := base_state if mask & 2 else state
		var candidate_context := "icon" if mask & 4 else context
		var candidate_animation := "still" if mask & 8 else animation
		if address_exists.call(candidate_context, candidate_season, candidate_state, candidate_animation):
			return {
				"is_procedural": false,
				"context": candidate_context,
				"season": candidate_season,
				"state": candidate_state,
				"animation": candidate_animation,
			}
	return {
		"is_procedural": true,
		"context": context,
		"season": season,
		"state": state,
		"animation": animation,
	}


## The 16 relaxation bitmasks (bit 0=season, 1=state, 2=context,
## 3=animation), ordered fewest-bits-first, ties broken by mask value
## ascending -- which, for masks built from bit weights 1/2/4/8, is
## exactly "prefer relaxing season, then state, then context, then
## animation" among same-popcount candidates. See this file's own header
## comment for why that specific tie-break order matches the spec doc's
## worked example.
static func _ordered_masks() -> Array:
	var masks: Array = range(16)
	masks.sort_custom(func(a, b):
		var pa := _popcount(a)
		var pb := _popcount(b)
		if pa != pb:
			return pa < pb
		return a < b
	)
	return masks


static func _popcount(mask: int) -> int:
	var count := 0
	while mask > 0:
		count += mask & 1
		mask >>= 1
	return count
