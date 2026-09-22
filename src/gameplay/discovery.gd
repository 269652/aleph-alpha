extends RefCounted
## What going out there records, pays and says (docs/concept/discovery.md).
##
## Measured before this module existed: `EarthChunkManager.mark_chunk_explored`
## and `ExploredTiles` are real and tested, and `MapProjection.landmarks_
## visible_on_map` and `/map` really read them -- but a repo-wide grep for
## callers outside the manager and its own tests found exactly ONE:
## `Player._cast_reveal`, the `reveal` spell atom. Walking across a continent
## marked nothing, so the map stayed empty for every player who never wove
## that spell. docs/concept/wayfinding.md names this as its own open gap.
##
## Two more measurements from the same pass: distance from spawn appeared in
## no XP formula anywhere (all three `gain_experience` callers are a kill, a
## fruit harvest and a village sale), so the far country was strictly more
## dangerous and strictly no more rewarding -- the ring gradient was a pure
## tax. And `JourneyRing.crossing_between` was written for a card that did
## not exist.
##
## This module is the rule that connects them, and nothing else. It decides
## the whole step from three plain numbers -- where you were, where you are,
## and whether this ground is new -- and hands back what happened. The
## caller performs it: World marks the manager's own ExploredTiles, pays the
## player, floats the receipt and raises the card.
##
## Deliberately, like `JourneyRing` itself, it cannot say no. There is no
## can_enter here and test_nothing_here_can_refuse_entry reads this script's
## own method list to keep it that way. The card is a warning, never a fence.
##
## Pure: RefCounted, static functions, no world, no player, no scene tree,
## no clock.

const JourneyRing = preload("res://src/gameplay/journey_ring.gd")
const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")

## A chunk is CHUNK_SIZE tiles square. Restated rather than preloading
## EarthChunkManager -- a pure gameplay rule must not drag the whole
## streaming layer into every test that touches a number, the same reason
## `JourneyRing` and `SprintCost` give for restating theirs -- and held to
## `EarthChunkManager.CHUNK_SIZE` by test.
const CHUNK_SIZE_TILES := 32

## "This character has not moved yet", for `report_for`'s first argument. A
## first frame is not a crossing: the arrival briefing owns that moment
## (docs/concept/arrival.md), not a card fired at the start of every session.
const NO_PREVIOUS_DISTANCE := -1

## What first setting foot in the mildest ground is worth: read from
## `EcologicalLiteracy`'s own baseline rather than retyped, so "engaging a
## real system at all" is ONE number across the whole XP economy.
const DISCOVERY_XP_BASE := EcologicalLiteracy.HARVEST_XP_BASE

## `Player.XP_PER_KILL`, restated for the same purity reason CHUNK_SIZE_TILES
## is (scenes/player.gd is a Node2D scene script) and held to it by test.
const XP_PER_KILL := 6

## The ONE tuned number here, and the anchor everything else is derived
## from: what a newly-walked chunk of the hardest ground on the planet is
## worth, counted in level-1 kills. There is no real-world anchor for a
## game-balance XP figure -- it is the same category as `XP_PER_KILL` and
## `HEALTH_PER_LEVEL` themselves -- so the deliberate anchor is internal
## consistency with the economy that already exists, exactly as
## `EcologicalLiteracy` states for its own numbers. Two kills: the far
## country is the only ground where bear, lion and venomous snake exist at
## all, and walking a chunk of it and living is worth about what killing
## twice is.
const FAR_COUNTRY_KILLS := 2

## The player-facing name for ground nobody has stood on before. On the
## floating receipt rather than in a banner, because at walking speed a
## chunk edge arrives every ~13 s and a banner at that rate teaches a player
## to stop reading banners (docs/concept/feedback.md).
const NEW_GROUND_LABEL := "New ground"



## The chunk a global tile sits in. `floori` rather than integer division:
## ground west and north of the origin is ordinary ground, and truncation
## would fold tile -1 into chunk 0 and make two different places the same
## place on the map.
static func chunk_of(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / float(CHUNK_SIZE_TILES)),
		floori(float(tile.y) / float(CHUNK_SIZE_TILES))
	)


## How many things the outermost ring expects a traveller to be carrying --
## the denominator of the derivation below, read off the real table so a
## retune of the packing list moves the payoff with it.
static func max_demand_count() -> int:
	return int(JourneyRing.RINGS[JourneyRing.RINGS.size() - 1]["demands"].size())


## What each item on a ring's packing list adds to a newly-walked chunk.
## Derived from the anchor, never typed in; the division is exact for the
## real table and test_the_per_demand_step_divides_the_anchor_exactly is
## what keeps it exact.
static func xp_per_demand() -> int:
	var demands := max_demand_count()
	if demands <= 0:
		return 0
	return (XP_PER_KILL * FAR_COUNTRY_KILLS - DISCOVERY_XP_BASE) / demands


## What first setting foot in a chunk this far from spawn is worth.
##
## The price is the ring's OWN declared packing list (`JourneyRing.demands_at`
## -- already cumulative outward, already test-pinned), so the payoff scale
## is exactly the risk scale the rings already declare and there is no second
## difficulty model anywhere in this file.
static func xp_for_distance(distance: int) -> int:
	return DISCOVERY_XP_BASE + xp_per_demand() * JourneyRing.demands_at(distance).size()


## A `JourneyRing` demand id as a player reads it ("a_weapon_that_kills" ->
## "a weapon that kills") -- the same snake-case-to-words rule
## `ArrivalBriefing._spoken` and `ErrandDelivery._item_word` apply, and for
## the same reason: an id must never reach a player.
static func demand_phrase(demand_id: String) -> String:
	return demand_id.strip_edges().replace("_", " ")


## "Carry: provisions, a weapon that kills." -- or nothing at all for a ring
## that demands nothing, rather than an empty "Carry: ."
static func packing_line(ring: Dictionary) -> String:
	var demands: Variant = ring.get("demands", [])
	if not (demands is Array) or demands.is_empty():
		return ""
	var parts: Array[String] = []
	for demand in demands:
		var phrase := demand_phrase(String(demand))
		if phrase != "":
			parts.append(phrase)
	if parts.is_empty():
		return ""
	return "Carry: %s." % ", ".join(parts)


## The three lines a crossing reads as: where you now are, what is new and
## lethal about it, and what it expects you to be carrying.
##
## Outward is a warning and inward is relief, which is a distinction the
## player actually feels -- the same ring, crossed the other way, is the
## moment the run home ends.
static func crossing_card(ring: Dictionary, outward: bool) -> String:
	var name := _ring_name(ring)
	if name == "":
		return ""
	var lines: Array[String] = []
	lines.append(("You are entering %s." if outward else "You are back in %s.") % name)
	var description := String(ring.get("description", "")).strip_edges()
	if description != "":
		lines.append(description)
	var carry := packing_line(ring)
	if carry != "":
		lines.append(carry)
	return "\n".join(lines)


## The ring's name as it reads INSIDE a sentence: "the Marches", never
## "The Marches". Crude, and correct for every name the real table holds --
## and a line that reads wrong is exactly what a first-time player notices.
static func _ring_name(ring: Dictionary) -> String:
	var name := String(ring.get("name", "")).strip_edges()
	if name.begins_with("The "):
		return "the " + name.substr(4)
	return name


## The whole step, decided: what this footfall is worth, whether a boundary
## is behind it, and what to say.
##
## `is_new_ground` is the caller's own `ExploredTiles.mark_visited` return
## value -- idempotent and true only on the first mark -- which is what makes
## the payoff one-time per chunk and unfarmable by pacing over a boundary.
static func report_for(from_distance: int, to_distance: int, is_new_ground: bool) -> Dictionary:
	var xp := xp_for_distance(to_distance) if is_new_ground else 0
	var crossing: Dictionary = {}
	var outward := false
	if from_distance >= 0:
		crossing = JourneyRing.crossing_between(from_distance, to_distance)
		outward = (
			JourneyRing.ring_index_at(to_distance) > JourneyRing.ring_index_at(from_distance)
		)
	return {
		"xp": xp,
		"crossing": crossing,
		"outward": outward,
		"message": crossing_card(crossing, outward),
		"float_text": ("%s  +%d XP" % [NEW_GROUND_LABEL, xp]) if xp > 0 else "",
	}


## The one reading of the journey that never goes away: where you are, how
## far out that is, and how much ground you have recorded.
##
## Measured by instrumenting a `--solo` launch, after the report *"no card or
## XP visible"*: the wiring was fine -- frame one paid its 2 XP and produced
## the float -- but everything this module fed was TRANSIENT. The receipt
## lasts `Answerback.DELIBERATE_INTERVAL_SECONDS` (~1 s) and only re-fires
## after a whole chunk of walking (512 px, ~13 s in a straight line at
## `Player.BASE_SPEED`); the crossing card needs six chunks, over a minute
## one way. A player who wanders inside their spawn chunk meets the whole
## journey layer once, for one second, during the loading fade.
##
## So it gets a permanent surface. This is the "HUD place chip naming the
## ring" docs/concept/journey_rings.md has listed as unbuilt since the rings
## shipped, and it is what makes walking legible: the known count ticks up
## every chunk, which is the visible proof that ground is being recorded.
##
## The distance is the PLAY scale (`JourneyRing.walking_metres_from_spawn`),
## never the map's kilometres -- so "411 m out" and `SprintCost`'s "one burst
## carries 80 m" are numbers about the same world. Standing at home reports
## no distance at all rather than "0 m", the same rule
## `ArrivalBriefing.distance_phrase` already keeps.
static func place_chip(distance: int, explored_count: int) -> String:
	var ring := JourneyRing.ring_at(distance)
	var parts: Array[String] = [String(ring.get("name", ""))]
	if distance > 0:
		parts.append("%d m out" % int(roundf(JourneyRing.walking_metres_from_spawn(distance))))
	else:
		parts.append("home")
	parts.append("%d known" % maxi(0, explored_count))
	return "  -  ".join(parts)
