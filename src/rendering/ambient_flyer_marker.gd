extends Sprite2D

## A butterfly/songbird ambient wildlife marker -- pure decorative presence
## (see docs/concept/ecosystem_dynamics.md's Species roster), driven by
## AmbientFlyerMovement's idle-flight drift. Deliberately lighter than
## FishMarker/CreatureMarker: no needs/perception/behavior AI, no water
## confinement (flyers roam freely over both land and water), and no
## population simulation behind it -- a fixed, capped, decorative presence
## like the game's original static tree/grass-tuft layers.

const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const ScentField = preload("res://src/world/scent_field.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const GroundForageBehavior = preload("res://src/gameplay/ground_forage_behavior.gd")
const BirdDigestion = preload("res://src/gameplay/bird_digestion.gd")
const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")
const FlyerDiet = preload("res://src/gameplay/flyer_diet.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const Courtship = preload("res://src/gameplay/courtship.gd")
const LifeCycle = preload("res://src/gameplay/life_cycle.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")

## Only bees recognize blossoming fruit trees as a food source (see
## _step_scent) -- real apple/cherry trees are pollinated mainly by bees, so
## this is scoped to the one species rather than every nectar-feeder.
const TREE_POLLINATING_SPECIES := "bee"

## Own dedicated group for _look_for_a_partner's nearby-flyer search --
## deliberately NOT the same group as HoverTargetFinder.GROUP_NAME below.
## That group now covers every hoverable entity in the loaded world
## (dropped items, stones, ore, trees, ...), so scanning it for courtship
## partners would mean walking the whole loaded world's item/stone/tree
## count on every search instead of just nearby flyers -- a real
## performance regression the two groups being separate avoids entirely.
const FLOCK_GROUP := "ambient_flyer"

var home := Vector2.ZERO
var wander_seed := 0
var species := "sparrow"

## Shared AnimalFitness instance (stateless -- nothing per-individual to
## keep here). wander_seed is assigned by AmbientFlyerRenderer AFTER this
## node is constructed, so this individual's fitness cannot be precomputed
## at declaration time -- see _fitness_score(), which derives it fresh from
## wander_seed's CURRENT value on each of its (rare, throttled) call sites.
static var _animal_fitness := AnimalFitness.new()

var _movement: AmbientFlyerMovement

## Set for pollinators only (see AmbientFlyerRenderer): the chunk manager,
## duck-typed for flowers_near/current_season, so this flyer can smell its
## way toward blooms. Left null for birds, which ignore flowers entirely.
var scent_world = null

## Ground foraging -- a robin hunting earthworms (see GroundForageBehavior /
## docs/concept/soil_fauna.md).
##
## Set only for species whose diet contains a ground food (see FlyerDiet and
## AmbientFlyerRenderer._build_marker): `worm_world` is the chunk manager,
## duck-typed for worms_near/take_worm_at, and `ground_forage` is this bird's
## own state machine. BOTH stay null for every other flyer, which is what
## makes "sparrows don't hunt worms" structural rather than a branch -- a
## sparrow has no brain to run and no world to query, so nothing below can
## fire for it.
var worm_world = null
## Fallen tree fruit -- endozoochory (see SeedEndozoochory /
## docs/concept/flora.md#bird-endozoochory). Set only for species whose diet
## contains fruit (currently the robin -- see FlyerDiet): `fruit_world` is
## the chunk manager, duck-typed for fruit_near/take_fruit_at/
## try_plant_seed_at. Shares `ground_forage` with worm-hunting -- a bird only
## ever pursues one prey at a time, worm or fruit, through the same seek/
## descend/peck/resume cycle; which one it is heading for is tracked purely
## by which of `_worm_target`/`_fruit_target` is set.
var fruit_world = null
## Flower SEED lying in the grass -- granivory (currently the sparrow, see
## FlyerDiet). A flower whose bloom is over has gone to seed (see
## FlowerPatch.seed_cells / concept/flora.md), so the same meadow that feeds
## pollinators in season feeds seed-eaters out of it. Duck-typed for
## seeds_near/take_seed_at/plant_flower_at. Shares `ground_forage` with worm
## and fruit foraging -- a bird pursues one item at a time whatever it is.
var seed_world = null
var ground_forage: GroundForageBehavior = null

## The head-dipped sprite shown at the bottom of each peck (see
## ProceduralBirdSprite.generate_pecking_texture), alternated against
## `perched_frame` while the bird works the worm.
var peck_frame: Texture2D = null

## Re-scanning the soil every frame would query the worm set per bird per
## frame; worms surface on a weather timescale, so it is throttled the same
## way the pollinator's scent sniff is.
const WORM_SNIFF_INTERVAL := 0.5
var _worm_sniff_accumulator := 0.0
## Where this bird is headed on the ground, or null while it is just flying.
var _worm_target = null  # Vector2, or null
## Bumped per commit and mixed into the scatter seed, so a bird's successive
## picks differ while staying deterministic (see GroundForageBehavior.
## choose_worm).
var _worm_pick_index := 0

## Fallen fruit uses the same throttled-sniff shape as worms, but its own
## accumulator/target/pick-index -- worm-hunting and fruit-foraging run in
## parallel (both are tried every SEEKING tick), not as alternatives.
var _fruit_sniff_accumulator := 0.0
var _fruit_target = null  # Vector2, or null
var _fruit_pick_index := 0

## Seed uses the same throttled-sniff shape, tried in parallel with the
## other two every SEEKING tick.
var _seed_sniff_accumulator := 0.0
var _seed_target = null  # Vector2, or null
var _seed_pick_index := 0

## Grass seed (see TallGrass.shed_seed / docs/concept/long_grass.md's
## "Reproduction" section) uses the SAME `seed_world` port as flower seed
## above -- a sparrow's crop does not care whether what it swallowed came
## from a flower head or a grass seed head, so this is a fourth parallel
## sniff track on the one existing duck-typed world, not a new export.
var _grass_seed_sniff_accumulator := 0.0
var _grass_seed_target = null  # Vector2, or null
var _grass_seed_pick_index := 0

## The seed currently working its way through this bird after eating a fruit
## (a species id, or "" while not carrying one) -- see SeedEndozoochory. Only
## ONE seed is carried at a time, deliberately: a real bird's crop holds one
## meal's worth in flight before the next matters, and this keeps "which
## species gets planted" unambiguous. Ticks down independently of
## ground_forage's own state, so a bird can keep hunting its next meal while
## a previous seed is still digesting.
var _carried_seed_species := ""

## The PixelNoise seed this particular swallowed seed's granivory roll was
## (or will be) drawn from -- see SeedEndozoochory.seed_is_consumed, called
## from _step_seed_carrying at the moment the carry timer elapses. Set
## alongside _carried_seed_species by whichever _take_targeted_* method just
## ate a GROUND seed (flower or grass; fruit does not set this, since
## fruit's seed is never rolled for predation -- see _step_seed_carrying).
var _carried_seed_carrier_seed := 0

## How full this bird's crop is, and how long it has been carrying whatever it
## swallowed (see BirdDigestion).
##
## A bird foraged constantly whether or not it needed to, which makes it a
## harvesting machine rather than an animal. It eats when it is hungry now, and
## what it swallowed passes through and comes out as a DROPPING -- the visible
## half of dispersal, without which a seed simply appears somewhere a bird
## happened to be and the player never sees the connection.
var _fullness := BirdDigestion.STARTING_FULLNESS
var _carry_seconds_remaining := 0.0
## Whether the carried seed is a FLOWER's (planted via plant_flower_at), a
## grass seed's (planted via plant_grass_at), or -- if neither -- tree fruit
## (try_plant_seed_at). All three ride the same carry timer; only one of
## these two flags is ever true at a time, and every _take_targeted_* method
## resets BOTH before setting its own, so a stale flag from a previous kind
## can never survive into what a later swallowed item plants (see
## _step_seed_carrying).
var _carried_seed_is_flower := false
var _carried_seed_is_grass := false

## How strongly a pollinator's drift bends up the scent gradient, 0 = pure
## wander, 1 = fly straight at the flowers. Partial on purpose: a butterfly
## that beelines looks scripted, one that merely LEANS toward blooms while
## still wandering reads as foraging.
const SCENT_STEER_WEIGHT := 0.55

## Re-sniffing every frame would query the flower set per flyer per frame;
## the field barely changes at that rate, so it's cached between sniffs.
const SCENT_SNIFF_INTERVAL := 0.5
var _scent_accumulator := 0.0
var _scent_direction := Vector2.ZERO

## Foraging state (see PollinatorForaging). Steering alone has a stable
## attractor at the strongest bloom, so a pollinator that only steered just
## oscillated over one flower forever. Now it commits to a target, lands,
## drinks, remembers it, and moves on.
## Where it FLIES to: the blossom, above the stem.
var _forage_target = null  # Vector2, or null while wandering
## The flower's OWN position (its stem base). Kept separate from the landing
## point because both drinking and visit-memory key off it: draining needs
## the flower's tile (the blossom sits a stem-height up, which resolves to
## the tile ABOVE it) and choose_target compares against it. Conflating the
## two made every approach both fail to drink AND fail to register as
## visited, so the same flower was re-targeted forever -- the bobbing loop.
var _forage_flower = null  # Vector2, or null
## Whether `_forage_target`/`_forage_flower` above is a blossoming TREE (see
## EarthChunkManager.blossoms_near) rather than a flower -- decides which
## world call fires on arrival (see _process): record_pollination_visit_at
## for a tree, drink_nectar_at for a flower. Only ever set true for
## TREE_POLLINATING_SPECIES ("bee" -- see _step_scent); every other flyer
## keeps working flowers exclusively.
var _forage_target_is_tree := false
var _drink_remaining := 0.0

## What this pollinator carries away from its last flower visit (see
## Pollination.pollen_after_visit): "" until it visits a male flower, and
## then that flower's own species. A female flower leaves it alone -- a
## single load can fertilise more than one plant, which is why one bee is
## worth anything at all -- and a later male replaces it. This needs no
## decay or reset logic of its own: it is exactly and only what that pure
## function computes on each visit.
var _carried_pollen := ""
var _visited: Array = []
var _elapsed_time := 0.0

## Where this pollinator belongs: relocation hops are leashed to it (see
## PollinatorForaging.MAX_RELOCATION_TILES), so a fruitless search can't
## random-walk the flyer clean out of the flowered, loaded part of the world.
## Captured lazily from `home` rather than in setup(), so it doesn't depend on
## whether a caller assigns home before or after wiring up movement. Re-
## anchored wherever the flyer actually finds nectar, so its territory follows
## the food instead of pinning it to a spawn point that may have gone barren.
var _origin = null  # Vector2, or null until first needed

## Bumped every time a target is chosen, and mixed into the scatter seed so a
## pollinator's successive picks differ from each other while staying
## deterministic for a given flyer (see PollinatorForaging.choose_target).
var _forage_pick_index := 0


## `movement` (an AmbientFlyerMovement tuned per species-category -- see
## AmbientFlyerRenderer) drives this marker's flight; left unset (default
## null), it stays still, the same isolated-test fallback other markers use.
## Flying things draw above ground clutter.
##
## Flowers, grass and flyers all sort by Y in one tree, and a flower is
## anchored at its stem FOOT so it sorts against the player like a tree does.
## A butterfly hovering at the blossom is higher on screen -- a smaller y --
## than the flower it is visiting, so it sorted BEHIND the bloom and
## disappeared into it. Y-sorting cannot resolve that, because the two are
## answering different questions: the flower's sort position is where it is
## rooted and the flyer's is where it is flying. Being airborne is the answer.
const AIRBORNE_Z_INDEX := 1


func _ready() -> void:
	add_to_group(HoverTargetFinder.GROUP_NAME)
	add_to_group(FLOCK_GROUP)
	z_index = AIRBORNE_Z_INDEX


## This individual's own AnimalFitness fitness_score, derived from
## wander_seed (see AnimalFitness.phenotype_for) -- AnimalFitness's first
## real caller for this species: a bee's own fitness modestly scales its
## pollination effectiveness (_step_scent's tree-blossom branch, via
## FruitingModel.visit_weight_for_fitness) and a bird's own fitness modestly
## scales its seed-predation chance (_step_seed_carrying, via
## SeedEndozoochory.seed_is_consumed's forager_seed). Recomputed on each
## (rare, throttled) call rather than cached at declaration time, since
## wander_seed is only assigned by AmbientFlyerRenderer AFTER construction.
func _fitness_score() -> float:
	return _animal_fitness.fitness_score(_animal_fitness.phenotype_for(wander_seed))


func setup(movement: AmbientFlyerMovement) -> void:
	_movement = movement


## For World's mouse-hover animal-name tooltip.
func get_display_name() -> String:
	return species.capitalize()


var _lod_accumulated := 0.0

## Courtship (see Courtship / concept/ecosystem_dynamics.md): who this flyer
## is dancing with, how far into the dance they are, and how long until it is
## willing to court again. `_courting_with` is a plain instance id rather than
## a node reference, so a partner that despawns mid-dance simply ends it.
var _courting_with := 0
var _courting_centre := Vector2.ZERO
var _courting_elapsed := 0.0
var _courting_cooldown := 0.0
## Throttle on the (whole-group) partner search after it comes up empty, so an
## idle adult doesn't rescan every flyer every frame (see _step_courtship).
const PARTNER_SEARCH_INTERVAL := 0.5
var _partner_search_cooldown := 0.0
var _courtship_round := 0
## How old this flyer is, in real seconds. Spawned flyers start as ADULTS --
## the meadow is not full of newborns -- while anything born from a courting
## pair starts at zero and has to grow up (see LifeCycle).
var age_seconds := LifeCycle.MATURE_SECONDS
## The size this flyer is when fully grown. Captured when the renderer sets
## `scale`, so growth scales the species' own adult size rather than assuming
## every flyer is the same size.
var _adult_scale := Vector2.ONE

## Set by the renderer so a mating can tell the world about its offspring.
var courtship_world = null

## Distance-based update rate (see SimulationLod). Returns the time to advance
## by, or NEGATIVE when this frame should be skipped entirely.
##
## Negative rather than zero as the skip signal, because zero is a legitimate
## step: a zero-delta frame still has to run the body (a caller passing 0.0
## expects state to settle, not to be ignored -- see
## test_processing_a_zero_delta_frame_leaves_is_moving_false).
##
## The accumulated time is handed to the update when it does run, so a skipped
## frame is never LOST time -- a creature far from the player lives at exactly
## the same rate, it just does so in fewer, larger steps that nobody is close
## enough to see.
func _lod_step(delta: float) -> float:
	_lod_accumulated += delta
	var player = _nearest_player_position()
	if player == null:
		return _take_lod_step()  # nobody to be far from: always full rate
	var interval := SimulationLod.update_interval(position.distance_to(player))
	if _lod_accumulated < interval:
		return -1.0
	return _take_lod_step()


func _take_lod_step() -> float:
	var step := _lod_accumulated
	_lod_accumulated = 0.0
	return step


## Cheap: the player group holds one node in solo play. Cached per frame by
## the caller rather than scanned per creature would be better still, but this
## is already off the hot path for everything nearby.
func _nearest_player_position():
	# Not in the tree (a marker built standalone in a test) means there is no
	# player to measure against, so it runs at full rate.
	if not is_inside_tree():
		return null
	# Cache the player node -- this runs every frame for every flyer just to
	# find the (single) player; re-query only when the cached ref is invalid.
	if _cached_player == null or not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return null
		_cached_player = players[0]
	return _cached_player.position


var _cached_player: Node = null


func _process(frame_delta: float) -> void:
	# Off-screen flyers update in fewer, larger steps (see SimulationLod).
	# There are hundreds of these -- 266 butterflies were counted in one
	# meadow -- and almost none of them are on screen.
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	_elapsed_time += delta
	# Runs regardless of ground-forage/wander state -- a carried seed keeps
	# digesting whether the bird is mid-flight, hunting its next meal, or
	# sitting on a branch.
	_fullness = BirdDigestion.fullness_after(_fullness, delta)
	_step_seed_carrying(delta)

	_step_growing(delta)

	# Courting takes precedence over foraging: a pair mid-dance is doing that
	# and nothing else, which is what makes it legible as an interaction
	# rather than two flyers happening to overlap.
	if _step_courtship(delta):
		_animate_wings()
		return
	if _movement == null:
		return

	# Ground foraging runs BEFORE the perched check, and has to: this is the
	# only thing in the game that ever sets `perched` (it was a dead flag
	# until worms landed), and the early-return below would otherwise freeze
	# the bird's own state machine the instant it sat down -- it would peck
	# once and never stand up again. Returns false for every flyer that isn't
	# a ground feeder, and while a ground feeder is merely airborne, so the
	# ordinary wander/pollinator path below is untouched.
	if _step_ground_forage(delta):
		return

	if perched:
		_animate_wings()
		return  # sitting still: no drift, no beat

	var before := position

	# Sitting on a bloom, drinking: hold still (wings still beat) until done,
	# then bank the visit and go looking for the next one.
	if _drink_remaining > 0.0:
		_drink_remaining -= delta
		_animate_wings()
		return

	_step_scent(delta)

	if _forage_target != null:
		# Committed to a flower: fly straight at it, and land on arrival.
		var to_target: Vector2 = _forage_target - position
		if to_target.length() <= PollinatorForaging.LANDING_DISTANCE:
			position = _forage_target
			# Drink from, and remember, the FLOWER -- not the blossom point
			# it is now perched on (see _forage_flower). Remembered at this
			# marker's OWN elapsed time, so it's actually forgotten again
			# ~VISIT_MEMORY_SECONDS later rather than never (or immediately).
			var flower_position: Vector2 = _forage_flower
			_visited = PollinatorForaging.remember_visit(_visited, flower_position, _elapsed_time)
			_forage_target = null
			_forage_flower = null
			# A claim says where this flyer is GOING (see ForageClaims). It has
			# arrived, so it is going nowhere -- holding the claim would pin
			# this bloom in the table forever and route every neighbour around
			# grass that is actually free.
			_release_forage_claim()
			# A blossoming TREE gets the tree-side world call, never
			# drink_nectar_at -- a blossom is not a flower patch cell (see
			# EarthChunkManager.record_pollination_visit_at / _forage_target_
			# is_tree).
			var fed := false
			if _forage_target_is_tree:
				if scent_world.has_method("record_pollination_visit_at"):
					# A fitter bee is a somewhat more effective pollinator --
					# see FruitingModel.visit_weight_for_fitness for the
					# bounded +/-15% swing this individual's own fitness
					# nudges its visit by, around the flat 1.0 an average
					# bee (fitness 0.5) still banks.
					var visit_weight := FruitingModel.visit_weight_for_fitness(_fitness_score())
					fed = scent_world.record_pollination_visit_at(flower_position, visit_weight)
			else:
				fed = scent_world.drink_nectar_at(flower_position)
				# Nectar and pollen are separate resources here (FlowerPatch
				# tracks _nectar and _pollinated as separate dicts), so this
				# runs regardless of `fed` -- a drained bloom can still
				# exchange pollen.
				if scent_world.has_method("pollinate_flower_at"):
					_carried_pollen = scent_world.pollinate_flower_at(flower_position, _carried_pollen)
			_forage_target_is_tree = false
			if fed:
				_drink_remaining = PollinatorForaging.DRINK_SECONDS
				# Somewhere that actually feeds it: make this the centre of
				# its territory, so the relocation leash follows the food
				# rather than holding it to a spawn point that has gone
				# barren.
				_origin = flower_position
			# Already drained: the visit is banked above, so it moves on at
			# the next sniff instead of sitting on an empty bloom.
			return
		# Tumbling rather than tracking a straight line at the bloom (see
		# PollinatorForaging.tumbled_heading): real butterfly flight is
		# erratic, and it steadies up only as it closes in to land.
		var heading := PollinatorForaging.tumbled_heading(
			to_target, to_target.length(), _elapsed_time, wander_seed
		)
		position += heading * _movement.speed * delta
		face_travel(position - before, delta)
		return

	if _scent_direction == Vector2.ZERO:
		position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	else:
		# Blend the wander heading with the scent gradient rather than
		# replacing it, so the flyer still meanders while drifting toward
		# the strongest bloom (see ScentField.gradient_direction).
		var wander := _movement.direction_at(home, position, _elapsed_time, wander_seed)
		var steered := wander.lerp(_scent_direction, SCENT_STEER_WEIGHT)
		if steered.length() <= 0.001:
			# The wander heading and the scent gradient pointed against each
			# other and cancelled. Blending opposing vectors and then using
			# the residual is ill-conditioned -- here it meant simply not
			# moving that frame, i.e. a flyer stalling in mid-air (reported:
			# "butterflies should only stop moving when they sit down on a
			# flower... not during wandering"). Fall back to the wander
			# heading: only drinking may ever hold a flyer still.
			steered = wander
		position += steered.normalized() * _movement.speed * delta
	var moved := position - before
	if moved.length() > 0.001:
		face_travel(moved, delta)
	_animate_wings()


## How much horizontal travel is needed before the sprite mirrors. Without
## a deadzone, a near-vertical drift jitters either side of zero and the
## bird strobes between facings.
const FACING_DEADZONE := 0.05

## The bird must want to turn for this long before it actually does.
##
## A deadzone alone was not enough: the wander's horizontal component
## crosses zero constantly, so the sprite still mirrored several times a
## second and read as two overlapping birds. A real bird BANKS slowly and
## flaps fast -- the wings are the quick part, the heading is not. Holding
## a facing until the flyer has genuinely been travelling the other way for
## this long separates those two rates.
const FACING_TURN_DELAY := 1.4

## How long the flyer has continuously wanted to face the other way.
var _contrary_travel_time := 0.0


## Points the flyer the way it is travelling by MIRRORING it, never by
## rotating. Setting `rotation = moved.angle()` (as this did) spun the
## sprite a full 180 degrees whenever the wander reversed, rendering the
## bird upside-down -- reported as "birds appear doubled as they rotate 180
## degree with every wing flap". The art is drawn facing right, so facing
## left is a horizontal flip.
## Refreshes this pollinator's sense of where the flowers are, on a throttled
## interval. A lone bloom still pulls (weakly) because the gradient is
## sampled from the summed field, not from a "is there a meadow" test.
func _step_scent(delta: float) -> void:
	if scent_world == null:
		return
	_scent_accumulator += delta
	if _scent_accumulator < SCENT_SNIFF_INTERVAL:
		return
	_scent_accumulator = 0.0
	# NOTE: a committed flyer keeps sniffing from here on. This used to
	# early-return outright ("don't re-target while already committed"), which
	# fixed a real thrash -- re-picking freely mid-approach had it oscillating
	# between candidates instead of ever arriving at one -- but it bought that
	# with the opposite failure: a flyer committed to a bloom three tiles away
	# sailed straight past a live, unvisited bloom a fraction of a tile off
	# its path without even looking at it (reported: "butterfly is still
	# ignoring unvisited flowers"). Both are avoided by looking every sniff
	# and switching only for a MEANINGFULLY better bloom -- see
	# RETARGET_IMPROVEMENT_TILES and _is_worth_switching_to below.
	# Queried at the RANGED radius, not just as far as scent carries (see
	# PollinatorForaging.FORAGE_SEARCH_TILES). Sniffing only within
	# ScentField.RADIUS_TILES meant a flyer whose own neighbourhood was
	# worked out could not even see the next patch over, so it had nothing to
	# do but drift. The gradient below is unaffected by the wider list:
	# ScentField.falloff returns exactly 0.0 beyond RADIUS_TILES, so the
	# extra flowers contribute nothing to the steering, only to target
	# choice.
	# KNOWN DIVERGENCE from "a pollinator should only steer to a flower once
	# scent strength reaches a threshold": targeting still queries the wide
	# FORAGE_SEARCH_TILES (18 tiles) while scent only carries
	# ScentField.RADIUS_TILES (6), so a flyer does commit to blooms it could
	# not literally smell. Gating commitment on real scent concentration was
	# implemented and REVERTED: with it, a pollinator that had worked its
	# patch dry searched by wandering alone and never found a patch 12 tiles
	# away in 33 simulated minutes -- foraging stopped happening at all,
	# which is strictly worse than the unrealistic reach. Making the rule
	# work needs a directed search (holding a heading across several
	# relocation hops so it flies transects instead of random-walking), not
	# just the gate. See docs/progress.md.
	var flowers: Array = scent_world.flowers_near(
		position, int(PollinatorForaging.FORAGE_SEARCH_TILES)
	)
	# ScentField's gradient is about which species are in BLOOM, not their
	# current nectar level -- it doesn't know a flower has been drained. Left
	# unfiltered, a fully-drained local patch kept pulling the steering
	# toward its exact position just as strongly as a full one, even though
	# choose_target correctly refused to land there -- which read as orbiting
	# the same spent bloom (reported: "they should move to a new flower
	# field when the last flower nearby got emptied so they don't circle the
	# last flower for an hour"). Filtering here, before the gradient is even
	# computed, makes an all-drained patch read as nothing to smell at all,
	# so ordinary wander actually carries the flyer elsewhere.
	# In BLOOM this season, and holding nectar. Bloom is filtered here, at the
	# single point every downstream decision reads, so scent-steering,
	# target-choice and the rendered world all agree about what is on offer.
	# They did not: ScentField zeroes an out-of-bloom species' scent, but
	# choose_target never checked bloom, so a pollinator could not SMELL an
	# out-of-season flower yet would still drink one it happened to drift
	# into -- while EarthChunkManager drew every planted flower year-round
	# regardless. The visible result was a butterfly sitting beside two
	# perfectly good-looking flowers doing nothing (reported twice: "they are
	# not attracted by scent at all"), because those blooms were summer
	# species being drawn in spring.
	var season: String = scent_world.current_season()
	# Bloom is filtered; NECTAR LEVEL deliberately is not. A pollinator can
	# see (and smell) that a flower is blooming from a distance, but it
	# cannot tell how full it is without landing -- filtering on nectar here
	# made flyers skip blooms they had never visited, as though they already
	# knew (reported: "somehow they know it's empty without checking for
	# nectar first"). Emptiness is discovered on arrival and remembered
	# personally, for VISIT_MEMORY_SECONDS, which is what moves the flyer on
	# without granting it knowledge it has no way to have.
	var blooming: Array = flowers.filter(
		func(f): return FlowerSpecies.is_in_bloom(String(f["species"]), season)
	)
	# Bees alone also recognize blossoming apple/cherry trees as a food
	# source (see TreeSpecies.needs_pollinators_for / EarthChunkManager.
	# blossoms_near) -- real fruit trees are insect-pollinated and bees are
	# their primary pollinator, so this is scoped to TREE_POLLINATING_SPECIES
	# rather than every nectar-feeder here. blossoms_near already gates on
	# "in blossom right now" (spring canopy only) at the source, so these
	# merge straight into `blooming` with no is_in_bloom check of their own --
	# unlike FlowerSpecies-keyed entries, a tree species isn't in that table
	# to check against anyway.
	if species == TREE_POLLINATING_SPECIES and scent_world.has_method("blossoms_near"):
		blooming += scent_world.blossoms_near(
			position, int(PollinatorForaging.FORAGE_SEARCH_TILES)
		)
	# Two lists, deliberately. STEERING uses only blooms that still hold
	# nectar -- a spent flower has no reward left to advertise, and letting
	# drained blooms keep pulling on the gradient is what made a flyer orbit
	# a worked-out patch. TARGET CHOICE (below) uses the full blooming list,
	# nectar unknown, so an unvisited flower is always worth flying over to
	# check.
	# Blooms that still hold nectar AND that this flyer has not just worked.
	# The visit-memory half matters as much as the nectar half: the gradient
	# outweighs the wander in the steering blend (SCENT_STEER_WEIGHT), so a
	# bloom this flyer is forbidden to land on but still smells pulls it into
	# a hover it never leaves -- see PollinatorForaging.unvisited_only.
	var flowers_with_nectar: Array = PollinatorForaging.unvisited_only(
		blooming.filter(func(f): return float(f.get("nectar", 1.0)) > 0.0),
		_visited,
		_elapsed_time
	)
	if blooming.is_empty():
		_scent_direction = Vector2.ZERO
		_forage_target = null
		_forage_flower = null
		_forage_target_is_tree = false
		_release_forage_claim()
		_relocate()
		return
	_scent_direction = ScentField.gradient_direction(
		position, flowers_with_nectar, scent_world.current_season(), float(TerrainRenderer.TILE_SIZE)
	)
	# Pick something concrete to land on. Falls back to gradient drift above
	# when every nearby bloom is drained or already visited, so the flyer
	# leaves a worked-out patch instead of hovering in it. `_elapsed_time`:
	# visit memory now expires by real time (see PollinatorForaging.
	# VISIT_MEMORY_SECONDS), not by a bounded count.
	# The scatter seed is this flyer's own, mixed with how many targets it has
	# picked so far: two pollinators sitting in the same patch pick different
	# blooms instead of queueing behind each other for the same one, and a
	# single pollinator's successive picks vary -- while both stay fully
	# deterministic (see PollinatorForaging.NEAREST_CANDIDATE_POOL).
	_forage_pick_index += 1
	# What the NEIGHBOURS have already committed to (see ForageClaims). The
	# scatter seed alone could not fix chaining, because 86.5% of targeting
	# decisions had only one bloom in the scatter band -- nothing to scatter
	# over -- so 62.1% of nearby pairs picked the same flower and arrived at
	# an empty one. choose_target DEMOTES claimed blooms within the band
	# rather than excluding them, so this can never make a flyer skip a
	# closer bloom or stall with nothing to do.
	var peer_claims: Array = []
	if scent_world.has_method("claims_near"):
		peer_claims = scent_world.claims_near(
			position, PollinatorForaging.FORAGE_SEARCH_TILES * float(TerrainRenderer.TILE_SIZE),
			get_instance_id()
		)
	var target := PollinatorForaging.choose_target(
		position, blooming, _visited, _elapsed_time,
		hash("%d_%d_forage" % [wander_seed, _forage_pick_index]), peer_claims
	)
	# Aim at the blossom, falling back to the flower's own position for
	# any caller that does not publish a landing point.
	if target.is_empty():
		_forage_target = null
		_forage_flower = null
		_forage_target_is_tree = false
		_release_forage_claim()
		_relocate()
	else:
		var candidate_landing: Vector2 = target.get("landing", target["position"])
		# Already on its way somewhere: only abandon that for a genuinely
		# better bloom, never for a near-tie (see _is_worth_switching_to).
		if _forage_target != null and not _is_worth_switching_to(candidate_landing):
			return
		_forage_flower = target["position"]
		_forage_target = candidate_landing
		_forage_target_is_tree = TreeSpecies.needs_pollinators_for(String(target.get("species", "")))
		# Announce it, so neighbours deciding in the next moment can route
		# around this flyer instead of chaining behind it. Claiming again
		# simply replaces this flyer's previous row, so the table stays
		# bounded by live flyer count (see ForageClaims) -- which is also what
		# moves the claim when it switches targets mid-flight.
		if scent_world.has_method("claim_flower"):
			scent_world.claim_flower(_forage_flower, get_instance_id())
		# Move the wander tether to the flower it's committing to. Without
		# this the flyer flew to a distant bloom and was then immediately
		# dragged back by AmbientFlyerMovement's home anchor (it steers
		# straight home once further than `radius` away), so it could never
		# actually take up residence in a new patch -- measured before this
		# fix, a flyer with a full patch 12 tiles away drank nothing at all
		# in ten simulated minutes and never got further than 31.6px from a
		# 30px tether.
		if _forage_flower.distance_to(home) > _movement.radius:
			home = _forage_flower


## Drives this bird's ground-feeding cycle (see GroundForageBehavior /
## docs/concept/soil_fauna.md), applying the state machine's decisions to the
## real world: flying at the worm, sitting down on it, and actually removing
## it from the chunk.
##
## Returns true when it has fully handled this frame (the bird is committed to
## a worm, or sitting on one), and false when the bird should carry on with
## ordinary ambient flight -- which is every frame for a flyer that doesn't
## ground-feed at all.
func _step_ground_forage(delta: float) -> bool:
	if ground_forage == null:
		return false
	# A bird that is not hungry gets on with its life. Mid-cycle is left alone
	# -- a bird already down on the grass finishes its peck rather than
	# abandoning it the instant its crop fills.
	if ground_forage.can_commit() and not BirdDigestion.is_hungry(_fullness):
		return false

	var struck := ground_forage.advance(delta)
	# The bird sits down for exactly the phases it is on the ground for, and
	# stands up again the moment the cycle closes.
	perched = ground_forage.is_grounded()

	match ground_forage.phase:
		GroundForageBehavior.Phase.DESCENDING:
			# Exactly one of worm/fruit/seed/grass-seed is ever set at a time
			# (see the field doc comments) -- whichever committed is what it
			# flies at.
			if _worm_target != null:
				_fly_at_worm(delta)
			elif _fruit_target != null:
				_fly_at_fruit(delta)
			elif _seed_target != null:
				_fly_at_seed(delta)
			elif _grass_seed_target != null:
				_fly_at_grass_seed(delta)
			_animate_wings()
			return true
		GroundForageBehavior.Phase.PECKING:
			# The strike resolves once, part way through the peck (see
			# GroundForageBehavior.PECK_STRIKE_FRACTION), with the beak
			# actually down in the grass -- so the worm/fruit disappears on
			# the frame the player sees the head go in, and the animation
			# plays out afterwards.
			if struck:
				if _worm_target != null:
					_take_targeted_worm()
				elif _fruit_target != null:
					_take_targeted_fruit()
				elif _seed_target != null:
					_take_targeted_seed()
				elif _grass_seed_target != null:
					_take_targeted_grass_seed()
			_animate_wings()
			return true
		GroundForageBehavior.Phase.RESUMING:
			_animate_wings()
			return true

	# SEEKING: airborne. Drop any stale target and look for the next worm,
	# then the next fruit, on a throttled interval, then let ordinary flight
	# carry the bird. Both are tried every tick -- worm-hunting and fruit-
	# foraging run in PARALLEL, not as alternatives; if the worm search
	# already committed (moved ground_forage out of SEEKING), the fruit
	# search's own can_commit() check is simply false and it no-ops.
	_worm_target = null
	_fruit_target = null
	_seed_target = null
	_grass_seed_target = null
	_look_for_worms(delta)
	_look_for_fruit(delta)
	_look_for_seeds(delta)
	_look_for_grass_seeds(delta)
	return false


## Flies straight at the committed worm, landing on arrival. Aborts if the
## target vanished (the chunk unloaded mid-approach), so the bird returns to
## the air rather than descending onto nothing.
func _fly_at_worm(delta: float) -> void:
	if _worm_target == null:
		ground_forage.abort()
		return
	var before := position
	var to_target: Vector2 = _worm_target - position
	if to_target.length() <= GroundForageBehavior.LANDING_DISTANCE:
		# Snap onto the worm, so the bird is standing ON what it eats rather
		# than pecking at empty grass a few pixels away.
		position = _worm_target
		ground_forage.arrive()
		perched = true
		return
	position += to_target.normalized() * _movement.speed * delta
	face_travel(position - before, delta)


## Actually removes the worm from the world. The behaviour module decides WHEN
## the strike lands; this is the only place the real chunk gets touched -- the
## same split PiscivoreBirdMarker uses for a dive's catch.
func _take_targeted_worm() -> void:
	_fullness = BirdDigestion.fullness_after_meal(_fullness)
	if worm_world == null or _worm_target == null:
		return
	worm_world.take_worm_at(_worm_target)


## Flies straight at the committed fruit, landing on arrival. Mirrors
## _fly_at_worm exactly -- the flight itself doesn't care what's on the
## ground, only which target var is driving it.
func _fly_at_fruit(delta: float) -> void:
	if _fruit_target == null:
		ground_forage.abort()
		return
	var before := position
	var to_target: Vector2 = _fruit_target - position
	if to_target.length() <= GroundForageBehavior.LANDING_DISTANCE:
		position = _fruit_target
		ground_forage.arrive()
		perched = true
		return
	position += to_target.normalized() * _movement.speed * delta
	face_travel(position - before, delta)


## Actually removes the fruit from the world (see EarthChunkManager.
## take_fruit_at) and, unless a seed is already being carried (see
## _carried_seed_species), starts this bird's carry timer for the species it
## just swallowed (see SeedEndozoochory.carry_distance_tiles) -- converted
## from a distance to a TIME here, at this bird's own flight speed, since the
## marker has no reliable notion of "distance travelled since eating" once
## ordinary wander/other foraging resumes in between.
func _take_targeted_fruit() -> void:
	_fullness = BirdDigestion.fullness_after_meal(_fullness)
	if fruit_world == null or _fruit_target == null:
		return
	var eaten_species: String = fruit_world.take_fruit_at(_fruit_target)
	if eaten_species == "" or _carried_seed_species != "":
		return
	_carried_seed_species = eaten_species
	# Neither flag: this is tree fruit, the "otherwise" case _step_seed_carrying
	# falls through to. Reset explicitly rather than relying on a fresh bird's
	# default -- a bird that swallowed a flower or grass seed earlier in its
	# life, planted it, and is only now eating fruit for the first time would
	# otherwise carry a stale flag from that first meal forever (see the
	# shared doc comment on _carried_seed_is_flower/_carried_seed_is_grass).
	_carried_seed_is_flower = false
	_carried_seed_is_grass = false
	var carry_tiles := SeedEndozoochory.carry_distance_tiles(wander_seed + _fruit_pick_index)
	_carry_seconds_remaining = carry_tiles * float(TerrainRenderer.TILE_SIZE) / maxf(_movement.speed, 1.0)


## Looks for the next worm, on a throttled interval, and commits to one.
func _look_for_worms(delta: float) -> void:
	if worm_world == null:
		return
	_worm_sniff_accumulator += delta
	if _worm_sniff_accumulator < WORM_SNIFF_INTERVAL:
		return
	_worm_sniff_accumulator = 0.0
	# The re-hunt interval is the "run" half of a robin's run-stop-peck cycle:
	# it has to fly around a while between meals (see
	# GroundForageBehavior.REHUNT_SECONDS).
	if not ground_forage.can_commit():
		return
	var worms: Array = worm_world.worms_near(
		position, int(GroundForageBehavior.SEARCH_TILES)
	)
	if worms.is_empty():
		return
	_worm_pick_index += 1
	# Scatter seed from PixelNoise, NOT from a string hash. choose_worm takes
	# it modulo a tiny candidate pool, which is precisely the seeded-index
	# form Godot's `hash` collapses on: measured here at every seed in a
	# plausible range landing in bucket 0, so every robin in a meadow would
	# have picked the identical worm and conga-lined behind it -- the same
	# single-bucket freeze PixelNoise's doc comment records ("every village
	# house came out the same size"). Mixed with this bird's own pick count so
	# its successive choices differ while staying fully deterministic.
	var target := GroundForageBehavior.choose_worm(
		position, worms, PixelNoise.value(wander_seed, _worm_pick_index, 0)
	)
	if target.is_empty():
		return
	_worm_target = target["position"]
	if not ground_forage.begin_descent():
		_worm_target = null
		return
	# Move the wander tether to the worm it is committing to. Ambient flight
	# steers straight back home once further than `radius` away (70px for a
	# bird), which is well inside GroundForageBehavior.SEARCH_TILES -- without
	# this the bird would be dragged back off any worm it could actually see,
	# the exact failure the pollinator path already hit and fixed.
	if _worm_target.distance_to(home) > _movement.radius:
		home = _worm_target


## Looks for the next fallen fruit, on a throttled interval, and commits to
## one -- the same shape as _look_for_worms, run independently so a bird with
## both diets tries worms first, then fruit, every SEEKING tick.
func _look_for_fruit(delta: float) -> void:
	if fruit_world == null:
		return
	_fruit_sniff_accumulator += delta
	if _fruit_sniff_accumulator < WORM_SNIFF_INTERVAL:
		return
	_fruit_sniff_accumulator = 0.0
	if not ground_forage.can_commit():
		return
	# By SMELL, and much further than sight, when the world offers it.
	#
	# A bird that only finds fruit it happens to fly over is not foraging, and
	# a windfall under a tree went unvisited for exactly that reason. A nose
	# reaches Olfaction.MAX_RANGE_TILES, and it also declines what has gone
	# over -- a robin takes ripe fruit and leaves the rot to the flies.
	var fruit: Array = []
	if fruit_world.has_method("smells_near") and ScentForaging.forages_by_smell(species):
		var smelled: Array = fruit_world.smells_near(position, Olfaction.MAX_RANGE_TILES)
		var best := ScentForaging.best_source(species, position, smelled)
		if not best.is_empty():
			fruit = [best]
	if fruit.is_empty():
		fruit = fruit_world.fruit_near(
			position, int(GroundForageBehavior.SEARCH_TILES)
		)
	# WHICH fruit, not just whether fruit: a sparrow works walnuts but not
	# soft cherries (see FlyerDiet.eats_fruit_species).
	fruit = fruit.filter(
		func(f): return FlyerDiet.eats_fruit_species(species, String(f.get("species", "")))
	)
	if fruit.is_empty():
		return
	_fruit_pick_index += 1
	var target := GroundForageBehavior.choose_worm(
		position, fruit, PixelNoise.value(wander_seed, _fruit_pick_index, 1)
	)
	if target.is_empty():
		return
	_fruit_target = target["position"]
	if not ground_forage.begin_descent():
		_fruit_target = null
		return
	if _fruit_target.distance_to(home) > _movement.radius:
		home = _fruit_target


## Flies straight at the committed seed, landing on arrival -- same shape as
## _fly_at_worm/_fly_at_fruit.
func _fly_at_seed(delta: float) -> void:
	if _seed_target == null:
		ground_forage.abort()
		return
	var before := position
	var to_target: Vector2 = _seed_target - position
	if to_target.length() <= GroundForageBehavior.LANDING_DISTANCE:
		position = _seed_target
		ground_forage.arrive()
		perched = true
		return
	position += to_target.normalized() * _movement.speed * delta
	face_travel(position - before, delta)


## Eats the committed seed and starts carrying it, so it can be planted
## somewhere else entirely (see _step_seed_carrying).
func _take_targeted_seed() -> void:
	_fullness = BirdDigestion.fullness_after_meal(_fullness)
	if seed_world == null or _seed_target == null:
		return
	var eaten_species: String = seed_world.take_seed_at(_seed_target)
	if eaten_species == "" or _carried_seed_species != "":
		return
	_carried_seed_species = eaten_species
	_carried_seed_is_flower = true
	_carried_seed_is_grass = false  # see the shared doc comment on both flags
	# Same carry model as fruit (see _take_targeted_fruit): a distance, not a
	# fixed time, so a faster bird carries the seed proportionally further.
	var carrier_seed := wander_seed + _seed_pick_index
	_carried_seed_carrier_seed = carrier_seed
	var carry_tiles := SeedEndozoochory.carry_distance_tiles(carrier_seed)
	_carry_seconds_remaining = carry_tiles * float(TerrainRenderer.TILE_SIZE) / maxf(_movement.speed, 1.0)


## Whether a grass seed this bird can currently see is strictly closer than
## every flower seed candidate it can also see right now -- the tie-break
## between the two seed kinds that replaces the old fixed
## flower-seed-always-first order (see _look_for_seeds).
##
## Deliberately compares raw candidate distance, not the post-scatter pick
## GroundForageBehavior.choose_worm would land on for either list (see
## PollinatorForaging.NEAREST_CANDIDATE_POOL): "is the grass seed genuinely
## closer" is a question about what's actually on the ground, not about which
## of several near-tied candidates the scatter happens to land on -- that
## scatter still applies AFTER this decides which kind to go for, exactly as
## before, inside whichever of _look_for_seeds/_look_for_grass_seeds ends up
## committing.
##
## A tie (equal distance) keeps the flower seed, matching the old order in
## the one case where "nearest" genuinely can't decide -- ties are not the
## gap this exists to fix, and the two seed kinds never legitimately share
## the exact same tile in practice.
func _grass_seed_is_nearer_than(flower_seeds: Array) -> bool:
	if seed_world == null or not seed_world.has_method("grass_seeds_near"):
		return false
	var grass_seeds: Array = seed_world.grass_seeds_near(
		position, int(GroundForageBehavior.SEARCH_TILES)
	)
	if grass_seeds.is_empty():
		return false
	var nearest_flower := INF
	for seed in flower_seeds:
		nearest_flower = minf(nearest_flower, position.distance_to(seed["position"]))
	var nearest_grass := INF
	for seed in grass_seeds:
		nearest_grass = minf(nearest_grass, position.distance_to(seed["position"]))
	return nearest_grass < nearest_flower


## Looks for the next seed on a throttled interval, in parallel with the
## worm and fruit searches (see _step_ground_forage's SEEKING branch).
##
## Worm and fruit still unconditionally outrank both seed kinds (checked
## earlier in that same SEEKING branch) -- protein/energy wins over a seed
## snack regardless of distance. But between flower seed and grass seed
## specifically, this backs off to let _look_for_grass_seeds (called right
## after this, still in the same SEEKING branch) commit instead whenever a
## grass seed is actually the nearer of the two -- see
## _grass_seed_is_nearer_than for why: a live probe found a fixed
## flower-seed-always-first order meant a sparrow with ANY flower seed in
## range never even attempted grass seed, however much closer the grass seed
## really was (docs/concept/long_grass.md, "11/11 dispersal events from mice,
## zero from sparrows").
func _look_for_seeds(delta: float) -> void:
	if seed_world == null:
		return
	_seed_sniff_accumulator += delta
	if _seed_sniff_accumulator < WORM_SNIFF_INTERVAL:
		return
	_seed_sniff_accumulator = 0.0
	if not ground_forage.can_commit():
		return
	var seeds: Array = seed_world.seeds_near(
		position, int(GroundForageBehavior.SEARCH_TILES)
	)
	if seeds.is_empty():
		return
	if _grass_seed_is_nearer_than(seeds):
		return
	_seed_pick_index += 1
	var target := GroundForageBehavior.choose_worm(
		position, seeds, PixelNoise.value(wander_seed, _seed_pick_index, 1)
	)
	if target.is_empty():
		return
	_seed_target = target["position"]
	if not ground_forage.begin_descent():
		_seed_target = null
		return
	if _seed_target.distance_to(home) > _movement.radius:
		home = _seed_target


## Flies straight at the committed grass seed, landing on arrival -- same
## shape as _fly_at_seed/_fly_at_worm/_fly_at_fruit.
func _fly_at_grass_seed(delta: float) -> void:
	if _grass_seed_target == null:
		ground_forage.abort()
		return
	var before := position
	var to_target: Vector2 = _grass_seed_target - position
	if to_target.length() <= GroundForageBehavior.LANDING_DISTANCE:
		position = _grass_seed_target
		ground_forage.arrive()
		perched = true
		return
	position += to_target.normalized() * _movement.speed * delta
	face_travel(position - before, delta)


## Eats the committed grass seed and starts carrying it, exactly like flower
## seed (see _take_targeted_seed) -- a sparrow's crop does not distinguish
## which plant a swallowed seed came from, only _carried_seed_is_grass does,
## so _step_seed_carrying calls plant_grass_at instead of plant_flower_at.
func _take_targeted_grass_seed() -> void:
	_fullness = BirdDigestion.fullness_after_meal(_fullness)
	if seed_world == null or _grass_seed_target == null:
		return
	var eaten: bool = seed_world.take_grass_seed_at(_grass_seed_target)
	if not eaten or _carried_seed_species != "":
		return
	# No species to carry -- a chunk grows only one kind of grass -- but
	# _carried_seed_species still has to go non-empty, since that is what
	# every other part of the carry cycle (only-one-at-a-time, the carry
	# timer, _step_seed_carrying) gates on.
	_carried_seed_species = "grass"
	_carried_seed_is_flower = false  # see the shared doc comment on both flags
	_carried_seed_is_grass = true
	var carrier_seed := wander_seed + _grass_seed_pick_index
	_carried_seed_carrier_seed = carrier_seed
	var carry_tiles := SeedEndozoochory.carry_distance_tiles(carrier_seed)
	_carry_seconds_remaining = carry_tiles * float(TerrainRenderer.TILE_SIZE) / maxf(_movement.speed, 1.0)


## Looks for the next grass seed on a throttled interval, in parallel with
## the worm/fruit/flower-seed searches (see _step_ground_forage's SEEKING
## branch).
func _look_for_grass_seeds(delta: float) -> void:
	if seed_world == null or not seed_world.has_method("grass_seeds_near"):
		return
	_grass_seed_sniff_accumulator += delta
	if _grass_seed_sniff_accumulator < WORM_SNIFF_INTERVAL:
		return
	_grass_seed_sniff_accumulator = 0.0
	if not ground_forage.can_commit():
		return
	var seeds: Array = seed_world.grass_seeds_near(
		position, int(GroundForageBehavior.SEARCH_TILES)
	)
	if seeds.is_empty():
		return
	_grass_seed_pick_index += 1
	var target := GroundForageBehavior.choose_worm(
		position, seeds, PixelNoise.value(wander_seed, _grass_seed_pick_index, 1)
	)
	if target.is_empty():
		return
	_grass_seed_target = target["position"]
	if not ground_forage.begin_descent():
		_grass_seed_target = null
		return
	if _grass_seed_target.distance_to(home) > _movement.radius:
		home = _grass_seed_target


## Ticks down this bird's seed-carry timer (see _carried_seed_species),
## independent of ground_forage's own state -- a bird keeps digesting a
## swallowed seed while it flies, wanders, or hunts its next meal. Once the
## timer elapses, the seed is deposited at wherever the bird happens to be
## right now (see EarthChunkManager.try_plant_seed_at) -- a real bird doesn't
## pick a spot, it simply is somewhere by the time digestion finishes.
## The pre-hatch sprite (see ProceduralEggSprite), shown in place of the
## ordinary wing-flap texture for the entire COURTING/MATED/EGG span (see
## _is_pre_hatch). Set by the renderer, exactly like flap_frames/
## perched_frame -- left null for any caller that predates this, which
## simply leaves the texture alone for that span rather than erroring (see
## _animate_wings).
var egg_frame: Texture2D = null


## Records the size this flyer is when grown, so a juvenile grows toward its
## own species' adult size rather than a shared assumption.
func set_adult_scale(full_size: Vector2) -> void:
	_adult_scale = full_size


## Starts this flyer at the beginning of its life rather than as an adult --
## what separates something BORN in front of the player from the adults the
## world seeds a meadow with.
func begin_life() -> void:
	age_seconds = 0.0
	scale = _adult_scale * LifeCycle.size_scale_at(0.0)


## Ages this flyer, and grows it into its adult size if it is still young.
##
## Real time, on the scale the design asks for: a hatchling takes days to
## reach full size (see LifeCycle), so a juvenile is something a returning
## player notices rather than something they watch happen.
func _step_growing(delta: float) -> void:
	if age_seconds >= LifeCycle.MATURE_SECONDS:
		return
	age_seconds += delta
	scale = _adult_scale * LifeCycle.size_scale_at(age_seconds)


## One frame of courting. Returns true while this flyer is dancing, which the
## caller treats as "busy" -- a dancing butterfly is not also foraging.
##
## Both partners run this independently and never message each other: they
## agree on who leads and on whether they mated by computing the same answers
## from the same two instance ids (see Courtship.leads / pair_seed). That is
## also why a partner disappearing mid-dance is harmless -- this side simply
## finds it gone and stops.
func _step_courtship(delta: float) -> bool:
	_courting_cooldown = maxf(0.0, _courting_cooldown - delta)

	if _courting_with != 0:
		var partner = instance_from_id(_courting_with)
		if partner == null or not is_instance_valid(partner):
			_end_courtship()
			return false
		_courting_elapsed += delta
		if _courting_elapsed >= Courtship.DANCE_SECONDS:
			_finish_courtship(partner)
			return false
		# Orbit the point between the two of them.
		position = _courting_centre + Courtship.dance_offset(
			_courting_elapsed,
			_courtship_round,
			Courtship.leads(get_instance_id(), _courting_with)
		)
		return true

	# Only grown flyers court. Without an age gate the young of a watched pair
	# would start breeding themselves, and a population with no such gate
	# grows without bound however slow each individual step is.
	if not LifeCycle.can_court_at(age_seconds):
		return false
	if _courting_cooldown > 0.0 or _drink_remaining > 0.0:
		return false
	# Scanning the whole flyer group for a partner every frame is O(flyers^2)
	# across a meadow. A flyer that comes up empty waits PARTNER_SEARCH_INTERVAL
	# before scanning again (a real bee doesn't re-survey the whole field 60x a
	# second) -- pairs still form within a fraction of a second.
	_partner_search_cooldown = maxf(0.0, _partner_search_cooldown - delta)
	if _partner_search_cooldown > 0.0:
		return false
	var partner_found = _look_for_a_partner()
	if partner_found == null:
		_partner_search_cooldown = PARTNER_SEARCH_INTERVAL
		return false
	_begin_courtship(partner_found)
	return true


## The nearest same-species flyer that is also free to court. Both sides find
## each other on the same frame or on adjacent ones; whichever starts first
## sets the shared centre, and the other adopts it when it starts too.
func _look_for_a_partner():
	# A flyer built standalone in a test is not in the tree and so has nobody
	# to court, the same guard the distance LOD uses.
	if not is_inside_tree():
		return null
	for other in get_tree().get_nodes_in_group(FLOCK_GROUP):
		if other == self or other.get("species") == null:
			continue
		if not Courtship.can_court(species, String(other.species)):
			continue
		if not Courtship.can_pair(get_instance_id(), other.get_instance_id()):
			continue
		if other.get("_courting_cooldown") == null or float(other._courting_cooldown) > 0.0:
			continue
		if int(other._courting_with) != 0:
			continue
		if other.get("age_seconds") == null or not LifeCycle.can_court_at(float(other.age_seconds)):
			continue
		if position.distance_to(other.position) > Courtship.NOTICE_RADIUS_PX:
			continue
		return other
	return null


func _begin_courtship(partner) -> void:
	_courting_with = partner.get_instance_id()
	_courting_elapsed = 0.0
	_courtship_round += 1
	# The midpoint, computed identically on both sides so the pair orbits one
	# shared centre rather than two slightly different ones.
	_courting_centre = (position + partner.position) * 0.5


## The dance is over. Both partners resolve the same answer from the same
## seed, so exactly one offspring appears rather than two (only the leader
## spawns it) and neither has to tell the other what happened.
func _finish_courtship(partner) -> void:
	var seed_value := Courtship.pair_seed(
		get_instance_id(), _courting_with, _courtship_round
	)
	var mated := Courtship.mates(seed_value)
	var leads := Courtship.leads(get_instance_id(), _courting_with)
	var centre := _courting_centre
	_end_courtship()
	if mated and leads and courtship_world != null:
		if courtship_world.has_method("spawn_flyer_offspring"):
			courtship_world.spawn_flyer_offspring(species, centre)


func _end_courtship() -> void:
	_courting_with = 0
	_courting_elapsed = 0.0
	_courting_cooldown = Courtship.COOLDOWN_SECONDS


func _step_seed_carrying(delta: float) -> void:
	if _carried_seed_species == "":
		return
	_carry_seconds_remaining -= delta
	if _carry_seconds_remaining > 0.0:
		return
	# A bare GROUND seed (flower or grass) is the meal itself for a true
	# granivore -- real predation destroys the large majority of it before
	# it ever gets a chance to sprout (see SeedEndozoochory.
	# GRANIVORY_CONSUMED_CHANCE). Tree fruit is deliberately exempt: a fleshy
	# fruit exists specifically so the seed riding inside is swallowed whole
	# and passed unharmed, a real mutualism rather than predation, so that
	# branch below is never gated by this roll.
	var seed_survives := true
	if _carried_seed_is_flower or _carried_seed_is_grass:
		# forager_seed is THIS bird's own identity seed (wander_seed), fixed
		# for its whole life, separate from the per-pick roll seed
		# (_carried_seed_carrier_seed) -- a fitter individual forager is a
		# slightly more efficient predator (see SeedEndozoochory.
		# FITNESS_CHANCE_SWING), but each seed it eats still rolls
		# independently.
		seed_survives = not SeedEndozoochory.seed_is_consumed(
			_carried_seed_carrier_seed, wander_seed
		)
	# Where it lands decides what grows: a swallowed FLOWER seed becomes a
	# flower, a GRASS seed becomes a new tall-grass patch (see
	# docs/concept/long_grass.md's "Reproduction" section), tree fruit
	# becomes a tree (bird endozoochory -- see
	# concept/flora.md#bird-endozoochory). All three are simply dropped
	# where the bird happens to be, which is what ties plant spread to the
	# ecosystem's real movement corridors rather than to a spread radius --
	# unless the seed was destroyed above, in which case nothing sprouts.
	if seed_survives:
		if _carried_seed_is_flower:
			if seed_world != null and seed_world.has_method("plant_flower_at"):
				seed_world.plant_flower_at(position, _carried_seed_species)
		elif _carried_seed_is_grass:
			if seed_world != null and seed_world.has_method("plant_grass_at"):
				seed_world.plant_grass_at(position)
		elif fruit_world != null:
			fruit_world.try_plant_seed_at(position, _carried_seed_species)
	# The dropping itself: the visible half of dispersal, so the player can see
	# where the seedling under the perch came from.
	if seed_world != null and seed_world.has_method("drop_guano_at"):
		seed_world.drop_guano_at(position, _carried_seed_species)
	_carried_seed_species = ""
	_carried_seed_is_flower = false
	_carried_seed_is_grass = false


## How much closer a bloom must be than the one this flyer is already flying
## at before it will switch, in TILES.
##
## This is hysteresis, and it is the whole reason re-evaluating en route is
## safe. With no margin at all, any improvement -- a pixel, a rounding
## difference between two near-identical candidates -- flips the target, and
## the flyer oscillates between blooms instead of arriving at one (the exact
## failure the old "never re-target while committed" early-return was added
## to fix). With a margin, only a bloom that is genuinely, visibly better is
## worth the turn, so a flyer still commits and arrives while no longer
## sailing past a flower right under it.
##
## Sized against the distances that actually matter here: comfortably more
## than PollinatorForaging.LANDING_DISTANCE (4px, so an arrival can never be
## stolen from under itself) and well inside FORAGE_SEARCH_TILES, so a bloom
## anywhere in the near band can still win.
const RETARGET_IMPROVEMENT_TILES := 2.0


## Whether `candidate_landing` beats the current commitment by more than the
## hysteresis margin.
func _is_worth_switching_to(candidate_landing: Vector2) -> bool:
	var margin := RETARGET_IMPROVEMENT_TILES * float(TerrainRenderer.TILE_SIZE)
	return position.distance_to(candidate_landing) + margin < position.distance_to(_forage_target)


## Gives up this flyer's forage claim (see ForageClaims). Safe to call
## unconditionally -- releasing a claim a flyer doesn't hold is a no-op, and
## the has_method guard keeps this working against any world that predates
## claims. Despawn is handled on the chunk-unload path
## (EarthChunkManager._unload_chunk) rather than here: NOTIFICATION_PREDELETE
## is not reliable for this.
func _release_forage_claim() -> void:
	if scent_world != null and scent_world.has_method("release_flower_claim"):
		scent_world.release_flower_claim(get_instance_id())


## Nothing worth foraging anywhere in range: move the wander tether itself,
## so the flyer genuinely searches new ground instead of orbiting a barren
## spawn point forever (reported: "they ... just drift around meaninglessly").
##
## Deliberately a discrete HOP taken only once the flyer has arrived at its
## current home, rather than a continuously-receding target: that keeps the
## motion reading as ordinary wander punctuated by a purposeful move on,
## instead of an endless straight-line chase.
func _relocate() -> void:
	if _movement == null:
		return
	if _origin == null:
		_origin = home
	if position.distance_to(home) > _movement.radius:
		return  # still travelling to the last relocation -- let it arrive
	var heading := _movement.direction_at(home, position, _elapsed_time, wander_seed)
	if heading.length() <= 0.001:
		return
	var step := PollinatorForaging.RELOCATION_STEP_TILES * float(TerrainRenderer.TILE_SIZE)
	var candidate: Vector2 = home + heading.normalized() * step
	# Leashed to its territory. Unleashed, these hops are a random walk with
	# nothing pulling back, so a flyer that found nothing kept going: measured
	# at 93 tiles from spawn in ten simulated minutes, by which point it was
	# outside the chunks that have any flowers at all and could never find its
	# way back -- searching had become a one-way trip.
	var leash := PollinatorForaging.MAX_RELOCATION_TILES * float(TerrainRenderer.TILE_SIZE)
	if candidate.distance_to(_origin) > leash:
		var homeward: Vector2 = _origin - home
		if homeward.length() <= 0.001:
			return
		candidate = home + homeward.normalized() * step
	home = candidate


func face_travel(direction: Vector2, delta: float = 0.0) -> void:
	if absf(direction.x) < FACING_DEADZONE:
		return  # too vertical to imply a facing -- keep the current one
	var wants_flip := direction.x < 0.0
	if wants_flip == flip_h:
		_contrary_travel_time = 0.0
		return
	# Only commit to the turn once the flyer has meant it for a while.
	_contrary_travel_time += delta
	if _contrary_travel_time >= FACING_TURN_DELAY or delta <= 0.0:
		flip_h = wants_flip
		_contrary_travel_time = 0.0


## Wing-beat frames for this flyer, and how fast they cycle. Birds beat
## several times a second -- fast, unlike the slow banking of FACING_TURN_
## DELAY. The two rates are deliberately far apart: "they should change
## direction slowly, only their wings should flap fast".
var flap_frames: Array = []
## The folded-wing sprite shown while perched (see ProceduralBirdSprite.
## generate_perched_texture).
var perched_frame: Texture2D = null
## True while the flyer is sitting rather than flying.
var perched := false
const FLAP_SECONDS_PER_FRAME := 0.09


## Whether this flyer is still in the pre-hatch span (COURTING/MATED/EGG,
## i.e. before LifeCycle.STAGE_JUVENILE begins) -- the "an egg, not a tiny
## adult" window. Wild-spawned flyers start at LifeCycle.MATURE_SECONDS (see
## `age_seconds`'s own doc comment), so this is only ever true for something
## actually BORN in front of the player (see begin_life) -- an ordinary
## meadow flyer is never affected.
func _is_pre_hatch() -> bool:
	return LifeCycle.stage_at(age_seconds) < LifeCycle.STAGE_JUVENILE


## Advances the wing-beat. Separate from the movement step so a flyer
## animates even while hovering.
func _animate_wings() -> void:
	# Pre-hatch: an egg, not a flapping insect (see ProceduralEggSprite /
	# _is_pre_hatch). No egg_frame set (an older caller, a test double) is a
	# no-op rather than an error -- the texture is simply left whatever it
	# was, matching every other optional-field guard in this file.
	if _is_pre_hatch():
		if egg_frame != null:
			texture = egg_frame
		return
	# A perched bird holds still. Flapping while sitting on a branch reads
	# as a glitch, not as a bird.
	if perched:
		# ...except for the head, which dips into the grass and back up
		# several times while it works a worm (see
		# GroundForageBehavior.is_beak_down). Without this the whole "sits
		# down and picks the worm up" beat is a bird holding perfectly still
		# while a worm silently vanishes.
		if ground_forage != null and peck_frame != null and ground_forage.is_beak_down():
			texture = peck_frame
		elif perched_frame != null:
			texture = perched_frame
		return
	if flap_frames.is_empty():
		return
	var index := int(_elapsed_time / FLAP_SECONDS_PER_FRAME) % flap_frames.size()
	texture = flap_frames[index]
