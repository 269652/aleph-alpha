extends GutTest

## One legible HUD surface (see docs/concept/hud.md).
##
## The pure parts of what World draws over the world: which transient message
## banners are on screen and in what order, when a world-space hint may be
## drawn at all, and what a survival meter's number says. World's own node
## wiring is untested glue over these tested pieces -- the same boundary
## docs/concept/persistence.md already draws for the persistence wiring.

const World = preload("res://scenes/world.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")


# -- the message stack -------------------------------------------------------

## The taming and trade banners used to be two separate absolutely-positioned
## Labels pinned to the SAME offset_top (144), so a trade message and a taming
## message drew straight through each other. They are one stack now, and
## overlap is structurally impossible rather than avoided by hand-picked
## constants.
func test_two_messages_at_once_never_share_a_line():
	var lines: PackedStringArray = World.message_banner_lines("", "Lasso thrown", "That'll be 3 gold", "", "")
	assert_eq(lines.size(), 2)
	assert_true("Lasso thrown" in lines)
	assert_true("That'll be 3 gold" in lines)


## A hidden banner is a hidden CARD, not an empty one: it takes no room, so
## the banners below it move up instead of a blank gap opening.
func test_an_empty_message_takes_no_room_in_the_stack():
	var lines: PackedStringArray = World.message_banner_lines("A trout!", "", "", "Good morning", "")
	assert_eq(lines.size(), 2)
	assert_eq(lines[0], "A trout!")
	assert_eq(lines[1], "Good morning")


func test_nothing_to_say_shows_no_banners():
	assert_eq(World.message_banner_lines("", "", "", "", "").size(), 0)


## Fixed top-to-bottom order, so a message never moves around under the
## player's eye depending on which other ones happen to be showing.
func test_the_banner_order_is_fixed():
	var lines: PackedStringArray = World.message_banner_lines("fish", "lasso", "trade", "talk", "egg")
	assert_eq(
		Array(lines), ["fish", "lasso", "trade", "talk", "egg"]
	)


## The banners must be drawn on the shared themed card rather than as bare
## text over the world: five white Labels with no background were invisible
## over snow (reported) and washed out over sand. This pins the property that
## makes the card readable -- it is opaque -- so a later "simplification" back
## to a translucent rect or a plain Label has to fail this first. Green from
## the start by design: it is the pin, not the bug.
func test_a_banner_card_is_opaque_enough_to_read_over_snow():
	assert_gte(UiTheme.PANEL_BG.a, 0.9)


# -- the world's hints never cover a window -----------------------------------

## Every HUD node in scenes/world.gd is a child of the same `$UI` CanvasLayer,
## where draw order is sibling order -- and the world-space floaters are built
## AFTER the inventory/crafting/skill windows, so "Talk (G)" and a tooltip
## about a tree BEHIND the modal painted straight over the open modal
## (reported). Hiding them while a window is open is the fix.
func test_a_world_hint_shows_when_no_window_is_open():
	assert_true(World.world_hint_visible_for(true, false))


func test_an_open_gameplay_window_hides_the_world_space_hint():
	assert_false(World.world_hint_visible_for(true, true))


## Nothing to say stays silent either way -- the window state may only ever
## take a hint away, never conjure one.
func test_nothing_to_show_stays_hidden_even_with_no_window_open():
	assert_false(World.world_hint_visible_for(false, false))
	assert_false(World.world_hint_visible_for(false, true))


# -- a number and the bar beside it always mean the same thing -----------------

const HealthBar = preload("res://src/gameplay/health_bar.gd")


## SurvivalMeters stores hunger and thirst as DEFICITS (rising = worse) and
## stamina/warmth as RESERVES. The panel used to fill all four BARS with the
## reserve but print the raw stored value for all four -- so a starving player
## read "Hunger 100%" over an EMPTY bar, two rows above "Warmth 100%" over a
## FULL one meaning the opposite.
func test_a_starving_player_reads_zero_food_not_a_hundred_hunger():
	assert_eq(World.meter_label_text("Food", World.reserve_for_deficit(1.0)), "Food 0%")


func test_a_full_belly_reads_a_hundred_percent_food():
	assert_eq(World.meter_label_text("Food", World.reserve_for_deficit(0.0)), "Food 100%")


## The anti-regression pin: the number and the fill beside it are the same
## value by construction, not by two lines agreeing to stay in step.
func test_the_number_always_matches_the_bar_beside_it():
	var bar := HealthBar.new()
	for deficit in [0.0, 0.25, 0.6, 1.0]:
		var reserve: float = World.reserve_for_deficit(deficit)
		var fill: float = bar.fill_width(reserve, 1.0, World.SURVIVAL_BAR_WIDTH)
		var bar_percent := int(round(fill / World.SURVIVAL_BAR_WIDTH * 100.0))
		var label: String = World.meter_label_text("Food", reserve)
		assert_eq(
			label, "Food %d%%" % bar_percent,
			"the label and the bar disagree at deficit %s" % deficit
		)


## A meter never reads outside 0-100, however far out of range the model's
## own value has wandered.
func test_a_meter_percent_never_leaves_the_zero_to_a_hundred_range():
	assert_eq(World.meter_label_text("Water", World.reserve_for_deficit(1.4)), "Water 0%")
	assert_eq(World.meter_label_text("Water", World.reserve_for_deficit(-0.3)), "Water 100%")
	assert_eq(World.meter_label_text("Stamina", 2.0), "Stamina 100%")
	assert_eq(World.meter_label_text("Stamina", -1.0), "Stamina 0%")
