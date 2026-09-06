extends GutTest

## WildMushroomPatch (see docs/concept/mushrooms.md's "Where and when a
## flush happens"). Unlike WildCropPatch's continuous 0..1 growth, a cell
## here is binary -- fruiting or not -- because a real fruiting body
## appears fully formed. Mirrors EarthwormPatch's shape more than
## WildCropPatch's: a fixed set of possible SITES is decided once at
## construction, and advance() only ever rolls against that small fixed
## set, never the whole chunk grid.
##
## One instance covers all six species together -- deliberately NOT
## WildCropPatch's "one instance per crop, partitioned territory" shape,
## since two different real mushroom species fruiting near each other in
## the same patch of forest floor is completely normal.

const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")


func _all_biome(id: String, width: int, height: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(width * height)
	for i in biome.size():
		biome[i] = id
	return biome


# -- where sites can even exist --------------------------------------------

func test_desert_never_hosts_a_site():
	var patch := WildMushroomPatch.new(1, 20, 20, _all_biome("desert", 20, 20))
	assert_eq(patch.site_count(), 0)


func test_forest_can_host_several_species():
	var patch := WildMushroomPatch.new(3, 40, 40, _all_biome("forest", 40, 40))
	assert_gt(patch.site_count(), 0, "a 40x40 forest chunk should have some sites")
	var seen := {}
	for cell in patch.get_site_cells():
		seen[patch.species_at(cell)] = true
	assert_gt(seen.size(), 1, "a real forest should host more than one species")


## Reported live: "forest mushrooms should spawn in forests and e.g.
## champignons on pasture" -- Champignon (the real "field mushroom") is
## specifically a pasture species, genuinely uncommon in deep forest (see
## MushroomSpecies.allows_biome's own doc comment), unlike the mixed-
## habitat Psilocybe/Parasol.
func test_champignon_never_hosts_in_forest():
	var patch := WildMushroomPatch.new(3, 60, 60, _all_biome("forest", 60, 60))
	for cell in patch.get_site_cells():
		assert_ne(patch.species_at(cell), "champignon", "champignon should never site in forest")


func test_grassland_only_ever_hosts_real_saprotrophs():
	var patch := WildMushroomPatch.new(5, 40, 40, _all_biome("grassland", 40, 40))
	assert_gt(patch.site_count(), 0, "grassland should host real saprotroph species")
	for cell in patch.get_site_cells():
		var species := patch.species_at(cell)
		assert_true(
			MushroomSpecies.is_saprotroph(species),
			"grassland should only ever host a real saprotroph (%s is not one)" % species
		)


func test_champignon_can_host_in_grassland():
	# A big enough grassland patch that champignon (1 of only 3 eligible
	# saprotrophs there) should turn up at least once.
	var patch := WildMushroomPatch.new(5, 80, 80, _all_biome("grassland", 80, 80))
	var seen := {}
	for cell in patch.get_site_cells():
		seen[patch.species_at(cell)] = true
	assert_true(seen.has("champignon"), "champignon should be able to site in grassland")


func test_sites_are_capped():
	var patch := WildMushroomPatch.new(9, 200, 200, _all_biome("forest", 200, 200))
	assert_true(patch.site_count() <= WildMushroomPatch.MAX_SITES)


# -- determinism -------------------------------------------------------------

func test_is_deterministic_for_the_same_seed_and_layout():
	var biome := _all_biome("forest", 30, 30)
	var a := WildMushroomPatch.new(42, 30, 30, biome)
	var b := WildMushroomPatch.new(42, 30, 30, biome)
	assert_eq(a.get_fruiting_cells(), b.get_fruiting_cells())
	for cell in a.get_fruiting_cells():
		assert_eq(a.species_at(cell), b.species_at(cell))


# -- picking -------------------------------------------------------------

func test_pick_returns_false_when_nothing_is_fruiting_there():
	var patch := WildMushroomPatch.new(1, 20, 20, _all_biome("desert", 20, 20))
	assert_false(patch.pick(Vector2i(0, 0)))


func test_pick_removes_a_fruiting_mushroom():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	assert_gt(patch.get_fruiting_cells().size(), 0, "expected at least one initially-fruiting cell")
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	assert_true(patch.pick(cell))
	assert_false(patch.has_fruiting(cell))
	assert_false(patch.pick(cell), "picking the same spot twice should find nothing the second time")


# -- recovery: a just-picked (or just-spent) site cannot refruit instantly --

func test_recovery_blocks_immediate_refruiting_even_at_max_drive():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	patch.pick(cell)
	for i in 10:
		patch.advance(1.0, 1.0)  # 10 seconds at maximum flush drive
	assert_false(
		patch.has_fruiting(cell),
		"a spent site should still be recovering nowhere near SPENT_SECONDS later"
	)


func test_a_site_can_fruit_again_once_recovery_expires():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	patch.pick(cell)
	# Age recovery all the way out with flush_drive at 0 so nothing can
	# flush prematurely while doing so.
	patch.advance(WildMushroomPatch.SPENT_SECONDS + 1.0, 0.0)
	# Now give it every chance to flush again.
	var refruited := false
	for i in 400:
		patch.advance(1.0, 1.0)
		if patch.has_fruiting(cell):
			refruited = true
			break
	assert_true(refruited, "a recovered site should be able to fruit again")


func test_an_unpicked_fruiting_body_eventually_ages_out_on_its_own():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	# A big jump, no new flush chance to interfere -- just ageing.
	patch.advance(WildMushroomPatch.SPENT_SECONDS + 1.0, 0.0)
	assert_false(
		patch.has_fruiting(cell), "a real fruiting body doesn't last forever, even unpicked"
	)


# -- flush drive gating -------------------------------------------------------

func test_zero_flush_drive_never_creates_new_fruiting():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var before := patch.get_fruiting_cells()
	for i in 5:
		patch.advance(1.0, 0.0)
	assert_eq(patch.get_fruiting_cells(), before)


# -- crushed underfoot (see docs/concept/soil_fauna.md "Crushed underfoot",
# CrushMechanic) -- reported live: "A mushroom is a physical entity...
# when you walk over one it should be crushed because of the player
# weight." Mirrors EarthwormPatch.crush exactly: the same shared
# CrushMechanic.is_crushed_by threshold, the same "recover on the
# identical clock as being taken" shape -- a crushed site is not
# destroyed, only whatever fruiting body was on it at the time.

func test_crush_below_threshold_leaves_a_fruiting_mushroom_untouched():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	assert_false(patch.crush(cell, 0.01), "momentum this small should not crush anything")
	assert_true(patch.has_fruiting(cell), "the mushroom should still be there")


func test_crush_above_threshold_removes_a_fruiting_mushroom():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	assert_true(patch.crush(cell, CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0))
	assert_false(patch.has_fruiting(cell), "the mushroom should be gone once crushed")


## Nothing to crush where nothing is fruiting -- crush honors the same
## has_fruiting gate pick() already does.
func test_crush_fails_on_a_cell_that_is_not_fruiting_even_at_huge_momentum():
	var patch := WildMushroomPatch.new(1, 20, 20, _all_biome("desert", 20, 20))
	assert_false(patch.crush(Vector2i(5, 5), 1000000.0))


func test_a_crushed_site_recovers_on_the_same_clock_as_a_picked_one():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	patch.crush(cell, CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	for i in 10:
		patch.advance(1.0, 1.0)
	assert_false(
		patch.has_fruiting(cell),
		"a crushed site should still be recovering nowhere near SPENT_SECONDS later"
	)


# -- force_fruit_near: a debug/dev-console way to see one on demand --------
#
# Reported live, after an extended investigation confirmed the fruiting sim
# itself was working correctly: "make a command that grows one near me" --
# real fruiting is a rare roll by design (SITE_CHANCE/FLUSH_CHANCE_PER_STEP
# are both deliberately small), too slow to demo/verify against on demand.

func test_force_fruit_near_makes_the_nearest_site_fruit_immediately():
	var patch := WildMushroomPatch.new(5, 40, 40, _all_biome("forest", 40, 40))
	var site: Vector2i = patch.get_site_cells()[0]
	if patch.has_fruiting(site):
		patch.pick(site)  # start from a clean not-fruiting site

	var fruited := patch.force_fruit_near(site)

	assert_eq(fruited, site)
	assert_true(patch.has_fruiting(site))


func test_force_fruit_near_returns_the_sentinel_when_the_patch_has_no_sites():
	var patch := WildMushroomPatch.new(1, 20, 20, _all_biome("desert", 20, 20))
	assert_eq(patch.force_fruit_near(Vector2i(5, 5)), Vector2i(-1, -1))


func test_force_fruit_near_picks_the_actual_nearest_site_not_just_any_site():
	var patch := WildMushroomPatch.new(5, 40, 40, _all_biome("forest", 40, 40))
	var sites: Array = patch.get_site_cells()
	assert_gt(sites.size(), 1, "precondition: more than one site to choose between")
	# A point that is itself NOT a site, so "nearest" is a real question --
	# querying an actual site trivially returns itself (distance 0).
	var target := Vector2i(-1000, -1000)
	var nearest: Vector2i = sites[0]
	var nearest_distance: float = (nearest - target).length_squared()
	for site in sites:
		var distance: float = (site - target).length_squared()
		if distance < nearest_distance:
			nearest = site
			nearest_distance = distance

	var fruited := patch.force_fruit_near(target)

	assert_eq(fruited, nearest)


func test_force_fruit_near_overrides_recovery_so_a_just_picked_site_can_be_forced():
	var patch := WildMushroomPatch.new(11, 60, 60, _all_biome("forest", 60, 60))
	var cell: Vector2i = patch.get_fruiting_cells()[0]
	patch.pick(cell)
	assert_false(patch.has_fruiting(cell), "precondition: freshly picked, now recovering")

	var fruited := patch.force_fruit_near(cell)

	assert_eq(fruited, cell)
	assert_true(patch.has_fruiting(cell))
