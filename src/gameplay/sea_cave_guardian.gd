extends RefCounted

## "A hidden sea cave at the Bermuda Triangle, with a dueling-birds cabinet
## inside" (docs/concept/easter_eggs.md's biggest single Starter Collection
## entry). This module is the location + interaction gate for an ORIGINAL
## guardian spirit -- the Brinewarden, a barnacle-crowned figure invented
## for this world, never RP1's own specific character (pillar 4, "homage
## over reproduction") -- who challenges the player to a best-of-three
## aerial joust the instant a nearby stone seat visibly reconfigures into
## an arcade cabinet. The joust's own rules live entirely in JoustMatch;
## the actual on-screen transform/rendering lives in the node/rendering
## adapter (JoustMatchView + scenes/world.gd's own wiring) -- this module
## only tracks WHERE the cave is and WHETHER a challenge is currently
## active, the same pure-module-plus-node-adapter split every other system
## in this project uses.
##
## Location: the exact same Bermuda Triangle coordinate Squallmaw itself
## uses (EasterEggCreatures.SIGHTINGS["squallmaw"]) -- "a hidden, half-
## flooded sea cave at the exact Bermuda Triangle coordinates... alongside
## Squallmaw above" per the doc's own words. Duplicated here as its own
## named constants rather than reached into EasterEggCreatures' dictionary
## at const-eval time (GDScript's own const-folding doesn't reliably
## support dictionary subscripting at parse time) -- test_sea_cave_
## guardian.gd's own test pins the two in lockstep instead, so they can
## never silently drift apart.
##
## RADIUS_KM is deliberately smaller than Squallmaw's own 30km radius (a
## cave mouth is one specific, findable point, not "somewhere in this
## stretch of open ocean") -- matching every other pinned-to-a-point
## cameo's own small radius (see AncientTerminal.RADIUS_KM's own comment).
##
## Interaction: like AncientTerminal (see that module's own doc comment),
## proximity alone doesn't trigger anything -- a deliberate "talk" press
## at the cave mouth does, gated in scenes/world.gd every frame the same
## way _check_ancient_terminal is (a single-frame just-pressed edge would
## be dropped by the throttled cadence the rarity-roll cameos use).
##
## Repeatable by design (unlike AncientTerminal/SignedSecretRoom's one-shot
## has_been_found() latch): is_challenge_active alone gates re-triggering
## while a joust is already running -- once a match ends, approaching and
## talking again starts a fresh one. Zero mechanical weight (pillar 2)
## means there is no reason to prevent a rematch; the surprise is the
## discovery and the match itself, not a one-time flag.

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

const LATITUDE := 25.5
const LONGITUDE := -71.0
const RADIUS_KM := 4.0

const GUARDIAN_NAME := "the Brinewarden"

## Shown the moment a fresh challenge begins, before the transform below --
## the challenge reads as a choice the guardian offers, not an ambush.
const CHALLENGE_LINE := (
	"Barnacles crack like knuckles as a shape in the flooded dark unfolds"
	+ " to its full height, ragged fin-wings settling at its sides."
	+ " \"You may pass, traveler,\" the Brinewarden rasps, \"if you can"
	+ " unseat me first.\" It nods at the stone bench beside it."
)

## The scripted transform beat itself -- one small transformation, not a
## full cutscene system, per this stage's own task description.
const TRANSFORM_LINE := (
	"The stone bench grinds, splits, and folds itself inside out -- old,"
	+ " barnacled rock rearranging into a squat, glowing cabinet with two"
	+ " worn control sticks, humming like it has been waiting a long time."
)

const VICTORY_LINE := (
	"The Brinewarden dips its ragged wings in something like a bow."
	+ " \"Well flown,\" it rasps, and steps aside from the passage deeper"
	+ " into the cave."
)

const DEFEAT_LINE := (
	"The Brinewarden rights itself with a wet, creaking laugh. \"Again,\""
	+ " it says, \"if you dare -- the tide isn't going anywhere.\""
)

var _geo := GeoCoordinates.new()
var _challenge_active := false


## The tile this cave's location corresponds to on a world_width x
## world_height grid.
func tile(world_width: int, world_height: int) -> Vector2i:
	return _geo.tile_for_coordinate(LATITUDE, LONGITUDE, world_width, world_height)


## True if (tile_x, tile_y) is within RADIUS_KM of the cave mouth --
## necessary but not sufficient to start a challenge; see can_begin_
## challenge, which also checks is_challenge_active.
func is_in_range(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return _geo.tile_is_within_radius(
		tile_x, tile_y, LATITUDE, LONGITUDE, RADIUS_KM, world_width, world_height
	)


func is_challenge_active() -> bool:
	return _challenge_active


## True only when a fresh challenge may begin: in range AND no joust
## already running. scenes/world.gd calls this on the player's own "talk"
## press, the same interaction verb AncientTerminal reuses.
func can_begin_challenge(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	if _challenge_active:
		return false
	return is_in_range(tile_x, tile_y, world_width, world_height)


func begin_challenge() -> void:
	_challenge_active = true


func end_challenge() -> void:
	_challenge_active = false


func challenge_line() -> String:
	return CHALLENGE_LINE


func transform_line() -> String:
	return TRANSFORM_LINE


## `winner` is JoustMatch's own "player"/"ai" winner id.
func outcome_line(winner: String) -> String:
	return VICTORY_LINE if winner == "player" else DEFEAT_LINE
