extends GutTest

## The vector arithmetic under the ethogram (see docs/concept/ethogram.md §6):
## a stimulus is a feature vector, an animal is a sensitivity vector and a
## valence vector, and everything the kernel decides is a product of the
## three. Pinned on its own so the kernel's tests can be about wirings, not
## about sums.

const Affinity = preload("res://src/gameplay/affinity.gd")


# -- pull: what a thing means to this animal ---------------------------------

func test_pull_sums_feature_times_sensitivity_times_valence_over_the_named_channels():
	var features := {"decay": 1.0, "sugar": 0.5}
	var sensitivity := {"decay": 1.0, "sugar": 0.8}
	var valence := {"decay": 1.0, "sugar": 0.3}
	# decay: 1.0 * 1.0 * 1.0 = 1.0; sugar: 0.5 * 0.8 * 0.3 = 0.12
	assert_almost_eq(Affinity.pull(features, sensitivity, valence, ["decay", "sugar"]), 1.12, 0.0001)
	assert_almost_eq(Affinity.pull(features, sensitivity, valence, ["decay"]), 1.0, 0.0001)


func test_pull_defaults_to_every_feature_channel_when_none_are_named():
	var features := {"decay": 1.0, "sugar": 0.5}
	var sensitivity := {"decay": 1.0, "sugar": 0.8}
	var valence := {"decay": 1.0, "sugar": 0.3}
	assert_almost_eq(Affinity.pull(features, sensitivity, valence), 1.12, 0.0001)


## An animal with no receptor for a channel is not merely indifferent to it,
## it cannot detect it: the channel contributes exactly nothing.
func test_a_channel_the_receptor_lacks_contributes_nothing():
	var features := {"smoke": 1.0}
	assert_eq(Affinity.pull(features, {}, {"smoke": -1.0}), 0.0)
	assert_eq(Affinity.pull(features, {"smoke": 1.0}, {}), 0.0)


## Negative valence is repulsion, and it keeps its sign through the sum.
func test_negative_valence_makes_the_pull_negative():
	var features := {"decay": 1.0}
	assert_lt(Affinity.pull(features, {"decay": 0.7}, {"decay": -0.6}), 0.0)


# -- loudness: how much it notices, whether or not it cares -----------------

func test_loudness_ignores_valence():
	var features := {"decay": 1.0, "sugar": 0.5}
	var sensitivity := {"decay": 1.0, "sugar": 0.8}
	# decay 1.0 + sugar 0.4
	assert_almost_eq(Affinity.loudness(features, sensitivity), 1.4, 0.0001)
	assert_almost_eq(Affinity.loudness(features, sensitivity, ["sugar"]), 0.4, 0.0001)


# -- proximity: a ranking, not physics ---------------------------------------

func test_proximity_is_one_at_the_source_and_falls_but_never_reaches_zero():
	assert_almost_eq(Affinity.proximity(0.0), 1.0, 0.0001)
	assert_lt(Affinity.proximity(10.0), 1.0)
	assert_gt(Affinity.proximity(100000.0), 0.0, "a reported stimulus is never silently dropped")


func test_proximity_is_strictly_decreasing():
	var previous := Affinity.proximity(0.0)
	for step in range(1, 40):
		var now := Affinity.proximity(float(step) * 25.0)
		assert_lt(now, previous, "step %d" % step)
		previous = now


# -- headings ----------------------------------------------------------------

func test_toward_and_away_are_unit_opposites():
	var toward := Affinity.toward(Vector2.ZERO, Vector2(30, 40))
	var away := Affinity.away_from(Vector2.ZERO, Vector2(30, 40))
	assert_almost_eq(toward.length(), 1.0, 0.0001)
	assert_almost_eq(toward.x, 0.6, 0.0001)
	assert_almost_eq(toward.y, 0.8, 0.0001)
	assert_almost_eq((toward + away).length(), 0.0, 0.0001)


## A creature standing exactly on its threat still has to go SOMEWHERE --
## CreatureBehavior's own OVERLAP_FALLBACK, kept here.
func test_overlapping_the_target_still_yields_a_nonzero_direction():
	assert_gt(Affinity.toward(Vector2(5, 5), Vector2(5, 5)).length(), 0.5)
	assert_gt(Affinity.away_from(Vector2(5, 5), Vector2(5, 5)).length(), 0.5)
	assert_eq(Affinity.away_from(Vector2(5, 5), Vector2(5, 5)), Affinity.OVERLAP_FALLBACK)
