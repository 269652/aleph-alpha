extends RefCounted

## Per-chunk fallen-leaf litter (see docs/concept/leaf_litter.md). Mirrors
## AntColony's own shape exactly: cheap plain data, created at chunk load and
## erased at unload (see EarthChunkManager's own `_leaf_litter_fields`),
## `.advance(delta)` ages/prunes. This exists so a decomposer has a real,
## individually-addressable position to forage from and remove -- the
## concrete answer to "how does a decomposer eat from this" that sank a pure
## GPU density-field aggregate (the SnowBombShader approach) tried and
## abandoned twice for this exact feature: a density field has no discrete
## position left to hand back.
##
## Each leaf is a plain Dictionary:
##   position         -- current/target ground position (the GPU's "to").
##   species          -- TreeSpecies id ("cherry", "acorn", ...).
##   season           -- "summer" or "autumn" -- which fall it dropped in,
##                        for the renderer's own colour choice (see
##                        LeafLitterAtlas).
##   spawned_at       -- world_age_seconds when this leaf first fell. Drives
##                        LIFETIME pruning ONLY -- never touched by a later
##                        relocation, so a wind-nudged leaf does not get a
##                        fresh lease on life.
##   transition_from  -- world position the CURRENT easing motion starts
##                        from. Set to a point FALL_HEIGHT above `position`
##                        when the leaf first falls, and to the leaf's own
##                        PRIOR position on every later relocation -- one
##                        transition mechanism serves the fall-in and every
##                        later wind/player/animal nudge alike (see
##                        relocate_leaf_near). Snapped back to equal
##                        `position` exactly once TRANSITION_DURATION has
##                        passed (see advance) -- the renderer needs this
##                        real, CPU-confirmed "at rest" state rather than
##                        trusting a wrapped GPU clock forever (see
##                        LeafLitterRenderer's own doc comment on why: an
##                        8-bit-quantized packed start time can alias after
##                        long enough, and a flat zero offset is immune to
##                        that regardless of what the eased-time math reads).
##   transition_start -- world_age_seconds when the CURRENT transition began.
##   seed             -- a unique per-leaf integer (assignment order), for any
##                        caller needing an independent deterministic roll
##                        per leaf (see docs/concept/leaf_litter.md's wind
##                        section) without two leaves' rolls correlating.

## Un-eaten litter despawns after this many seconds -- same tidiness-not-
## spoilage reasoning DroppedItem.LIFETIME always had for a "material" kind
## item (litter does not rot the way a dropped nut does).
const LIFETIME := 90.0

## How high above its own landing spot a falling leaf starts, in world
## pixels -- ported unchanged from DroppedItem.FALL_HEIGHT (see
## LeafLitterRenderer, which mirrors the rest of that fall).
const FALL_HEIGHT := 40.0

## How long ANY eased transition takes -- the initial fall-in, and every
## later wind/player/animal relocation alike (see relocate_leaf_near's own
## doc comment: "one transition mechanism, multiple triggers"). Ported
## unchanged from DroppedItem.FALL_DURATION.
const TRANSITION_DURATION := 0.9

## How close a query position has to be to a leaf's own position to count as
## "the same leaf" for consume_leaf_at -- an exact-enough match, mirroring
## EarthChunkManager.take_fruit_at's identical 1.0px tolerance for the same
## "the caller hands back exactly the position a near-query already gave it"
## reason.
const CONSUME_TOLERANCE_PX := 1.0

var _leaves: Array[Dictionary] = []

## Assigns each leaf a unique, deterministic-enough seed for any later
## per-leaf roll (see the "seed" field's own doc comment above) -- a plain
## incrementing counter rather than a hash of position, so two leaves that
## happen to land extremely close together (a real possibility -- see
## LEAF_SCATTER_RADIUS) never collide on the same roll.
var _next_leaf_seed := 0


## Every leaf currently in this field, as plain Dictionaries (see this file's
## own doc comment for the shape). Returned directly, the same
## "caller treats this as read-only" convention AntColony.mound_cells() uses.
func leaves() -> Array[Dictionary]:
	return _leaves


## Adds a freshly-fallen leaf at `position` (its own final landing spot --
## the fall drops FROM FALL_HEIGHT above it, never TO it, mirroring
## DroppedItem's identical "the physics may drift but the destination is
## fixed" contract). `now` is world_age_seconds at the moment it fell.
func add_leaf(position: Vector2, species: String, season: String, now: float) -> void:
	_leaves.append({
		"position": position,
		"species": species,
		"season": season,
		"spawned_at": now,
		"transition_from": position - Vector2(0.0, FALL_HEIGHT),
		"transition_start": now,
		"seed": _next_leaf_seed,
	})
	_next_leaf_seed += 1


## The single nearest leaf to `pos` within `radius` world pixels, as
## {position, species, season}, or {} if none -- mirrors
## EarthChunkManager.seeds_near's {position, species} shape. The concrete
## answer DecomposerMarker's _nearest_food() (via
## EarthChunkManager.nearest_leaf_litter_near) and the player/animal
## dispersal entrypoints all query.
func nearest_leaf_near(pos: Vector2, radius: float) -> Dictionary:
	var best_index := -1
	var best_distance := radius
	for i in _leaves.size():
		var distance: float = _leaves[i].position.distance_to(pos)
		if distance <= best_distance:
			best_index = i
			best_distance = distance
	if best_index < 0:
		return {}
	var leaf: Dictionary = _leaves[best_index]
	return {"position": leaf.position, "species": leaf.species, "season": leaf.season}


## Removes the leaf standing at `pos` (see CONSUME_TOLERANCE_PX), returning
## whether one was actually there -- the mutation counterpart of
## nearest_leaf_near, mirroring take_fruit_at/take_seed_at's identical
## "best-effort, no-op on a miss" contract. A caller is expected to have just
## learned this exact position FROM nearest_leaf_near -- a leaf someone else
## already ate or moved in between is correctly reported as a miss, not an
## error.
func consume_leaf_at(pos: Vector2) -> bool:
	for i in _leaves.size():
		if _leaves[i].position.distance_to(pos) <= CONSUME_TOLERANCE_PX:
			_leaves.remove_at(i)
			return true
	return false


## The persisted-relocation mechanism every dispersal trigger (wind/player/
## animal) shares -- mirrors PebbleDispersion's shape: a nudge that STAYS,
## not a wake that recovers. Finds the nearest leaf to `pos` within `radius`
## and moves it to `new_position`, starting a fresh eased transition from its
## own prior position (see transition_from's doc comment) without touching
## its original spawned_at -- a nudged leaf keeps aging on the SAME lifetime
## clock it always had. Returns whether a leaf was actually found and moved.
func relocate_leaf_near(pos: Vector2, radius: float, new_position: Vector2, now: float) -> bool:
	var best_index := -1
	var best_distance := radius
	for i in _leaves.size():
		var distance: float = _leaves[i].position.distance_to(pos)
		if distance <= best_distance:
			best_index = i
			best_distance = distance
	if best_index < 0:
		return false
	var leaf: Dictionary = _leaves[best_index]
	leaf.transition_from = leaf.position
	leaf.transition_start = now
	leaf.position = new_position
	return true


## Ages every leaf, prunes anything past LIFETIME, and settles any transition
## whose TRANSITION_DURATION has elapsed (see transition_from's own doc
## comment). `now` is the authoritative world_age_seconds this step is
## happening at (see EarthChunkManager.step_leaf_litter) -- an explicit
## absolute clock, not a locally-accumulated one, the same convention
## _fruiting_model.state_at/TreeMaturity's planted_at already use, so a
## leaf's fall/relocation timing tracks the SAME clock /ecotest fast-forwards
## along with the rest of the ecosystem. `delta` is accepted (or not
## strictly needed by pruning/settling themselves, both of which compare
## `now` directly) to match the shared patch-sim advance(delta) shape every
## other per-chunk sim in this project uses, and IS needed by the throttled
## wind-dispersal roll (see docs/concept/leaf_litter.md).
func advance(_delta: float, now: float) -> void:
	for i in range(_leaves.size() - 1, -1, -1):
		var leaf: Dictionary = _leaves[i]
		if now - leaf.spawned_at >= LIFETIME:
			_leaves.remove_at(i)
			continue
		if leaf.transition_from != leaf.position and now - leaf.transition_start >= TRANSITION_DURATION:
			leaf.transition_from = leaf.position
