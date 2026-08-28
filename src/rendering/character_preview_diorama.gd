extends Node2D

## The only Godot-coupled piece of the character preview diorama (see
## docs/concept/character_creator_preview_scene.md): turns
## CharacterPreviewLayout's pure placement data into actual nodes --
## grass, a pond, pebbles, trees, and the hero -- and drives
## CharacterStroll against the hero's CharacterView every frame. Built from
## the SAME rendering classes the real world uses (IllustratedGrassPatch,
## WaterShader, StoneRenderer, TreeRenderer, CharacterView itself), not a
## parallel art style -- see the design doc's first pillar.

const CharacterPreviewLayout = preload("res://src/rendering/character_preview_layout.gd")
const CharacterStroll = preload("res://src/rendering/character_stroll.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")
const ProceduralShoreDistanceSprite = preload("res://src/rendering/procedural_shore_distance_sprite.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const CharacterActionPicker = preload("res://src/rendering/character_action_picker.gd")
const IllustratedTerrainSprite = preload("res://src/rendering/illustrated_terrain_sprite.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
## Richer scene life (reported live: "We need flowers, butterflies, worms").
## Both are plain art generators with no chunk/biome dependency (see
## EarthChunkManager._sync_flower_sprites/_sync_worm_sprites, the same inline-
## Sprite2D pattern _build_flowers/_build_worms below mirror) -- no dedicated
## "spawn one at a position" renderer exists for either, unlike fish/trees/
## birds, so this diorama builds the Sprite2D itself.
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const ProceduralWormSprite = preload("res://src/rendering/procedural_worm_sprite.gd")
## An ambient boar for the hero to spar with (see the FIGHT action) --
## CreatureRenderer.spawn_single is the real game's own "one marker, no
## chunk/AI needed" spawn path (already used by DevConsole's /spawn and the
## easter-egg boss cameos), reused here rather than restated.
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
## Fishing gets a real cast now (see the FISH action) -- both pure geometry/
## art already used by the real Player for exactly this (Player._fishing_
## step/_start_cast_visuals), reused as-is rather than invented for the
## diorama.
const FishingCast = preload("res://src/gameplay/fishing_cast.gd")
const ProceduralBobberSprite = preload("res://src/rendering/procedural_bobber_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
## The one reusable primitive for the pond's own organic edge (see
## _generate_pond_cells) -- already used by CharacterPreviewLayout for its
## own grass-clump scatter; no lake/organic-blob generator exists anywhere
## else in this codebase to reuse instead (the real world's own water
## silhouette comes from a bundled Earth elevation DEM lookup, not
## synthesized shape, which has nothing to look up for a standalone diorama
## pond).
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Which weapon the diorama's hero wears for the SWING action -- any real
## weapon-kind item id works here (see item_catalog.gd); an iron sword is
## the most recognizable "swinging a sword" silhouette.
const WEAPON_ITEM_ID := "iron_sword"

## World units -- see the design doc's own sizing note (a tree spans ~20x26,
## the character stands ~22 tall, one grass clump covers ~one 16x16 tile):
## a ~6x6-tile footprint comfortably fits a couple of trees, a pond with a
## few pebbles at its rim, several grass clumps, and room to stroll.
## Widened 96 -> 144 (9x6 tiles), height unchanged (reported live: "the
## diorama is still a square and does NOT span the whole rectangular
## panel" -- measured live, the diorama's own hero column in main_menu.gd
## has real width to spare (a 276px glow_wrap sitting in a 528px column)
## that a square viewport can never use).
##
## Widened AGAIN 144 -> 192 (12x6 tiles) once 144 was itself seen live and
## still fell short (reported live: "it's now a rectangle but it still
## doesn't cover the whole width of its containing panel"). Re-measured
## rather than guessed a second time: the hero column's real available
## width is genuinely 528px (the class-icon row directly above the diorama
## already spans it in full), and growing the diorama's own glow_wrap to
## match introduces no NEW minimum-width pressure of its own, since the
## icon row already claims that width regardless. 192 is exactly 2x the
## original 96 -- a whole-tile multiple, matching this constant's own
## established "clean number of ground tiles" convention -- and, like the
## 144 before it, chosen so `main_menu.gd`'s own DIORAMA_VIEW_SIZE.x
## (which must scale by the SAME factor as this axis to keep the camera's
## zoom uniform -- see _build_diorama_view's zoom formula) lands on a
## whole pixel count (248 * 2 = 496) without rounding. Height stays 96 on
## purpose, still: growing it too would push the diorama's own bottom edge
## further into the pre-existing, separately-tracked scroll-clipping
## regression (test_the_diorama_fits_within_the_first_unscrolled_view_of_
## the_character_tab) rather than leaving it exactly as-is.
const FOOTPRINT := Vector2(192, 96)
## The biome this little corner of the world is a corner OF.
const GROUND_BIOME := "grassland"
## One diorama ground tile covers exactly one REAL world tile -- read from
## TerrainRenderer rather than restated, so the diorama can never disagree
## with the world about how much ground a tile is (the same rule the grass
## cards already follow: IllustratedGrassPatch.WORLD_SIZE == TILE_SIZE).
const GROUND_TILE_WORLD_SIZE := float(TerrainRenderer.TILE_SIZE)
## Below BOTH the pond and the grass band, which each sit at -1 (see their
## own doc comments on why they use a z_index group rather than Y-sort).
const GROUND_Z_INDEX := -2
const PEBBLE_DIAMETER_CM := 4.0
## How many attempts _pick_new_target makes before giving up and holding
## position for a frame rather than looping forever -- mirrors
## CharacterPreviewLayout._position_clear_of_pond's own bounded-retry
## reasoning (a pathological footprint/seed could leave little clear room).
const MAX_TARGET_ATTEMPTS := 30
## Slower than CreatureWander.WANDER_SPEED (24) -- a small pond fish drifts,
## it doesn't march. Passed to FishMarker.configure_wander (see _build_fish),
## NOT CharacterStroll -- fish are driven by the real wander algorithm now,
## not a point-to-point walk (reported live: "fish don't swim like in the
## real game").
##
## Doubled 4.0 -> 8.0 once the pond itself had grown well past the size this
## was originally tuned against (reported live, a second time: "the fishes
## don't speed boost and they don't swim naturally like in game"). The boost
## mechanism itself was never broken -- measured directly: glide/flap speeds
## matched this constant and this*FLAP_SPEED_MULTIPLIER exactly, and a burst
## genuinely fired several times within a realistic 30s window. The real
## gap was purely how slow 4.0 reads at the diorama's own on-screen scale
## once measured against something concrete rather than eyeballed: a fish
## took 4.0s just to glide across its OWN configured wander circle (not even
## the whole, now-bigger pond) -- too close to standing still to register as
## "swimming" at a glance, boost included. Test-pinned against that exact
## property (test_fish_swim_speed_crosses_its_own_wander_circle_briskly),
## not the bare number, so a future pond-size or wander-fraction change gets
## re-measured against the same "reads as swimming" bar automatically.
const FISH_SWIM_SPEED := 8.0
## How often the hero spawns a water-ripple disturbance while genuinely
## swimming/wading -- matches scenes/player.gd's own WATER_RIPPLE_INTERVAL
## ("once per stroke, not every frame; the ring itself takes a couple of
## seconds to fade, so anything faster would just stack redundant rings at
## the same spot"). The real player already does this; the diorama's own
## hero, driven by its own separate movement code rather than Player, never
## did (reported live: "player doesnt cause water ripples").
const HERO_WATER_RIPPLE_INTERVAL := 0.4
## The real world's own AmbientFlyerRenderer.BIRD_RADIUS (70 world units)
## comfortably exceeds this diorama's whole ~96-unit FOOTPRINT -- scaled down
## for the same reason FISH_SWIM_SPEED already scales fish movement for the
## tiny pond, so a bird's circling stays mostly on-screen instead of spending
## most of its time off past the frame's own edge.
const BIRD_WANDER_RADIUS := 20.0
## Same scaled-down reasoning as BIRD_WANDER_RADIUS -- AmbientFlyerRenderer's
## own BUTTERFLY_RADIUS (30.0) comfortably exceeds this diorama's footprint.
## build_flyer has no radius-override parameter the way build_bird does (see
## the investigation this was scoped from), so butterflies fly at the real
## BUTTERFLY_RADIUS as-is -- close enough to on-screen at this footprint size
## that a diorama-only override isn't worth the extra surface area yet.
##
## How far apart the hero stands from the boar while sparring (see the FIGHT
## action) -- CreatureMarker.ATTACK_RANGE, the real game's own idea of
## "close enough to fight," derived rather than restated as a diorama-only
## number.
const FIGHT_RANGE := CreatureMarker.ATTACK_RANGE
## How often a fresh swing lands while FIGHT holds and the hero has already
## closed to FIGHT_RANGE -- brisker than an idle SWING's own one-off duration
## since this has to visibly read as sparring, not one single stray swing.
const FIGHT_SWING_INTERVAL := 0.8

var character_view: Node2D = null
## The ground plane's own tiles (see _build_ground) -- kept so tests can
## check coverage and so a rebuild replaces them rather than stacking.
var ground_tiles: Array[Node2D] = []
var tree_nodes: Array[Node2D] = []
var pebble_nodes: Array[Node2D] = []
var flower_nodes: Array[Node2D] = []
var worm_nodes: Array[Node2D] = []
var butterfly_nodes: Array[Node2D] = []
## Single ambient boar (see CharacterPreviewLayout.Result.boar_position) --
## null only before the first build().
var boar_node: Node2D = null
var fish_nodes: Array[Node2D] = []
var bird_nodes: Array[Node2D] = []

var _layout: CharacterPreviewLayout.Result
var _stroll_target := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## The hero's own current ambient action and how much longer it holds --
## see CharacterActionPicker (reported live: "make it so that the char
## does random actions like swinging the sword or fishing or just staying
## still then wandering"). Reset by _pick_next_action, ticked down in
## _process.
var _current_action := CharacterActionPicker.Action.WANDER
var _action_time_remaining := 0.0
## A fixed spot just outside the pond's own rim -- computed once per
## build() (see _compute_fishing_spot), not re-picked per FISH action, so
## the SAME hero always "fishes" from the same place in their own little
## scene rather than wandering to a new spot each time.
var _fishing_spot := Vector2.ZERO
## The grass patch's own instance (RefCounted, not a node -- see
## _build_grass) and the MultiMeshInstance2D it draws into, kept so
## _process can report the hero's current position to it every frame (see
## _build_grass's own doc comment on why).
var _grass_patch: IllustratedGrassPatch = null
var _grass_mmi: MultiMeshInstance2D = null
## The pond's own world-space bounding rect (set in _build_pond) -- a fast
## outer-bound reject for biome_at_global, and the same rect test_fish_stay_
## within_the_ponds_real_bounds_via_shore_avoidance verifies fish never
## cross. No longer sufficient BY ITSELF to decide "is this point really
## water" now that the pond's own silhouette is irregular (see _pond_cells) --
## a corner this rect covers can still be genuinely eroded/land.
var _pond_bounds := Rect2()
## The pond's own real, possibly-irregular silhouette (set in _build_pond,
## see _generate_pond_cells) -- grid-LOCAL Vector2i cell coordinates, keyed
## true. biome_at_global checks a global tile's centre against THIS, not
## just _pond_bounds, so a fish never reads an eroded corner as water it
## isn't (nothing renders there -- see _build_pond's own skip-if-not-kept).
var _pond_cells: Dictionary = {}
## The seed build() was called with -- kept (not just passed straight
## through) so _build_pond can derive the pond's own organic shape from it
## directly, independent of how many OTHER _rng draws happened first this
## build() (see _build_pond's own doc comment on why not _rng.seed).
var _dna_seed := 0
## The pond's own WaterShader instance -- kept (not just its shared
## material) so record_water_disturbance can forward a fish's own ripple
## straight to it, and _process can age those ripples every frame the same
## way EarthChunkManager does for the real world's own water.
var _water_shader: WaterShader = null
## The hero's own position the last time the water-ripple gate ran --
## unset (null) until the first check, since "did it move" needs a prior
## sample (see _process's own ripple block, mirroring FishMarker._step_
## water_ripple's identical "moved" gate).
var _last_hero_position_for_ripple: Variant = null
var _hero_water_ripple_accumulator := 0.0
## The FISH action's own bobber (see _build_bobber/_start_fishing_cast) --
## one Sprite2D, hidden until a cast actually lands, top_level like Player's
## own _bobber so its world position doesn't inherit this diorama root's
## transform.
var _bobber: Sprite2D = null
## Whether the current FISH action has already cast its line -- reset by
## _enter_action so re-ENTERING fish (a fresh cast to a fresh spot) casts
## again, but arriving doesn't recast every frame it stays arrived.
var _fish_has_cast := false
## Seconds until the next swing lands while FIGHT holds and the hero has
## already closed to sparring range (see FIGHT_SWING_INTERVAL) -- reset by
## _enter_action so every fresh FIGHT starts with an immediate swing rather
## than waiting out a stale countdown from whatever action came before.
var _fight_swing_remaining := 0.0


## Tears down and rebuilds the whole diorama for `dna_seed` -- the WORLD
## layout (pond/tree/pebble/grass positions) is reseeded from it too (see
## the design doc's Determinism pillar: same hero seed, same little scene),
## while the stroll target itself is freshly randomized regardless --
## ambient motion, not part of the hero's own identity.
func build(dna_seed: int) -> void:
	# Immediate free, not queue_free -- this runs synchronously from build(),
	# never from a signal/callback on one of these children itself, so
	# there is nothing an immediate free could interrupt mid-handler. A
	# deferred queue_free left every previous generation's nodes as real,
	# counted orphans for the rest of a test that calls build() more than
	# once (nothing processes the deferred queue between two synchronous
	# calls in the same test) -- matches this codebase's own test-cleanup
	# convention (see test_character_view.gd's after_each: view.free(), not
	# queue_free()).
	for child in get_children():
		remove_child(child)
		child.free()
	ground_tiles = []
	tree_nodes = []
	pebble_nodes = []
	fish_nodes = []
	bird_nodes = []
	flower_nodes = []
	worm_nodes = []
	butterfly_nodes = []
	boar_node = null
	character_view = null
	_grass_patch = null
	_grass_mmi = null
	_pond_cells = {}
	_last_hero_position_for_ripple = null
	_hero_water_ripple_accumulator = 0.0
	_bobber = null
	_fish_has_cast = false
	_fight_swing_remaining = 0.0
	_dna_seed = dna_seed

	# Seeded before anything below reads _rng -- the world LAYOUT above is
	# already independently seeded from dna_seed (CharacterPreviewLayout
	# .generate), but the starting stroll target/position picked below is
	# not claimed to be deterministic (see the design doc's Determinism
	# pillar: ambient motion, not part of the hero's own identity) -- this
	# just keeps one build() call's own randomness internally consistent
	# rather than leaving _rng in whatever state a PREVIOUS build() left it.
	_rng.seed = dna_seed

	_layout = CharacterPreviewLayout.generate(dna_seed, FOOTPRINT)
	_build_ground()
	_build_grass()
	_build_pond()
	_build_pebbles()
	_build_fish()
	_build_trees()
	_build_birds()
	_build_flowers()
	_build_worms()
	_build_butterflies()
	_build_boar()
	_build_character()
	_build_bobber()

	_stroll_target = character_view.position
	_fishing_spot = _compute_fishing_spot()
	var first_action := CharacterActionPicker.pick_next(_rng)
	_enter_action(first_action.action)
	_action_time_remaining = first_action.duration


## Redresses the live, already-strolling CharacterView -- everything else
## (the world layout, where the hero currently is) is left exactly as it
## was, so cycling an appearance axis in the creator doesn't reset the
## scene or teleport the hero back to the middle of a stride.
func apply_appearance(appearance: Dictionary) -> void:
	if character_view != null:
		character_view.apply_appearance(appearance)


func _process(delta: float) -> void:
	if character_view == null:
		return

	_action_time_remaining -= delta
	if _action_time_remaining <= 0.0:
		var next := CharacterActionPicker.pick_next(_rng)
		_enter_action(next.action)
		_action_time_remaining = next.duration

	# WANDER walks and keeps re-targeting forever; FISH walks to its one
	# fixed spot, casts once on arrival, then holds still facing the pond;
	# FIGHT walks to sparring range of the boar and swings there
	# periodically; IDLE/SWING never walk at all (SWING's own animation was
	# already triggered once in _enter_action -- see that function's own
	# doc comment on why it can't just live here instead).
	match _current_action:
		CharacterActionPicker.Action.WANDER:
			if CharacterStroll.has_arrived(character_view.position, _stroll_target):
				_stroll_target = _pick_new_target()
			_walk_toward(_stroll_target, delta)
		CharacterActionPicker.Action.FISH:
			if CharacterStroll.has_arrived(character_view.position, _stroll_target):
				character_view.set_facing(_layout.pond_center - character_view.position)
				_hold_still()
				if not _fish_has_cast:
					_fish_has_cast = true
					_start_fishing_cast()
			else:
				_walk_toward(_stroll_target, delta)
		CharacterActionPicker.Action.FIGHT:
			var boar_position: Vector2 = _layout.boar_position
			if character_view.position.distance_to(boar_position) <= FIGHT_RANGE:
				character_view.set_facing(boar_position - character_view.position)
				_hold_still()
				_fight_swing_remaining -= delta
				if _fight_swing_remaining <= 0.0:
					_fight_swing_remaining = FIGHT_SWING_INTERVAL
					character_view.play_attack_swing(_facing_string(), CharacterActionPicker.SWING_DURATION)
			else:
				_walk_toward(boar_position, delta)
		CharacterActionPicker.Action.IDLE, CharacterActionPicker.Action.SWING:
			_hold_still()

	# Water tinting: whenever the hero's CURRENT position genuinely sits
	# inside the pond (only the FISH action's own wade-in spot puts it
	# there today -- see _compute_fishing_spot), switch to SWIMMING so the
	# submersion shader/leg-hiding CharacterView already applies
	# automatically for real swimming (see CharacterView._process's own
	# set_waterline call) kicks in here too, overriding whatever movement
	# state the action above set (reported live: "no water tinting when
	# player walks in water in diorama" -- the hero never actually entered
	# the pond under any action before FISH's spot moved inside it).
	if character_view.position.distance_to(_layout.pond_center) < _layout.pond_radius:
		character_view.is_moving = false
		character_view.set_movement_state(character_view.MovementState.SWIMMING)

	# Water ripples: mirrors scenes/player.gd's own _step_water_ripples --
	# gated on the hero genuinely being IN the water (SWIMMING, set just
	# above) AND having actually moved since the last check (an idle float
	# doesn't ripple, only movement does -- the real player's own gate is
	# input_direction.length() > 0.01; this diorama has no input, so
	# comparing position across frames is the equivalent "did it actually
	# move" check), throttled to HERO_WATER_RIPPLE_INTERVAL the same way.
	#
	# PLUS one thing the real player doesn't need: an IMMEDIATE splash the
	# instant the hero steps into the water at all (_last_hero_position_
	# for_ripple still null -- see build()'s own reset, and the not-
	# swimming branch below), not gated on the throttle interval. The real
	# player's own water is a whole lake/ocean, so its throttled-only gate
	# always has plenty of moving-through-water time to fire in; this
	# diorama's own wade-in spot (_compute_fishing_spot's WADE_FRACTION)
	# sits so close to the pond's own rim that the hero is only ever
	# "moving while in the water" for a few tenths of a second before it
	# arrives and holds still -- measured too short, in practice, for the
	# real player's own 0.4s throttle to ever fire even once. A real splash
	# doesn't wait for a timer either way.
	if character_view.movement_state == character_view.MovementState.SWIMMING:
		var just_entered_water := _last_hero_position_for_ripple == null
		var moved: bool = (
			not just_entered_water and character_view.position != _last_hero_position_for_ripple
		)
		_last_hero_position_for_ripple = character_view.position
		if just_entered_water:
			_hero_water_ripple_accumulator = 0.0
			record_water_disturbance(character_view.position)
		elif moved:
			_hero_water_ripple_accumulator += delta
			if _hero_water_ripple_accumulator >= HERO_WATER_RIPPLE_INTERVAL:
				_hero_water_ripple_accumulator = 0.0
				record_water_disturbance(character_view.position)
		else:
			_hero_water_ripple_accumulator = 0.0
	else:
		# Reset (not just on rebuild) so a LATER re-entry into the water
		# is detected as "just entered" again too, not mistaken for
		# continuous movement against a stale, long-ago in-water position.
		_last_hero_position_for_ripple = null
		_hero_water_ripple_accumulator = 0.0

	# Grass parts near the hero as it strolls through (reported live: "the
	# grass blades don't part when it walks through") -- purely cosmetic,
	# no-op if never called (IllustratedGrassPatch's own default walker
	# position is far away), so this is the one line needed to turn it on.
	if _grass_patch != null:
		_grass_patch.set_walker_position(character_view.position)

	# Fish drive themselves now (Godot's own automatic per-frame _process --
	# see _build_fish's own doc comment); this diorama's only remaining job
	# for them is aging their ripples, the same way EarthChunkManager ages
	# its own real-world disturbances every frame -- nothing else would do
	# it here.
	if _water_shader != null:
		_water_shader.advance_disturbances(delta)


func _walk_toward(target: Vector2, delta: float) -> void:
	var direction: Vector2 = target - character_view.position
	if direction.length() > 0.01:
		character_view.set_facing(direction)
	character_view.is_moving = true
	character_view.set_movement_state(character_view.MovementState.WALKING)
	character_view.position = CharacterStroll.advance(character_view.position, target, delta)


func _hold_still() -> void:
	character_view.is_moving = false
	character_view.set_movement_state(character_view.MovementState.IDLE)


func _pick_new_target() -> Vector2:
	var bounds := Rect2(Vector2.ZERO, FOOTPRINT)
	for attempt in MAX_TARGET_ATTEMPTS:
		var candidate := CharacterStroll.pick_target(bounds, _rng)
		if _layout.is_clear(candidate):
			return candidate
	return character_view.position


## A fixed point just outside the pond's own rim, for the FISH action --
## computed once per build(), not re-picked per action, so the SAME hero
## always fishes from the same spot in their own little scene. Tries 8
## evenly-spaced compass points around the pond rather than a single fixed
## direction, since that one direction might happen to have a tree in it.
## Just INSIDE the pond's own rim (not outside it) -- a shallow wade at the
## shore's edge, close enough to shore that the walk there never has to
## cross deep water, but genuinely standing IN the pond so the water-
## tinting submersion shader (see this file's own _process, "in_water")
## actually has something to show (reported live: "no water tinting when
## player walks in water in diorama" -- the hero never actually entered
## the pond under any action before this). No is_clear check here on
## purpose -- that predicate REJECTS anything inside the pond by design
## (see CharacterPreviewLayout.Result.is_clear), which is exactly where
## this spot needs to be.
func _compute_fishing_spot() -> Vector2:
	const WADE_FRACTION := 0.85  # of pond_radius -- shallow, near the rim
	const COMPASS_POINTS := 8
	for step in COMPASS_POINTS:
		var angle := float(step) / float(COMPASS_POINTS) * TAU
		var candidate := _layout.pond_center + Vector2(cos(angle), sin(angle)) * (_layout.pond_radius * WADE_FRACTION)
		if Rect2(Vector2.ZERO, FOOTPRINT).has_point(candidate):
			return candidate
	return _layout.pond_center


## The FISH action's own cast (reported live, alongside more scene life:
## "the character should do random things like ... fish a fish") -- called
## once, the frame the hero arrives at the fishing spot (see _process's own
## FISH branch and _fish_has_cast). Mirrors Player._start_cast_visuals
## exactly: a rod-throw swing reusing the same animation as a melee attack,
## plus a bobber landing at FishingCast.cast_point -- the real game's own
## fishing has never had a dedicated cast animation either (see FishingCast/
## ProceduralBobberSprite's own doc comments), so there is nothing new to
## build here, only to wire in.
func _start_fishing_cast() -> void:
	character_view.play_attack_swing(_facing_string(), CharacterActionPicker.SWING_DURATION)
	if _bobber == null:
		return
	var facing_direction: Vector2 = _layout.pond_center - character_view.position
	_bobber.global_position = FishingCast.new().cast_point(character_view.position, facing_direction)
	_bobber.visible = true


## One-time setup for a newly-entered action -- called once on the frame it
## starts, not every frame it's held (a SWING, for instance, must trigger
## exactly once, not re-trigger every frame for its own short duration).
func _enter_action(action: CharacterActionPicker.Action) -> void:
	_current_action = action
	match action:
		CharacterActionPicker.Action.WANDER:
			_stroll_target = _pick_new_target()
		CharacterActionPicker.Action.FISH:
			_stroll_target = _fishing_spot
			_fish_has_cast = false
			if _bobber != null:
				_bobber.visible = false
		CharacterActionPicker.Action.SWING:
			character_view.play_attack_swing(_facing_string(), CharacterActionPicker.SWING_DURATION)
		CharacterActionPicker.Action.FIGHT:
			# 0.0, not FIGHT_SWING_INTERVAL -- the first frame the hero is
			# actually within range should swing immediately, not wait out a
			# full interval first (see _process's own FIGHT branch).
			_fight_swing_remaining = 0.0
		CharacterActionPicker.Action.IDLE:
			pass


func _facing_string() -> String:
	match character_view.facing:
		character_view.Facing.RIGHT:
			return "right"
		character_view.Facing.LEFT:
			return "left"
		character_view.Facing.UP:
			return "up"
		_:
			return "down"


## The ground the whole diorama stands on. There was none at all before:
## grass, pond, pebbles and trees were drawn straight onto the SubViewport's
## transparent background, so what showed between them was the creator
## panel's own near-black StyleBox (reported live). Worse, the pond's
## shore-to-shore fade is pure ALPHA (water_shader: COLOR.a =
## alpha_strength * smoothstep over the shore distance), so with nothing
## behind it to fade INTO, a deliberately rectangular pond (kept rectangular
## on direct instruction: "should be more rectangular not a real circle")
## read as a hard-edged blue box rather than water lying on a bank.
##
## Uses the SAME has-art-then-fallback seam TerrainRenderer._biome_frame_image
## uses, so the diorama's ground is literally the world's ground rather than
## a preview-only backdrop -- the design doc's first pillar. The predecessor
## stage this diorama replaced did have a ground backdrop; the capability was
## simply lost in the rewrite and never specified, which is why nothing
## caught it.
func _build_ground() -> void:
	var illustrated := IllustratedTerrainSprite.new()
	var procedural := ProceduralTerrainSprite.new()
	var columns := int(ceil(FOOTPRINT.x / GROUND_TILE_WORLD_SIZE))
	var rows := int(ceil(FOOTPRINT.y / GROUND_TILE_WORLD_SIZE))
	for row in rows:
		for column in columns:
			# Hash-derived per cell, so the same hero always stands on the
			# same ground (the design doc's Determinism pillar) while
			# neighbouring tiles still pick different art variants.
			var tile_seed := hash("%d_%d_diorama_ground" % [column, row])
			var image: Image = (
				illustrated.frame_for(GROUND_BIOME, tile_seed)
				if illustrated.has_variants(GROUND_BIOME)
				else procedural.generate_frame_image(GROUND_BIOME, tile_seed, 0)
			)
			var tile := Sprite2D.new()
			tile.name = "Ground%d_%d" % [column, row]
			tile.texture = ImageTexture.create_from_image(image)
			tile.centered = false
			# Derived from the art's OWN width, not a hard-coded
			# TerrainRenderer.LAYER_SCALE: illustrated tiles are
			# IllustratedTerrainSprite.CANVAS_SIZE (32px) while the procedural
			# fallback is ProceduralTerrainSprite.SIZE (64px), and both have to
			# end up covering exactly GROUND_TILE_WORLD_SIZE.
			tile.scale = Vector2.ONE * (GROUND_TILE_WORLD_SIZE / float(image.get_width()))
			tile.position = Vector2(column, row) * GROUND_TILE_WORLD_SIZE
			tile.z_index = GROUND_Z_INDEX
			add_child(tile)
			ground_tiles.append(tile)


func _build_grass() -> void:
	if _layout.grass_positions.is_empty():
		return
	var patch := IllustratedGrassPatch.new()
	var mmi := MultiMeshInstance2D.new()
	mmi.name = "Grass"
	# fill_band requires band_anchor == mmi.position (see its own doc
	# comment) -- the first clump's own position is as reasonable an anchor
	# as any single one, since every cell's own ground_position is already
	# absolute, not relative to the anchor.
	mmi.position = _layout.grass_positions[0]
	# _build_trees enables y_sort_enabled on this whole diorama root, which
	# would otherwise compare grass's own SINGLE anchor point (one arbitrary
	# clump's position, not where any given blade actually draws) against
	# the character/fish/pond's own positions -- one MultiMesh spanning the
	# whole footprint has no business being treated as one Y-sortable
	# point, and whenever that anchor's own Y happened to exceed theirs the
	# ENTIRE grass mesh drew over the ENTIRE character (reported live: "the
	# char's head is behind long grass") or the pond/fish beneath it
	# (reported live, again, after already being fixed once for a
	# different reason: "no fish in pond"). The same z_index fix the pond
	# already uses -- a z_index group always wins over Y-sort, which only
	# orders nodes WITHIN the same group.
	mmi.z_index = -1
	add_child(mmi)
	var long_positions := _pick_long_grass_positions(_layout.grass_positions)
	# fill_band now takes pre-expanded per-CARD specs (see
	# IllustratedGrassPatch.cards_for_cell/fill_band's own doc comments) --
	# this diorama has no Y-sort bands of its own (one single MultiMesh, see
	# the z_index comment above), so every cell's cards are simply expanded
	# and flattened into the one call.
	var card_specs: Array[Dictionary] = []
	for grass_position in _layout.grass_positions:
		var growth := LONG_GRASS_GROWTH if long_positions.has(grass_position) else 1.0
		var cell_spec := {"seed": hash(grass_position), "ground_position": grass_position, "growth": growth}
		card_specs.append_array(IllustratedGrassPatch.cards_for_cell(cell_spec))
	patch.fill_band(mmi, mmi.position, card_specs)
	# Kept for _process (see set_walker_position's own call site there) --
	# reported live: "the grass blades don't part when it walks through".
	_grass_patch = patch
	_grass_mmi = mmi


## A few clumps render taller than the rest (reported live: "add a few long
## grass blades") -- growth is IllustratedGrassPatch.fill_band's own real
## per-clump scale factor (see that file's `maxf(0.3, entry.growth)`), the
## same mechanism a genuinely overgrown real-world patch would use, just fed
## a value the real world's own TallGrass never actually reaches (growth is
## documented there as "0..1; 1 is mature" -- see that file's own
## get_growth). A deliberate, small stretch of a real mechanism for a
## decorative touch, not new art or a new rendering path.
##
## Static and pure (no Godot nodes) so it's directly testable: ranks every
## clump by distance to the footprint's own centre and keeps the closest
## LONG_GRASS_MAX_COUNT. First tried ranking by hash instead (the same
## deterministic "small subset via hash rank" convention AmbientFlyerRenderer
## ._spawn_species already uses to pick which cells of a larger pool
## qualify) -- but that has no spatial preference at all, so the accent
## could land anywhere the ordinary scatter did, including right at a
## corner easy to miss entirely (reported live: "grass blades exist, but
## they should be more in the center"). Distance-to-centre instead puts the
## accent where it's actually seen.
const LONG_GRASS_GROWTH := 1.5
const LONG_GRASS_MAX_COUNT := 3


static func _pick_long_grass_positions(positions: Array[Vector2]) -> Array[Vector2]:
	var center := FOOTPRINT * 0.5
	var ranked: Array[Vector2] = positions.duplicate()
	ranked.sort_custom(func(a, b): return a.distance_to(center) < b.distance_to(center))
	var picked: Array[Vector2] = []
	for i in mini(LONG_GRASS_MAX_COUNT, ranked.size()):
		picked.append(ranked[i])
	return picked


## One real water tile per TerrainRenderer.TILE_SIZE (16 world units) --
## matches _build_ground's own grid, and the real world's own water overlay
## (EarthChunkManager._paint_water_overlay / set_water_layer), rather than
## the diorama's earlier single 32px ProceduralShoreDistanceSprite texture
## stretched over the pond's WHOLE diameter.
##
## That single-stretched-tile approach was itself a real, deliberate fix at
## the time (see the git history: "should be more rectangular not a real
## circle" replaced a genuinely circular pond with this) -- but it meant
## EVERY pixel of the pond, all the way to its own centre, measured shore-
## distance from ALL 4 sides simultaneously, because the whole pond was
## being treated as a single tile touching land on every side regardless of
## its own size. WaterShader's edge_alpha only reaches full opacity within
## the inner ~45-50% of a tile's OWN half-width (see WaterShader.EDGE_ALPHA_
## FADE_END's own doc comment) -- stretched across the pond's full diameter,
## that meant the genuinely fully-opaque "obviously water" region was a
## small core surrounded by a fade covering most of the pond's own area
## (reported live: "it's supposed to fill the entire rectangle").
##
## Tiling instead reuses the real world's own actual pattern: a cell with NO
## land-facing side (fully interior to the grid) renders as
## ProceduralShoreDistanceSprite.generate_deep_water_image() -- uniformly
## Color(1,1,1,1), no fade at all -- and only a cell that genuinely touches
## the grid's own rim fades on the side(s) actually facing outward
## (generate_image(land_directions)). A simplified port of the real world's
## own per-cell decision (TerrainRenderer.atlas_coords_for_water_overlay /
## EarthChunkManager._land_directions_at): this diorama's pond is small
## enough, and never needs the real system's intermediate "a few rings out"
## tier (TerrainRenderer.RING_MAX/generate_ring_image) at all -- every cell
## is either touching the rim or fully interior.
const POND_TILE_WORLD_SIZE := float(TerrainRenderer.TILE_SIZE)
## How deep into a CORNER a cell must sit (its SHORTER-axis fraction from
## centre -- see _generate_pond_cells's own "corner_frac" doc comment) before
## the noise below can erode it at all. First tried against the LONGER axis
## (Chebyshev distance -- a cell was eligible the instant it was far along
## EITHER axis), which meant an entire outer row/column all shared the same
## eligibility and, under correlated noise, could erode away TOGETHER --
## checked directly with a rendered dump (composited the live tile grid to a
## PNG and looked at it): one seed's pond came out a lopsided wedge with
## nearly a whole side missing, not a rounded rectangle. Requiring BOTH axes
## to be simultaneously far from centre keeps every pure edge-midpoint cell
## (always low on at least one axis) permanently safe -- only genuine
## corners, where noise can only ever nibble a small diagonal bite, are ever
## eligible. Test-pinned (CLAUDE.md: tuned values need a tested function or
## a pinned constant, never just an eyeballed comment) against the two
## properties that actually matter for "reads as an organic rectangle, not a
## crisp one or a shapeless blob": test_generate_pond_cells_erodes_at_least_
## one_outer_cell_for_some_seed (genuinely irregular) and test_generate_
## pond_cells_keeps_most_of_the_grid_on_average (still mostly rectangular).
const POND_EROSION_SAFE_FRACTION := 0.35
## Noise sampling scale, in GRID CELLS (not world units) -- small enough
## that neighbouring rim cells still correlate (an eroded shoreline reads as
## a few connected bites out of the rectangle, not single-cell peppering),
## the same "structural, not eyeballed" reasoning CharacterPreviewLayout.
## GRASS_FIELD_NOISE_SCALE documents for its own noise sampling.
const POND_EROSION_NOISE_SCALE := 0.35


## Column/row counts derived from `layout`'s own pond_half_size (see that
## field's own doc comment: x is the long axis, pinned to pond_radius; y is
## the short axis, pond_radius / POND_ASPECT_RATIO) -- two DIFFERENT axis
## lengths, not one pond_radius doubled into a square (reported live: "not
## square / circle but a rectangle"). Split into two tiny static functions
## (rather than inlined in _build_pond) so test_pond_grid_is_wider_than_it_
## is_tall can check the property directly against the live diorama's own
## layout without needing to reach into _build_pond's local variables.
static func _pond_columns_for(layout: CharacterPreviewLayout.Result) -> int:
	return maxi(1, int(ceil(layout.pond_half_size.x * 2.0 / POND_TILE_WORLD_SIZE)))


static func _pond_rows_for(layout: CharacterPreviewLayout.Result) -> int:
	return maxi(1, int(ceil(layout.pond_half_size.y * 2.0 / POND_TILE_WORLD_SIZE)))


## Which cells of a `columns` x `rows` grid are actually part of the pond --
## the "rectangle with some curves (organic shape)" the tile grid renders
## (reported live: "the pond should be ... not square / circle but a
## rectangle with some curves"). No lake/organic-blob generator exists
## anywhere in this codebase to reuse -- see PixelNoise's own preload
## comment above -- so this is built from scratch, using that same primitive
## CharacterPreviewLayout already reaches for.
##
## A corner-only "perturbed distance field" blob: `corner_frac` is the
## SHORTER of a cell's two per-axis distances from the grid's own centre (0
## at centre, up to ~1 approaching a true corner) -- deliberately the
## SHORTER, not the longer/Chebyshev one, so a cell far along only ONE axis
## (an ordinary edge-midpoint) always scores low and stays permanently in
## the kept core; only a cell that's simultaneously far along BOTH axes (a
## genuine corner) can ever reach the eroded band (see POND_EROSION_SAFE_
## FRACTION's own doc comment on why -- a real rendered dump showed the
## alternative eroding a whole side away at once). PixelNoise.smooth decides
## survival within that band, weighted so cells deeper into the corner need
## a higher roll -- the same "erodes MORE near the true corner" curve a real
## shoreline has, rather than a uniform coin-flip that would fray every
## eligible corner cell just as readily.
##
## Pure and static, no Godot nodes, so it's directly testable without a live
## diorama -- the same split this file already keeps for
## _pick_long_grass_positions.
static func _generate_pond_cells(columns: int, rows: int, seed_value: int) -> Dictionary:
	var kept := {}
	var center := Vector2(float(columns - 1), float(rows - 1)) * 0.5
	var half_size := Vector2(columns, rows) * 0.5
	for row in rows:
		for column in columns:
			var offset := Vector2(column, row) - center
			var x_frac := absf(offset.x) / half_size.x
			var y_frac := absf(offset.y) / half_size.y
			var corner_frac := minf(x_frac, y_frac)
			if corner_frac <= POND_EROSION_SAFE_FRACTION:
				kept[Vector2i(column, row)] = true
				continue
			if corner_frac > 1.0:
				continue
			var noise := PixelNoise.smooth(
				seed_value, float(column) * POND_EROSION_NOISE_SCALE, float(row) * POND_EROSION_NOISE_SCALE
			)
			var erosion_progress := (corner_frac - POND_EROSION_SAFE_FRACTION) / (1.0 - POND_EROSION_SAFE_FRACTION)
			if noise > erosion_progress:
				kept[Vector2i(column, row)] = true
	return kept


## Which of `cell`'s 4 cardinal neighbours count as "land" for the shore-
## fade texture -- true whenever a neighbour is either past the grid's own
## bounds OR inside the grid but not in `kept`. The OLD logic (row == 0,
## column == columns - 1, etc.) only ever checked the grid's own outer rim,
## which was correct only because every cell used to be kept -- now that
## _generate_pond_cells can erode an INTERIOR cell too, a kept cell can
## border an eroded neighbour without being anywhere near the grid's own
## edge, and still needs the fade facing that direction.
static func _land_directions_for_cell(cell: Vector2i, kept: Dictionary, columns: int, rows: int) -> Array[Vector2i]:
	var land_directions: Array[Vector2i] = []
	for direction in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var neighbor: Vector2i = cell + direction
		var neighbor_in_grid := neighbor.x >= 0 and neighbor.x < columns and neighbor.y >= 0 and neighbor.y < rows
		if not neighbor_in_grid or not kept.has(neighbor):
			land_directions.append(direction)
	return land_directions


func _build_pond() -> void:
	var pond := Node2D.new()
	pond.name = "Pond"
	add_child(pond)

	var columns := _pond_columns_for(_layout)
	var rows := _pond_rows_for(_layout)
	var grid_size := Vector2(columns, rows) * POND_TILE_WORLD_SIZE
	var top_left := _layout.pond_center - grid_size * 0.5
	_pond_bounds = Rect2(top_left, grid_size)
	# Seeded from _dna_seed directly, not the mutable _rng (whose state
	# depends on how many OTHER draws happened first this build() -- see
	# _dna_seed's own doc comment) -- the pond's own visual shape follows
	# the design doc's Determinism pillar (same seed, same layout) exactly
	# like every other placement, independent of call order.
	_pond_cells = _generate_pond_cells(columns, rows, _dna_seed)

	var shore_sprite := ProceduralShoreDistanceSprite.new()
	# Kept as an instance (not discarded after .shared_material()) so
	# record_water_disturbance/_process can call add_disturbance/
	# advance_disturbances on it later -- see those two doc comments.
	_water_shader = WaterShader.new()
	# One shared material for every tile, exactly like the real water
	# overlay's own single TileSet -- the shader reads TEXTURE (per node)
	# and world_pos (per vertex), so many sprites can safely share one
	# ShaderMaterial instance.
	var material := _water_shader.shared_material()

	for row in rows:
		for column in columns:
			var cell := Vector2i(column, row)
			if not _pond_cells.has(cell):
				continue
			var land_directions := _land_directions_for_cell(cell, _pond_cells, columns, rows)

			var image: Image = (
				shore_sprite.generate_deep_water_image()
				if land_directions.is_empty()
				else shore_sprite.generate_image(land_directions)
			)
			var tile := Sprite2D.new()
			tile.name = "PondTile%d_%d" % [column, row]
			tile.texture = ImageTexture.create_from_image(image)
			tile.centered = false
			tile.scale = Vector2.ONE * (POND_TILE_WORLD_SIZE / float(image.get_width()))
			tile.position = top_left + Vector2(column, row) * POND_TILE_WORLD_SIZE
			tile.material = material
			# _build_trees enables y_sort_enabled on this whole diorama
			# root, which would otherwise compare each pond tile's own
			# position against each fish's individually -- a fish above a
			# given tile draws correctly on top, but one below it would
			# sort BEHIND that tile and vanish, since y-sort has no idea a
			# tile is one piece of a large flat ground feature rather than
			# a small discrete object. Every tile carries its own z_index
			# directly (not inherited from the "Pond" container) -- the
			# same "always set it explicitly" convention the grass/ground
			# already follow -- below every other sibling's default (0) so
			# the whole grid always draws first regardless of any Y
			# comparison.
			tile.z_index = -1
			pond.add_child(tile)


## Duck-typed "world" for FishMarker.setup (see _build_fish) -- lets the
## diorama's own fish run through FishMarker's REAL _process, the same one
## every other in-game fish uses (shore-avoidance, TURN_RATE-smoothed
## heading, tail-wag speed bursts, ripples), rather than either the
## diorama's own earlier point-to-point movement or FishMarker's own "no
## world at all" fallback -- that fallback is a documented isolated-test/
## standalone-rendering convenience (see FishMarker.setup's own doc
## comment), not what any real in-game fish actually experiences, and it
## showed (reported live, after an earlier CreatureWander-based fix still
## fell short: "fish still don't move natural like ingame also no
## ripples").
##
## A tile is "ocean" exactly when its own centre point falls on a cell the
## pond's own grid actually KEPT (_pond_cells, set in _build_pond) -- not
## merely inside _pond_bounds's outer rectangle, which the pond's now-
## irregular silhouette (see _generate_pond_cells) can leave partly eroded
## back to land. _pond_bounds is checked first purely as a cheap reject (no
## point converting to a local cell for a point nowhere near the pond at
## all); nothing requires FishMarker's global tile grid (anchored at world
## origin) to line up with the pond's own rendered tiles (anchored at
## _layout.pond_center, an arbitrary seeded position), which is why the
## centre point is re-expressed in the pond's own LOCAL cell coordinates
## before checking _pond_cells.
func biome_at_global(tile_x: int, tile_y: int) -> String:
	var tile_center := Vector2(
		(float(tile_x) + 0.5) * POND_TILE_WORLD_SIZE, (float(tile_y) + 0.5) * POND_TILE_WORLD_SIZE
	)
	if not _pond_bounds.has_point(tile_center):
		return GROUND_BIOME
	var local := (tile_center - _pond_bounds.position) / POND_TILE_WORLD_SIZE
	var cell := Vector2i(floori(local.x), floori(local.y))
	return "ocean" if _pond_cells.has(cell) else GROUND_BIOME


## The other half of the same duck-typed "world" contract -- a fish's own
## tail-wag/ripple step (FishMarker._step_water_ripple) calls this exactly
## the way EarthChunkManager.record_water_disturbance does for real ocean
## fish (reported live, alongside the movement complaint: "no ripples").
## Forwards straight to the pond's own WaterShader instance -- the same
## shared material every pond tile already renders with, so a ripple
## recorded here is visible on every tile it reaches. advance_disturbances
## (aging/expiring them) is this diorama's own _process's job, the same way
## EarthChunkManager ages its own -- nothing else would do it here.
func record_water_disturbance(world_pos: Vector2) -> void:
	_water_shader.add_disturbance(world_pos)


func _build_pebbles() -> void:
	var stone_renderer := StoneRenderer.new()
	for pebble_position in _layout.pebble_positions:
		var pebble := stone_renderer.build_liftable_stone_node(hash(pebble_position), PEBBLE_DIAMETER_CM)
		pebble.position = pebble_position
		add_child(pebble)
		pebble_nodes.append(pebble)


## A fish pond needs actual fish (reported live: "add fish to the pond").
## FishRenderer.spawn_fish_at (a new public wrapper -- see that file's own
## doc comment) sidesteps the chunk-based ocean-tile spawning
## FishRenderer.spawn_fish itself requires, materializing one real fish
## directly wherever CharacterPreviewLayout already decided one should go.
func _build_fish() -> void:
	var fish_renderer := FishRenderer.new()
	for fish_position in _layout.fish_positions:
		var seed_value := hash(fish_position)
		var species: String = FishRenderer.SPECIES_POOL[absi(seed_value) % FishRenderer.SPECIES_POOL.size()]
		var fish := fish_renderer.spawn_fish_at(self, species, fish_position, seed_value)
		# A real "world" (this diorama itself, duck-typed -- see
		# biome_at_global/record_water_disturbance's own doc comments)
		# instead of leaving it null: lets this fish's own _process run the
		# FULL real path -- shore-avoidance, TURN_RATE-smoothed heading,
		# tail-wag speed bursts, ripples -- the same one every other fish in
		# the game uses. No more manual driving/set_process(false): Godot's
		# own automatic per-frame _process is exactly what every OTHER fish
		# in the game already relies on too.
		fish.setup(self, TerrainRenderer.TILE_SIZE)
		# The wander's own HOME is the pond's centre for every fish, not
		# each one's own scattered spawn point -- CreatureWander.direction_
		# at's containment math guarantees a fish's own PREFERRED roaming
		# stays within wander_radius of ITS OWN home (the shore-avoidance
		# above is the separate HARD guarantee that actually keeps it wet),
		# so anchoring every fish to the SAME point the radius was derived
		# against (FISH_SAFE_RADIUS_FRACTION * pond_radius) is what makes
		# that preference actually centre on the pond itself.
		fish.home = _layout.pond_center
		fish.configure_wander(_layout.pond_radius * CharacterPreviewLayout.FISH_SAFE_RADIUS_FRACTION, FISH_SWIM_SPEED)
		fish_nodes.append(fish)


func _build_trees() -> void:
	var tree_renderer := TreeRenderer.new()
	for tree_position in _layout.tree_positions:
		# spawn_tree_at sets y_sort_enabled on its parent -- exactly what
		# this diorama wants anyway, so the strolling hero draws correctly
		# in front of / behind a tree by its own Y position, not always on
		# top or always behind.
		tree_nodes.append(tree_renderer.spawn_tree_at(self, tree_position))


## A few songbirds circling overhead (reported live, alongside the long-grass
## request: "add ... birds") -- purely decorative ambience, the same "reuse
## the real rendering, no gameplay behind it" contract the diorama's fish
## already have (AmbientFlyerRenderer.build_bird wires no scent/worm/seed/
## fruit world, so a bird placed this way just flies its own home-tethered
## wander -- see that function's own doc comment). Species picked the same
## deterministic way FishRenderer._build_fish already picks a fish species
## (hash of its own position, modulo the pool). AmbientFlyerMarker sets its
## OWN z_index above ground clutter (see test_a_flyer_draws_above_ground_
## clutter) -- nothing extra needed here for draw order, unlike the pond/
## grass below it.
func _build_birds() -> void:
	var flyer_renderer := AmbientFlyerRenderer.new()
	for bird_position in _layout.bird_positions:
		var seed_value := hash(bird_position)
		var pool := AmbientFlyerRenderer.BIRD_SPECIES_POOL
		var species: String = pool[absi(seed_value) % pool.size()]
		var bird := flyer_renderer.build_bird(self, species, bird_position, seed_value, BIRD_WANDER_RADIUS)
		bird_nodes.append(bird)


## Flowers scattered through the meadow (reported live, alongside more scene
## life: "We need flowers, butterflies, worms..."). ProceduralFlowerSprite has
## no chunk/biome dependency at all -- generate_texture takes only (species_id,
## seed_value, nectar, withered) -- so this mirrors EarthChunkManager._sync_
## flower_sprites' own inline Sprite2D construction directly rather than
## inventing a new pattern. No FlowerPatch/nectar-field exists here to read
## real values from, so nectar/withered stay at their own "full bloom"
## defaults (1.0/false) -- the same "permanently grown" convention every
## other diorama plant (grass, trees) already follows.
func _build_flowers() -> void:
	var generator := ProceduralFlowerSprite.new()
	for flower_position in _layout.flower_positions:
		var seed_value := hash(flower_position)
		var species: String = FlowerSpecies.IDS[absi(seed_value) % FlowerSpecies.IDS.size()]
		var sprite := Sprite2D.new()
		sprite.texture = generator.generate_texture(species, seed_value)
		sprite.scale = Vector2.ONE * ProceduralFlowerSprite.plant_scale_for(species, seed_value)
		sprite.offset.y = -float(ProceduralFlowerSprite.SIZE.y) * 0.5
		sprite.position = flower_position
		add_child(sprite)
		flower_nodes.append(sprite)


## Worms lying in the grass -- same "no chunk dependency, thin Sprite2D
## wrapper" shape as flowers, mirroring EarthChunkManager._sync_worm_sprites
## minus its partial-emergence region-rect trick (see EarthwormPatch.
## emergence_for): purely decorative and always fully surfaced here, not
## tied to any real burrow/weather state.
func _build_worms() -> void:
	var generator := ProceduralWormSprite.new()
	for worm_position in _layout.worm_positions:
		var seed_value := hash(worm_position)
		var sprite := Sprite2D.new()
		sprite.texture = generator.generate_texture(seed_value)
		sprite.scale = Vector2.ONE * ProceduralWormSprite.world_scale()
		sprite.position = worm_position
		add_child(sprite)
		worm_nodes.append(sprite)


## Butterflies (and the occasional bee) drifting near the flowers --
## AmbientFlyerRenderer.build_flyer is already a ready-made non-bird wrapper
## (used in production for flies on carcasses), so this needs no new
## rendering code at all -- the same "reuse the real thing" contract
## _build_birds already follows.
func _build_butterflies() -> void:
	var flyer_renderer := AmbientFlyerRenderer.new()
	for butterfly_position in _layout.butterfly_positions:
		var seed_value := hash(butterfly_position)
		var pool := AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL
		var species: String = pool[absi(seed_value) % pool.size()]
		var butterfly := flyer_renderer.build_flyer(self, species, butterfly_position, seed_value)
		butterfly_nodes.append(butterfly)


## One ambient boar for the hero to spar with (see the FIGHT action) --
## CreatureRenderer's own real "one marker, no chunk/AI needed" spawn path
## (already used by DevConsole's /spawn and easter-egg boss cameos). Calls
## the underlying _build_marker directly rather than the public spawn_single
## wrapper so the boar's own wander seed is DETERMINISTIC from its position
## (spawn_single itself rolls a fresh randi() every call -- correct for its
## own debug-spawn use case, but not for this diorama's "same seed, same
## scene" pillar) -- the same reasoning fish/birds already hash their own
## spawn position for. `world` stays null (CreatureMarker's own documented
## no-AI fallback): a real boar's attack pose is gated behind full AI/
## perception with no public trigger to force it on cue, so this boar stays
## a harmlessly ambient presence, exactly like the diorama's fish/birds
## already are -- the hero's own swing (see the FIGHT action) is what
## actually reads as "fighting", not the boar fighting back.
func _build_boar() -> void:
	var seed_value := hash(_layout.boar_position)
	boar_node = CreatureRenderer.new()._build_marker(
		self, "boar", _layout.boar_position, seed_value, null, TerrainRenderer.TILE_SIZE
	)


## The FISH action's own bobber (see _start_fishing_cast) -- one Sprite2D,
## hidden until a cast actually lands, mirroring Player's own _bobber setup
## exactly (ProceduralBobberSprite texture at ArtResolution.SPRITE_SCALE,
## top_level so its world position doesn't inherit this diorama root's
## transform).
func _build_bobber() -> void:
	_bobber = Sprite2D.new()
	_bobber.name = "Bobber"
	_bobber.texture = ProceduralBobberSprite.new().generate_texture()
	_bobber.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	_bobber.visible = false
	_bobber.top_level = true
	add_child(_bobber)


func _build_character() -> void:
	character_view = CharacterViewScene.instantiate()
	character_view.name = "Hero"
	# A reasonable starting position -- clear of the pond/trees by
	# construction whenever the layout found one; falls back to the
	# footprint's own centre if every attempt failed (see
	# CharacterPreviewLayout._position_clear_of_pond's own doc comment on
	# why this can't loop forever).
	var start := FOOTPRINT * 0.5
	for attempt in MAX_TARGET_ATTEMPTS:
		var candidate := Vector2(_rng.randf_range(0.0, FOOTPRINT.x), _rng.randf_range(0.0, FOOTPRINT.y))
		if _layout.is_clear(candidate):
			start = candidate
			break
	character_view.position = start
	add_child(character_view)
	character_view.apply_appearance(HeroAppearance.new().appearance_for("warrior", 0))
	_equip_starting_weapon()


## So the SWING action has something to actually swing (reported live,
## alongside the ask for random actions: "swinging the sword"). Unlike
## apply_appearance, CharacterView.equip_weapon has no pending-value stash
## for a view that isn't ready yet -- it writes straight to _tool_slot (an
## @onready var, null until CharacterView's own _ready fires). add_child
## above makes _ready fire SYNCHRONOUSLY only if this diorama's own
## ancestor chain is already inside a live SceneTree at that exact moment;
## if the diorama itself was built before being attached (e.g. inside a
## test that constructs the surrounding MainMenu without a live tree yet),
## it isn't, and calling equip_weapon immediately crashed
## ("Invalid assignment of property ... on a base object of type 'Nil'").
## is_inside_tree() takes the fast synchronous path when possible; the
## `ready` signal covers the deferred case, exactly once.
func _equip_starting_weapon() -> void:
	var texture := ProceduralItemSprite.new().generate_texture(WEAPON_ITEM_ID)
	if character_view.is_inside_tree():
		character_view.equip_weapon(texture)
	else:
		character_view.ready.connect(character_view.equip_weapon.bind(texture), CONNECT_ONE_SHOT)
