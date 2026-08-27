extends RefCounted

## "A signed secret room (Atari Adventure homage -- the deepest cut)"
## (docs/concept/easter_eggs.md): RP1's whole premise is modeled on a real
## historical event -- Warren Robinett hid the FIRST video game Easter egg
## ever (his own name, in a secret room) inside Atari's 1980 *Adventure*,
## without Atari's knowledge. The most fitting tribute isn't referencing the
## game itself; it's repeating the actual gesture -- a small, genuinely
## hard-to-reach room somewhere in this world, reachable only via an obscure
## action sequence (not a coordinate alone, unlike every other cameo in this
## doc -- see the doc's own parenthetical), containing nothing but a quiet
## signature/credit.
##
## Location: a real-world coordinate (Sunnyvale, California -- Atari's own
## historical 1980s headquarters, where Robinett actually worked), reusing
## GeoCoordinates' reverse lookup + radius exactly like every other real-
## coordinate cameo in this project (RushAmbientCue/AncientTerminal) -- never
## named or hinted at in-game, the same "quiet, factual pick, never shown to
## the player" register those modules' own doc comments already set.
## Deliberately far from this game's own Berlin spawn point (World.
## SPAWN_LATITUDE/SPAWN_LONGITUDE) -- reaching it at all takes real travel,
## on top of the sequence below, which is the "genuinely hard-to-reach"
## the doc asks for.
##
## The "obscure action sequence": stash, then lasso, then fish, then mount,
## each a real, existing interaction verb (scenes/player.gd's own input
## actions) that are normally used in completely unrelated contexts (opening
## storage; equipping the taming lasso; casting a fishing rod; mounting a
## tamed animal) -- four unrelated verbs in one specific order is not a
## combination any normal play session would ever produce by accident,
## which is exactly the "unusual combination... documented clearly in code
## comments so a future developer understands how to reach it" this stage's
## own task asked for. Chosen deliberately over context-dependent combat
## verbs (attack/block/kick), which DO plausibly chain together in real
## combat and would risk a false-positive/accidental discovery.
##
## matches_sequence checks only the raw ACTION NAMES the player pressed, not
## whether each action's normal in-game effect actually fired (e.g. "fish"
## still counts even with no water nearby) -- scenes/world.gd
## (_check_signed_secret_room) is the one place that reads real Input just-
## pressed edges for exactly these four actions into a small rolling buffer
## and calls this module with it; this module never touches Input itself,
## the same "caller supplies the real input, module only decides" shape as
## every sibling module in this Easter-egg family.
##
## "Found" state: has_been_found()/mark_found() are a clean, testable
## boolean signal for a later system (docs/concept/easter_eggs.md's "Three
## Fragments" hunt) to check "has the player found the secret room" against
## -- this module only exposes that signal; it does not decide what a later
## system does with it (no fragment item, no bonus trigger here; see
## scenes/world.gd's own forwarding getter, has_found_signed_secret_room).

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

const LATITUDE := 37.3688
const LONGITUDE := -122.0363
## Small and pinned, matching every other point cameo in this project family
## (see AncientTerminal.RADIUS_KM's own comment for why this isn't a
## property-tested threshold: there's no rarity dimension here to tune).
const RADIUS_KM := 3.0

## The exact, ordered sequence of action-input names required (see this
## module's own doc comment for why these four verbs specifically).
const ACTION_SEQUENCE: Array[String] = ["stash", "lasso", "fish", "mount"]

## Tasteful, generic, placeholder credit -- a single clearly-marked constant
## so whoever actually ships this can swap in real credited names with a
## one-line edit. TODO(ship): replace with the real credit before release.
const CREDIT_TEXT := "You found this. Made with care by the people who built this world."

var _geo := GeoCoordinates.new()
var _found := false


## The tile this room's location corresponds to on a world_width x
## world_height grid.
func tile(world_width: int, world_height: int) -> Vector2i:
	return _geo.tile_for_coordinate(LATITUDE, LONGITUDE, world_width, world_height)


## True if (tile_x, tile_y) is within RADIUS_KM of the room's location --
## necessary but not sufficient on its own; see has_been_found's own note
## that presence here alone does nothing without matches_sequence too.
func is_in_range(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return _geo.tile_is_within_radius(
		tile_x, tile_y, LATITUDE, LONGITUDE, RADIUS_KM, world_width, world_height
	)


## True if the TAIL of `recent_actions` (its last ACTION_SEQUENCE.size()
## entries, in order) equals ACTION_SEQUENCE exactly -- a tail match rather
## than requiring the whole buffer to be exactly this length, so a caller
## can safely keep pushing onto a small rolling buffer without needing to
## reset it first (any earlier, unrelated presses simply fall off the front).
func matches_sequence(recent_actions: Array) -> bool:
	var needed := ACTION_SEQUENCE.size()
	if recent_actions.size() < needed:
		return false
	var tail := recent_actions.slice(recent_actions.size() - needed, recent_actions.size())
	for i in range(needed):
		if String(tail[i]) != ACTION_SEQUENCE[i]:
			return false
	return true


func credit_text() -> String:
	return CREDIT_TEXT


func mark_found() -> void:
	_found = true


func has_been_found() -> bool:
	return _found
