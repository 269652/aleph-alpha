extends RefCounted

## Pure damage-over-time model for a poisonous mushroom (see
## docs/concept/mushrooms.md's "Eating one"). Stacking state itself is
## tracked by the existing generic DebuffStack (apply/advance/stacks_of),
## the same way VenomModel already rides it -- this module only adds "how
## much does N stacks hurt per second", plus a per-REAL-SPECIES severity
## VenomModel didn't need: a snake bite is one snake, but mushroom toxicity
## varies enormously by which real species you ate.

const DEBUFF_ID := "mushroom_toxin"

## Same duration/cap shape as VenomModel -- a real dose lingers and stacks
## rather than an instant burst.
const DURATION_SECONDS := 8.0
const MAX_STACKS := 3
const BASE_DAMAGE_PER_SECOND_PER_STACK := 1.5

## Real: ibotenic-acid/muscimol poisoning (Fly Agaric) carries genuinely
## more physical risk (sedation, GI distress, occasional severe reactions)
## than psilocybin poisoning (Psilocybe), which is primarily perceptual and
## rarely physically dangerous -- not a second copy of the same number.
## Pinned as an ORDERING (fly_agaric > psylo), the same "pinned above/below
## its siblings, not an eyeballed absolute value" idiom AntColony.
## WINDFALL_CONSUMED_CHANCE uses. Neither is anywhere near as dangerous as
## the originally-designed roster's Death Cap (real amatoxin poisoning,
## often fatal) -- this roster genuinely has no "certainly lethal" tier
## (see docs/concept/mushrooms.md's merge note). A non-toxic species (or an
## unrecognized id) does no damage at all.
const _SEVERITY_BY_SPECIES := {
	"fly_agaric": 1.0,
	"psylo": 0.5,
}
const _DEFAULT_SEVERITY := 0.0


static func severity_for(species_id: String) -> float:
	return float(_SEVERITY_BY_SPECIES.get(species_id, _DEFAULT_SEVERITY))


func damage_per_second(stacks: int, species_id: String) -> float:
	return (
		float(clampi(stacks, 0, MAX_STACKS))
		* BASE_DAMAGE_PER_SECOND_PER_STACK
		* severity_for(species_id)
	)
