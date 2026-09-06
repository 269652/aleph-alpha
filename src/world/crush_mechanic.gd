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
