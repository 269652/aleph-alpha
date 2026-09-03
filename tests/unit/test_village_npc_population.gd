extends GutTest

## Capstone integration proof for docs/concept/npc.md's "AI-native NPCs"
## pillar at roadmap.md Phase 2's own target ("prove the daily-plan NPC
## architecture at small scale (5-10 NPCs, one village)"): a REAL settlement,
## located the same way the live game finds one -- VillageFinder searching
## outward over SettlementGenerator's own deterministic chunk placement, NOT
## a hand-authored test-only village or a hardcoded chunk coordinate -- spawns
## a real population of NpcMarkers via VillageRenderer.spawn_village (the
## exact call EarthChunkManager makes on ordinary chunk load, see
## EarthChunkManager._loaded_villages), each with its own distinct
## NpcIdentity and a real NpcNeeds-backed hunger that measurably rises as
## simulated time passes through NpcMarker._process -- the same per-frame
## loop that drives every villager in the live, running game.
##
## Every piece exercised here (SettlementGenerator, VillageFinder,
## VillageRenderer, NpcIdentity, NpcNeeds, NpcMarker) already has its own
## dedicated unit test file; this file is deliberately NOT redundant with
## those -- it is the one place that chains the REAL production entry points
## together end to end and asserts on the specific combination roadmap.md
## Phase 2 and npc.md's Identity/Needs sections both call for: N real NPCs,
## in one real settlement, each a distinct individual, each with needs that
## genuinely progress over time -- rather than trusting that proving each
## piece in isolation implies the whole slice actually holds together.

const VillageFinder = preload("res://src/world/village_finder.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageRenderer = preload("res://src/rendering/village_renderer.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcNeeds = preload("res://src/world/npc_needs.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32

## Chebyshev-ring search radius handed to VillageFinder.find_nearest --
## generous enough that finding nothing would itself be a real signal
## something regressed, not a tuning knob: SettlementGenerator's own
## ~1-in-30-habitable-chunks density means a search out to this radius covers
## (2*30+1)^2 = 3721 candidate chunks, an expected ~124 settlements.
const SEARCH_RADIUS_CHUNKS := 30

## Duck-typed world, same shape as test_npc_marker.gd's StubWorld: all
## grassland (dry, habitable, so no water-avoidance edge case interferes with
## locating villagers at their real home/workspot) plus the real weather-tied
## production accessors a working producer's NpcEconomy reads from.
class StubWorld:
	var biome := "grassland"
	var vegetation_density := 0.6
	var herbivore_population := 10.0
	var fish_population := 8.0
	func biome_at_global(_x: int, _y: int) -> String:
		return biome
	func vegetation_density_near(_pos: Vector2) -> float:
		return vegetation_density
	func herbivore_population_near(_pos: Vector2) -> float:
		return herbivore_population
	func fish_population_near(_pos: Vector2) -> float:
		return fish_population


var _generator := SettlementGenerator.new()
var _finder := VillageFinder.new()
var _renderer: VillageRenderer
var _parent: Node2D
var _world: StubWorld


func before_each():
	_renderer = VillageRenderer.new()
	_parent = Node2D.new()
	_world = StubWorld.new()


func after_each():
	_parent.free()


func _grassland(_chunk_coord: Vector2i) -> String:
	return "grassland"


## Locates a real settlement chunk via VillageFinder.find_nearest -- the same
## outward-ring search EarthChunkManager.find_nearest_village uses for the
## live /village command -- rather than a hand-rolled linear scan.
func _find_real_settlement_chunk() -> Vector2i:
	var found: Variant = _finder.find_nearest(Vector2i(0, 0), SEARCH_RADIUS_CHUNKS, _generator, _grassland)
	assert_not_null(
		found,
		"precondition: VillageFinder should locate a real settlement within %d chunks" % SEARCH_RADIUS_CHUNKS
	)
	return found


## Spawns the located settlement through the real VillageRenderer.spawn_village
## entry point (the same one EarthChunkManager calls on ordinary chunk load)
## and returns just the NpcMarker villagers, discarding the landmark/prop
## sprites also present in the spawned array.
func _spawn_real_village() -> Array[NpcMarker]:
	var chunk_coord := _find_real_settlement_chunk()
	var spawned := _renderer.spawn_village(
		_parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", _world
	)
	var npcs: Array[NpcMarker] = []
	for node in spawned:
		if node is NpcMarker:
			npcs.append(node)
	return npcs


# -- roadmap.md Phase 2: "small scale (5-10 NPCs, one village)" ------------

func test_a_real_settlement_spawns_between_5_and_10_real_npcs():
	var npcs := _spawn_real_village()
	assert_between(npcs.size(), 5, 10, "roadmap.md Phase 2 targets 5-10 NPCs in one village")


# -- each NPC is a real, distinct individual (npc.md "Identity") -----------

func test_every_npc_in_the_village_has_its_own_distinct_identity():
	var npcs := _spawn_real_village()
	assert_gt(npcs.size(), 0, "precondition: the located settlement should have spawned real villagers")
	var seen_seeds := {}
	for npc in npcs:
		assert_not_null(npc.identity, "every spawned marker should carry a real NpcIdentity")
		assert_false(seen_seeds.has(npc.identity.seed_value), "two villagers share the same identity seed")
		seen_seeds[npc.identity.seed_value] = true
	assert_eq(seen_seeds.size(), npcs.size(), "every villager should be a genuinely distinct individual")


func test_villagers_are_not_visually_identical_clones():
	var npcs := _spawn_real_village()
	var seen_names := {}
	for npc in npcs:
		seen_names[npc.identity.npc_name] = true
	assert_gt(seen_names.size(), 1, "a whole village sharing one name would read as clones, not individuals")


# -- real needs that measurably change over simulated time (npc.md "Needs
# and the local production economy") ---------------------------------------

## Deliberately short: NpcNeeds.START_STAGGER caps a fresh villager's
## starting hunger at 0.45 and HUNGER_RATE_PER_SECOND is 0.02/sec, so the
## EARLIEST any villager could possibly cross HUNGRY_THRESHOLD (0.5) and get
## fed (which would reset its hunger back toward 0 -- see
## NpcEconomy._try_eat) is (0.5 - 0.45) / 0.02 = 2.5 simulated seconds away.
## Staying comfortably under that keeps "hunger only goes up" true
## unconditionally for this window, regardless of which villager is a
## producer, which schedule entry happens to be active, or what the
## freshly-empty VillageMarket holds -- no eyeballed number, pinned directly
## against the real tested constants it depends on.
const SIMULATED_SECONDS := 1.5
const _MAX_SAFE_SIMULATED_SECONDS := (NpcNeeds.HUNGRY_THRESHOLD - NpcNeeds.START_STAGGER) / NpcNeeds.HUNGER_RATE_PER_SECOND
const STEPS := 15
const STEP_DELTA := SIMULATED_SECONDS / STEPS


func test_the_simulated_window_is_provably_shorter_than_any_villager_could_take_to_get_fed():
	# Guards the reasoning above itself against NpcNeeds' own tuned constants
	# ever changing out from under it.
	assert_lt(SIMULATED_SECONDS, _MAX_SAFE_SIMULATED_SECONDS)


func test_every_villagers_hunger_measurably_rises_as_simulated_time_passes():
	var npcs := _spawn_real_village()
	assert_gt(npcs.size(), 0, "precondition: the located settlement should have spawned real villagers")

	var starting_hunger: Array[float] = []
	for npc in npcs:
		assert_not_null(npc.economy, "every real villager should carry a real NpcEconomy/NpcNeeds")
		starting_hunger.append(npc.economy.needs.hunger)

	for i in STEPS:
		for npc in npcs:
			npc._process(STEP_DELTA)

	for i in npcs.size():
		assert_gt(
			npcs[i].economy.needs.hunger, starting_hunger[i],
			"%s's hunger should have measurably risen over %s simulated seconds" % [npcs[i].identity.npc_name, SIMULATED_SECONDS]
		)


## Each villager's rise is their OWN NpcNeeds instance progressing, not one
## shared/aggregate counter mistaken for N individuals' needs: advancing only
## the first villager's simulated time must leave every other villager's
## hunger untouched.
func test_hunger_rises_are_independent_per_villager_not_one_shared_counter():
	var npcs := _spawn_real_village()
	assert_gt(npcs.size(), 1, "precondition: need more than one villager to compare")

	var starting_hunger: Array[float] = []
	for npc in npcs:
		starting_hunger.append(npc.economy.needs.hunger)

	for i in STEPS:
		npcs[0]._process(STEP_DELTA)  # only the FIRST villager's simulated time advances

	assert_gt(npcs[0].economy.needs.hunger, starting_hunger[0], "the processed villager's own hunger should rise")
	for i in range(1, npcs.size()):
		assert_eq(
			npcs[i].economy.needs.hunger, starting_hunger[i],
			"an un-processed villager's hunger must not move just because another villager's did"
		)
