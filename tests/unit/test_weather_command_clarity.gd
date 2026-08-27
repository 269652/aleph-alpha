extends GutTest

## `/weather off` means "stop PINNING the weather, go back to the real cycle"
## -- it does not, and should not, mean "make it stop raining". Both readings
## are natural, and the wrong one was actually reached during a play session
## (2026-08-26): the console said "Weather back to its own devices." while the
## HUD went on showing Autumn - Rain, and the honest conclusion at the time was
## that the command was broken. It was not. Nothing had been pinned, so
## clearing the pin correctly changed nothing, and real autumn weather carried
## on being real autumn weather.
##
## The command is right; the message is what misleads, because it reports a
## state change that did not happen. So the fix is in what it SAYS: when
## nothing was pinned, say nothing was pinned.
##
## Pinned from source text rather than by driving a real World node (which
## needs a full chunk manager, see test_earth_chunk_manager.gd's runtime), the
## same shape as test_world_backup_paths.gd.

const WeatherModel = preload("res://src/world/weather_model.gd")


func _weather_command_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _handle_weather_command(")
	assert_gt(start, -1, "World._handle_weather_command should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


## The "off" branch has to distinguish the two cases before it reports one.
func test_turning_weather_off_checks_whether_it_was_ever_pinned():
	var body := _weather_command_body()
	var off_branch := body.find("\"off\"")
	assert_gt(off_branch, -1, "the weather command should still handle 'off'")
	var clear_call := body.find("clear_forced_weather()")
	assert_gt(clear_call, -1, "the off branch should still clear the pin")
	assert_string_contains(body, "is_weather_forced()")


## The wording that caused the confusion: reporting a change when none
## happened. A no-op must not read like an effect.
func test_the_off_message_does_not_claim_a_change_that_did_not_happen():
	var body := _weather_command_body()
	var was_not_pinned := body.find("was not pinned")
	assert_gt(
		was_not_pinned, -1,
		"the off branch should say so when there was nothing pinned to clear"
	)


## The real cycle is still the authority -- "off" must never reach into the
## weather model to set a state, only to stop overriding one.
func test_turning_weather_off_does_not_force_a_state():
	var body := _weather_command_body()
	var off_index := body.find("\"off\"")
	var tail := body.substr(off_index, body.find("return", off_index) - off_index)
	assert_false(
		tail.contains("force_weather("),
		"'off' must clear the override, never set one"
	)


## Guards the doc claim the message leans on: WeatherModel really does own a
## set of natural states that the cycle picks from, so "its own devices" is a
## real thing to hand control back to.
func test_the_weather_model_has_real_states_to_return_to():
	assert_gt(WeatherModel.STATES.size(), 1)


## The subtle half, and a bug in the first version of this fix: the branch that
## DID release a pin has to read the sky AFTER releasing it.
##
## `here` is computed once at the top of the handler, while the pin is still in
## force -- and `current_weather` returns the pinned state first, by design. So
## quoting that variable in the "released" message reports the state that was
## just deleted: `/weather rain` then `/weather off` announced "back to its own
## devices: rain here now" while the natural roll was, three times in four,
## something else. The one branch that most needs an honest reading of the sky
## was reporting the override.
func test_the_released_message_reads_the_sky_after_clearing_the_pin():
	var body := _weather_command_body()
	var clear_call := body.find("clear_forced_weather()")
	assert_gt(clear_call, -1, "the off branch should still clear the pin")
	var after := body.substr(clear_call, body.length() - clear_call)
	assert_string_contains(
		after, "current_weather(",
		"the released message must re-read the weather after the pin is gone"
	)
