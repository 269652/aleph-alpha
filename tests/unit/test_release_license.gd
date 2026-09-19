extends GutTest

## Whether a `license.txt` may be BUNDLED INTO a release package (see
## docs/licensing.md, "Bundling a license with a release", and
## tools/release/build_release.ps1's packaging step).
##
## Asked for directly: *"make it so that the license.txt is included in the
## release if it's still valid at the time of build"*. "Still valid" is
## SerialVerifier's own answer -- signature against a known key, and not
## past its expiry -- so this never re-implements verification. What it
## adds is the packaging policy on top of that answer, which is the part
## with real consequences: a release is published once and downloaded by
## people, so bundling the wrong serial is not something a later patch
## takes back.

const ReleaseLicense = preload("res://src/licensing/release_license.gd")

const _DAY := 86400
## An arbitrary fixed "now" -- 2026-09-18, the day this was written. Nothing
## depends on the real clock.
const _NOW := 1789689600


func _verdict(overrides: Dictionary = {}) -> Dictionary:
	var verdict := {
		"valid": true, "product_mask": 1, "license_id": 2,
		"expiry_unix": 0, "github_user_id": 0, "reason": "",
	}
	verdict.merge(overrides, true)
	return verdict


# -- the rule that was asked for -------------------------------------------

func test_a_perpetual_license_is_bundled():
	var decision := ReleaseLicense.bundle_decision("SOME-CODE", _verdict(), _NOW)
	assert_true(decision.bundle)
	assert_eq(decision.expires_in_days, -1, "a perpetual license never counts down")


func test_a_license_that_outlives_the_build_is_bundled():
	var decision := ReleaseLicense.bundle_decision(
		"SOME-CODE", _verdict({"expiry_unix": _NOW + 200 * _DAY}), _NOW
	)
	assert_true(decision.bundle)
	assert_eq(decision.expires_in_days, 200)


func test_a_license_that_is_not_valid_at_build_time_is_not_bundled():
	var decision := ReleaseLicense.bundle_decision(
		"SOME-CODE", _verdict({"valid": false, "reason": "expired"}), _NOW
	)
	assert_false(decision.bundle)
	assert_string_contains(decision.reason, "expired")


func test_no_license_file_is_not_an_error_it_is_simply_nothing_to_bundle():
	var decision := ReleaseLicense.bundle_decision("", _verdict(), _NOW)
	assert_false(decision.bundle)
	assert_string_contains(decision.reason, "no license")


# -- what the build must refuse even though it IS valid --------------------

## docs/licensing.md's own issued-serials table marks license_id 1 -- every
## product bit set, never expires -- as "Owner/developer key, local testing
## only. Not for distribution." It is the most valid license in existence
## and the single worst one to ship, and the folder the packaging step
## reads from is exactly where a developer's own testing copy lives (see
## build_release.ps1's existing note). Same defence-in-depth shape as
## Assert-NoPrivateKeyAmong: refuse it in code, not in a habit.
func test_the_owner_key_is_refused_however_valid_it_is():
	var decision := ReleaseLicense.bundle_decision(
		"SOME-CODE", _verdict({"product_mask": ReleaseLicense.OWNER_PRODUCT_MASK}), _NOW
	)
	assert_false(decision.bundle)
	assert_string_contains(decision.reason, "owner")


func test_a_normal_product_mask_is_not_mistaken_for_the_owner_key():
	for mask in [1, 3, 0xFFFF, 0x7FFFFFFFFFFFFFFF]:
		var decision := ReleaseLicense.bundle_decision(
			"SOME-CODE", _verdict({"product_mask": mask}), _NOW
		)
		assert_true(decision.bundle, "mask %d is a real product grant, not the owner key" % mask)


# -- expiring soon still ships, but never quietly --------------------------

## A license that is valid today and gone next week produces a release that
## stops working for whoever downloads it, days after it was published, with
## nothing in the build output that said so. It still ships -- it IS valid,
## which is the rule that was asked for -- but the build has to say it out
## loud.
func test_a_license_expiring_soon_still_ships_but_is_flagged():
	var decision := ReleaseLicense.bundle_decision(
		"SOME-CODE", _verdict({"expiry_unix": _NOW + 3 * _DAY}), _NOW
	)
	assert_true(decision.bundle)
	assert_true(decision.warn, "three days left is worth saying out loud")


func test_a_license_with_plenty_of_life_left_is_not_flagged():
	var decision := ReleaseLicense.bundle_decision(
		"SOME-CODE",
		_verdict({"expiry_unix": _NOW + (ReleaseLicense.EXPIRY_WARNING_DAYS + 1) * _DAY}),
		_NOW
	)
	assert_true(decision.bundle)
	assert_false(decision.warn)


func test_a_perpetual_license_is_never_flagged_as_expiring():
	assert_false(ReleaseLicense.bundle_decision("SOME-CODE", _verdict(), _NOW).warn)


## The threshold is a tuned value, so it is pinned here rather than left as
## a number in a comment: a month is long enough that a release published
## today is still usable through an ordinary patch cycle.
func test_the_warning_window_is_a_month():
	assert_eq(ReleaseLicense.EXPIRY_WARNING_DAYS, 30)


# -- what the build prints -------------------------------------------------

## The build log is a DEVELOPER surface, so unlike the player-facing gate it
## may name the reason (docs/licensing.md's "generic failure message" rule
## is about not handing a keygen author a debugging oracle -- your own
## release console is not that).
func test_the_report_line_names_the_license_and_its_expiry():
	var line := ReleaseLicense.report_line(
		ReleaseLicense.bundle_decision("SOME-CODE", _verdict({"expiry_unix": _NOW + 200 * _DAY}), _NOW)
	)
	assert_string_contains(line, "200")
	assert_string_contains(line.to_lower(), "bundl")


func test_the_report_line_says_why_nothing_was_bundled():
	var line := ReleaseLicense.report_line(
		ReleaseLicense.bundle_decision("", _verdict(), _NOW)
	)
	assert_string_contains(line.to_lower(), "no license")
