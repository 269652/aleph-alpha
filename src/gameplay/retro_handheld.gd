extends RefCounted

## "A hidden retro handheld, playing an original mini-game starring this
## GAME's own creatures" (docs/concept/easter_eggs.md) -- the location +
## interaction gate for the battered handheld prop itself, mirroring
## AncientTerminal/SeaCaveGuardian's own established real-coordinate +
## "talk" interaction shape (see scenes/world.gd's own _check_ancient_
## terminal/_check_sea_cave_guardian for the wiring precedent this stage's
## own _check_retro_handheld follows). This module only tracks WHERE the
## prop is and WHETHER its mini-game screen is currently open -- the
## battle/catch/collection rules live entirely in HandheldBattle/
## HandheldCatch/HandheldCollection; the actual playable screen lives in
## HandheldBattleView.
##
## Location: Kyoto, Japan -- the real-world home of the handheld/monster-
## collecting games era this prop is an affectionate wink at, never named
## in-game (no brand, no console name, no logo -- see flavor_line's own doc
## comment and its regression test). The same "a quiet, factual geography
## pick, never shown to the player" register RushAmbientCue/AncientTerminal/
## SignedSecretRoom already use for their own real-world location choices
## (MIT/Cambridge for Zork, Atari's Sunnyvale HQ for the signed room).
##
## Repeatable by design, like SeaCaveGuardian (NOT a one-shot
## has_been_found() latch the way AncientTerminal/SignedSecretRoom gate
## re-entry) -- a handheld you pick back up and keep playing/catching on is
## more in the spirit of a real found prop than a one-time cutscene.
## is_open() alone gates re-triggering while the mini-game is already
## showing; has_been_found()/mark_found() exist ONLY to pick which
## flavor_line plays (a quieter "you found it" beat once, a plain "it's on
## again" beat every time after), never to block re-entry.

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

const LATITUDE := 35.0116
const LONGITUDE := 135.7681
## Deliberately small, matching every other pinned-to-a-point cameo's own
## "small radius" (see AncientTerminal.RADIUS_KM's own comment) -- not a
## rarity dimension to tune, just "how close counts as at the prop".
const RADIUS_KM := 3.0

## Shown once, the first time the prop is ever interacted with -- generic,
## undescribed hardware per the doc's own explicit ask ("no trademarked
## shape or logo"), enforced by this module's own regression test
## (test_retro_handheld.gd's "never names a trademarked handheld brand").
const FOUND_LINE := (
	"Half-buried in leaf litter, a small, battered handheld powers on in"
	+ " your hands -- its plastic case scuffed and nameless, its screen"
	+ " impossibly still lit after all this time."
)
## Shown on every visit after the first.
const REOPEN_LINE := "The little handheld blinks awake again, screen humming faintly."


var _geo := GeoCoordinates.new()
var _is_open := false
var _found := false


## The tile this prop's location corresponds to on a world_width x
## world_height grid.
func tile(world_width: int, world_height: int) -> Vector2i:
	return _geo.tile_for_coordinate(LATITUDE, LONGITUDE, world_width, world_height)


## True if (tile_x, tile_y) is within RADIUS_KM of the prop's location.
func is_in_range(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return _geo.tile_is_within_radius(
		tile_x, tile_y, LATITUDE, LONGITUDE, RADIUS_KM, world_width, world_height
	)


func is_open() -> bool:
	return _is_open


## True only when the mini-game screen may freshly open: in range AND not
## already open (mirrors SeaCaveGuardian.can_begin_challenge exactly).
func can_open(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	if _is_open:
		return false
	return is_in_range(tile_x, tile_y, world_width, world_height)


func open() -> void:
	_is_open = true


func close() -> void:
	_is_open = false


func has_been_found() -> bool:
	return _found


func mark_found() -> void:
	_found = true


## `already_found` is the caller's own has_been_found() reading FROM BEFORE
## this interaction (the same "read the flag before mark_found, so the very
## first find gets its own line" shape _check_ancient_terminal already uses
## for "Three Fragments" granting).
func flavor_line(already_found: bool) -> String:
	return REOPEN_LINE if already_found else FOUND_LINE
