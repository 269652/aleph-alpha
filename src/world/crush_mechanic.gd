extends RefCounted

## Physics-based "crushed underfoot" check (see docs/concept/soil_fauna.md
## "Crushed underfoot: weight-emergent worm mortality" and its "Generalized
## to caterpillars too" follow-up) -- ONE shared momentum rule for every
## soft-bodied creature small enough to be at risk underfoot at all (today:
## worms via EarthwormPatch.crush, caterpillars via EarthChunkManager.
## crush_caterpillars_near), not a rule each victim duplicates on its own.
## Moved out of EarthwormPatch once a second victim needed the identical
## physics: which creature is doing the crushing (player or any
## CreatureMarker, via CreatureMass.mass_kg_for) and which is being
## crushed both plug into this single check, so a third crushable creature
## needs no new rule of its own, only detection wiring.
##
## Generalized again (2026-09-19, see that doc's own "Generalized to ANY
## animal") to real animals -- a frog underfoot, a mouse under a horse --
## which need ONE more term than a worm does, and take it from an
## anatomical fraction that already exists rather than a new tuned
## number: see crushes_underfoot.

const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")

## Momentum here is a full body's weight settling through one foot at
## ordinary walking pace (CreatureMass.mass_kg_for(species) *
## PebbleDispersion.FOOTSTEP_SPEED_MPS) -- deliberately the CREATURE'S OWN
## FULL mass, not PebbleDispersion's own foot-mass FRACTION: kicking a
## pebble aside in passing is a glancing, foot-only contact, but standing
## weight settling onto something underfoot transmits close to the whole
## body's own mass through that one point of contact, a genuinely
## different physical situation. Calibrated at the soft-invertebrate
## scale, not combat scale (see ImpactResolver.T_CRUSH's own doc comment
## on why that number belongs to an unrelated scale entirely --
## thrown-rock-vs-creature combat, not "anything at all stepping near
## something this small"). Pinned so a mouse/squirrel's own momentum falls
## under it and a deer/boar/horse/player's own falls over it (see
## test_is_crushed_by_spares_small_creatures_and_kills_under_large_ones)
## -- the real boundary this whole mechanic exists to draw.
const CRUSH_MOMENTUM_THRESHOLD_KG_M_S := 5.0


## Whether `momentum_kg_m_s` of downward force is enough to crush something
## at this scale -- mirrors ImpactResolver.resolve_impact's own
## `momentum >= threshold` shape exactly, kept separate since that
## resolver's own thresholds are combat-scaled (see
## CRUSH_MOMENTUM_THRESHOLD_KG_M_S's own doc comment).
static func is_crushed_by(momentum_kg_m_s: float) -> bool:
	return momentum_kg_m_s >= CRUSH_MOMENTUM_THRESHOLD_KG_M_S


## One foot's own real mass for a body of `stepper_mass_kg` -- PebbleDispersion.
## FOOT_MASS_FRACTION's already-cited anthropometric figure (the foot segment
## alone is roughly 1.4% of total body mass) applied to THIS stepper rather
## than to PebbleDispersion's own fixed human reference body, so a horse has a
## horse's foot and a mouse a mouse's.
static func foot_mass_kg(stepper_mass_kg: float) -> float:
	return stepper_mass_kg * PebbleDispersion.FOOT_MASS_FRACTION


## Whether a creature of `stepper_mass_kg` crushes an ANIMAL of
## `victim_mass_kg` by putting a foot on it (see docs/concept/soil_fauna.md
## "Generalized to ANY animal": "Stepping on a frog doesn't kill it?
## Shouldn't this work out of the box for ANY animal when enough pressure is
## put on it? A boar walking over a frog should kill it as well").
##
## is_crushed_by alone cannot answer this. It asks only "is the stepper heavy
## enough to crush anything at all", which is the WHOLE question for a worm --
## anything over that threshold flattens a worm -- and the wrong question on
## its own for an animal: a boar clears it, a deer is also an animal, and a
## boar does not crush a deer by stepping on it.
##
## So an animal victim needs a second term, and it is DERIVED, not picked:
## an animal goes under a foot rather than being stepped on when it weighs
## less than that foot does. Physically that is exactly the boundary -- if a
## whole body is lighter than the foot coming down, the foot does not deflect
## around it and the stepper's full weight settles through a contact patch
## larger than the victim. Above it, the victim is something the stepper
## stumbles ON rather than through.
##
## The two terms compose and neither is redundant: the momentum gate rules
## out steppers too light to crush anything (a mouse crushes no ant, even
## though an ant is lighter than a mouse's foot), and the foot-mass term
## rules out victims too heavy to go under a foot (a horse crushes no wolf,
## even though a horse crushes worms all day). It also falls out that nothing
## crushes something its own size, which is what stops a herd flattening
## itself.
static func crushes_underfoot(stepper_mass_kg: float, victim_mass_kg: float) -> bool:
	if not is_crushed_by(stepper_mass_kg * PebbleDispersion.FOOTSTEP_SPEED_MPS):
		return false
	return victim_mass_kg <= foot_mass_kg(stepper_mass_kg)
