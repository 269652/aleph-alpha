extends GutTest

## BackToTheFutureDay (docs/concept/easter_eggs.md's calendar-gated cameo):
## fires only on the REAL system calendar date of October 21st -- Time.
## get_datetime_dict_from_system(), NOT this game's own fictional
## SeasonCycle clock, which is a completely different calendar (see the
## module's own doc comment). Same "caller supplies the already-computed
## real value, module only decides" shape as KrakenTrigger/
## EasterEggSightings -- these tests exercise is_today as a pure function of
## (month, day), no Time singleton involved, so the suite stays exact and
## deterministic regardless of what day it's actually run on.
##
## Pillar 4 (homage over reproduction): the cameo is description-only, no
## trademarked name anywhere -- cameo_message()'s own test enforces that
## automatically rather than leaving it as an unverified comment.

const BackToTheFutureDay = preload("res://src/gameplay/back_to_the_future_day.gd")

var cameo: BackToTheFutureDay


func before_each():
	cameo = BackToTheFutureDay.new()


func test_is_today_true_on_october_21st():
	assert_true(cameo.is_today(10, 21))


func test_is_today_false_the_day_before():
	assert_false(cameo.is_today(10, 20))


func test_is_today_false_the_day_after():
	assert_false(cameo.is_today(10, 22))


func test_is_today_false_on_the_same_day_of_a_different_month():
	assert_false(cameo.is_today(1, 21))


func test_is_today_false_on_an_unrelated_date():
	assert_false(cameo.is_today(7, 4))


func test_cameo_message_is_a_real_nonempty_line():
	assert_true(cameo.cameo_message().length() > 0)


## No trademarked name anywhere in the flavor text (pillar 4) -- checked
## automatically rather than left to a comment.
func test_cameo_message_never_names_the_trademarked_car():
	var message: String = cameo.cameo_message().to_lower()
	assert_false(message.contains("delorean"))
