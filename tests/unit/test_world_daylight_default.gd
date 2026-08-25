extends GutTest

## What sky the world is lit by, and how the dev console pins one.
##
## There is deliberately no build-type default any more. `always_day_for` used
## to end in `return is_debug`, so every editor/debug run was sun-at-zenith --
## elevation 90 at two in the morning -- and nobody developing the game ever
## saw the night the shipped build has. `/day`, `/night` and `/time <hh:mm>`
## put a chosen sky one keystroke away, which is what that default was really
## providing. See World.always_day_for / forced_elevation_for /
## clock_hour_for_console_argument.

const World = preload("res://scenes/world.gd")


# -- which sky ---------------------------------------------------------------

## The bug this file used to pin, inverted: a debug build now runs the same
## real UTC day/night cycle the shipped game does.
func test_a_debug_build_now_runs_the_real_day_night_cycle():
	assert_false(World.always_day_for(false, ""))


func test_env_one_still_forces_day():
	assert_true(World.always_day_for(false, "1"))


## "0" used to be the one escape from the permanent-noon default. With no
## default left there is nothing to opt out of, so it means what an unset
## variable means.
func test_env_zero_is_now_the_same_as_no_override():
	assert_eq(World.always_day_for(false, "0"), World.always_day_for(false, ""))
	assert_false(World.always_day_for(false, "0"))


func test_the_live_console_toggle_still_forces_day():
	assert_true(World.always_day_for(true, "0"))


# -- the elevation the world is actually lit by -------------------------------

func test_night_pins_the_sun_below_the_horizon():
	assert_lt(World.forced_elevation_for("night", "", 42.0), 0.0)


func test_day_pins_the_sun_overhead():
	assert_eq(World.forced_elevation_for("day", "", -42.0), World.ALWAYS_DAY_ELEVATION)


func test_an_unpinned_sky_uses_the_real_elevation():
	assert_almost_eq(World.forced_elevation_for("", "", -7.5), -7.5, 0.0001)


## /night beats a stale AA_DEBUG_ALWAYS_DAY=1 in the environment: whoever is
## typing at the console now is more current than whoever set the variable at
## launch. One function decides, so /day and /night can never disagree.
func test_a_pinned_night_wins_over_the_env_var():
	assert_lt(World.forced_elevation_for("night", "1", 42.0), 0.0)


# -- /time <hh:mm> ------------------------------------------------------------

func test_a_clock_argument_accepts_hours_and_minutes():
	assert_almost_eq(World.clock_hour_for_console_argument("22:30"), 22.5, 0.0001)


func test_a_bare_hour_is_on_the_hour():
	assert_almost_eq(World.clock_hour_for_console_argument("6"), 6.0, 0.0001)
	assert_almost_eq(World.clock_hour_for_console_argument("0"), 0.0, 0.0001)


func test_a_nonsense_clock_argument_is_rejected():
	assert_eq(World.clock_hour_for_console_argument("teatime"), World.NO_FORCED_HOUR)
	assert_eq(World.clock_hour_for_console_argument("12:ish"), World.NO_FORCED_HOUR)
	assert_eq(World.clock_hour_for_console_argument("1:2:3"), World.NO_FORCED_HOUR)
	assert_eq(World.clock_hour_for_console_argument(""), World.NO_FORCED_HOUR)


func test_an_out_of_range_clock_argument_is_rejected():
	assert_eq(World.clock_hour_for_console_argument("24:00"), World.NO_FORCED_HOUR)
	assert_eq(World.clock_hour_for_console_argument("-1"), World.NO_FORCED_HOUR)
	assert_eq(World.clock_hour_for_console_argument("12:60"), World.NO_FORCED_HOUR)


## One word clears any of the three pins.
func test_off_is_recognised_for_any_of_the_three_commands():
	assert_true(World.is_off_argument(["off"]))
	assert_true(World.is_off_argument(["OFF"]))
	assert_false(World.is_off_argument([]))
	assert_false(World.is_off_argument(["22:30"]))


## `/ecotest off` is a durable return to real-time ecology.  In particular,
## no diagnostic update may silently restore the fast-forward scale afterwards.
func test_ecotest_off_keeps_normal_ecology_scale():
	assert_eq(World.ecology_scale_for_console_argument(15360.0, "off"), 1.0)
