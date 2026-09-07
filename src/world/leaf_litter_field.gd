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
##   season           -- "spring"/"summer"/"autumn" at first -- which fall
##                        it dropped in, for the renderer's own colour
##                        choice (see LeafLitterAtlas) -- decaying one-way
##                        through exactly 3 stages while settled (see
##                        advance): its own fall colour, then "fading" once
##                        DECAY_TO_FADING_SECONDS elapses, then the
##                        terminal "winter" once DECAY_TO_WINTER_SECONDS
##                        does. Never any other value, and never reverts
##                        once "winter".
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
##   contact_count    -- how many player/animal contact rolls this leaf has
##                        already had (see try_disperse_near) -- its own
##                        running counter, salted separately from `seed`
##                        alone so consecutive contacts don't reuse one roll.
##   on_water         -- is this leaf currently floating on a river (see
##                        docs/concept/leaf_litter.md's "Floating on water"
##                        section)? Re-derived from the injected current
##                        probe (see set_current_probe/_is_on_water)
##                        every time a leaf's position is actually set --
##                        add_leaf, relocate_leaf_near, try_disperse_near,
##                        and advance's own wind-roll -- NOT re-checked every
##                        frame for a leaf that hasn't moved, so the vast
##                        majority of (dry, motionless) litter never costs a
##                        single current-probe call. Once true, advance's
##                        main loop probes it fresh every frame instead (a
##                        floating leaf's position changes every frame by
##                        definition, so there is no motionless case to
##                        cheaply skip there) and flips it back to false the
##                        moment that probe ever reports no real current at
##                        the leaf's own (still updating) position.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const WindDispersal = preload("res://src/world/wind_dispersal.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const LeafWaterDrift = preload("res://src/world/leaf_water_drift.gd")

## How long un-eaten litter lingers before it despawns -- reported directly:
## "leafs should take roughly 270 days to rot / decay / vanish". 270
## real-world days is ~3 of the 4 real seasons a year actually has (~91
## days each, matching real leaf litter's genuine decomposition timescale),
## expressed here as exactly 3/4 of a real year and translated through the
## SAME real-year -> compressed-game-year ratio every other real-world-
## grounded timing constant in this codebase already uses
## (SeasonCycle.SECONDS_PER_YEAR) -- the same idiom TreePhenology's own
## blossom timing already established for turning a real biological
## duration into game-playable time, applied here for the first time to
## litter rather than to a tree. Was a flat, arbitrary 90-SECOND "tidiness"
## cutoff with no real-world grounding at all before this; see
## test_lifetime_is_pinned_to_three_quarters_of_a_compressed_game_year in
## test_leaf_litter_field.gd.
const LIFETIME := 0.75 * SeasonCycle.SECONDS_PER_YEAR

## How long a settled leaf keeps the season it fell in (see the `season`
## field's own doc comment) before it fades partway to decay -- see
## advance. An even three-way split of LIFETIME (see
## test_decay_thresholds_are_pinned_to_an_even_three_way_split_of_lifetime),
## itself now grounded in the same real-world "3 seasons to fully decay"
## figure LIFETIME's own doc comment explains -- so "fading" genuinely
## lands at the one-real-season mark, and "winter" (below) at the two-
## real-season mark, matching the report's own "3 seasons" framing exactly:
## fresh for a season, fading for a season, winter for the final season
## before vanishing.
const DECAY_TO_FADING_SECONDS := LIFETIME / 3.0

## How long a settled leaf keeps its season at all -- see
## DECAY_TO_FADING_SECONDS' own doc comment for why this is pinned at
## exactly two-thirds of LIFETIME (the second of the "3 seasons" the
## report asked for) rather than an independently-chosen number.
const DECAY_TO_WINTER_SECONDS := LIFETIME * 2.0 / 3.0

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

## How often a SETTLED leaf gets a chance to be nudged by the ambient wind
## (see advance/set_wind) -- throttled the same way every other periodic,
## content-adding step in EarthChunkManager is (c.f. GRASS_REFRESH_INTERVAL,
## WORM_REFRESH_INTERVAL): litter blowing around is background scenery, not
## something that needs re-rolling every single frame.
const WIND_DISPERSAL_INTERVAL := 2.0

## The chance a given settled leaf is nudged by the wind at each throttled
## check -- kept small, the same "reads as ongoing background activity, not
## everything moving at once" reasoning AntColony.FORAGE_CHANCE's own doc
## comment gives for why ITS number is small. Its actual spread-not-instant
## effect (some settled leaves move over many checks, not all of them on the
## first one, and none at all in a dead calm) is pinned by
## test_wind_eventually_relocates_at_least_one_settled_leaf/
## test_wind_does_not_relocate_every_leaf_on_the_very_first_check/
## test_wind_does_not_relocate_anything_in_dead_calm in
## test_leaf_litter_field.gd.
const WIND_DISPERSAL_CHANCE := 0.12

## Salts keeping the per-leaf "does the wind take it this check" roll and its
## own landing-offset seed independent of each other and of the leaf's own
## spawn-order counter -- the same independent-second-sample technique
## AntColony's _FORAGE_SALT/_CARRY_SALT already use for the identical reason.
const _WIND_ROLL_SALT := 8501
const _WIND_LANDING_SALT := 30011

## A dry fallen leaf's real mass -- commonly cited at well under a gram for
## a single leaf; kept generous (2g, roughly a small handful of litter) so
## this never depends on getting any one species' exact leaf mass right.
## Fed into PebbleDispersion.dispersion_chance (see try_disperse_near) the
## same "footstep momentum vs. the target's own mass" model
## LiftableStone.try_disperse already uses for pebbles -- at this mass the
## ratio is so lopsided that it clamps to PebbleDispersion.MAX_DISPERSION_
## CHANCE_PER_CONTACT regardless (pinned by
## test_a_leaf_is_light_enough_to_hit_the_max_dispersion_chance in
## test_leaf_litter_field.gd), which is exactly right: real dry litter is
## light enough that almost any footstep disturbs it.
const LEAF_EFFECTIVE_MASS_KG := 0.002

## Salt for the per-contact dispersion roll (see try_disperse_near),
## independent of the wind salts above -- the same independent-second-
## sample technique this file already uses between its own rolls.
const _CONTACT_ROLL_SALT := 51193

var _leaves: Array[Dictionary] = []
var _wind_direction := Vector2.RIGHT
var _wind_strength := 0.0
var _wind_accumulator := 0.0
## {direction, speed_m_s} for a given world position -- EarthChunkManager.
## river_current_at_global (wrapped to take a pixel position, see that
## class's own leaf-litter wiring), invalid until set_current_probe is
## called. Left invalid (rather than defaulting to a real river query this
## file would have to reach across to EarthChunkManager for) is what keeps
## this file's own "cheap plain data, no scene-tree/world dependency" shape
## -- see this file's own header comment -- and every EXISTING test that
## never calls set_current_probe sees exactly its old behaviour: no probe,
## no leaf is ever on_water, full stop.
var _current_probe: Callable = Callable()
## The world positions of every nearby wader/fish (see RiverFlowShader.
## obstacle_lateral_shift_px) -- pushed once per frame the same way
## set_wind is, read by advance's own on-water turbulence term.
var _nearby_waders: PackedVector2Array = PackedVector2Array()
## Which throttled wind check this is -- salted into the per-leaf roll (see
## _WIND_ROLL_SALT) so consecutive checks don't all reuse the same sample.
var _wind_check_count := 0

## Assigns each leaf a unique, deterministic-enough seed for any later
## per-leaf roll (see the "seed" field's own doc comment above) -- a plain
## incrementing counter rather than a hash of position, so two leaves that
## happen to land extremely close together (a real possibility -- see
## LEAF_SCATTER_RADIUS) never collide on the same roll.
var _next_leaf_seed := 0

## Bumped every time something about this field's RENDERING-relevant state
## actually changes -- see generation()'s own doc comment for the full list
## of triggers and why each one is (or, for things the shader animates on
## its own, deliberately is NOT) included.
var _generation := 0


## Every leaf currently in this field, as plain Dictionaries (see this file's
## own doc comment for the shape). Returned directly, the same
## "caller treats this as read-only" convention AntColony.mound_cells() uses.
func leaves() -> Array[Dictionary]:
	return _leaves


## A monotonically-increasing counter, bumped whenever this field's own
## RENDERING-relevant state changes: a leaf added/removed/relocated/
## dispersed, a settled leaf's throttled wind-roll nudge (see advance), a
## decay-tier transition (the "season" field's own doc comment), the
## CPU-side transition-settle snap (transition_from's own doc comment --
## the renderer NEEDS this pushed once to stay alias-safe past
## LeafLitterRenderer.WRAP_PERIOD), and any leaf currently on_water (see
## _advance_floating_leaf's own doc comment: its continuous drift is driven
## entirely on the CPU side every frame, unlike the vertex-shader-animated
## fall/sway every other leaf gets, so it must always look dirty).
##
## Deliberately NOT bumped for: a no-op query (consume/relocate/disperse
## that found nothing), re-asserting a season a leaf already has, or an
## ordinary settled leaf simply existing while nothing about it changes --
## these are exactly the cases EarthChunkManager.step_leaf_litter uses this
## counter to skip re-pushing to LeafLitterRenderer.fill (see that
## function's own doc comment for why a periodic throttle would be wrong
## here instead).
func generation() -> int:
	return _generation


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
		"contact_count": 0,
		"on_water": _is_on_water(position),
	})
	_next_leaf_seed += 1
	_generation += 1


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


## Every leaf within `radius` of `pos`, each as {position, species, season}
## -- the plural counterpart nearest_leaf_near never had (see that
## function's own doc comment: it only ever tracks the single closest
## match). Used by AntForagerMarker._sense_food_nearby with a SMALL,
## local sensing radius around a scouting forager's own current position
## (see docs/concept/soil_fauna.md "Scouting: real search, not omniscient
## dispatch") -- a caller checking for more than one real candidate at
## once needs a plural query to run in the first place, which
## nearest_leaf_near alone could never provide.
func leaves_near(pos: Vector2, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for leaf in _leaves:
		if leaf.position.distance_to(pos) <= radius:
			found.append({"position": leaf.position, "species": leaf.species, "season": leaf.season})
	return found


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
			_generation += 1
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
	leaf.on_water = _is_on_water(new_position)
	_generation += 1
	return true


## Player/animal contact dispersion -- mirrors PebbleDispersion's own mass-
## weighted per-contact roll shape (LiftableStone.try_disperse), applied to
## the nearest leaf within `radius` of `walker_position`. Rolled fresh on
## every contact off the leaf's own seed + its own running contact_count
## (never engine randf() -- see PixelNoise's own doc comment on why), so a
## leaf that survives one brush might still be nudged by the next. Reuses
## relocate_leaf_near's own transition machinery once the roll succeeds, so
## a player-scattered leaf eases into its new spot exactly like a wind- or
## animal-scattered one does. Returns whether a leaf was actually found and
## nudged.
func try_disperse_near(walker_position: Vector2, radius: float, now: float) -> bool:
	var best_index := -1
	var best_distance := radius
	for i in _leaves.size():
		var distance: float = _leaves[i].position.distance_to(walker_position)
		if distance <= best_distance:
			best_index = i
			best_distance = distance
	if best_index < 0:
		return false
	var leaf: Dictionary = _leaves[best_index]
	var roll := PixelNoise.unit(leaf.seed, leaf.contact_count, _CONTACT_ROLL_SALT)
	leaf.contact_count += 1
	if roll >= PebbleDispersion.dispersion_chance(LEAF_EFFECTIVE_MASS_KG):
		return false
	var new_position := PebbleDispersion.nudge(walker_position, leaf.position)
	leaf.transition_from = leaf.position
	leaf.transition_start = now
	leaf.position = new_position
	leaf.on_water = _is_on_water(new_position)
	_generation += 1
	return true


## Pushes today's live per-chunk wind (see EarthChunkManager.step_flowers's
## identical wiring for flower/seed dispersal) -- read by advance's own
## throttled wind-dispersal roll below. No new weather state: this is the
## SAME continuous per-chunk wind already computed every frame for flower/
## seed dispersal, just handed to one more consumer.
func set_wind(direction: Vector2, strength: float) -> void:
	_wind_direction = direction
	_wind_strength = strength


## The water-current query this field uses to decide, and continuously
## drive, which leaves are floating (see the "on_water" field's own doc
## comment and docs/concept/leaf_litter.md's "Floating on water" section).
## `probe` takes a world pixel position and returns {direction, speed_m_s},
## the exact shape EarthChunkManager.river_current_at_global itself returns
## -- EarthChunkManager wraps that call (pixel -> tile, mirroring FishMarker
## ._current_at's identical conversion) and passes the wrapper here once,
## at field creation, since the underlying river data it reads never needs
## refreshing the way the day's ambient wind does (see set_wind).
func set_current_probe(probe: Callable) -> void:
	_current_probe = probe


## The world positions of every nearby wader/fish -- pushed once per frame
## from the SAME already-computed list EarthChunkManager.set_river_flow_
## waders feeds the visual current-line shader, so a floating leaf's own
## turbulence wobble is driven by the identical waders the water's surface
## art already bends around (see LeafWaterDrift.turbulence_velocity_px_s).
func set_nearby_waders(positions: PackedVector2Array) -> void:
	_nearby_waders = positions


## Is `position` on real, currently-flowing water right now? A real river
## reach never reports exactly zero speed (RiverFlowShader.STILL_FLOW_M_S's
## own doc comment: no Manning-solved channel is that quiet), so a positive
## speed IS "there is a river or a river-mouth plume here" -- no separate
## is_river_at_global call needed. No probe set (the common case: most
## worlds/tests never call set_current_probe) means "no way to know, so no"
## rather than an error.
func _is_on_water(position: Vector2) -> bool:
	if not _current_probe.is_valid():
		return false
	var current: Dictionary = _current_probe.call(position)
	return current.get("speed_m_s", 0.0) > 0.0


## The continuous half of a floating leaf's motion, called once per frame
## from advance's own main loop for any leaf already on_water -- see
## LeafWaterDrift for the actual current/wind/turbulence math. Re-probes at
## the leaf's OWN current position every call (not once at the moment it
## started floating): a real river's course bends and its hydraulics vary
## along its length, so the current a leaf actually feels must track where
## it has drifted TO, not where it fell. Flips on_water back off the
## instant that probe ever reports no real current at the leaf's own
## (still updating) position -- see _is_on_water's own doc comment on why a
## positive speed already means "real river or plume here" with no separate
## check -- at which point it simply stops moving and rejoins ordinary
## land-litter behaviour (the wind-roll below, once next SETTLED).
##
## Keeps transition_from equal to position on every call, deliberately
## skipping the eased fall-in/relocation cosmetic entirely for a floating
## leaf -- see LeafWaterDrift's own doc comment for why a continuous glide
## and an occasional discrete hop cannot share that one mechanism: an
## uncorrected eased transition would show the leaf perpetually chasing a
## target that keeps moving away from it, snapping back into sync every
## TRANSITION_DURATION rather than gliding.
func _advance_floating_leaf(leaf: Dictionary, delta: float) -> void:
	if not _current_probe.is_valid():
		leaf.on_water = false
		return
	var current: Dictionary = _current_probe.call(leaf.position)
	if current.get("speed_m_s", 0.0) <= 0.0:
		leaf.on_water = false
		leaf.transition_from = leaf.position
		return
	var velocity := LeafWaterDrift.velocity_px_s(
		current.direction, current.speed_m_s,
		_wind_direction, _wind_strength,
		_nearby_waders, leaf.position
	)
	leaf.position = leaf.position + velocity * delta
	leaf.transition_from = leaf.position


## Ages every leaf, prunes anything past LIFETIME, settles any transition
## whose TRANSITION_DURATION has elapsed (see transition_from's own doc
## comment), decays a SETTLED leaf's own `season` through exactly 3 stages
## -- its own fall colour, then "fading" once DECAY_TO_FADING_SECONDS has
## passed, then the terminal "winter" once DECAY_TO_WINTER_SECONDS has
## (see those constants' own doc comments -- one-way, never reverts, never
## applies to a leaf still mid-transition), and -- at its own
## throttled cadence -- gives the ambient wind a chance to nudge a SETTLED
## leaf out of place (see WIND_DISPERSAL_INTERVAL/
## WIND_DISPERSAL_CHANCE/set_wind). `now` is the authoritative
## world_age_seconds this step is happening at (see EarthChunkManager.
## step_leaf_litter) -- an explicit absolute clock, not a locally-
## accumulated one, the same convention _fruiting_model.state_at/
## TreeMaturity's planted_at already use, so a leaf's fall/relocation timing
## tracks the SAME clock /ecotest fast-forwards along with the rest of the
## ecosystem.
func advance(delta: float, now: float) -> void:
	for i in range(_leaves.size() - 1, -1, -1):
		var leaf: Dictionary = _leaves[i]
		if now - leaf.spawned_at >= LIFETIME:
			_leaves.remove_at(i)
			_generation += 1
			continue
		if leaf.on_water:
			# A floating leaf's position is driven right here, continuously,
			# every single frame -- the vertex shader never animates it (see
			# _advance_floating_leaf's own doc comment), unlike a settled/
			# transitioning leaf whose motion the shader handles entirely
			# once its data has been pushed once. So it must always look
			# dirty to a caller comparing generation() against a prior
			# fill, or it would visibly freeze mid-drift the moment
			# dirty-tracking stopped the routine per-frame refill.
			_advance_floating_leaf(leaf, delta)
			_generation += 1
		if leaf.transition_from != leaf.position and now - leaf.transition_start >= TRANSITION_DURATION:
			leaf.transition_from = leaf.position
			# The renderer NEEDS this real, CPU-confirmed "at rest" snap
			# pushed at least once -- see transition_from's own doc comment
			# on why a wrapped GPU clock can alias after long enough
			# without it. Skipping this bump would leave stale, un-snapped
			# (non-zero-offset) data sitting in the MultiMesh forever once
			# nothing else about this leaf ever changes again.
			_generation += 1
		if leaf.transition_from == leaf.position:
			var age: float = now - leaf.spawned_at
			if age >= DECAY_TO_WINTER_SECONDS:
				if leaf.season != "winter":
					leaf.season = "winter"
					_generation += 1
			elif age >= DECAY_TO_FADING_SECONDS:
				if leaf.season != "fading":
					leaf.season = "fading"
					_generation += 1

	_wind_accumulator += delta
	if _wind_accumulator < WIND_DISPERSAL_INTERVAL:
		return
	_wind_accumulator = 0.0
	_wind_check_count += 1
	if _wind_strength <= 0.0:
		return  # dead calm: litter must not spontaneously scatter
	for leaf in _leaves:
		# A floating leaf is EXCLUDED outright, not just "unlikely to roll"
		# -- see LeafWaterDrift's own doc comment on why a continuous glide
		# and this discrete, occasional hop cannot share one leaf's motion
		# without visibly fighting each other. Wind still reaches a floating
		# leaf, just far less (WATER_WIND_DAMPING), continuously, through
		# _advance_floating_leaf above instead.
		if leaf.on_water:
			continue
		# Only a SETTLED leaf is eligible -- one still mid-transition (just
		# fallen, or already nudged earlier this very check) is left alone
		# rather than re-rolled on top of its own unfinished motion.
		if leaf.transition_from != leaf.position:
			continue
		var roll_seed: int = leaf.seed + _wind_check_count * 97 + _WIND_ROLL_SALT
		if PixelNoise.unit(roll_seed, 0, 0) >= WIND_DISPERSAL_CHANCE:
			continue
		var landing_seed: int = leaf.seed + _wind_check_count * 97 + _WIND_LANDING_SALT
		# leaf_ground_drift, NOT landing_offset -- see that function's own
		# doc comment: a leaf already settled on the ground and nudged by
		# the SAME ambient wind repeatedly over time needs a directionally
		# COHERENT drift across many nudges, or consecutive nudges read as
		# being yanked back and forth (reported directly: "it's a hard back
		# forth motion atm") -- landing_offset's own independent 0-360
		# degree scatter angle is right for a seed falling once, not this.
		var offset := WindDispersal.leaf_ground_drift(landing_seed, _wind_direction, _wind_strength)
		leaf.transition_from = leaf.position
		leaf.transition_start = now
		leaf.position = leaf.position + offset
		# A gust can blow a dry leaf straight into the river -- from the
		# very next frame it floats and this same mechanism never touches
		# it again (see the on_water guard just above).
		leaf.on_water = _is_on_water(leaf.position)
		_generation += 1
