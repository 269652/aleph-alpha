extends RefCounted

## The flies living on one rotting thing (see docs/concept/flies.md).
##
## The loop: rot draws a fly, the fly lays, the maggots eat the rot, the
## maggots become flies, those flies lay. A pile of rotten apples ends up with
## a swarm that is its OWN offspring, rather than flies teleported in because
## the game decided a swarm was due.
##
## Engine-free: a colony is a list of ages. The renderer asks how many are
## flying and puts that many specks in the air; nothing here knows about nodes.
##
## Every growth path is capped. A breeding population with no ceiling is the
## tree-spread bug again and worse, because flies breed in days rather than
## years -- so the caps are the load-bearing part, not a safety net.

const FlyLifeCycle = preload("res://src/gameplay/fly_life_cycle.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How long an adult lives before dying of old age, measured from hatching.
##
## A colony has to turn over rather than accumulating immortals: without this
## a source would sit permanently at its ceiling, and the swarm would stop
## being a reading of how the rot is doing.
const ADULT_LIFESPAN_SECONDS := FlyLifeCycle.ADULT_AT_SECONDS + SeasonCycle.SECONDS_PER_DAY * 8.0

## How often a mated female lays, once she can.
const LAYING_INTERVAL_SECONDS := SeasonCycle.SECONDS_PER_DAY * 2.0

## Ages of everything living on this source, in seconds since it was laid.
var _ages: Array[float] = []
## How many clutches each adult has laid, and when it last laid.
var _clutches: Array[int] = []
var _since_laid: Array[float] = []
## How many individuals have been replaced by death, for tests and for anyone
## wanting to know whether a colony is turning over.
var _replacements := 0


## Flies arriving from outside and settling on this source. They arrive as
## ADULTS, because a fly that flew here is a fly.
func settle(count: int) -> void:
	for index in count:
		if _ages.size() >= FlyLifeCycle.MAX_PER_SOURCE:
			return
		_ages.append(FlyLifeCycle.ADULT_AT_SECONDS)
		_clutches.append(0)
		_since_laid.append(0.0)


## Ages everything, buries the dead, and lets the mated lay.
##
## `rot_remains` is whether the thing they live on is still there. When it is
## not, nothing more is laid and the colony simply runs out -- flies do not
## outlive what they live on.
func advance(delta_seconds: float, rot_remains: bool) -> void:
	var survivors: Array[float] = []
	var survivor_clutches: Array[int] = []
	var survivor_since: Array[float] = []
	for index in _ages.size():
		var age: float = _ages[index] + delta_seconds
		if age >= ADULT_LIFESPAN_SECONDS:
			_replacements += 1
			continue
		survivors.append(age)
		survivor_clutches.append(_clutches[index])
		survivor_since.append(_since_laid[index] + delta_seconds)
	_ages = survivors
	_clutches = survivor_clutches
	_since_laid = survivor_since

	if not rot_remains:
		return

	# Laying, one female at a time so a colony steps toward its ceiling rather
	# than jumping to it.
	for index in _ages.size():
		if _since_laid[index] < LAYING_INTERVAL_SECONDS:
			continue
		var stage := FlyLifeCycle.stage_at(_ages[index])
		# Every adult that has been around long enough is treated as a mated
		# female. Modelling sexes here would double the population needed for
		# any of it to happen and show the player nothing.
		if not FlyLifeCycle.can_lay(stage, true, _clutches[index]):
			continue
		var laid := FlyLifeCycle.eggs_for_clutch(_ages.size())
		if laid <= 0:
			break
		_clutches[index] += 1
		_since_laid[index] = 0.0
		for egg in laid:
			_ages.append(0.0)
			_clutches.append(0)
			_since_laid.append(0.0)
		break


## How many are flying. Only adults: eggs and maggots are in the fruit.
func adults() -> int:
	var count := 0
	for age in _ages:
		if FlyLifeCycle.flies(FlyLifeCycle.stage_at(age)):
			count += 1
	return count


## How much extra decay this colony's maggots inflict in `delta_seconds`, as a
## fraction of a thing's whole shelf life.
##
## A swarm makes its own food run out. That is what stops one apple supporting
## flies forever, and it is why the maggot is the only stage that eats: a
## heavily-blown windfall goes sooner, which is the feedback that keeps the
## loop bounded from the food side as well as by the ceilings.
const DECAY_PER_MAGGOT_PER_DAY := 0.12


func decay_hastened_by(delta_seconds: float) -> float:
	var days := maxf(delta_seconds, 0.0) / SeasonCycle.SECONDS_PER_DAY
	return float(maggots()) * DECAY_PER_MAGGOT_PER_DAY * days


## How many maggots are eating, which is what actually consumes the rot.
func maggots() -> int:
	var count := 0
	for age in _ages:
		if FlyLifeCycle.eats(FlyLifeCycle.stage_at(age)):
			count += 1
	return count


func total() -> int:
	return _ages.size()


func replacements() -> int:
	return _replacements


## Everything alive here, counted by stage -- for tests and for anything that
## wants to show what is going on inside a windfall.
func stage_counts() -> Dictionary:
	var counts := {
		FlyLifeCycle.STAGE_EGG: 0,
		FlyLifeCycle.STAGE_MAGGOT: 0,
		FlyLifeCycle.STAGE_PUPA: 0,
		FlyLifeCycle.STAGE_ADULT: 0,
	}
	for age in _ages:
		var stage := FlyLifeCycle.stage_at(age)
		counts[stage] = int(counts[stage]) + 1
	return counts
