extends GutTest

## Tests for condition-gated animal reproduction (bioenergetics).
## Pure, stateless helpers operating on passed-in values.

var Repro = preload("res://src/gameplay/animal_reproduction.gd")


func test_max_energy_is_unit_scale() -> void:
	assert_eq(Repro.MAX_ENERGY, 1.0, "energy is on a 0..1 unit scale")


# --- decay: basal metabolic decline, clamped >= 0 ---

func test_decay_reduces_energy_over_time() -> void:
	var after = Repro.decay(1.0, 1.0)
	assert_lt(after, 1.0, "decay lowers energy")
	assert_almost_eq(after, 1.0 - Repro.DECAY_RATE_PER_SECOND, 0.0001, "decay is rate*delta")


func test_decay_scales_with_delta() -> void:
	assert_almost_eq(
		Repro.decay(1.0, 2.0),
		1.0 - Repro.DECAY_RATE_PER_SECOND * 2.0,
		0.0001,
		"decay scales linearly with delta")


func test_decay_clamps_at_zero() -> void:
	assert_eq(Repro.decay(0.0, 1000.0), 0.0, "energy never goes negative")


# --- feed: eating raises energy, clamped <= MAX_ENERGY ---

func test_feed_raises_energy() -> void:
	assert_almost_eq(Repro.feed(0.2, 0.3), 0.5, 0.0001, "feed adds amount")


func test_feed_clamps_at_max() -> void:
	assert_eq(Repro.feed(0.9, 5.0), Repro.MAX_ENERGY, "energy never exceeds MAX_ENERGY")


# --- can_reproduce: all three gates ---

func test_can_reproduce_when_all_conditions_met() -> void:
	assert_true(Repro.can_reproduce(
		Repro.REPRO_ENERGY_THRESHOLD,
		Repro.REPRO_HEALTH_THRESHOLD,
		Repro.REPRO_COOLDOWN),
		"true at exact boundaries of all three gates")


func test_cannot_reproduce_below_energy_threshold() -> void:
	assert_false(Repro.can_reproduce(
		Repro.REPRO_ENERGY_THRESHOLD - 0.01,
		1.0,
		Repro.REPRO_COOLDOWN + 10.0),
		"energy just below threshold blocks reproduction")


func test_cannot_reproduce_below_health_threshold() -> void:
	assert_false(Repro.can_reproduce(
		1.0,
		Repro.REPRO_HEALTH_THRESHOLD - 0.01,
		Repro.REPRO_COOLDOWN + 10.0),
		"health just below threshold blocks reproduction")


func test_cannot_reproduce_before_cooldown() -> void:
	assert_false(Repro.can_reproduce(
		1.0,
		1.0,
		Repro.REPRO_COOLDOWN - 0.01),
		"still within refractory cooldown blocks reproduction")


func test_can_reproduce_well_above_all_thresholds() -> void:
	assert_true(Repro.can_reproduce(1.0, 1.0, Repro.REPRO_COOLDOWN * 2.0),
		"comfortably above every gate reproduces")


# --- birth energy cost: drops energy below threshold so it cannot re-fire ---

func test_birth_energy_cost_is_positive() -> void:
	assert_gt(Repro.birth_energy_cost(), 0.0, "reproduction costs energy")


func test_energy_after_birth_subtracts_cost() -> void:
	assert_almost_eq(
		Repro.energy_after_birth(1.0),
		1.0 - Repro.birth_energy_cost(),
		0.0001,
		"birth pays the cost")


func test_energy_after_birth_drops_below_threshold_from_max() -> void:
	assert_lt(Repro.energy_after_birth(Repro.MAX_ENERGY), Repro.REPRO_ENERGY_THRESHOLD,
		"even at max energy, birth drops below the repro threshold so it cannot immediately re-fire")


func test_energy_after_birth_clamps_at_zero() -> void:
	assert_eq(Repro.energy_after_birth(0.0), 0.0, "energy never goes negative after birth")


## Requested: "reproduction should take at least 1 real day (24h)". At the
## previous 30 seconds a fed animal bred twice a minute -- which only ever
## looked acceptable because the ecology simulation was never running (see
## World.owns_ecosystem_simulation_for); once it did, a clearing filled with
## deer within a minute of play.
func test_an_animal_cannot_breed_twice_within_a_real_day():
	assert_gte(Repro.REPRO_COOLDOWN, 24.0 * 60.0 * 60.0)


func test_a_well_fed_healthy_animal_still_waits_out_the_cooldown():
	var almost: float = Repro.REPRO_COOLDOWN - 1.0
	assert_false(
		Repro.can_reproduce(1.0, 1.0, almost),
		"perfect condition does not shorten the wait"
	)
	assert_true(Repro.can_reproduce(1.0, 1.0, Repro.REPRO_COOLDOWN))
