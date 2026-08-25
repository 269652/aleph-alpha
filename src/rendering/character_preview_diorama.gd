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

## Which weapon the diorama's hero wears for the SWING action -- any real
## weapon-kind item id works here (see item_catalog.gd); an iron sword is
## the most recognizable "swinging a sword" silhouette.
const WEAPON_ITEM_ID := "iron_sword"

## World units -- see the design doc's own sizing note (a tree spans ~20x26,
## the character stands ~22 tall, one grass clump covers ~one 16x16 tile):
## a ~6x6-tile footprint comfortably fits a couple of trees, a pond with a
## few pebbles at its rim, several grass clumps, and room to stroll.
const FOOTPRINT := Vector2(96, 96)
const PEBBLE_DIAMETER_CM := 4.0
## How many attempts _pick_new_target makes before giving up and holding
## position for a frame rather than looping forever -- mirrors
## CharacterPreviewLayout._position_clear_of_pond's own bounded-retry
## reasoning (a pathological footprint/seed could leave little clear room).
const MAX_TARGET_ATTEMPTS := 30
## Slower than CharacterStroll.WALK_SPEED -- a small pond fish drifts, it
## doesn't march.
const FISH_SWIM_SPEED := 4.0
## Matches FishMarker.TURN_RATE (radians/sec) -- its own built-in wander is
## disabled here (see _fish_targets' own doc comment), but the same turn
## smoothing still applies to keep a fish reading as steering, not
## snapping.
const FISH_TURN_RATE := 3.0

var character_view: Node2D = null
var tree_nodes: Array[Node2D] = []
var pebble_nodes: Array[Node2D] = []
var fish_nodes: Array[Node2D] = []

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
## Per-fish stroll target, parallel to fish_nodes -- FishMarker's own
## built-in wander (CreatureWander.WANDER_RADIUS, a flat 40 world units)
## is tuned for real ocean/lake bodies far bigger than this diorama's
## whole ~21-unit-radius pond, so an unconfined fish drifts clean out of
## the water within moments (reported live: "the pond has no fish" --
## they were there, just no longer visibly IN the pond by the time it was
## looked at). Each diorama fish has its OWN _process disabled (see
## _build_fish) and is driven here instead, the same CharacterStroll logic
## the hero's own stroll uses, confined to a box comfortably inside the
## pond's own rim.
var _fish_targets: Array[Vector2] = []
## The grass patch's own instance (RefCounted, not a node -- see
## _build_grass) and the MultiMeshInstance2D it draws into, kept so
## _process can report the hero's current position to it every frame (see
## _build_grass's own doc comment on why).
var _grass_patch: IllustratedGrassPatch = null
var _grass_mmi: MultiMeshInstance2D = null


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
	tree_nodes = []
	pebble_nodes = []
	fish_nodes = []
	_fish_targets = []
	character_view = null
	_grass_patch = null
	_grass_mmi = null

	# Seeded before anything below reads _rng -- the world LAYOUT above is
	# already independently seeded from dna_seed (CharacterPreviewLayout
	# .generate), but the starting stroll target/position picked below is
	# not claimed to be deterministic (see the design doc's Determinism
	# pillar: ambient motion, not part of the hero's own identity) -- this
	# just keeps one build() call's own randomness internally consistent
	# rather than leaving _rng in whatever state a PREVIOUS build() left it.
	_rng.seed = dna_seed

	_layout = CharacterPreviewLayout.generate(dna_seed, FOOTPRINT)
	_build_grass()
	_build_pond()
	_build_pebbles()
	_build_fish()
	_build_trees()
	_build_character()

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
	# fixed spot and then holds still facing the pond once it arrives;
	# IDLE/SWING never walk at all (SWING's own animation was already
	# triggered once in _enter_action -- see that function's own doc
	# comment on why it can't just live here instead).
	match _current_action:
		CharacterActionPicker.Action.WANDER:
			if CharacterStroll.has_arrived(character_view.position, _stroll_target):
				_stroll_target = _pick_new_target()
			_walk_toward(_stroll_target, delta)
		CharacterActionPicker.Action.FISH:
			if CharacterStroll.has_arrived(character_view.position, _stroll_target):
				character_view.set_facing(_layout.pond_center - character_view.position)
				_hold_still()
			else:
				_walk_toward(_stroll_target, delta)
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

	# Grass parts near the hero as it strolls through (reported live: "the
	# grass blades don't part when it walks through") -- purely cosmetic,
	# no-op if never called (IllustratedGrassPatch's own default walker
	# position is far away), so this is the one line needed to turn it on.
	if _grass_patch != null:
		_grass_patch.set_walker_position(character_view.position)

	for i in fish_nodes.size():
		var fish: Node2D = fish_nodes[i]
		if CharacterStroll.has_arrived(fish.position, _fish_targets[i]):
			_fish_targets[i] = _pick_new_fish_target()
		var fish_direction: Vector2 = _fish_targets[i] - fish.position
		if fish_direction.length() > 0.01:
			# Turned gradually toward the target, not snapped -- the same
			# FishMarker.TURN_RATE smoothing its own (now-disabled)
			# built-in wander used, so a fish reads as steering through
			# the water instead of instantly flipping to face each new
			# target (reported live: "can't swim").
			fish.rotation = lerp_angle(fish.rotation, fish_direction.angle(), clampf(FISH_TURN_RATE * delta, 0.0, 1.0))
		fish.position = CharacterStroll.advance(fish.position, _fish_targets[i], delta, FISH_SWIM_SPEED)


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
		CharacterActionPicker.Action.SWING:
			character_view.play_attack_swing(_facing_string(), CharacterActionPicker.SWING_DURATION)
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


## A random point comfortably inside the pond -- CharacterPreviewLayout
## .FISH_SAFE_RADIUS_FRACTION of its own radius (the SAME fraction the
## initial spawn positions already use, not a separately hand-copied
## number -- see that constant's own doc comment on why it's this
## conservative), so a fish's own drawn body never overhangs the shore.
func _pick_new_fish_target() -> Vector2:
	var half_extent := _layout.pond_radius * CharacterPreviewLayout.FISH_SAFE_RADIUS_FRACTION
	var bounds := Rect2(_layout.pond_center - Vector2.ONE * half_extent, Vector2.ONE * half_extent * 2.0)
	return CharacterStroll.pick_target(bounds, _rng)


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
	var cells: Array[Dictionary] = []
	for grass_position in _layout.grass_positions:
		cells.append({"seed": hash(grass_position), "ground_position": grass_position, "growth": 1.0})
	patch.fill_band(mmi, mmi.position, cells)
	# Kept for _process (see set_walker_position's own call site there) --
	# reported live: "the grass blades don't part when it walks through".
	_grass_patch = patch
	_grass_mmi = mmi


func _build_pond() -> void:
	var pond := Sprite2D.new()
	pond.name = "Pond"
	# ProceduralShoreDistanceSprite, with real shore on all 4 cardinal
	# sides -- reported live, after a first attempt at a genuinely circular
	# pond (CircularPondSprite, a real fix for a real "seems tinted" bug at
	# the time -- an empty land_directions list gave a uniform "no shore
	# anywhere" fill with no alpha mask, a flat untextured tint): "should be
	# more rectangular not a real circle". This is the SAME class the real
	# terrain water tiles use (see that class's own doc comment); passing
	# all 4 directions gives a real shore-to-centre gradient in a clean
	# rectangular silhouette -- deep water in the middle, fading toward
	# every edge -- with no alpha masking or blocky low-res circle-edge
	# involved at all.
	const ALL_SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	pond.texture = ProceduralShoreDistanceSprite.new().generate_texture(ALL_SIDES)
	pond.centered = true
	var texture_size: Vector2 = pond.texture.get_size()
	var diameter := _layout.pond_radius * 2.0
	pond.scale = Vector2(diameter, diameter) / texture_size
	pond.position = _layout.pond_center
	pond.material = WaterShader.new().shared_material()
	# _build_trees enables y_sort_enabled on this whole diorama root, which
	# would otherwise compare the pond's own CENTRE position against each
	# fish's position individually -- fish above the pond's centre would
	# draw correctly on top, but fish below it would sort BEHIND the pond
	# sprite and vanish, since y-sort has no idea the pond is one large flat
	# ground feature rather than a small discrete object. A z_index below
	# every other sibling's default (0) makes the pond always draw first
	# regardless of any Y comparison -- z_index groups take priority over
	# y-sort, which only orders nodes WITHIN the same z_index.
	pond.z_index = -1
	add_child(pond)


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
		# Disables FishMarker's own built-in wander/ripple _process --
		# driven from THIS diorama's _process instead (see _fish_targets'
		# own doc comment on why: its WANDER_RADIUS is tuned for a real
		# ocean/lake, not this tiny pond).
		fish.set_process(false)
		fish_nodes.append(fish)
		_fish_targets.append(fish_position)


func _build_trees() -> void:
	var tree_renderer := TreeRenderer.new()
	for tree_position in _layout.tree_positions:
		# spawn_tree_at sets y_sort_enabled on its parent -- exactly what
		# this diorama wants anyway, so the strolling hero draws correctly
		# in front of / behind a tree by its own Y position, not always on
		# top or always behind.
		tree_nodes.append(tree_renderer.spawn_tree_at(self, tree_position))


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
