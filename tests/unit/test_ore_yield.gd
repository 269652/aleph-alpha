extends GutTest

const OreYield = preload("res://src/gameplay/ore_yield.gd")

var oy: OreYield


func before_each():
	oy = OreYield.new()


func _total_of(drops: Array, item_id: String) -> int:
	var total := 0
	for d in drops:
		if d.item_id == item_id:
			total += d.count
	return total


func test_bare_hands_yield_only_stone_no_ore():
	var drops := oy.yields("iron", 0.0, 123)
	assert_gt(_total_of(drops, "stone"), 0, "should still get some stone")
	assert_eq(_total_of(drops, "iron_ore"), 0, "bare hands yield no ore")


func test_pickaxe_yields_ore_item_for_type():
	var drops := oy.yields("iron", 2.0, 123)
	assert_gt(_total_of(drops, "iron_ore"), 0)


func test_copper_yields_copper_ore():
	var drops := oy.yields("copper", 2.0, 55)
	assert_gt(_total_of(drops, "copper_ore"), 0)
	assert_eq(_total_of(drops, "iron_ore"), 0)


func test_coal_yields_coal_item():
	var drops := oy.yields("coal", 2.0, 55)
	assert_gt(_total_of(drops, "coal"), 0)


func test_always_yields_some_stone():
	var drops := oy.yields("iron", 3.0, 7)
	assert_gt(_total_of(drops, "stone"), 0)


func test_deterministic_per_seed():
	var a := oy.yields("iron", 2.0, 999)
	var b := oy.yields("iron", 2.0, 999)
	assert_eq(a, b)


func test_higher_power_yields_more_ore_on_average():
	var low := 0
	var high := 0
	for s in range(0, 60):
		low += _total_of(oy.yields("iron", 1.0, s), "iron_ore")
		high += _total_of(oy.yields("iron", 4.0, s), "iron_ore")
	assert_gt(high, low, "stronger pickaxe should net more ore overall")


func test_ore_count_respects_max_scaling_constant():
	# Ore count is bounded by BASE_ORE + power scaling. Pin the ceiling.
	for s in range(0, 200):
		var drops := oy.yields("iron", 3.0, s)
		var n := _total_of(drops, "iron_ore")
		assert_between(
			n,
			1,
			OreYield.BASE_ORE + int(ceil(3.0 * OreYield.ORE_PER_POWER)),
			"ore count out of pinned range at seed %d" % s
		)


func test_stone_count_is_pinned_constant():
	var drops := oy.yields("iron", 2.0, 1)
	assert_eq(_total_of(drops, "stone"), OreYield.STONE_PER_MINE)


# --- Luck (see docs/concept/karma_and_luck.md) ------------------------------
#
# Luck nudges the existing extra-ore roll's own position within its already-
# tuned [0, span] range, never the guaranteed base yield -- bad luck can only
# make BONUS ore rarer, never take away the ore a swing already earned.


## At zero luck (a neutral-karma character), yields must behave exactly as
## before this parameter existed -- the same "byte-identical with no
## investment" guarantee Taming.break_free_chance's luck parameter has.
func test_yields_is_unchanged_with_zero_luck():
	for s in range(0, 60):
		assert_eq(
			oy.yields("iron", 3.0, s, 0.0),
			oy.yields("iron", 3.0, s),
			"seed %d should be unaffected by an explicit zero luck" % s
		)


## Good luck can only ever push the extra-ore roll UP from its zero-luck
## result, never down -- the roll's position within its own range shifts
## toward the top, it never gets reshuffled to a worse draw.
func test_good_luck_never_reduces_the_extra_ore_roll():
	for s in range(0, 60):
		var neutral := _total_of(oy.yields("iron", 3.0, s, 0.0), "iron_ore")
		var lucky := _total_of(oy.yields("iron", 3.0, s, 1.0), "iron_ore")
		assert_gte(lucky, neutral, "good luck should never yield less ore at seed %d" % s)


## Symmetric: bad luck can only ever push the roll DOWN, never up.
func test_bad_luck_never_increases_the_extra_ore_roll():
	for s in range(0, 60):
		var neutral := _total_of(oy.yields("iron", 3.0, s, 0.0), "iron_ore")
		var unlucky := _total_of(oy.yields("iron", 3.0, s, -1.0), "iron_ore")
		assert_lte(unlucky, neutral, "bad luck should never yield more ore at seed %d" % s)


## Luck has to actually DO something, not just be a no-op bounds clamp --
## across enough seeds, full good luck must beat neutral at least once.
func test_good_luck_sometimes_actually_increases_the_extra_ore_roll():
	var any_increase := false
	for s in range(0, 60):
		var neutral := _total_of(oy.yields("iron", 3.0, s, 0.0), "iron_ore")
		var lucky := _total_of(oy.yields("iron", 3.0, s, 1.0), "iron_ore")
		if lucky > neutral:
			any_increase = true
			break
	assert_true(any_increase, "full good luck never once increased the roll across 60 seeds")


## However far luck pushes the roll, the guaranteed base ore a swing already
## earned is never taken away, and the ceiling this power level already
## pins is never exceeded either -- luck only moves the roll WITHIN the
## already-tested range, it cannot widen it.
func test_luck_never_pushes_ore_count_out_of_the_pinned_range():
	for luck in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for s in range(0, 100):
			var drops := oy.yields("iron", 3.0, s, luck)
			var n := _total_of(drops, "iron_ore")
			assert_between(
				n,
				OreYield.BASE_ORE,
				OreYield.BASE_ORE + int(ceil(3.0 * OreYield.ORE_PER_POWER)),
				"ore count out of pinned range at luck %.1f, seed %d" % [luck, s]
			)
