extends RefCounted

## Seasons arriving GRADUALLY rather than all at once.
##
## A canopy that swaps frames on a single frame boundary reads as a bug: the
## whole forest changes colour between one step and the next. A wood should
## turn over days, branch by branch, and be fully turned by the time the season
## it is turning into actually starts -- so when spring arrives it is already
## saturated rather than beginning to think about it.
##
## Pure and engine-free: this says WHICH two seasons a tree is between and HOW
## FAR along. Blending the art is the renderer's job.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How much of a season is spent turning into the next one.
##
## The last third: a settled middle, then a visible turn. Shorter and the turn
## is a swap with extra steps; much longer and no season is ever simply itself.
const TURN_FRACTION := 0.34

## How many distinct stages the turn is reported in.
##
## Quantised because every distinct value is a whole tree picture that has to
## be composited and cached (see ProceduralTreeSprite). Six reads as gradual --
## a few branches at a time -- while keeping the number of images a wood needs
## affordable, which is the constraint that bit hard when the fast-forward
## first ran.
const TURN_STEPS := 6


## Which seasons this moment is between, and how far along, as
## {from, to, progress}.
##
## A settled season reports itself as both ends with progress 0, so a caller
## can use the same path all year rather than branching on "is it turning".
static func state_at(year_fraction: float) -> Dictionary:
	var count := SeasonCycle.SEASONS.size()
	var span := 1.0 / float(count)
	var position := fposmod(year_fraction, 1.0)
	var index := clampi(int(position * float(count)), 0, count - 1)
	var current: String = SeasonCycle.SEASONS[index]

	var within := (position - float(index) * span) / span
	if within < 1.0 - TURN_FRACTION:
		return {"from": current, "to": current, "progress": 0.0}

	var next: String = SeasonCycle.SEASONS[(index + 1) % count]
	var raw := (within - (1.0 - TURN_FRACTION)) / TURN_FRACTION
	return {"from": current, "to": next, "progress": _quantise(raw)}


## Snapped to TURN_STEPS stages. Rounded UP so the turn reaches a full 1.0
## before the boundary rather than arriving at it still a step short -- the
## whole point is that the new season starts already complete.
static func _quantise(raw: float) -> float:
	var clamped := clampf(raw, 0.0, 1.0)
	return ceilf(clamped * float(TURN_STEPS)) / float(TURN_STEPS)
