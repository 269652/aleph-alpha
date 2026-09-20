extends RefCounted

## The underground's energy budget, and the difficulty curve that falls
## out of it (see docs/concept/underground.md "Chemosynthesis: the second
## biosphere").
##
## Depth is deliberately NOT a stat multiplier here. The underground food
## web runs on chemical energy instead of sunlight -- chemolithoautotrophy,
## carbon fixed by oxidising sulfide, hydrogen, iron, ammonium or methane
## -- and three real consequences follow from that energy being scarce and
## steeply zoned around wherever reduced fluids rise:
##
##   few        population density follows energy, and away from a seep
##              there is almost none of it
##   old        scarcity means a low metabolic rate, which buys longevity;
##              the olm is the anchor, and age is exactly what
##              worldbosses.md's promotion threshold already reads
##   enormous   but only where endosymbiosis is involved, because an
##              animal farming its own producers is not limited by what
##              the surrounding rock supplies at all
##
## Real ecosystems behind each number: Movile Cave (sealed ~5.5Ma, ~48
## species on sulfur- and methane-oxidising mats), Frasassi and Cueva de
## Villa Luz (snottite biofilms at pH 0-1), Candidatus Desulforudis
## audaxviator (2.8km down in Mponeng, living on radiolytic hydrogen), and
## the vent fauna -- Riftia, Bathymodiolus, Kiwa -- that carry their
## producers inside them.

## Real global mean terrestrial net primary production, the yardstick
## everything here is read against.
const SURFACE_NPP_G_C_PER_M2_YR := 426.0

## Right at the fluid, a seep or vent community reaches biomass densities
## comparable to the most productive ecosystems on Earth. Taken as equal
## to a good surface ecosystem rather than above it -- the conservative
## reading of "comparable to a rainforest".
const SEEP_PEAK_NPP_G_C_PER_M2_YR := SURFACE_NPP_G_C_PER_M2_YR

## Rock with no reduced fluid reaching it is not merely dimmer than the
## surface, it is starved: the deep subsurface biosphere turns over on
## century-to-millennium timescales, roughly three orders of magnitude
## below surface productivity. Never zero, because radiolytic hydrogen is
## produced everywhere there is water and rock.
const BACKGROUND_NPP_G_C_PER_M2_YR := 0.4

## Real vent and seep communities are tightly zoned around the fluid, on a
## scale of metres to tens of metres -- which is what makes the deep
## underground "almost nothing, punctuated by somewhere rich and
## dangerous" rather than uniformly poor.
const SEEP_EFOLD_M := 12.0

## Proteus anguinus, the olm: estimated maximum lifespan past 100 years,
## average adult lifespan around 68 (Voituron et al., 2011, Biology
## Letters). Europe's blind cave salamander is the canonical demonstration
## that darkness and scarcity buy longevity.
const OLM_MAX_LIFESPAN_YEARS := 100.0

## How steeply longevity trades against energy supply.
##
## Grounded in a real comparison pair rather than chosen: the olm lives
## past 100 years where a comparable surface salamander manages 20-25, a
## ratio of about 4-5x across a productivity ratio of about 1000x, which
## gives ln(5)/ln(1000) ~ 0.23. That it lands on the quarter-power
## exponent governing metabolic allometry generally is a helpful
## coincidence, not the derivation. The model's own check: fed
## surface-equivalent energy it returns ~17 years, which is a surface
## salamander's lifespan -- so the curve reproduces the other end of the
## pair it was not fitted to.
const LONGEVITY_ENERGY_EXPONENT := 0.25

## Metabolic rate scales with mass^0.75 (Kleiber's law), so the largest
## mass an energy supply can sustain scales with that supply^(1/0.75).
const KLEIBER_EXPONENT := 0.75


## Chemosynthetic primary production this far (in metres) from the nearest
## rising reduced fluid. Peaks at the seep, decays exponentially with
## distance, and floors at the starved background rather than at zero.
func ambient_energy_at(distance_from_seep_m: float) -> float:
	var distance := maxf(distance_from_seep_m, 0.0)
	var above_background := SEEP_PEAK_NPP_G_C_PER_M2_YR - BACKGROUND_NPP_G_C_PER_M2_YR
	return BACKGROUND_NPP_G_C_PER_M2_YR + above_background * exp(-distance / SEEP_EFOLD_M)


## How densely populated this energy supply can be, relative to a good
## surface ecosystem. This is the "few" in few/old/enormous: away from a
## seep it is a fraction of a percent, so the player meets individuals,
## never a swarm.
func population_density_factor(npp_g_c_per_m2_yr: float) -> float:
	if npp_g_c_per_m2_yr <= 0.0:
		return 0.0
	return npp_g_c_per_m2_yr / SURFACE_NPP_G_C_PER_M2_YR


## Expected lifespan at this energy supply. Falls as energy rises, because
## energy is what buys metabolic speed and speed is what costs longevity
## -- the textbook K-strategy of cave fauna: slow growth, delayed
## maturity, few large eggs, long life.
##
## Honest limitation: deep-sea seep tubeworms (Lamellibrachia lives 170-250
## years at high local energy) are a real exception this relation does not
## capture. It is grounded in the cave-fauna pattern, which is the one
## this doc's biosphere is actually built on.
func longevity_years(npp_g_c_per_m2_yr: float) -> float:
	if npp_g_c_per_m2_yr <= BACKGROUND_NPP_G_C_PER_M2_YR:
		return OLM_MAX_LIFESPAN_YEARS
	var scarcity := BACKGROUND_NPP_G_C_PER_M2_YR / npp_g_c_per_m2_yr
	return OLM_MAX_LIFESPAN_YEARS * pow(scarcity, LONGEVITY_ENERGY_EXPONENT)


## The largest body mass this energy supply can sustain, relative to what
## a good surface ecosystem sustains. Kleiber's law inverted: metabolic
## demand scales with mass^0.75, so attainable mass scales with supply
## raised to 1/0.75.
func attainable_body_mass_factor(npp_g_c_per_m2_yr: float) -> float:
	if npp_g_c_per_m2_yr <= 0.0:
		return 0.0
	var supply_ratio := npp_g_c_per_m2_yr / SURFACE_NPP_G_C_PER_M2_YR
	return pow(supply_ratio, 1.0 / KLEIBER_EXPONENT)


## The energy actually available to an animal carrying endosymbiotic
## chemoautotrophs, given what the surrounding rock supplies.
##
## This is the ceiling break, and it is the whole reason anything large
## can exist somewhere this energy-poor. Riftia has no gut at all;
## Bathymodiolus and Kiwa farm their producers too. Such an animal is not
## limited by ambient supply, so it reads a seep's worth of energy
## wherever it happens to be -- which is what makes an apex down here, in
## place of a stat budget.
func symbiotic_effective_energy(ambient_npp_g_c_per_m2_yr: float) -> float:
	return maxf(ambient_npp_g_c_per_m2_yr, SEEP_PEAK_NPP_G_C_PER_M2_YR)
