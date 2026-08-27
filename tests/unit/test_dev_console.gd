extends GutTest

## Covers DevConsole's OUTPUT surface -- the "the console cannot show its own
## answers" bug class, reported live: every logged line rendered as ONE WORD
## PER ROW, most of a command's reply was cut off before it was ever stored,
## and whatever did fit landed below the fold because the view never moved.
##
## Three separate causes, one per group of tests here:
##   1. The output Label was not SIZE_EXPAND_FILL inside its ScrollContainer.
##      Godot only stretches a scroll child to the container's width when the
##      child has the EXPAND flag; otherwise it gets its own MINIMUM width,
##      and an autowrapping Label claims ~nothing (it can wrap to any width).
##   2. The scrollback cap counted LOGICAL lines and was a dozen, while a
##      /history report logs one line per recorded event.
##   3. Nothing ever scrolled the view to the newest line.

const DevConsole = preload("res://scenes/dev_console.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Keep in sync with World._build_dev_console's offsets (±210 x ±80).
const WORLD_ANCHOR_BOX := Vector2(420, 160)

## A verbatim copy of the longest single line the console ever prints:
## World._on_console_command's "help" branch. This is the exact line that
## rendered as one word per row.
const HELP_LINE := (
	"Commands: /day  /season [name]  /weather [state|off]"
	+ "  /ecotest [seconds_per_year|off]"
	+ "  /history <entity_id>  /why <event_id>  /remember <entity_id>"
	+ "  /household <entity_id>  /contract <entity_id>  /market <entity_id>"
	+ "  /institution <entity_id>  /settlement <entity_id>  /boss <entity_id>"
	+ "  /quests <entity_id>  /emergence"
	+ "  /spawn <species> [count]  /give <item_id> [count]"
	+ "  /craft <recipe_id>  /gold <amount>  /village  /species  /help"
	+ "  /compass  /map  /weatherglass  /almanac  /deed"
	+ "  /ledger propose|accept|fulfill|breach ...  /charter found <type> <counterparty_id>"
	+ "  /journal <entity_id>"
)

## The length of one realistic multi-line report. /history logs ONE line per
## recorded event -- World._handle_history_command splits Why.explain_entity's
## report on "\n" and calls log_line for each line -- so a settlement with a
## few dozen recorded events reports this long. Deliberately modest: the old
## twelve-line cap could not hold even a fifth of it.
const REPORT_LINES := 60

var console: DevConsole


func before_each():
	console = DevConsole.new()
	# World._build_dev_console assigns the shared UI theme, and the theme is
	# what decides the font size and therefore how many rows fit in the output
	# viewport -- the geometry MAX_LOG_LINES is derived from.
	console.theme = UiTheme.new().build_theme()
	add_child(console)
	# _ready() hides the console, and a Container skips fit_child_in_rect for
	# children that are not visible_in_tree -- without this every layout
	# assertion below would read 0 both BEFORE and after the fix, i.e. would
	# be vacuous rather than red.
	console.visible = true
	console.size = WORLD_ANCHOR_BOX


func after_each():
	console.free()


## Geometry readers that work against EITHER output control, so the tests
## below measure the real defect on the old ScrollContainer+Label stack rather
## than merely erroring on a missing method.
func _output_control():
	return console._output_label


func _scroll_bar():
	return _output_control().get_v_scroll_bar()


## How tall the log actually IS -- the number the container gets wrong.
func _content_height() -> float:
	var control = _output_control()
	if control.has_method("get_content_height"):
		return float(control.get_content_height())
	return control.get_combined_minimum_size().y


func _visible_height() -> float:
	return _output_control().size.y


## How far the view can be scrolled down. A scrollbar clamps to max - page, so
## this is the real floor of what the user can reach.
func _scroll_range() -> float:
	var bar = _scroll_bar()
	return bar.max_value - bar.page


func _scroll_position() -> float:
	return float(_scroll_bar().value)


func _log_report(count: int) -> void:
	for i in count:
		console.log_line("  evt_%d_settlement_founded  (tick %d)" % [i, i * 3])


## The original symptom this guards: a horizontal scrollbar both let the text
## stay narrow (one word per row) and ate height out of an already-short box.
## RichTextLabel has no horizontal scroll at all -- autowrap is what keeps the
## text inside the width, so THAT is the thing worth pinning.
func test_output_wraps_rather_than_scrolling_sideways():
	assert_eq(console._output_label.autowrap_mode, TextServer.AUTOWRAP_WORD)
	assert_true(console._output_label.scroll_active, "the log must scroll vertically")


## The load-bearing flag: without EXPAND the ScrollContainer hands the label
## its own minimum width, which for AUTOWRAP_WORD is ~1px. Every other
## scrolling surface in this project sets this pair (crafting_window.gd,
## settings_overlay.gd, skill_tree_window.gd, main_menu.gd); the console was
## the single omission.
func test_output_label_expands_to_fill_the_scroll_width():
	assert_eq(console._output_label.size_flags_horizontal, Control.SIZE_EXPAND_FILL)


## The behavioural version of the above: after a real layout pass the label
## must actually be about as wide as the console, not a sliver.
func test_output_label_is_laid_out_at_the_console_width_not_its_own_minimum():
	console.log_line(HELP_LINE)
	# wait_process_frames, NOT wait_frames: GUT 9.7.1's wait_frames forwards to
	# wait_physics_frames, and Control layout runs on process/idle frames.
	await wait_process_frames(2)
	assert_gt(
		console._output_label.size.x,
		WORLD_ANCHOR_BOX.x * 0.5,
		"the output label must fill the console width, not its own ~0 minimum"
	)


## The reported symptom itself: one word per row. The /help line has ~60
## words; correctly wrapped at the console width it is a handful of rows.
func test_a_long_line_wraps_into_a_few_rows_not_one_word_per_row():
	console.log_line(HELP_LINE)
	await wait_process_frames(2)
	var words := HELP_LINE.split(" ", false).size()
	assert_lt(
		console._output_label.get_line_count(),
		int(words / 2.0),
		"wrapped rows must be far fewer than the %d words in the line" % words
	)


## REMOVED: test_logging_scrolls_to_the_newest_line.
##
## It compared scroll_vertical against `max_value - page` -- i.e. against the
## scrollbar's own idea of the bottom, which was the number that went stale.
## It passed for as long as the bug existed, which is the worst thing a test
## can do: it made "fixed and tested" and "still broken in play" both true at
## once, and cost a session's worth of trusting it. Superseded by
## test_the_bottom_of_the_log_is_actually_reachable and its siblings below,
## which measure against the CONTENT height instead.


## The cap counts LOGICAL lines, and /history logs one per recorded event, so
## a whole report has to survive intact -- the previous cap of a dozen
## truncated every report to its own tail before it could be read.
func test_scrollback_holds_a_whole_multi_line_report():
	var before := console._log_lines.size()
	_log_report(REPORT_LINES)
	assert_eq(
		console._log_lines.size(),
		before + REPORT_LINES,
		"a %d-line /history report must survive intact" % REPORT_LINES
	)


## GUARD (green before and after): the cap was raised, not removed -- a long
## session must not grow the text buffer without bound, and the OLDEST lines
## are the ones dropped.
func test_scrollback_is_still_bounded():
	_log_report(DevConsole.MAX_LOG_LINES * 2)
	assert_eq(console._log_lines.size(), DevConsole.MAX_LOG_LINES)
	var newest: String = console._log_lines[-1]
	assert_true(
		newest.contains("evt_%d_" % (DevConsole.MAX_LOG_LINES * 2 - 1)),
		"the newest line must be kept; got '%s'" % newest
	)


## Pins the scrollback's derivation instead of leaving it an eyeballed number:
## MAX_LOG_LINES is VISIBLE_ROWS (the output viewport's real height divided by
## a real themed line height) times SCROLLBACK_SCREENS. This asserts the font
## half against the actual theme, so a theme font change is caught here rather
## than silently making the constant a fiction.
func test_visible_rows_is_derived_from_the_real_font_metrics():
	var label := console._output_label
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	assert_eq(font_size, UiTheme.BASE_FONT_SIZE, "the console uses the shared UI theme")
	var line_height := font.get_height(font_size)
	assert_almost_eq(
		float(DevConsole.LINE_HEIGHT_PX),
		line_height,
		1.0,
		"LINE_HEIGHT_PX must track the real themed line height"
	)
	assert_eq(
		DevConsole.VISIBLE_ROWS,
		int(DevConsole.OUTPUT_HEIGHT / DevConsole.LINE_HEIGHT_PX),
		"VISIBLE_ROWS is the viewport height divided by a line"
	)
	assert_eq(
		DevConsole.MAX_LOG_LINES,
		DevConsole.VISIBLE_ROWS * DevConsole.SCROLLBACK_SCREENS
	)


## The bug test_logging_scrolls_to_the_newest_line could never catch, because
## it measures the newest line against `max_value - page` -- the very number
## that goes stale. It is self-consistently green while the bottom of the log
## is physically unreachable.
##
## Measured on the real class before this was fixed: after a burst of lines the
## content stood 848 px tall while the scroll range stopped at 779. Those 69 px
## are the last three rows, and nothing could reach them -- not the scroll call,
## not the mouse wheel, because a scrollbar clamps to `max - page`. It did not
## heal, either: the container never queued another sort, so the range was
## never recomputed. The answer to "what did that command say" was sitting just
## below the floor of the box, permanently.
##
## So this asserts against the CONTENT, which is the thing that is actually
## true, rather than against the scrollbar's own idea of how tall it is.
func test_the_bottom_of_the_log_is_actually_reachable():
	_log_report(REPORT_LINES)
	await wait_process_frames(2)
	assert_gt(_content_height(), _visible_height(), "precondition: the log must overflow")
	assert_almost_eq(
		_scroll_range(),
		_content_height() - _visible_height(),
		2.0,
		"the scroll range must cover the whole log, not stop short of its last rows"
	)


## The same defect under the cadence that actually produced it: a burst of
## commands, several lines landing per frame, rather than one tidy batch.
func test_the_bottom_is_reachable_after_a_burst_spread_over_frames():
	for _batch in 12:
		_log_report(3)
		await wait_process_frames(1)
	await wait_process_frames(2)
	assert_almost_eq(
		_scroll_range(),
		_content_height() - _visible_height(),
		2.0,
		"a burst of commands must not leave its own tail out of reach"
	)


## And the payoff the whole thing exists for: after logging, the view is
## actually parked at the newest line rather than somewhere above it.
func test_the_newest_line_is_what_you_are_looking_at():
	_log_report(REPORT_LINES)
	await wait_process_frames(2)
	assert_almost_eq(
		_scroll_position(), _scroll_range(), 2.0,
		"the view must sit at the bottom of the log after logging"
	)
