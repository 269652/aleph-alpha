extends RefCounted

## "A found ancient terminal (Zork homage, not reproduction)"
## (docs/concept/easter_eggs.md): interacting with a specific, out-of-the-way
## ruin drops the player into a few lines of ORIGINAL old-school parser-
## style prose before returning them to normal play -- "evoking the FEEL of
## a 1980 text adventure, not lifting from one" (the doc's own words). Zork's
## actual prose is Infocom/Activision's copyrighted text (pillar 4, "homage
## over reproduction") -- TERMINAL_LINES below is fully original writing,
## enforced by test_ancient_terminal.gd's own "does not quote Zork's own
## famous text" check rather than left as an unverified comment, the same
## discipline test_wargames_response.gd already applies to the WarGames egg.
##
## Location: a real-world coordinate (Cambridge, Massachusetts -- home of
## MIT, where Zork itself was actually written on a PDP-10 in 1977-79),
## reusing GeoCoordinates' reverse lookup + radius exactly like every other
## real-coordinate cameo in this project (RushAmbientCue/EasterEggSightings)
## -- never named or hinted at in-game, the same "quiet, factual pick, never
## shown to the player" register RushAmbientCue's own doc comment already
## sets for its own real-world location choice.
##
## Unlike every proximity-only cameo elsewhere in this project family
## (Rush/Mothman/etc., which fire on approach or a rarity roll alone), this
## one needs a deliberate ACTION at the location -- "interacting with" per
## the doc, not just walking near -- so scenes/world.gd (see
## _check_ancient_terminal) gates this on the player's own "talk" input, the
## same generic interact verb villager conversations already use (Player.
## _talk_step/TALK_RADIUS), rather than firing automatically like Rush does.
## Deliberately NO floating interaction prompt is shown first (unlike a real
## villager) -- a "Talk (G)" label hovering over an otherwise-unremarkable
## ruin would itself be a hint, contradicting pillar 3 ("no hint system
## pointing at these -- discovery is the reward").
##
## "Found" state: has_been_found()/mark_found() are a clean, testable
## boolean signal for a later system (docs/concept/easter_eggs.md's "Three
## Fragments" hunt) to check "has the player found the Zork terminal"
## against. This module only exposes that signal -- it does not decide what
## a later system does with it (no fragment item, no bonus trigger here;
## see scenes/world.gd's own forwarding getter, has_found_ancient_terminal).

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

const LATITUDE := 42.3736
const LONGITUDE := -71.1097
## Deliberately small, matching every other pinned-to-a-point cameo's own
## "small radius" (see RushAmbientCue.RADIUS_KM) -- not a rarity dimension
## to tune, just "how close counts as at the ruin", so this is a plain
## constant rather than a property-tested threshold.
const RADIUS_KM := 3.0

## Fully original prose, in order -- deliberately short ("a few lines" per
## the doc), evoking a 1980s text-adventure parser's FEEL (a blinking ">"
## prompt, terse capitalized system replies) without lifting any of Zork's
## own specific rooms, objects, or phrasing.
const TERMINAL_LINES: Array[String] = [
	"A terminal, half-swallowed by moss and rubble, is somehow still lit.",
	"> LOOK",
	"CURSOR READY. It blinks, patient as stone, for a line that was never going to come.",
	"> WAIT",
	"NOTHING HAPPENS. THIS WAS ALWAYS GOING TO BE THE ANSWER.",
	"The screen dims on its own. The ruin is a ruin again, and you are exactly where you were standing.",
]

var _geo := GeoCoordinates.new()
var _found := false


## The tile this terminal's location corresponds to on a world_width x
## world_height grid.
func tile(world_width: int, world_height: int) -> Vector2i:
	return _geo.tile_for_coordinate(LATITUDE, LONGITUDE, world_width, world_height)


## True if (tile_x, tile_y) is within RADIUS_KM of the terminal's location --
## proximity alone (unlike has_been_found below, which also needs a
## deliberate interaction; see this module's own doc comment).
func is_in_range(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return _geo.tile_is_within_radius(
		tile_x, tile_y, LATITUDE, LONGITUDE, RADIUS_KM, world_width, world_height
	)


## Every original prose line, in order -- the caller joins/displays them
## however fits its own UI (scenes/world.gd currently joins them with "\n"
## into the shared Easter-egg banner label; see _check_ancient_terminal).
## Returns a duplicate so a caller can't mutate the shared constant.
func terminal_lines() -> Array[String]:
	return TERMINAL_LINES.duplicate()


func mark_found() -> void:
	_found = true


func has_been_found() -> bool:
	return _found
