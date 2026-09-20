extends RefCounted
## The three facts a new character needs in their first ten seconds
## (docs/concept/arrival.md): where you are, what is near you, and one thing
## to do.
##
## Measured in the 2026-09-20 diagnosis pass: a repo-wide grep for
## tutorial/onboarding/welcome/objective across scenes/ and src/ hits a
## loading-screen joke and one NPC greeting. There is no first line of text
## in this game -- while underneath it there is a real river with a real
## name, a real season, real settlements, and real households really short of
## real recipe inputs. This module says three of those things out loud and
## nothing else.
##
## Pure, and a function of facts handed in: no world, no player, no market,
## no scene tree, in the spirit of errand_delivery.gd (whose own phrasing it
## follows) and journey_ring.gd. Every line is read off real state or is not
## printed -- no village nearby means no bearing line, never "null" and never
## a placeholder village.

const Compass = preload("res://src/gameplay/compass.gd")

## The eight points of the compass rose as words, in Compass's own order:
## index = bearing / Compass.ROUGH_STEP_DEGREES, clockwise from north, and
## north is this world's +Y (a documented convention, see compass.gd).
const POINTS: Array[String] = [
	"north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"
]

## The surface map's scale: Lithology.KM_PER_TILE, itself pinned to
## EarthChunkGenerator.TILES_PER_DEGREE. Restated rather than preloaded for
## the reason JourneyRing gives for restating the same figure -- a small pure
## module should not pull in the geology layer to multiply by one -- and
## pinned against both by test_the_tile_is_the_surface_maps_kilometre.
##
## (The other scale, CaveZonation's 1.426 m per tile, is the UNDERGROUND's
## play scale and is not this. A village eleven tiles away is an eleven
## kilometre walk, which is why the briefing speaks in kilometres.)
const KM_PER_TILE := 1.0
const METRES_PER_KM := 1000.0
const METRES_PER_TILE := KM_PER_TILE * METRES_PER_KM

## Under half a tile there is no kilometre to speak of yet.
const NEAR_KM := KM_PER_TILE / 2.0

## Below this, "about a kilometre" is what a person says; above it, the
## rounded number is. The upper edge of what rounds to 1.
const SINGLE_KM_CEILING := KM_PER_TILE * 1.5

## The unit a distance nobody has walked is spoken in. Five kilometres is
## the step; what makes it accountable rather than taste is MAX_RELATIVE_
## ERROR below, which the threshold is derived from.
const COARSE_STEP_KM := 5.0

## The most a spoken distance may be wrong by, as a fraction of itself. A
## quarter: "about 45 km" for a 43 km walk is a fair thing to say, "about
## 5 km" for a 7 km walk is not.
const MAX_RELATIVE_ERROR := 0.25

## Where rounding to the nearest COARSE_STEP_KM becomes honest: the worst
## error of that rounding is half a step, and half a step is MAX_RELATIVE_
## ERROR of exactly this distance. Below it the briefing names the kilometre
## instead. Derived, and swept by test_a_far_walk_is_never_claimed_to_the_
## kilometre.
const COARSE_ABOVE_KM := (COARSE_STEP_KM / 2.0) / MAX_RELATIVE_ERROR


## The bearing from one tile to another as a word -- Compass's own rough
## (45-degree snap) reading, named rather than re-derived, so the briefing
## can never be a second opinion about which way north is.
##
## The empty string for a target on the player's own tile: there is no
## direction to where you already stand, and an arbitrary "north" would be
## the kind of invented fact docs/concept/wayfinding.md's first pillar
## forbids.
static func bearing_word(from_position: Vector2, to_position: Vector2) -> String:
	if from_position.is_equal_approx(to_position):
		return ""
	return word_for_degrees(Compass.bearing_degrees(from_position, to_position))


## A bearing in degrees as one of the eight points. Boundaries fall halfway
## between the points (22.5, 67.5, ...) and round OUTWARD, because that is
## what Compass.rough_reading's roundf does with a half.
static func word_for_degrees(bearing_degrees: float) -> String:
	var snapped := Compass.rough_reading(bearing_degrees)
	var index := int(snapped / Compass.ROUGH_STEP_DEGREES) % POINTS.size()
	return POINTS[index]


## A tile distance as a person would say it. Nothing at all for a distance
## of zero -- the caller has no business printing "0 km away".
static func distance_phrase(tiles: float) -> String:
	if tiles <= 0.0:
		return ""
	var km := tiles * KM_PER_TILE
	if km < NEAR_KM:
		return "a few hundred metres"
	if km < SINGLE_KM_CEILING:
		return "about a kilometre"
	if km < COARSE_ABOVE_KM:
		return "about %d km" % int(roundf(km))
	return "about %d km" % int(roundf(km / COARSE_STEP_KM) * COARSE_STEP_KM)


## The one errand a newcomer is told about, from the whole array
## Quest.production_shortfall_quests_for returns (its entries unchanged:
## settlement_id, household_id, occupation, recipe_id, missing). {} when
## nothing is really short.
##
## Salience for a NEWCOMER is not the biggest crisis. It is the FEWEST total
## units missing -- the one errand a player with an axe and no reputation
## can actually finish today. A shortage of nine rock and four stick is a
## more serious shortage and a worse first thread of action; the friend's
## complaint was that nothing said what to do, not that nothing said what
## was worst.
##
## Ties break on settlement, household and recipe id, so the same world
## always gives the same first errand rather than whichever household a
## Dictionary happened to iterate first (its order is not a contract --
## quest.gd walks `household_occupations` directly).
static func salient_errand(errands: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for entry in errands:
		if not (entry is Dictionary):
			continue
		var total := _total_need(entry)
		if total <= 0:
			continue
		var key: Array = [
			total,
			String(entry.get("settlement_id", "")),
			String(entry.get("household_id", "")),
			String(entry.get("recipe_id", "")),
		]
		if best.is_empty() or _key_before(key, best_key):
			best = entry
			best_key = key
	return best


## The whole briefing: {place_line, bearing_line, errand_line}, every one of
## them a finished sentence or the empty string. Never a fragment, never an
## id, never "null" -- a missing fact is a line the caller does not draw.
##
## `facts` is a plain dictionary the caller assembles from state it already
## has: river_name (SpawnRiverPicker's own pick), season (SeasonCycle),
## player_tile / settlement_tile (real tile coordinates), settlement_name,
## and errands (Quest.production_shortfall_quests_for's array, unchanged).
static func briefing_for(facts: Dictionary) -> Dictionary:
	return {
		"place_line": _place_line(facts),
		"bearing_line": _bearing_line(facts),
		"errand_line": _errand_line(facts),
	}


## "You are on the Loire, in spring." -- and still a sentence when only one
## of the two is known.
static func _place_line(facts: Dictionary) -> String:
	var river := _spoken(facts.get("river_name", ""))
	var season := _spoken(facts.get("season", ""))
	if river != "" and season != "":
		return "You are on the %s, in %s." % [river, season]
	if river != "":
		return "You are on the %s." % river
	if season != "":
		return "It is %s." % season
	return ""


## "Aubance lies about 12 km northeast." An unnamed settlement is still worth
## the line -- the direction is the useful half, and "a village" is true.
static func _bearing_line(facts: Dictionary) -> String:
	var from_tile: Variant = _tile(facts, "player_tile")
	var to_tile: Variant = _tile(facts, "settlement_tile")
	if from_tile == null or to_tile == null:
		return ""
	var word := bearing_word(from_tile, to_tile)
	var phrase := distance_phrase(from_tile.distance_to(to_tile))
	if word == "" or phrase == "":
		return ""
	var name := _spoken(facts.get("settlement_name", ""))
	if name == "":
		name = "A village"
	return "%s lies %s %s." % [name, phrase, word]


## "In Aubance, a potter needs 3 clay." -- the count first and the item ids
## spoken as words, exactly as ErrandDelivery phrases the same shortfall at
## the villager's door, so the briefing and the give button are talking
## about one thing.
static func _errand_line(facts: Dictionary) -> String:
	var errand := salient_errand(facts.get("errands", []))
	if errand.is_empty():
		return ""
	var needed := _needed_phrase(errand.get("missing", []))
	if needed == "":
		return ""
	var occupation := _spoken(errand.get("occupation", ""))
	var who := "Someone"
	if occupation != "":
		who = "%s %s" % [_article(occupation), occupation]
	var place := _spoken(errand.get("settlement_name", facts.get("settlement_name", "")))
	if place != "":
		return "In %s, %s needs %s." % [place, who.to_lower(), needed]
	return "%s needs %s." % [_capitalized(who), needed]


## "3 rock" / "3 rock and 1 wood" / "3 rock, 1 wood and 2 clay" -- the same
## shape and the same order (the recipe's own input order, which `missing`
## preserves) as ErrandDelivery's phrasing. Entries needing nothing are
## dropped rather than printed as a zero.
static func _needed_phrase(missing: Variant) -> String:
	if not (missing is Array):
		return ""
	var parts: Array[String] = []
	for entry in missing:
		if not (entry is Dictionary):
			continue
		var need := int(entry.get("need", 0))
		var item := _spoken(entry.get("item_id", ""))
		if need > 0 and item != "":
			parts.append("%d %s" % [need, item])
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]


## Total units a shortfall entry is short of, across every missing input --
## the salience measure, and also the emptiness test (a shortfall of nothing
## is not a shortfall).
static func _total_need(entry: Dictionary) -> int:
	var missing: Variant = entry.get("missing", [])
	if not (missing is Array):
		return 0
	var total := 0
	for item in missing:
		if item is Dictionary:
			total += maxi(0, int(item.get("need", 0)))
	return total


## Lexicographic order over [total, settlement_id, household_id, recipe_id].
## Spelled out rather than relying on Array comparison, so the tie-break rule
## is visible where it is decided.
static func _key_before(key: Array, other: Array) -> bool:
	for index in key.size():
		if key[index] == other[index]:
			continue
		return key[index] < other[index]
	return false


## Anything a player reads, as a player would read it: whitespace trimmed and
## snake_case ids spoken as words ("plant_fibre" -> "plant fibre"), the same
## rule ErrandDelivery._item_word applies at the villager's door.
## Deliberately NOT an ItemCatalog lookup -- this module stays pure, and a
## shortfall names recipe inputs that are catalog ids by construction.
static func _spoken(value: Variant) -> String:
	if value == null:
		return ""
	return String(value).strip_edges().replace("_", " ")


## "a potter" / "an innkeeper". Crude but correct for every occupation
## NpcIdentity.OCCUPATIONS holds, and a line that reads wrong in the first
## ten seconds is exactly the kind of thing a first-time player notices.
static func _article(word: String) -> String:
	if word == "":
		return "a"
	if "aeiou".contains(word.substr(0, 1).to_lower()):
		return "an"
	return "a"


static func _capitalized(text: String) -> String:
	if text == "":
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1)


## A tile coordinate from the facts, accepting either Vector2 or Vector2i
## (the world holds player positions as one and tiles as the other), and null
## when the fact simply is not there -- which is what makes the bearing line
## optional rather than a "(0, 0)" that would point the player at the
## Atlantic.
static func _tile(facts: Dictionary, key: String) -> Variant:
	var value: Variant = facts.get(key)
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	return null
