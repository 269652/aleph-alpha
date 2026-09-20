extends RefCounted

## The pure HUD readouts -- see docs/concept/hud.md.
##
## The world-clock card, the opt-in diagnostics strip, the condition chips and
## the held-item line: numbers and strings in, text and colours out. Nothing
## here touches a node or knows what World is, which is why this is its own
## module rather than four more statics on a 17k-line scenes/world.gd.
##
## Pinned by tests/unit/test_hud_readouts.gd.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## Civil twilight: the sun is between these two elevations when the sky is lit
## but the sun itself is not up. Real boundaries rather than clock hours,
## because the clock hour of sunset moves by month and by latitude while the
## elevation does not -- which is the whole reason the strip printed an
## elevation in the first place.
const CIVIL_TWILIGHT_DEGREES := -6.0
const FULL_DAYLIGHT_DEGREES := 6.0

## Local SOLAR noon, which is 12 by construction here: the game's local hour is
## derived from longitude (see WorldCoordinates), so this is not an
## approximation of when the sun peaks, it is where the model puts it.
const SOLAR_NOON_HOUR := 12

## How many lines each card carries. The cards are built with exactly this many
## Labels, so a readout that grew a line without the card growing one would
## silently drop it on the floor.
const WORLD_CLOCK_LINE_COUNT := 3
const DIAGNOSTICS_LINE_COUNT := 3


## "Day" / "Dawn" / "Dusk" / "Night" -- what `Sun elev 41.3°` meant, said in
## the one word a player can act on. `local_hour` only ever chooses between
## the two twilights; it never decides whether it IS twilight.
static func day_phase(sun_elevation_degrees: float, local_hour: int) -> String:
	if sun_elevation_degrees >= FULL_DAYLIGHT_DEGREES:
		return "Day"
	if sun_elevation_degrees < CIVIL_TWILIGHT_DEGREES:
		return "Night"
	return "Dawn" if local_hour < SOLAR_NOON_HOUR else "Dusk"


## The player's half of the old top-left strip, as the three lines of one
## themed card. Fixed line order, and no line ever appears or disappears, so
## the card never resizes under the player's eye.
static func world_clock_lines(
	local_hour: int,
	local_minute: int,
	phase: String,
	season: String,
	weather: String,
	movement_mode: String,
	speed_multiplier: float
) -> PackedStringArray:
	return PackedStringArray(
		[
			# Zero-padded so the card keeps its width as the hour ticks over.
			"%02d:%02d · %s" % [local_hour, local_minute, phase],
			"%s · %s" % [season, weather],
			"%s · %d%%" % [movement_mode.capitalize(), roundi(speed_multiplier * 100.0)],
		]
	)


## The developer's half, which used to ship on. Same three facts, same raw
## shape -- a diagnostic is for reading against a debugger, so it is not
## prettified into compass letters it would then have to be translated back
## out of.
static func diagnostics_lines(
	frames_per_second: int, latitude: float, longitude: float, sun_elevation_degrees: float
) -> PackedStringArray:
	return PackedStringArray(
		[
			"FPS %d" % frames_per_second,
			"Lat %.1f  Lon %.1f" % [latitude, longitude],
			"Sun elev %.1f°" % sun_elevation_degrees,
		]
	)


## Which of SurvivalMeters' named states are true right now, as
## `{text, color}` chips -- the warning the bars only imply.
##
## Severe (NEGATIVE) first, then warnings (ACCENT), then facts about where the
## player is standing (TEXT_MUTED); within a tier the order is food, water,
## warmth, rest, nutrition, place. The fixed order is the same reasoning the
## message stack's is: a chip must not move because an unrelated one appeared.
##
## A severe state REPLACES its own warning -- "Starving" and "Hungry" are the
## same meter, and showing both would double-count one problem and make the
## row jitter as the deficit crosses the threshold.
##
## Nothing wrong on dry land returns nothing at all: the HUD is quiet when
## there is nothing to say, rather than showing a row of green "OK" badges.
static func condition_chips(meters, movement_mode: String) -> Array:
	var severe: Array = []
	var warnings: Array = []

	if meters.is_starving():
		severe.append(_chip("Starving", UiTheme.NEGATIVE))
	elif meters.is_hungry():
		warnings.append(_chip("Hungry", UiTheme.ACCENT))

	if meters.is_dehydrated():
		severe.append(_chip("Parched", UiTheme.NEGATIVE))
	elif meters.is_thirsty():
		warnings.append(_chip("Thirsty", UiTheme.ACCENT))

	if meters.is_freezing():
		severe.append(_chip("Freezing", UiTheme.NEGATIVE))
	elif meters.is_cold():
		warnings.append(_chip("Cold", UiTheme.ACCENT))

	if meters.is_exhausted():
		warnings.append(_chip("Exhausted", UiTheme.ACCENT))
	if meters.is_malnourished():
		warnings.append(_chip("Malnourished", UiTheme.ACCENT))

	var chips: Array = severe + warnings
	var place := _place_chip_text(movement_mode)
	if place != "":
		chips.append(_chip(place, UiTheme.TEXT_MUTED))
	return chips


## What `condition_chips` currently says, as one comparable string -- so the
## row is rebuilt only when it would actually look different.
##
## The chips are rebuilt rather than pooled (the row is empty in the common
## case, so five hidden PanelContainers kept around to avoid allocating in the
## rare one would be the more expensive of the two), which makes "has anything
## changed?" the thing that has to be cheap and exact. A bar drifting without
## crossing a threshold must NOT count as a change; two chips must not collide
## with one chip named after both, hence the separator.
static func chips_signature(chips: Array) -> String:
	var out := ""
	for chip in chips:
		out += String(chip["text"]) + "|"
	return out


## What is in hand and how close it is to breaking. `condition` is
## ItemWear.condition_for's grade, or "" for an item with no material to wear
## (a torch, a fish) -- which gets no grade rather than a meaningless
## "Pristine". An empty name is an empty line, which hides the whole card, the
## same rule _set_message_banner follows.
static func held_item_line(item_name: String, condition: String) -> String:
	if item_name == "":
		return ""
	if condition == "":
		return item_name
	return "%s · %s" % [item_name, condition.capitalize()]


## Standing in water is a fact worth naming (it halves the player's speed and
## chills them, see SurvivalMeters.WETNESS_CHILL); standing on dry ground is
## the default and is not worth a chip.
static func _place_chip_text(movement_mode: String) -> String:
	match movement_mode:
		"swimming":
			return "Swimming"
		"wading":
			return "Wading"
	return ""


static func _chip(text: String, color: Color) -> Dictionary:
	return {"text": text, "color": color}
