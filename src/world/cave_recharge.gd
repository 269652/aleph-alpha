extends RefCounted

## Which of Palmer's five groundwater recharge modes governs a place (see
## docs/concept/underground.md "Palmer: how the water gets in decides what
## the cave looks like").
##
## Palmer 1991 ("Origin and morphology of limestone caves", GSA Bulletin
## 103) found that solutional cave PATTERN is controlled primarily by the
## mode of recharge -- not by rock type, not by depth, not by age. So this
## classifier is where the real causal work happens, and CavePattern is
## only the lookup that follows from it.
##
## Pure and deterministic: every input is a real signal this world already
## computes (a sinking surface channel, an overlying permeable caprock,
## precipitation seasonality, hydrothermal proximity, distance to coast),
## so there is no hash and no seed here at all -- unlike Lithology, nothing
## about recharge is arbitrary.

const MODE_SINKHOLE := "sinkhole"
const MODE_DIFFUSE := "diffuse"
const MODE_FLOODWATER := "floodwater"
const MODE_HYPOGENIC := "hypogenic"
const MODE_MIXING_ZONE := "mixing_zone"

const MODES: Array[String] = [
	MODE_SINKHOLE, MODE_DIFFUSE, MODE_FLOODWATER, MODE_HYPOGENIC, MODE_MIXING_ZONE
]

## How close the rising sulfidic/thermal fluids of the hydrothermal layer
## (see geology.md) have to be, on a [0,1] proximity reading, before they
## become the dominant dissolution driver.
const HYPOGENIC_PROXIMITY_THRESHOLD := 0.5

## How far inland the fresh/salt mixing zone reaches. Real coastal
## carbonate cave systems -- Yucatan's Ox Bel Ha and Sac Actun, and
## flank-margin caves generally -- develop within roughly ten kilometres
## of the coast, not hundreds.
const MIXING_ZONE_COAST_KM := 10.0

## How strong a wet/dry contrast turns ordinary sinkhole recharge into
## episodic floodwater injection. Below this a point input feeds the cave
## steadily (branchwork); above it the same input arrives as high-energy
## floods that force water through every available opening at once, which
## is what braids an anastomotic maze rather than a dendritic network.
const FLOODWATER_SEASONALITY_THRESHOLD := 0.5


## The dominant recharge mode here.
##
## `has_sinking_channel`: a real surface watercourse sinking into the rock
## (a point input). `has_permeable_caprock`: insoluble but permeable rock
## overlying the soluble unit, spreading recharge out. `seasonality` and
## `hydrothermal_proximity`: [0,1] readings. `coast_distance_km`: real km.
##
## Precedence is causal, not arbitrary: acid rising from below dissolves
## whether or not anything is happening at the surface, so it wins first;
## a coastal mixing zone likewise dissolves independently of surface
## recharge; only then does it matter how surface water gets in.
func mode_at(
	has_sinking_channel: bool,
	has_permeable_caprock: bool,
	seasonality: float,
	hydrothermal_proximity: float,
	coast_distance_km: float
) -> String:
	if hydrothermal_proximity > HYPOGENIC_PROXIMITY_THRESHOLD:
		return MODE_HYPOGENIC
	if coast_distance_km < MIXING_ZONE_COAST_KM:
		return MODE_MIXING_ZONE
	if has_sinking_channel:
		# Floodwater recharge is episodic injection of ALLOGENIC discharge
		# -- a real surface stream in flood, forcing water through every
		# available opening at once. It needs both the point input and the
		# wet/dry contrast; either alone is ordinary sinkhole recharge.
		if seasonality > FLOODWATER_SEASONALITY_THRESHOLD:
			return MODE_FLOODWATER
		return MODE_SINKHOLE
	if has_permeable_caprock:
		# Percolation spread out across an insoluble but permeable cover --
		# sandstone over limestone, as in the Black Hills maze caves and
		# Mammoth Cave's own maze sections. This is the only genuinely
		# diffuse case.
		return MODE_DIFFUSE
	# Bare karst, no stream. It still takes autogenic recharge -- there is
	# no "this limestone never sees water" case -- but its own EPIKARST
	# concentrates that diffuse rain into discrete inputs at shaft tops, so
	# what reaches the cave is a point input. This is also why branchwork
	# dominates Palmer's survey: the commonest karst setting of all feeds
	# it.
	return MODE_SINKHOLE
