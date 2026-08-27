extends GutTest

## Unloaded-chunk ecology catch-up integration (variable-fidelity LOD).
## See docs/concept/ecosystem_dynamics.md -- Population dynamics + Variable-fidelity.

const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")

var catchup: ChunkEcologyCatchup


func before_each():
	catchup = ChunkEcologyCatchup.new()


func _state(
	herbivores: float, predators: float, fruit_stock: float, vegetation: float, fish: float = 0.0,
	robins: float = 0.0, sparrows: float = 0.0, kingfishers: float = 0.0
) -> Dictionary:
	return {
		"herbivores": herbivores,
		"predators": predators,
		"fruit_stock": fruit_stock,
		"vegetation": vegetation,
		"fish": fish,
		"robins": robins,
		"sparrows": sparrows,
		"kingfishers": kingfishers,
	}


func _capacity(
	herbivore_capacity: float, fruit_growth_rate: float, fish_capacity: float = 0.0,
	robin_capacity: float = 0.0, sparrow_capacity: float = 0.0
) -> Dictionary:
	return {
		"herbivore_capacity": herbivore_capacity,
		"fruit_growth_rate": fruit_growth_rate,
		"fish_capacity": fish_capacity,
		"robin_capacity": robin_capacity,
		"sparrow_capacity": sparrow_capacity,
	}


func test_zero_elapsed_returns_unchanged_state():
	var start := _state(5.0, 1.0, 2.0, 0.5)
	var out := catchup.advance(start, 0.0, _capacity(20.0, 0.1))
	assert_almost_eq(out["herbivores"], 5.0, 0.0001)
	assert_almost_eq(out["predators"], 1.0, 0.0001)
	assert_almost_eq(out["fruit_stock"], 2.0, 0.0001)
	assert_almost_eq(out["vegetation"], 0.5, 0.0001)


func test_is_pure_does_not_mutate_input():
	var start := _state(5.0, 1.0, 2.0, 0.5)
	catchup.advance(start, 100000.0, _capacity(20.0, 0.1))
	assert_almost_eq(start["herbivores"], 5.0, 0.0001)
	assert_almost_eq(start["vegetation"], 0.5, 0.0001)


func test_deterministic():
	var start := _state(5.0, 1.0, 2.0, 0.5)
	var a := catchup.advance(start, 12345.0, _capacity(20.0, 0.1))
	var b := catchup.advance(start, 12345.0, _capacity(20.0, 0.1))
	assert_eq(a, b)


func test_small_herbivore_pop_grows_toward_but_not_past_capacity():
	var start := _state(1.0, 0.0, 0.0, 1.0)
	var cap := _capacity(20.0, 0.0)
	var out := catchup.advance(start, 100000.0, cap)
	assert_gt(out["herbivores"], 1.0, "herbivores should grow")
	assert_lte(out["herbivores"], 20.0, "logistic must not overshoot capacity")


func test_herbivore_growth_is_logistic_no_overshoot_repeated():
	var s := _state(1.0, 0.0, 0.0, 1.0)
	var cap := _capacity(20.0, 0.0)
	for i in 200:
		s = catchup.advance(s, 100000.0, cap)
		assert_lte(s["herbivores"], 20.0001, "never overshoots capacity")
	assert_gt(s["herbivores"], 19.0, "eventually approaches capacity")


func test_predators_rise_when_herbivores_abundant():
	# Abundant prey -> predator capacity high -> predators grow.
	var start := _state(1000.0, 1.0, 0.0, 1.0)
	var out := catchup.advance(start, 100000.0, _capacity(2000.0, 0.0))
	assert_gt(out["predators"], 1.0, "predators should rise with abundant prey")


func test_predators_fall_when_herbivores_scarce():
	# Predators above what scarce prey can sustain -> decline.
	var start := _state(1.0, 50.0, 0.0, 1.0)
	var out := catchup.advance(start, 100000.0, _capacity(20.0, 0.0))
	assert_lt(out["predators"], 50.0, "predators should fall when prey is scarce")


func test_fruit_stock_increases_with_elapsed():
	var short := catchup.advance(_state(0.0, 0.0, 0.0, 1.0), 100.0, _capacity(20.0, 0.5))
	var long := catchup.advance(_state(0.0, 0.0, 0.0, 1.0), 500.0, _capacity(20.0, 0.5))
	assert_gt(short["fruit_stock"], 0.0)
	assert_gt(long["fruit_stock"], short["fruit_stock"])


func test_fruit_stock_stays_bounded():
	var out := catchup.advance(_state(0.0, 0.0, 0.0, 1.0), 1.0e12, _capacity(20.0, 100.0))
	assert_lte(out["fruit_stock"], ChunkEcologyCatchup.FRUIT_STOCK_MAX + 0.0001)


func test_vegetation_monotonically_approaches_one():
	var v := 0.1
	var s := _state(0.0, 0.0, 0.0, v)
	for i in 50:
		var out := catchup.advance(s, 5000.0, _capacity(20.0, 0.0))
		assert_gte(out["vegetation"], s["vegetation"] - 0.0001, "monotone non-decreasing")
		assert_lte(out["vegetation"], 1.0001, "never exceeds 1.0")
		s = out
	assert_gt(s["vegetation"], 0.9, "eventually near full regrowth")


func test_vegetation_does_not_overshoot_one():
	var out := catchup.advance(_state(0.0, 0.0, 0.0, 0.99), 1.0e12, _capacity(20.0, 0.0))
	assert_lte(out["vegetation"], 1.0001)
	assert_gte(out["vegetation"], 0.99)


## See docs/concept/fishing.md#unloaded-chunk-catch-up.

func test_fish_population_included_in_zero_elapsed_unchanged_state():
	var start := _state(5.0, 1.0, 2.0, 0.5, 3.0)
	var out := catchup.advance(start, 0.0, _capacity(20.0, 0.1, 20.0))
	assert_almost_eq(out["fish"], 3.0, 0.0001)


func test_small_fish_pop_grows_toward_but_not_past_capacity():
	var start := _state(1.0, 0.0, 0.0, 1.0, 1.0)
	var cap := _capacity(20.0, 0.0, 20.0)
	var out := catchup.advance(start, 100000.0, cap)
	assert_gt(out["fish"], 1.0, "fish should grow")
	assert_lte(out["fish"], 20.0, "logistic must not overshoot capacity")


func test_fish_growth_is_logistic_no_overshoot_repeated():
	var s := _state(1.0, 0.0, 0.0, 1.0, 1.0)
	var cap := _capacity(20.0, 0.0, 20.0)
	for i in 200:
		s = catchup.advance(s, 100000.0, cap)
		assert_lte(s["fish"], 20.0001, "never overshoots capacity")
	assert_gt(s["fish"], 19.0, "eventually approaches capacity")


## See docs/concept/world.md "Land health: overharvesting leaves a lasting
## mark, not just a slower respawn" -- land health must keep recovering
## while a chunk is UNLOADED (nothing is harvesting it while nobody is
## there), the same "the world moved on while you were away" principle
## already applied to herbivores/predators/fish/vegetation above. It must
## NOT silently reset to pristine on every reload, the way some earlier
## patch-sims are documented as not persisting -- persistence itself is
## EarthChunkManager's job (see ChunkSerializer/land_health round-trip
## tests); this only has to carry the value through unchanged at zero
## elapsed, and recover it (never harvest it down) over elapsed time.

func test_land_health_included_in_zero_elapsed_unchanged_state():
	var start := {
		"herbivores": 5.0, "predators": 1.0, "fruit_stock": 2.0, "vegetation": 0.5,
		"fish": 3.0, "land_health": 0.4,
	}
	var out := catchup.advance(start, 0.0, _capacity(20.0, 0.1, 20.0))
	assert_almost_eq(out["land_health"], 0.4, 0.0001)


func test_land_health_recovers_over_elapsed_unloaded_time():
	var start := {
		"herbivores": 5.0, "predators": 1.0, "fruit_stock": 2.0, "vegetation": 0.5,
		"fish": 3.0, "land_health": 0.3,
	}
	var out := catchup.advance(start, 1.0e9, _capacity(20.0, 0.1, 20.0))
	assert_gt(out["land_health"], 0.3, "land health should recover while nobody is harvesting it")


func test_land_health_never_exceeds_one_even_with_huge_elapsed_time():
	var start := {
		"herbivores": 5.0, "predators": 1.0, "fruit_stock": 2.0, "vegetation": 0.5,
		"fish": 3.0, "land_health": 0.99,
	}
	var out := catchup.advance(start, 1.0e12, _capacity(20.0, 0.1, 20.0))
	assert_almost_eq(out["land_health"], 1.0, 0.0001)


## A state dict from before this field existed (e.g. an in-session
## `_unloaded_ecology` record from an older running instance) defaults to
## pristine rather than crashing on a missing key.
func test_land_health_defaults_to_pristine_when_absent_from_state():
	var start := _state(5.0, 1.0, 2.0, 0.5)
	var out := catchup.advance(start, 1.0, _capacity(20.0, 0.1))
	assert_almost_eq(out["land_health"], 1.0, 0.0001)


## Robin/sparrow/kingfisher parity with herbivore/predator/fish (docs/concept/
## ecosystem_dynamics.md's "Persistence/catch-up gap, robin/sparrow/kingfisher"
## -- now resolved). Robin/sparrow use the SAME shape as fish: an independent
## carrying capacity supplied via the `capacity` dict (worm/seed density lives
## outside this pure function, same reason fish_capacity is an input rather
## than derived). Kingfisher instead mirrors PREDATOR: its capacity is derived
## INSIDE advance() from the freshly-advanced fish population, the same
## "post-step prey level" ordering predator_capacity already uses for
## herbivores.

func test_bird_populations_included_in_zero_elapsed_unchanged_state():
	var start := _state(5.0, 1.0, 2.0, 0.5, 3.0, 2.0, 4.0, 0.5)
	var out := catchup.advance(start, 0.0, _capacity(20.0, 0.1, 20.0, 10.0, 40.0))
	assert_almost_eq(out["robins"], 2.0, 0.0001)
	assert_almost_eq(out["sparrows"], 4.0, 0.0001)
	assert_almost_eq(out["kingfishers"], 0.5, 0.0001)


func test_small_robin_pop_grows_toward_but_not_past_capacity():
	var start := _state(1.0, 0.0, 0.0, 1.0, 1.0, 1.0)
	var cap := _capacity(20.0, 0.0, 20.0, 20.0)
	var out := catchup.advance(start, 100000.0, cap)
	assert_gt(out["robins"], 1.0, "robins should grow")
	assert_lte(out["robins"], 20.0, "logistic must not overshoot capacity")


func test_robin_growth_is_logistic_no_overshoot_repeated():
	var s := _state(1.0, 0.0, 0.0, 1.0, 1.0, 1.0)
	var cap := _capacity(20.0, 0.0, 20.0, 20.0)
	for i in 200:
		s = catchup.advance(s, 100000.0, cap)
		assert_lte(s["robins"], 20.0001, "never overshoots capacity")
	assert_gt(s["robins"], 19.0, "eventually approaches capacity")


func test_small_sparrow_pop_grows_toward_but_not_past_capacity():
	var start := _state(1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
	var cap := _capacity(20.0, 0.0, 20.0, 0.0, 20.0)
	var out := catchup.advance(start, 100000.0, cap)
	assert_gt(out["sparrows"], 1.0, "sparrows should grow")
	assert_lte(out["sparrows"], 20.0, "logistic must not overshoot capacity")


func test_sparrow_growth_is_logistic_no_overshoot_repeated():
	var s := _state(1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
	var cap := _capacity(20.0, 0.0, 20.0, 0.0, 20.0)
	for i in 200:
		s = catchup.advance(s, 100000.0, cap)
		assert_lte(s["sparrows"], 20.0001, "never overshoots capacity")
	assert_gt(s["sparrows"], 19.0, "eventually approaches capacity")


func test_kingfishers_rise_when_fish_abundant():
	# Abundant fish -> new_fish stays high -> kingfisher capacity (derived
	# from new_fish, mirroring predator's derivation from new_herbivores) is
	# high -> kingfishers grow. Mirrors test_predators_rise_when_herbivores_abundant.
	var start := _state(0.0, 0.0, 0.0, 1.0, 1000.0, 0.0, 0.0, 1.0)
	var out := catchup.advance(start, 100000.0, _capacity(0.0, 0.0, 2000.0))
	assert_gt(out["kingfishers"], 1.0, "kingfishers should rise with abundant fish")


func test_kingfishers_fall_when_fish_scarce():
	# Mirrors test_predators_fall_when_herbivores_scarce.
	var start := _state(0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 50.0)
	var out := catchup.advance(start, 100000.0, _capacity(0.0, 0.0, 20.0))
	assert_lt(out["kingfishers"], 50.0, "kingfishers should fall when fish is scarce")


## A state dict from before robin/sparrow/kingfisher existed (an in-session
## `_unloaded_ecology` record, or a pre-upgrade save) defaults all three to
## 0.0 rather than crashing on a missing key -- same convention as land_health
## defaulting to pristine when absent.
func test_bird_populations_default_to_zero_when_absent_from_state():
	var start := {
		"herbivores": 5.0, "predators": 1.0, "fruit_stock": 2.0, "vegetation": 0.5,
	}
	var out := catchup.advance(start, 1.0, _capacity(20.0, 0.1))
	assert_almost_eq(out["robins"], 0.0, 0.0001)
	assert_almost_eq(out["sparrows"], 0.0, 0.0001)
	assert_almost_eq(out["kingfishers"], 0.0, 0.0001)
