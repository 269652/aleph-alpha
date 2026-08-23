extends RefCounted

## How a pollinator works a meadow (see docs/concept/flora.md).
##
## Butterflies and bees used to drift back and forth over a single bloom
## forever, because scent steering alone has a stable attractor at the
## strongest flower -- arriving there and continuing to steer toward it just
## oscillates. Real foraging has a CYCLE: land, drink, and move on to a
## flower you haven't emptied yet.
##
## Two pieces of memory make that work, and they live in different places on
## purpose:
## - the FLOWER remembers it was drained (nectar, which refills over time),
##   so a patch is a depleting resource rather than an infinite one;
## - the POLLINATOR remembers which flowers it personally visited, so it
##   moves on even while a flower is still refilling, and two insects don't
##   lock onto the same bloom.
##
## Pure functions and constants, no nodes: the marker owns the state, this
## owns the rules.

## How long an insect sits on a bloom drinking, in seconds. Long enough to
## read as "settled on it" rather than a bounce.
const DRINK_SECONDS := 2.4

## How close it must get before it counts as landing.
const LANDING_DISTANCE := 4.0

## How long a pollinator remembers a flower it emptied, in seconds, before
## it's willing to revisit it -- long enough it won't immediately re-land on
## a bloom it just drained (which hasn't had time to refill meaningfully
## yet, see NECTAR_REGEN_PER_SECOND), short enough it doesn't blacklist a
## worked meadow for the rest of the session. TIME-based rather than the
## count-bounded memory this used to be: a pollinator with only one or two
## flowers in range emptied its whole local memory budget on them and had
## nowhere left to go until something aged out by COUNT (which, with nothing
## new to visit, never happened) -- reported: "bees and butterflies should
## remember emptied flowers for only 10 minutes or so".
const VISIT_MEMORY_SECONDS := 90.0

## How far a pollinator will look for something to forage, in tiles --
## deliberately much further than a single flower's scent carries
## (ScentField.RADIUS_TILES). Scent is how a pollinator picks its way around
## a patch it can already smell; this is how it finds the NEXT patch once its
## own neighbourhood is worked out. Real bees forage hundreds of metres from
## the hive, far beyond the range any individual bloom advertises over, and
## without this the flyer simply had nothing to do the moment its local
## flowers were drained.
const FORAGE_SEARCH_TILES := 18.0


## How far a pollinator relocates when even the ranged search turns up
## nothing at all. Must exceed ScentField.RADIUS_TILES, or it would just
## re-search ground it has already covered and orbit the same barren spot --
## which is exactly the "drift around meaninglessly" failure.
const RELOCATION_STEP_TILES := 8.0

## How far those relocation hops may carry a pollinator from where it
## spawned. Unleashed, relocation is a random walk and drift becomes an
## ABSORBING state: measured at 93 tiles from spawn after ten simulated
## minutes with nothing to eat, at which point a full meadow appearing back
## at the spawn point was invisible to it (zero flowers seen, zero drunk,
## ending 97 tiles out) -- reported as "don't resume foraging when they
## encounter new flowers", because it never encountered any again.
##
## Wider than FORAGE_SEARCH_TILES so ranging to a neighbouring patch still
## works, but inside the 3x3 chunk window EarthChunkManager.flowers_near
## actually scans (32 tiles to a chunk, and only LOADED chunks have flower
## patches at all) -- past that a flyer is blind regardless of what is really
## growing around it.
const MAX_RELOCATION_TILES := 24.0

## Tile size in world pixels. Flower positions arrive here already in pixels,
## so an absolute distance band has to be expressed against something. Held
## locally rather than preloading TerrainRenderer: this is pure gameplay
## logic with no rendering dependency (nothing else in src/gameplay imports
## the renderer), and procedural_flower_sprite.gd already keeps its own copy
## of this same number for the same reason.
const TILE_SIZE_PX := 16.0

## How much further than the NEAREST forageable bloom a candidate may be and
## still count as tied with it. This is the rule that keeps a pollinator
## working the flowers in front of it.
##
## Scattering across a fixed COUNT of nearest blooms (see
## NEAREST_CANDIDATE_POOL) is not enough on its own: in a real meadow the
## third-nearest bloom is routinely two or three times further than the
## first, so a fixed-count pool sent two thirds of commits to a visibly
## further flower. Measured in a live world -- mean chosen distance 5.83
## tiles against a mean nearest-available of 4.26, worst commit 14.40 tiles,
## 9 of 24 commits more than 2 tiles worse than what was on offer, e.g.
## "chose 8.5 (nearest 3.2)". To a player that reads as flying straight past
## flowers without even checking them.
##
## An absolute band rather than a ratio: a proportional tolerance would allow
## ever-sloppier choices the further out the nearest bloom happens to be,
## which is the same failure again at longer range.
const SCATTER_BAND_TILES := 1.5

## How many of the nearest forageable blooms a pollinator picks between,
## rather than always taking the single closest. Deterministic "nearest
## wins" meant every pollinator in an area computed the identical answer:
## measured at eight flyers in one spot all choosing the same bloom, so they
## conga-lined along one route and only the leader ever got nectar
## (reported: "not all bees and butterflies fly the same route following
## each other and only the first gets nectar"). Small on purpose -- nearness
## still dominates, it is near-ties that scatter.
const NEAREST_CANDIDATE_POOL := 3

## Hard ceiling on remembered visits, on top of VISIT_MEMORY_SECONDS. The
## time window alone stopped bounding this once foraging ran continuously
## instead of idling out most of the window -- a pollinator banks a visit
## every few seconds, measured at 205 live entries after 15 simulated
## minutes and rising with forage rate. Every entry is distance-checked
## against every candidate flower on every sniff for every pollinator on
## screen, the same per-frame cost the chunk manager already had to cap when
## scoring meadows. Comfortably more than the flowers reachable inside
## FORAGE_SEARCH_TILES, so the memory still does its job.
const MAX_REMEMBERED_VISITS := 48

## Whether this bloom is worth flying to at all.
##
## Takes WITHERED, not nectar.
##
## An earlier pass keyed this off the nectar level, which was wrong twice over.
## Depleted is not spent: nectar is a bloom's current contents and refills in
## about a minute, so a drained flower is a full flower that has just been
## visited -- refusing it stopped local pollinators returning to the plants
## they work, which is most of what a local pollinator does. Spent means
## WITHERED, a flower at the end of its own season, and which part of the year
## that is depends entirely on the flower (see FlowerBloom).
##
## The distance rule this module already documents still stands: a pollinator
## cannot see a flower's nectar level from across a meadow. It can see that a
## flower has gone over.
static func is_worth_visiting(withered: bool) -> bool:
	return not withered


## Fraction of a flower's nectar taken per visit.
const NECTAR_PER_DRINK := 1.0

## Nectar refilled per second, so a worked-over meadow recovers rather than
## going permanently dead.
const NECTAR_REGEN_PER_SECOND := 1.0 / 60.0


func _init() -> void:
	pass


## The flower this pollinator should head for: the nearest one that still has
## nectar, PREFERRING one it hasn't recently emptied (within
## VISIT_MEMORY_SECONDS of `now`). Returns an empty Dictionary only when
## nothing in range has any nectar left at all, so the caller falls back to
## ranging further rather than hovering.
##
## Visit memory RANKS rather than VETOES, and that distinction was a real
## bug. As a veto, a pollinator that had worked its local flowers went
## completely idle for the rest of the ten-minute memory window -- measured
## at four drinks in the first simulated minute, then nine minutes of
## nothing, resuming exactly when the memory expired -- even though every one
## of those flowers was back to full nectar within ~20s
## (NECTAR_REGEN_PER_SECOND). The memory is documented as being long enough
## not to re-land on a bloom that "hasn't had time to refill meaningfully
## yet", but at 30x the actual refill time it was rejecting a meadow that had
## already recovered (reported: "when all nearby are empty butterflies and
## bees stop foraging completely and just drift around meaninglessly"). A
## bloom it just drained is excluded by the nectar check anyway, so
## preferring-but-not-refusing keeps the original "work across the meadow"
## behaviour without the idle spell.
## `seed_value` scatters the choice across the NEAREST_CANDIDATE_POOL nearest
## candidates instead of always taking the single closest -- see that
## constant for why (every pollinator otherwise picked the same bloom and
## they queued up behind each other). It is the caller's own stable seed, so
## a given pollinator is deterministic and reproducible while two pollinators
## in the same spot disagree.
## DISTANCE IS DECIDED FIRST, and that ordering is load-bearing. Splitting
## unvisited-from-remembered across the whole flower list before considering
## distance meant any unvisited bloom at any range outranked every remembered
## one however close: measured with the three nearest blooms in memory, a
## pollinator's targets were the ones 20, 50 and 100 tiles out, flying past a
## refilled bloom one tile from its nose (reported: "they ignore most flowers
## and target some much further away than the nearest"). Because a
## continuously-foraging flyer remembers precisely its own local patch, that
## drove it away from exactly the flowers it should have been working.
## `claimed` is the positions other pollinators are already heading for (see
## ForageClaims). Those blooms are DEMOTED within the band, never excluded:
## a claim is a statement of intent, not ownership, so it can never make a
## flyer skip a closer bloom (demotion happens strictly inside the distance
## band) nor leave it stalling with nothing to do (if every candidate is
## spoken for, it still picks one -- chaining beats idling).
static func choose_target(
	position: Vector2,
	flowers: Array,
	visited: Array,
	now: float = 0.0,
	seed_value: int = 0,
	claimed: Array = []
) -> Dictionary:
	# Every bloom is a candidate REGARDLESS of how much nectar it holds. A
	# pollinator cannot see a flower's nectar level from across the meadow --
	# it finds out by landing. Filtering candidates on `nectar > 0` straight
	# out of world data was exactly that omniscience, and it showed: flyers
	# skipped blooms they had never been near (reported: "the butterflies are
	# NOT checking EVERY flower they haven't visited yet. Somehow they know
	# it's empty without checking for nectar first"). The only thing a
	# pollinator legitimately knows is where IT has already been -- that is
	# visit memory, applied below.
	var near := _nearest(position, flowers, NEAREST_CANDIDATE_POOL)
	if near.is_empty():
		return {}
	# Distance, not merely rank, decides who is in play: keep only the blooms
	# genuinely TIED with the nearest one (see SCATTER_BAND_TILES). Ranking
	# alone let the 2nd and 3rd nearest be multiples of the 1st's distance
	# away in a real meadow, so the flyer committed straight past closer
	# flowers. `near` is already sorted nearest-first, so this is a prefix.
	var band: float = position.distance_to(near[0]["position"]) + SCATTER_BAND_TILES * TILE_SIZE_PX
	var tied: Array = []
	for flower in near:
		if position.distance_to(flower["position"]) <= band:
			tied.append(flower)
	near = tied
	# Peers first, then memory. Both only ever reorder blooms that are already
	# tied on distance, so neither can cause a visible skip.
	#
	# Peers outrank memory deliberately: heading for a bloom a neighbour is
	# already committed to means arriving at an empty flower (measured mean
	# nectar on arrival: 0.182), whereas re-visiting one this flyer drained
	# itself a while ago is merely second-best -- it has had time to refill.
	var unclaimed: Array = []
	for flower in near:
		if not _is_claimed(flower["position"], claimed):
			unclaimed.append(flower)
	if not unclaimed.is_empty():
		near = unclaimed

	# Then memory breaks ties among what's left: prefer a bloom it hasn't
	# just drained, but never at the cost of crossing the meadow. If it has
	# worked all of them, they have had time to refill (drained ones were
	# already excluded above), so it simply works the patch again.
	var unvisited: Array = []
	for flower in near:
		if not _was_visited(flower["position"], visited, now):
			unvisited.append(flower)
	if unvisited.is_empty():
		# Everything in reach has already been checked by THIS flyer inside
		# VISIT_MEMORY_SECONDS. Memory now VETOES rather than merely ranking:
		# with nectar no longer visible from a distance (see above), falling
		# back to an already-checked bloom meant re-landing on the one flower
		# it had just found empty, over and over -- orbiting it. Returning
		# nothing sends the caller off to search instead, and once the memory
		# ages out (deliberately set just longer than a bloom takes to refill)
		# it comes back and checks again, which is what was asked for:
		# "butterflies should forget which flowers they visited after a
		# reasonable time so they can check same flowers again after a while
		# to see if nectar restocked".
		return {}
	return unvisited[absi(seed_value) % unvisited.size()]


## Whether some other flyer is already heading for this bloom. Compared with
## the same tolerance as visit memory (see _was_visited): a bloom's world
## position is rebuilt from its cell on every query, so exact float equality
## would silently never match and this would quietly do nothing at all.
static func _is_claimed(position: Vector2, claimed: Array) -> bool:
	for claim in claimed:
		if position.distance_squared_to(claim) < LANDING_DISTANCE * LANDING_DISTANCE:
			return true
	return false


## The `wanted` nearest of `candidates`, by true distance from `position`.
## Partial-selects rather than sorting the whole list: this runs per
## pollinator per sniff, and the pool is tiny next to the number of flowers a
## ranged search can return.
static func _nearest(position: Vector2, candidates: Array, wanted: int) -> Array:
	var pool: Array = []
	var remaining: Array = candidates.duplicate()
	var take: int = mini(wanted, remaining.size())
	for _i in take:
		var best_index := 0
		var best_distance := INF
		for index in remaining.size():
			var distance: float = position.distance_squared_to(remaining[index]["position"])
			if distance < best_distance:
				best_distance = distance
				best_index = index
		pool.append(remaining[best_index])
		remaining.remove_at(best_index)
	return pool


## Visited positions are compared with a tolerance rather than by identity:
## a flower's world position is rebuilt from its cell each query, so exact
## float equality would silently never match. Entries older than
## VISIT_MEMORY_SECONDS (relative to `now`) are treated as forgotten.
## The blooms that should still be pulling on this flyer: everything it has
## NOT worked inside its visit memory.
##
## Visit memory used to veto re-TARGETING a bloom but not the scent gradient
## that steers the flyer between targets -- and the gradient carries more
## weight in that blend than the wander does
## (AmbientFlyerMarker.SCENT_STEER_WEIGHT). So a flyer that had just drained a
## flower was still pulled straight back to it while being forbidden to land
## on it, and hung in front of it indefinitely (reported: "most butterflies
## stall in front of a single flower instead of wandering randomly in search
## for new unvisited flowers").
##
## What a flyer may not target, it must not be steered toward either: a
## butterfly that has just worked a flower is not drawn back to it. The memory
## is per-flyer and expires, so the bloom goes on advertising to everyone else
## and starts advertising to this one again once it has had time to refill.
static func unvisited_only(flowers: Array, visited: Array, now: float) -> Array:
	var out: Array = []
	for flower in flowers:
		if not _was_visited(flower["position"], visited, now):
			out.append(flower)
	return out


## How erratically a pollinator flies at its target, and how close it has to
## get before it steadies up to land.
##
## Butterfly flight is famously unpredictable -- that is an anti-predator
## adaptation rather than decoration -- and the approach used to be a dead
## straight line at the bloom (reported: "they should not fly straight to the
## next found but rather tumble around a bit like real butterflies").
##
## TUMBLE_STRENGTH is the sideways veer as a fraction of forward travel, kept
## below 1 so the flyer always makes progress: a tumble that could point
## backwards is a flyer that never arrives (pinned by
## test_a_tumbling_flyer_always_still_makes_progress).
const TUMBLE_STRENGTH := 0.8
const TUMBLE_FREQUENCY := 6.5
## The veer eases off inside this distance so the flyer settles onto the
## blossom instead of fluttering around it, never quite landing.
const TUMBLE_SETTLE_DISTANCE := 28.0


## `forward` (unit) veered off course by an amount that swings with time, so a
## pollinator crossing a meadow flutters rather than tracking a straight line.
##
## Returns a unit DIRECTION -- the caller applies its own speed -- and always
## keeps a positive component along `forward`.
static func tumbled_heading(
	forward: Vector2, distance_to_target: float, elapsed_seconds: float, seed_value: int
) -> Vector2:
	if forward.length() < 0.001:
		return forward
	var straight := forward.normalized()
	# Eased to zero as it arrives, so the last stretch is a clean approach.
	var settle := clampf(distance_to_target / TUMBLE_SETTLE_DISTANCE, 0.0, 1.0)
	if settle <= 0.0:
		return straight
	# Per-flyer phase, so two butterflies in one meadow don't flutter in
	# unison. Hash-derived like the rest of the world's per-individual
	# variation rather than held as RNG state.
	var phase := float(absi(hash(seed_value)) % 628) * 0.01
	# Two frequencies rather than one: a single sine reads as a regular
	# slalom, where a butterfly's path never repeats the same arc twice.
	var swing := (
		sin(elapsed_seconds * TUMBLE_FREQUENCY + phase)
		+ 0.5 * sin(elapsed_seconds * TUMBLE_FREQUENCY * 0.37 + phase * 2.1)
	) / 1.5
	var sideways := Vector2(-straight.y, straight.x)
	return (straight + sideways * swing * TUMBLE_STRENGTH * settle).normalized()


static func _was_visited(position: Vector2, visited: Array, now: float) -> bool:
	for seen in visited:
		if now - float(seen.get("time", 0.0)) > VISIT_MEMORY_SECONDS:
			continue
		if position.distance_squared_to(seen["position"]) < LANDING_DISTANCE * LANDING_DISTANCE:
			return true
	return false


## Records a visit at `now`, prunes any entry older than
## VISIT_MEMORY_SECONDS, and keeps at most MAX_REMEMBERED_VISITS of them so
## the memory stays bounded even when a pollinator forages continuously (the
## time window alone does not bound it -- see MAX_REMEMBERED_VISITS). The
## NEWEST entries are the ones kept: dropping those would re-target the bloom
## it just drained, which is the very thing this memory exists to prevent.
static func remember_visit(visited: Array, position: Vector2, now: float = 0.0) -> Array:
	visited.append({"position": position, "time": now})
	var pruned: Array = []
	for entry in visited:
		if now - float(entry.get("time", 0.0)) <= VISIT_MEMORY_SECONDS:
			pruned.append(entry)
	if pruned.size() > MAX_REMEMBERED_VISITS:
		pruned = pruned.slice(pruned.size() - MAX_REMEMBERED_VISITS)
	return pruned
