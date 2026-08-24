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
const CircularPondSprite = preload("res://src/rendering/circular_pond_sprite.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const TreeRenderer = preload("res://src/rendering/tree_renderer.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")

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

var character_view: Node2D = null
var tree_nodes: Array[Node2D] = []
var pebble_nodes: Array[Node2D] = []
var fish_nodes: Array[Node2D] = []

var _layout: CharacterPreviewLayout.Result
var _stroll_target := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
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
	if CharacterStroll.has_arrived(character_view.position, _stroll_target):
		_stroll_target = _pick_new_target()
	var direction: Vector2 = _stroll_target - character_view.position
	if direction.length() > 0.01:
		character_view.set_facing(direction)
	character_view.is_moving = true
	character_view.set_movement_state(character_view.MovementState.WALKING)
	character_view.position = CharacterStroll.advance(character_view.position, _stroll_target, delta)
	# Grass parts near the hero as it strolls through (reported live: "the
	# grass blades don't part when it walks through") -- purely cosmetic,
	# no-op if never called (IllustratedGrassPatch's own default walker
	# position is far away), so this is the one line needed to turn it on.
	if _grass_patch != null:
		_grass_patch.set_walker_position(character_view.position)


func _pick_new_target() -> Vector2:
	var bounds := Rect2(Vector2.ZERO, FOOTPRINT)
	for attempt in MAX_TARGET_ATTEMPTS:
		var candidate := CharacterStroll.pick_target(bounds, _rng)
		if _layout.is_clear(candidate):
			return candidate
	return character_view.position


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
	# CircularPondSprite, not ProceduralShoreDistanceSprite -- that class is
	# built around a square terrain TILE with land on specific cardinal
	# SIDES; an empty land_directions list gave a uniform "no shore
	# anywhere" fill with no alpha mask at all (a flat, square, untextured
	# tint -- reported live: the pond "seems tinted"). CircularPondSprite
	# measures shore-distance radially instead and masks a real circular
	# silhouette, in the same red-channel convention WaterShader already
	# reads.
	pond.texture = CircularPondSprite.generate_texture()
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
		fish_nodes.append(fish)


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
