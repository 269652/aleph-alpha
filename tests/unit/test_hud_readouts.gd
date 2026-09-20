extends GutTest

## The pure HUD readouts (see docs/concept/hud.md): the world-clock card, the
## opt-in diagnostics strip, the condition chips and the held-item line.
##
## These take numbers and strings and return text and colours -- they touch no
## node and know nothing about World, which is exactly why they live in their
## own module rather than as four more statics on a 17k-line scenes/world.gd.

const HudReadouts = preload("res://src/ui/hud_readouts.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")


# -- the phase of the day ----------------------------------------------------

## "Sun elev 41.3°" was a number with no meaning at the player's chair. The
## same number, named, is the thing they actually want to know.
func test_a_high_sun_is_plain_day():
	assert_eq(HudReadouts.day_phase(41.3, 14), "Day")


## The boundary is the real civil-twilight one rather than a clock hour,
## because the clock hour of sunset moves by month and by latitude while the
## elevation does not.
func test_six_degrees_up_is_already_day_not_still_dawn():
	assert_eq(HudReadouts.day_phase(6.0, 8), "Day")


func test_just_under_six_degrees_before_noon_is_dawn():
	assert_eq(HudReadouts.day_phase(5.9, 8), "Dawn")


## Same elevation, other side of solar noon: the sun on its way down is dusk,
## not dawn. Local hour here is local SOLAR time (derived from longitude, see
## WorldCoordinates), so 12 is solar noon by construction.
func test_the_same_elevation_after_noon_is_dusk():
	assert_eq(HudReadouts.day_phase(5.9, 19), "Dusk")


func test_noon_itself_counts_as_the_way_down():
	assert_eq(HudReadouts.day_phase(2.0, 12), "Dusk")


## Civil twilight ends at -6 degrees; -6 exactly is still twilight.
func test_six_degrees_below_the_horizon_is_still_twilight():
	assert_eq(HudReadouts.day_phase(-6.0, 5), "Dawn")


func test_past_civil_twilight_is_night():
	assert_eq(HudReadouts.day_phase(-6.1, 5), "Night")


func test_the_dead_of_night_is_night():
	assert_eq(HudReadouts.day_phase(-40.0, 2), "Night")


# -- the world-clock card ----------------------------------------------------

## The player's half of the old strip: the time, the phase, the season, the
## weather and how they are moving. Three lines on one themed card, in a fixed
## order -- never FPS, never a latitude.
func test_the_clock_card_reads_time_phase_season_weather_and_movement():
	var lines: PackedStringArray = HudReadouts.world_clock_lines(
		14, 32, "Day", "Summer", "Clear", "walking", 1.0
	)
	assert_eq(Array(lines), ["14:32 · Day", "Summer · Clear", "Walking · 100%"])


## Zero-padded, so the card never changes width as the hour ticks over and the
## season line below it never shifts sideways.
func test_a_single_digit_hour_is_padded():
	var lines: PackedStringArray = HudReadouts.world_clock_lines(
		6, 5, "Dawn", "Spring", "Rain", "walking", 1.0
	)
	assert_eq(lines[0], "06:05 · Dawn")


## Nothing the player can act on may be a developer's number.
func test_the_clock_card_never_mentions_a_frame_rate_or_a_coordinate():
	var lines: PackedStringArray = HudReadouts.world_clock_lines(
		14, 32, "Day", "Summer", "Clear", "walking", 1.0
	)
	var joined := " ".join(lines)
	assert_false("FPS" in joined, "the clock card is the player's half")
	assert_false("Lat" in joined, "the clock card is the player's half")


## Speed is a percentage of normal, so a mount or a bog reads as a number the
## player can compare against 100.
func test_a_slowed_swimmer_reads_its_own_mode_and_speed():
	var lines: PackedStringArray = HudReadouts.world_clock_lines(
		14, 32, "Day", "Summer", "Clear", "swimming", 0.45
	)
	assert_eq(lines[2], "Swimming · 45%")


## The card is built with exactly this many Labels, so a readout that grew a
## line without the card growing one would silently drop it on the floor.
func test_the_clock_card_has_exactly_as_many_lines_as_the_card_is_built_with():
	var lines: PackedStringArray = HudReadouts.world_clock_lines(
		14, 32, "Day", "Summer", "Clear", "walking", 1.0
	)
	assert_eq(lines.size(), HudReadouts.WORLD_CLOCK_LINE_COUNT)


# -- the diagnostics strip ---------------------------------------------------

## The developer's half, which used to ship on. Same three facts the old strip
## carried, now only when asked for.
func test_the_diagnostics_strip_carries_fps_position_and_sun_elevation():
	var lines: PackedStringArray = HudReadouts.diagnostics_lines(87, 48.0, 7.9, 41.3)
	assert_eq(Array(lines), ["FPS 87", "Lat 48.0  Lon 7.9", "Sun elev 41.3°"])


func test_a_southern_western_position_keeps_its_sign():
	var lines: PackedStringArray = HudReadouts.diagnostics_lines(60, -33.9, -70.7, -12.5)
	assert_eq(lines[1], "Lat -33.9  Lon -70.7")


func test_the_diagnostics_strip_has_exactly_as_many_lines_as_it_is_built_with():
	var lines: PackedStringArray = HudReadouts.diagnostics_lines(87, 48.0, 7.9, 41.3)
	assert_eq(lines.size(), HudReadouts.DIAGNOSTICS_LINE_COUNT)


# -- condition chips ---------------------------------------------------------

## A bar is a fraction, and a fraction is not a warning. SurvivalMeters has
## carried eight named states since it was written and the HUD showed exactly
## one of them.
func test_a_well_fed_player_on_dry_land_shows_no_chips_at_all():
	var meters := SurvivalMeters.new()
	assert_eq(HudReadouts.condition_chips(meters, "walking").size(), 0)


func test_a_hungry_player_is_told_they_are_hungry():
	var meters := SurvivalMeters.new()
	meters.hunger = 0.6
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips.size(), 1)
	assert_eq(chips[0]["text"], "Hungry")


## A warning is the theme's gold; the same good/bad pair Karma already uses.
func test_a_warning_chip_is_the_themes_gold_accent():
	var meters := SurvivalMeters.new()
	meters.hunger = 0.6
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips[0]["color"], UiTheme.ACCENT)


func test_a_severe_chip_is_the_themes_red():
	var meters := SurvivalMeters.new()
	meters.hunger = 0.9
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips[0]["color"], UiTheme.NEGATIVE)


## "Starving" and "Hungry" are the same meter. Showing both would double-count
## one problem and make the row jitter as the deficit crosses 0.85.
func test_starving_replaces_hungry_rather_than_stacking_with_it():
	var meters := SurvivalMeters.new()
	meters.hunger = 0.9
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips.size(), 1)
	assert_eq(chips[0]["text"], "Starving")


func test_parched_replaces_thirsty():
	var meters := SurvivalMeters.new()
	meters.thirst = 0.95
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips.size(), 1)
	assert_eq(chips[0]["text"], "Parched")


func test_freezing_replaces_cold():
	var meters := SurvivalMeters.new()
	meters.warmth = 0.1
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips.size(), 1)
	assert_eq(chips[0]["text"], "Freezing")


## Severe first, then warnings, then facts -- the same fixed-order reasoning
## the message stack already follows, so a chip never moves under the player's
## eye because an unrelated one appeared.
func test_the_severe_chip_comes_before_the_warning_one():
	var meters := SurvivalMeters.new()
	meters.thirst = 0.95  # severe
	meters.hunger = 0.6  # warning
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	assert_eq(chips[0]["text"], "Parched")
	assert_eq(chips[1]["text"], "Hungry")


## Within a tier: food, water, warmth, rest, nutrition, place.
func test_within_a_tier_the_order_is_fixed():
	var meters := SurvivalMeters.new()
	meters.nutrition = 0.1
	meters.stamina = 0.1
	meters.warmth = 0.3
	meters.thirst = 0.6
	meters.hunger = 0.6
	var chips: Array = HudReadouts.condition_chips(meters, "walking")
	var texts := []
	for chip in chips:
		texts.append(chip["text"])
	assert_eq(texts, ["Hungry", "Thirsty", "Cold", "Exhausted", "Malnourished"])


## Where the player is standing is a fact, not a warning, so it neither shouts
## in red nor glows gold -- and it sorts after everything that is wrong.
func test_swimming_is_a_muted_fact_after_every_warning():
	var meters := SurvivalMeters.new()
	meters.hunger = 0.6
	var chips: Array = HudReadouts.condition_chips(meters, "swimming")
	assert_eq(chips.size(), 2)
	assert_eq(chips[1]["text"], "Swimming")
	assert_eq(chips[1]["color"], UiTheme.TEXT_MUTED)


func test_wading_says_wading_not_swimming():
	var meters := SurvivalMeters.new()
	var chips: Array = HudReadouts.condition_chips(meters, "wading")
	assert_eq(chips.size(), 1)
	assert_eq(chips[0]["text"], "Wading")


func test_walking_on_dry_land_is_not_worth_a_chip():
	var meters := SurvivalMeters.new()
	assert_eq(HudReadouts.condition_chips(meters, "walking").size(), 0)


# -- the held-item line ------------------------------------------------------

## Nothing in the HUD showed wear: the only way a player learnt an axe was
## about to break was that it broke.
func test_a_worn_tool_says_so_beside_its_name():
	assert_eq(HudReadouts.held_item_line("Stone Axe", "worn"), "Stone Axe · Worn")


## An item with no material to wear (a torch, a fish) gets no grade rather
## than a meaningless "Pristine".
func test_an_item_that_cannot_wear_is_just_its_name():
	assert_eq(HudReadouts.held_item_line("Torch", ""), "Torch")


## Empty hides the whole card, the same rule _set_message_banner follows --
## nothing can leave a blank card holding a gap open.
func test_an_empty_hand_is_an_empty_line():
	assert_eq(HudReadouts.held_item_line("", ""), "")


# -- rebuilding the chip row only when it changed -----------------------------

## The chips are rebuilt rather than pooled (the row is empty in the common
## case, so a pool of five hidden cards to avoid allocating in the rare case is
## the more expensive of the two) -- which makes "has anything changed?" the
## thing that has to be cheap and exact.
func test_the_same_conditions_produce_the_same_signature():
	var meters := SurvivalMeters.new()
	meters.hunger = 0.6
	var a := HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking"))
	# A different deficit on the SAME side of the threshold says the same thing.
	meters.hunger = 0.7
	var b := HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking"))
	assert_eq(a, b, "a bar moving without crossing a threshold is not a rebuild")


func test_crossing_a_threshold_changes_the_signature():
	var meters := SurvivalMeters.new()
	var fed := HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking"))
	meters.hunger = 0.6
	var hungry := HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking"))
	meters.hunger = 0.9
	var starving := HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking"))
	assert_ne(fed, hungry)
	assert_ne(hungry, starving)


## Two different chips must not collide into one signature just because their
## texts concatenate the same way.
func test_two_chips_do_not_collide_with_one_chip_named_after_both():
	var separate := HudReadouts.chips_signature(
		[{"text": "Cold", "color": Color.WHITE}, {"text": "Wading", "color": Color.WHITE}]
	)
	var merged := HudReadouts.chips_signature([{"text": "ColdWading", "color": Color.WHITE}])
	assert_ne(separate, merged)


func test_no_chips_is_a_stable_signature_of_its_own():
	assert_eq(HudReadouts.chips_signature([]), HudReadouts.chips_signature([]))


# -- FPS is back on the always-on card (see docs/concept/hud.md) -----------
#
# Reported back simply: "also add back the FPS". It shipped in the middle
# of the clock line until the split-strip pass moved it, with lat/lon and
# sun elevation, into the F3 diagnostics strip -- off by default. Only FPS
# comes back: the other two are genuinely diagnostic, while a frame counter
# is wanted visible exactly when you are not thinking to press F3.

func test_the_clock_card_shows_the_frame_rate():
	var lines := HudReadouts.world_clock_lines(9, 5, "Day", "Spring", "Clear", "walking", 0.56, 59)
	var joined := " ".join(lines)
	assert_string_contains(joined, "59", "the frame rate is not on the always-on card")
	assert_string_contains(joined.to_upper(), "FPS")


func test_the_card_keeps_its_fixed_line_count_with_fps_on_it():
	# "No line ever appears or disappears, so the card never resizes under
	# the player's eye" -- FPS has to share a line, not add one.
	var lines := HudReadouts.world_clock_lines(9, 5, "Day", "Spring", "Clear", "walking", 0.56, 59)
	assert_eq(lines.size(), HudReadouts.WORLD_CLOCK_LINE_COUNT)


func test_the_clock_and_season_lines_are_untouched_by_the_frame_rate():
	var lines := HudReadouts.world_clock_lines(9, 5, "Day", "Spring", "Clear", "walking", 0.56, 59)
	assert_eq(lines[0], "09:05 · Day")
	assert_eq(lines[1], "Spring · Clear")


func test_an_unknown_frame_rate_leaves_the_card_readable():
	# Engine.get_frames_per_second() is 0 on the very first frame; a card
	# reading "0 FPS" then would be wrong rather than merely early.
	var lines := HudReadouts.world_clock_lines(9, 5, "Day", "Spring", "Clear", "walking", 0.56, 0)
	for line in lines:
		assert_ne(String(line).strip_edges(), "")


func test_fps_is_optional_so_every_existing_caller_is_untouched():
	var without := HudReadouts.world_clock_lines(9, 5, "Day", "Spring", "Clear", "walking", 0.56)
	assert_eq(without.size(), HudReadouts.WORLD_CLOCK_LINE_COUNT)
	assert_eq(without[0], "09:05 · Day")
