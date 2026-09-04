extends GutTest

## Nectar economy: does aggregate pollinator DEMAND across a real flower
## population outstrip the flowers' own regen SUPPLY? (see docs/progress.md,
## "Nectar economy rebalance".)
##
## Previously measured (before ForageClaims peer-sharing was wired up): 2.05x
## over-subscribed -- 64.24 drinks/s of demand against 31.30 nectar/s of
## regen across 626 reachable flowers. That number was flagged NOT to tune
## against, because the peer-claims chaining fix (ForageClaims /
## PollinatorForaging.choose_target's `claimed` argument) was landing at the
## same time and changes which flowers actually absorb demand -- so this
## re-measures with claims fully wired, the same two-sided shape as before:
## a real pollinator population foraging a real flower population, run to
## steady state.
##
## Scenario, grounded in real per-chunk constants rather than invented ones:
## a full LOAD_RADIUS neighbourhood of chunks (EarthChunkManager.LOAD_RADIUS,
## CHUNK_SIZE) -- 25 chunks -- each pure grassland biome (the densest ground
## flowers grow on), seeded by the real MeadowSpread/MAX_FLOWERS rules, in
## bloom for "summer" (the season with the most species flowering at once --
## see FlowerSpecies.SPECIES). Population is the real per-chunk pollinator
## ceiling (AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK +
## AmbientFlyerRenderer.MAX_BEES_PER_CHUNK, times 25 chunks = 150), flying at
## the real AmbientFlyerRenderer.BUTTERFLY_SPEED (bees share it -- there is
## no separate BEE_SPEED in that file).
##
## ## The meadow got sparser, and this measurement moved with it
##
## Re-measured after MeadowSpread replaced the per-cell coin flip that used
## to bake the initial meadow (reported live: flowers "spread or grow way too
## dense... more space between individual flowers"). The scenario is
## unchanged; the world it runs in is a third as flowery. 640 blooming
## flowers became 200, and the economy went from 0.86x (slightly
## UNDER-subscribed) to 1.56x over-subscribed.
##
## That is a real consequence, recorded rather than tuned away: with fewer
## blooms and the same pollinator ceiling, demand outstrips regen. Two things
## bound how much it matters, and neither is an excuse -- both are checkable:
##
## - This population is a CEILING, not a live one. Live spawning scales with
##   the peak scent concentration a chunk's blooms superpose to (see
##   EarthChunkManager._pollinator_multiplier_for /
##   ScentField.pollinator_spawn_multiplier), so a sparser meadow spawns
##   fewer pollinators into itself. The 150 here is the worst case the game
##   can reach, not the usual one.
## - Coverage did NOT collapse, which was the risk worth checking: 184 of 200
##   flowers were visited, 92% -- the same share as the old 592 of 640. The
##   population still works the whole meadow; there is simply less of it.
##
## Kept above 1.0 knowingly. Pushing it back under by raising nectar regen
## would be tuning a pollinator constant to hide a deliberate change in how
## much meadow the world has, and NECTAR_REGEN_PER_SECOND's own doc comment
## records the measurement it was set from -- if that number should move, it
## should move on its own evidence, not on this one's.
##
## What decides who drinks from what -- PollinatorForaging.choose_target,
## ForageClaims, FlowerPatch.drink/advance -- is the real, unmodified
## production code. Simplified only where the simplification cannot move the
## demand/supply arithmetic: no tumbling flight (a wobble around the
## straight line, not a change in average trip time) and no mid-flight
## re-sniff/hysteresis once committed (RETARGET_IMPROVEMENT_TILES).
##
## AMBIENT WANDER while uncommitted is NOT skipped, and an earlier version of
## this test that skipped it measured a badly wrong number: in real
## grassland density the SCATTER_BAND (1.5 tiles) is almost always narrower
## than the gap to the second-nearest flower, so a stationary pollinator's
## "nearest candidate" collapses to the ONE flower it just personally drank
## -- which its own visit memory then vetoes for the full
## VISIT_MEMORY_SECONDS (90s), freezing it solid. The live game never hits
## this because AmbientFlyerMovement keeps a flyer physically drifting
## (wander blended with scent-steering) even while `_forage_target` is null
## (see AmbientFlyerMarker._process/_step_scent) -- movement and target
## choice are independent systems there. This test's `_step_pollinator`
## reproduces that independence with a simplified wander (a heading held for
## AmbientFlyerRenderer.BUTTERFLY_INTERVAL, then re-rolled) rather than
## AmbientFlyerMovement's full home/radius model, since only "does the flyer
## keep covering ground between commits" matters for the demand arithmetic,
## not the exact shape of the drift.
##
## A per-tick "choose_target came up empty" decision is expected to be
## COMMON, not rare, even with wander running -- this codebase's own
## measurement (see ForageClaims's doc comment) found the scatter band holds
## only one candidate 86.5% of the time, and a decision is attempted every
## SIM_DELTA tick a pollinator is uncommitted, far more often than its
## wander heading changes. The real coverage signal is not "how often is any
## single decision empty" but "does the population as a whole reach most of
## the meadow over the run" -- see the `reachable_flowers` assertion below,
## which is what an earlier, wrongly-reasoned version of this test measured
## in its place.

const FlowerPatch = preload("res://src/world/flower_patch.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const ForageClaims = preload("res://src/gameplay/forage_claims.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const TILE_SIZE := PollinatorForaging.TILE_SIZE_PX
const CHUNK_TILES := EarthChunkManager.CHUNK_SIZE
const CHUNK_RADIUS := EarthChunkManager.LOAD_RADIUS
const SEASON := "summer"

## Simulation step. Landing is handled by snapping to the target the instant
## the remaining distance is less than one step's travel (see
## _step_pollinator), so this is a resolution/runtime tradeoff, not an
## accuracy cliff -- halving it does not change who lands where, only how
## finely arrival timing is discretised.
const SIM_DELTA := 0.5

## Long enough for the population to disperse across the meadow and for
## visit memory (PollinatorForaging.VISIT_MEMORY_SECONDS, 90s) and nectar
## regen (a ~60s full refill) to each cycle several times over before
## measurement starts.
const WARMUP_SECONDS := 300.0
## The window actual drinks and touched flowers are counted over, once the
## system has settled -- "ten simulated minutes" total, the same order of
## magnitude this codebase's own other foraging measurements use.
const MEASURE_SECONDS := 300.0

## The RNG seed this whole scenario is built from -- fixed, so the
## measurement is exactly reproducible from one run to the next.
const SCENARIO_SEED := 8420


func _build_flower_index() -> Dictionary:
	var patches: Array = []
	var flower_index: Array = []
	var next_id := 0
	for cy in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
		for cx in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			var biome := PackedStringArray()
			biome.resize(CHUNK_TILES * CHUNK_TILES)
			biome.fill("grassland")
			var chunk_seed := PixelNoise.value(SCENARIO_SEED, cx, cy)
			var patch := FlowerPatch.new(chunk_seed, CHUNK_TILES, CHUNK_TILES, biome)
			patches.append(patch)
			var origin_tiles := Vector2i(cx * CHUNK_TILES, cy * CHUNK_TILES)
			for cell in patch.blooming_cells(SEASON):
				var world_position := Vector2(
					(float(origin_tiles.x + cell.x) + 0.5) * TILE_SIZE,
					(float(origin_tiles.y + cell.y) + 0.5) * TILE_SIZE
				)
				flower_index.append({
					"id": next_id,
					"position": world_position,
					"patch": patch,
					"cell": cell,
				})
				next_id += 1
	return {"patches": patches, "flowers": flower_index}


func _spawn_pollinators(count: int, span_tiles: float) -> Array:
	var pollinators: Array = []
	var half := span_tiles * 0.5 * TILE_SIZE
	for i in count:
		pollinators.append({
			"id": i + 1,  # ForageClaims.NO_FLYER is 0 -- real ids never are.
			"position": Vector2(
				PixelNoise.range_value(SCENARIO_SEED + 1, i, 0, -half, half),
				PixelNoise.range_value(SCENARIO_SEED + 2, i, 0, -half, half),
			),
			"target": null,
			"entry": null,
			"drink_remaining": 0.0,
			"visited": [],
			"pick_index": 0,
			# Ambient wander while uncommitted (see the header comment) -- a
			# heading and a countdown to its next re-roll.
			"wander_dir": Vector2.RIGHT.rotated(
				PixelNoise.range_value(SCENARIO_SEED + 3, i, 0, 0.0, TAU)
			),
			"wander_timer": 0.0,
		})
	return pollinators


func _flowers_within(position: Vector2, flowers: Array, radius: float) -> Array:
	var out: Array = []
	var radius_squared := radius * radius
	for flower in flowers:
		if position.distance_squared_to(flower["position"]) <= radius_squared:
			out.append(flower)
	return out


## Advances one pollinator by `delta`. Returns "" while travelling or
## drinking, "empty" when a wandering pollinator's decision this tick found
## nothing to commit to, "picked" when it committed to a fresh target, or
## "drank" when it just completed a successful drink (what the caller counts
## for the demand/reachable-flower tallies).
func _step_pollinator(
	p: Dictionary, delta: float, now: float, claims: ForageClaims, flowers: Array
) -> String:
	if p["drink_remaining"] > 0.0:
		p["drink_remaining"] -= delta
		return ""

	if p["target"] != null:
		var to_target: Vector2 = p["target"] - p["position"]
		var distance := to_target.length()
		var step: float = AmbientFlyerRenderer.BUTTERFLY_SPEED * delta
		if step >= distance:
			p["position"] = p["target"]
			var entry: Dictionary = p["entry"]
			p["visited"] = PollinatorForaging.remember_visit(p["visited"], entry["position"], now)
			claims.release(p["id"])
			var fed: bool = entry["patch"].drink(entry["cell"])
			p["target"] = null
			p["entry"] = null
			if fed:
				p["drink_remaining"] = PollinatorForaging.DRINK_SECONDS
				# Recorded before `entry` goes out of scope -- the caller needs
				# to know WHICH flower this drink landed on (for the reachable-
				# flower tally) after `p["entry"]` has already been cleared above.
				p["last_drink_flower_id"] = entry["id"]
				return "drank"
			return ""
		else:
			p["position"] += to_target.normalized() * step
			return ""

	# Ambient wander: keeps covering ground while uncommitted, the same
	# independence from target-choice AmbientFlyerMovement gives the real
	# flyer (see header comment). Re-rolls the heading periodically rather
	# than every tick, so the drift reads as a real flight path, not jitter.
	p["wander_timer"] -= delta
	if p["wander_timer"] <= 0.0:
		p["wander_timer"] = AmbientFlyerRenderer.BUTTERFLY_INTERVAL
		var roll := PixelNoise.range_value(
			SCENARIO_SEED + 5, p["id"], int(now * 10.0), 0.0, TAU
		)
		p["wander_dir"] = Vector2.RIGHT.rotated(roll)
	p["position"] += p["wander_dir"] * AmbientFlyerRenderer.BUTTERFLY_SPEED * delta

	var near := _flowers_within(
		p["position"], flowers, PollinatorForaging.FORAGE_SEARCH_TILES * TILE_SIZE
	)
	var peer_claims := claims.claimed_positions_near(
		p["position"], PollinatorForaging.FORAGE_SEARCH_TILES * TILE_SIZE, p["id"]
	)
	p["pick_index"] += 1
	var chosen := PollinatorForaging.choose_target(
		p["position"], near, p["visited"], now,
		hash("%d_%d_nectar_economy" % [p["id"], p["pick_index"]]), peer_claims
	)
	if chosen.is_empty():
		return "empty"
	p["target"] = chosen["position"]
	p["entry"] = chosen
	claims.claim(chosen["position"], p["id"])
	return "picked"


func test_current_nectar_supply_vs_demand_ratio_is_measured():
	var built := _build_flower_index()
	var patches: Array = built["patches"]
	var flowers: Array = built["flowers"]
	assert_gt(flowers.size(), 0, "the scenario must actually seed a meadow")

	var chunks_per_side := CHUNK_RADIUS * 2 + 1
	var pollinator_count := chunks_per_side * chunks_per_side * (
		AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK + AmbientFlyerRenderer.MAX_BEES_PER_CHUNK
	)
	var pollinators := _spawn_pollinators(
		pollinator_count, float(chunks_per_side * CHUNK_TILES)
	)

	var claims := ForageClaims.new()
	var drinks_in_window := 0
	var flowers_touched_in_window := {}

	var elapsed := 0.0
	var total_seconds := WARMUP_SECONDS + MEASURE_SECONDS
	while elapsed < total_seconds:
		var in_window := elapsed >= WARMUP_SECONDS
		for patch in patches:
			# growth_modifier (see SeasonCycle.growth_modifier) only scales
			# seedling growth, never nectar regen -- irrelevant to this
			# measurement, so a neutral 1.0 is passed.
			patch.advance(SIM_DELTA, 1.0)
		for p in pollinators:
			var outcome := _step_pollinator(p, SIM_DELTA, elapsed, claims, flowers)
			if outcome == "drank" and in_window:
				drinks_in_window += 1
				flowers_touched_in_window[p["last_drink_flower_id"]] = true
		elapsed += SIM_DELTA

	var reachable_flowers: int = flowers_touched_in_window.size()
	assert_gt(reachable_flowers, 0, "the measurement window must see real drinking activity")
	# Coverage diagnostic (see header comment for why this replaces a
	# per-decision "empty is rare" check): with wander running, the
	# population as a whole should reach most of the seeded meadow over a
	# 5-minute window, not just a corner of it -- otherwise this scenario
	# would be measuring an artificially flower-starved population rather
	# than the intended busy one.
	assert_gt(
		reachable_flowers, flowers.size() / 2,
		"fewer than half the seeded flowers were ever visited -- the population isn't covering the meadow"
	)

	var measured_demand_per_second := float(drinks_in_window) / MEASURE_SECONDS
	var measured_supply_per_second := (
		float(reachable_flowers) * PollinatorForaging.NECTAR_REGEN_PER_SECOND
	)
	var ratio := measured_demand_per_second / measured_supply_per_second

	gut.p(
		(
			"nectar economy: %d pollinators, %d flowers seeded, %d reachable "
			+ "(touched) in the %.0fs measurement window -- demand %d drinks "
			+ "(%.2f/s) vs supply %.2f nectar/s -> %.4fx"
		) % [
			pollinator_count, flowers.size(), reachable_flowers, MEASURE_SECONDS,
			drinks_in_window, measured_demand_per_second, measured_supply_per_second, ratio,
		]
	)

	# Pinned regression guard, exact rather than a loose band: this whole
	# scenario is fully deterministic (SCENARIO_SEED, PixelNoise throughout,
	# no engine RNG), so re-running it reproduces the identical drink count
	# and reachable-flower count bit for bit -- confirmed across repeated
	# runs while this test was written. Pinning the two measured INPUTS to
	# the ratio, rather than the ratio itself, is what makes a future
	# regression legible: a changed `reachable_flowers` says the
	# claims/targeting logic now spreads demand differently, a changed
	# `drinks_in_window` says the population's throughput moved (population
	# budgets, DRINK_SECONDS, flight speed, ...) -- either failure mode
	# points straight at what to re-measure, which a single ratio number
	# would not. See docs/progress.md's "Nectar economy rebalance" entry and
	# PollinatorForaging.NECTAR_REGEN_PER_SECOND's doc comment for the
	# reasoning these numbers fed into.
	#
	# Re-measured when MeadowSpread made the baked meadow ~3x sparser (was
	# 592 reachable of 640 seeded, 2532 drinks, 0.86x under-subscribed; now
	# 184 of 200, 1438 drinks, 1.56x over-subscribed) -- see this file's
	# header for why that is recorded rather than tuned away, and for the two
	# bounds on how much it matters.
	assert_eq(reachable_flowers, 184, "reachable-flower count drifted -- re-measure the economy")
	assert_eq(drinks_in_window, 1438, "measured drink throughput drifted -- re-measure the economy")
