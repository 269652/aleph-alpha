extends GutTest

## Pins the dev-time lighting default: during development we want full day
## without waiting on real-world night, but an exported build must still
## follow real UTC-driven day/night. See World.always_day_for.

const World = preload("res://scenes/world.gd")


func test_debug_builds_default_to_full_day_with_no_env_override():
	assert_true(World.always_day_for(false, "", true))


func test_release_builds_still_follow_real_utc_day_night():
	assert_false(World.always_day_for(false, "", false))


func test_env_zero_opts_a_debug_build_back_into_real_day_night():
	assert_false(World.always_day_for(false, "0", true))


func test_env_one_forces_day_even_in_a_release_build():
	assert_true(World.always_day_for(false, "1", false))


func test_live_console_toggle_forces_day_regardless_of_build_or_env():
	assert_true(World.always_day_for(true, "0", false))
