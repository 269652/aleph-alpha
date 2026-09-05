extends Sprite2D

## An item lying on the ground: a visible, procedurally-drawn sprite holding an
## ItemStack. Its name only shows on mouse hover, via World's shared hover
## tooltip (see HoverTargetFinder/get_display_name/get_hover_actions) -- it
## used to float an always-on name label above every dropped item
## (Path-of-Exile style), which cluttered the ground with labels for every
## windfall and pebble lying around. Click the icon to pick it up. There is
## deliberately no proximity auto-pickup; walking past a dropped item leaves
## it alone until the player actually clicks it. Picking up merges the stack
## into the player's inventory and frees this node; if the inventory has no
## room the node stays (with whatever didn't fit).

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const GROUP_NAME := "dropped_item"
## Real fallen fruit/nut ground items ONLY -- a small, pre-filtered subset
## of GROUP_NAME a decomposer can scan cheaply (see DecomposerMarker.
## _nearest_food). GROUP_NAME itself is shared by every ground-pickable
## thing this game has, LiftableStone and PickableSeed very much included
## (both deliberately join it too, see their own doc comments) -- stones
## in particular are extremely dense, so a decomposer scanning the WHOLE
## group globally for every one of its own foraging checks is a real,
## measured performance cost (bug report: "game now has only 4-5 fps"),
## not merely a cosmetic inefficiency. Joined here, at creation, rather
## than filtered per-scan, so the cost of "is this a fruit/nut" is paid
## once per item instead of once per (item x every decomposer x every
## scan).
const FORAGEABLE_GROUP_NAME := "forageable_fruit"
## Un-picked-up items despawn after this many seconds so the ground doesn't
## fill up with forage over a long session.
const LIFETIME := 90.0

## The suffix every fallen-leaf item id carries -- "<species>_leaf"
## uniformly, even pine's own "pine_leaf" (displayed as "Pine Needles";
## see EarthChunkManager's own _LEAF_ITEMS doc comment). The one place this
## file turns a leaf item's own id back into the TreeSpecies id its
## foraging status and art come from (see _leaf_species_id below), so
## recognising "is this a leaf item" stays a single suffix check rather
## than a second species-by-species list next to TreeSpecies.IDS.
const _LEAF_ITEM_SUFFIX := "_leaf"

## How long THIS item lasts before it goes.
##
## Food overrides it with a real shelf life (see FruitSpoilage): a windfall
## should be worth walking back for and then be gone, and a nut in its shell
## should still be there long after the cherries beside it have rotted.
## Anything that is not food keeps the flat despawn, which is a tidiness rule
## rather than a spoilage one.
var spoil_seconds := LIFETIME

## Whether this item ages on WORLD time rather than wall-clock time.
##
## Food does. Rot is a thing the seasons do, so it has to run on the same clock
## as the seasons -- otherwise a run of /ecotest sweeps a year past a windfall
## that has aged ninety seconds, and fruit that should have rotted in autumn is
## still sitting there in spring.
var ages_on_world_time := false

const CLICK_AREA_SIZE := Vector2(64.0, 32.0)
const CLICK_AREA_OFFSET_Y := -8.0

static var _sprite_generator := ProceduralItemSprite.new()
static var _crop_sprite_generator := IllustratedCropSprite.new()
static var _tree_art_generator := IllustratedTree.new()

## How big a fallen leaf's illustrated litter texture reads on the ground,
## in world pixels -- bigger than a walnut (a leaf is visually broader
## than a nut) but well short of a whole apple/carrot (IllustratedCropSprite
## .ROOT_WORLD_SIZE): a leaf is a thin, flat thing on the ground, not a
## round fruit.
const LEAF_WORLD_SIZE := ProceduralItemSprite.WALNUT_WORLD_WIDTH * 1.5

## ## Falling and swaying
##
## A leaf does not simply appear on the ground the way every other dropped
## item does -- it visibly drops from above and settles, then keeps a
## gentle ongoing sway once landed, real wind rather than a one-shot
## animation that stops (see docs/concept/leaf_litter.md).
##
## How high above its own landing spot a falling leaf starts, in world
## pixels -- a plain fixed height rather than the tree's own actual
## canopy top: step_fruiting only ever hands this class a landing
## POSITION, not which tree or how tall it is, and a leaf drifting down
## from just off-screen above reads the same as one falling the tree's
## own full height would.
const FALL_HEIGHT := 40.0
## How long the drop takes, in seconds -- unhurried enough to actually see
## happen, short enough not to leave the ground looking like it is
## perpetually mid-snowfall when several trees are shedding at once.
const FALL_DURATION := 0.9
## How far a falling leaf drifts sideways from its own straight-line path,
## in world pixels, at the START of the fall -- real leaves flutter and
## spiral rather than dropping straight down. Tapers to zero by the time
## it lands (see _step_fall), so it always settles exactly at the position
## step_fruiting actually chose.
const FALL_SWAY_WORLD := 10.0
## How many full side-to-side swings one fall completes.
const FALL_SWAY_CYCLES := 2.2
## How far a landed leaf's own gentle ongoing sway rocks it, in radians.
const GROUND_SWAY_RADIANS := deg_to_rad(4.0)
## How long one full ground-sway cycle takes, in seconds.
const GROUND_SWAY_PERIOD := 3.2

var item_stack
var _age := 0.0
var _is_leaf := false
var _falling := false
var _fall_origin := Vector2.ZERO
var _fall_target := Vector2.ZERO
var _fall_elapsed := 0.0
## Per-instance phase offset for the ground sway, so several landed leaves
## don't all rock in unison -- purely cosmetic, so a plain randf() (rather
## than a seeded hash) is fine here; nothing depends on it replaying
## identically.
var _sway_phase := 0.0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	var leaf_species := _leaf_species_id(item_stack.item.id) if item_stack != null else ""
	_is_leaf = leaf_species != ""
	if item_stack != null and (TreeSpecies.IDS.has(item_stack.item.id) or _is_leaf):
		add_to_group(FORAGEABLE_GROUP_NAME)
	if item_stack != null and texture == null:
		# A pulled wild carrot/potato uses the real illustrated root art (see
		# docs/concept/wild_crops.md) -- the same texture the player just
		# watched rise out of the ground during the pull, not a different
		# fallback sprite once it lands. Checked first, ahead of the generic
		# procedural path every other item still uses.
		var leaf_season := _leaf_fallen_season(item_stack.item) if _is_leaf else ""
		if _crop_sprite_generator.has_crop(item_stack.item.sprite_id):
			texture = _crop_sprite_generator.root_texture(item_stack.item.sprite_id, 0)
			scale = Vector2.ONE * _crop_sprite_generator.root_world_scale(item_stack.item.sprite_id)
		elif leaf_season != "" and _tree_art_generator.has_foliage_leaf_for(leaf_species, leaf_season):
			# A fallen leaf uses the real single-leaf closeup already
			# sitting on its own species' composite tree sheet, coloured
			# to the season it actually fell in -- green in summer, orange
			# in autumn (see docs/concept/leaf_litter.md) -- same "check
			# real illustrated art first" precedent as the wild-carrot
			# branch above.
			texture = _tree_art_generator.foliage_leaf_for(leaf_species, leaf_season)
			scale = Vector2.ONE * (LEAF_WORLD_SIZE / maxf(IllustratedCropSprite.max_content_extent(texture), 1.0))
		else:
			texture = _sprite_generator.texture_for(item_stack.item.sprite_id)
			# Item art is authored DETAIL_MULTIPLIER times oversized; scaling
			# it back keeps a dropped item the right size on the ground (see
			# docs/concept/art_resolution.md). Tree fruit additionally has its
			# own per-species world width, because at the shared scale a
			# fallen cherry was as wide as the tile it lay on -- see
			# ProceduralItemSprite.world_scale_for.
			scale = Vector2.ONE * _sprite_generator.world_scale_for(item_stack.item.sprite_id)

	if _is_leaf:
		_fall_target = position
		_fall_origin = position - Vector2(0.0, FALL_HEIGHT)
		position = _fall_origin
		_falling = true
		_sway_phase = randf() * TAU

	var click_area := Area2D.new()
	var collision_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = CLICK_AREA_SIZE
	collision_shape.shape = shape
	collision_shape.position = Vector2(0, CLICK_AREA_OFFSET_Y)
	click_area.add_child(collision_shape)
	click_area.input_event.connect(_on_input_event)
	add_child(click_area)


## "cherry_leaf" -> "cherry", or "" if `item_id` is not a leaf item -- see
## _LEAF_ITEM_SUFFIX's own doc comment.
static func _leaf_species_id(item_id: String) -> String:
	if not item_id.ends_with(_LEAF_ITEM_SUFFIX):
		return ""
	var species_id := item_id.substr(0, item_id.length() - _LEAF_ITEM_SUFFIX.length())
	return species_id if TreeSpecies.IDS.has(species_id) else ""


## "cherry_leaf_autumn" -> "autumn", or "" if `item`'s own sprite_id
## doesn't carry a season this way -- see EarthChunkManager.step_fruiting's
## own doc comment on why sprite_id (not id) is where a fallen leaf's
## season lives: id/display_name/kind/max_stack are the shared identity
## every "cherry_leaf" has regardless of season, sprite_id is the one
## field this codebase already uses for "which art this specific item
## resolves to" (see Item's own doc comment).
static func _leaf_fallen_season(item) -> String:
	var prefix: String = item.id + "_"
	if not item.sprite_id.begins_with(prefix):
		return ""
	return item.sprite_id.substr(prefix.length())


func _process(delta: float) -> void:
	if _falling:
		_step_fall(delta)
	elif _is_leaf:
		_step_ground_sway(delta)
	# World-time items are aged by the ecology step instead (see advance).
	if ages_on_world_time:
		return
	advance(delta)


## Animates the drop from _fall_origin to _fall_target: a straight vertical
## descent eased in (real leaves catch air and start slow, not shoot off
## at full speed instantly) with a horizontal flutter that tapers to zero
## by the time it lands -- so however it wanders on the way down, it
## always settles exactly at the position step_fruiting actually chose,
## the same "the physics may drift but the destination is fixed" contract
## SnowBombShader's own tread mechanism keeps for a different reason.
func _step_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / FALL_DURATION, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t) # smoothstep: ease in, ease out
	var sway := sin(t * TAU * FALL_SWAY_CYCLES + _sway_phase) * FALL_SWAY_WORLD * (1.0 - t)
	position = _fall_origin.lerp(_fall_target, eased) + Vector2(sway, 0.0)
	rotation = sin(t * TAU * FALL_SWAY_CYCLES + _sway_phase) * deg_to_rad(20.0) * (1.0 - t)
	if t >= 1.0:
		position = _fall_target
		_falling = false


## The gentle ongoing rock a landed leaf keeps -- real wind, not a fall
## animation that simply stops moving once it ends. Reuses `_age` (see
## advance()) as the time input rather than a second counter: a leaf is
## never a food item (ages_on_world_time stays false for "material" kind),
## so _age already advances every real frame regardless.
func _step_ground_sway(_delta: float) -> void:
	rotation = sin(_age * TAU / GROUND_SWAY_PERIOD + _sway_phase) * GROUND_SWAY_RADIANS


## Ages this item by `delta` seconds and removes it once it is past keeping.
func advance(delta: float) -> void:
	_age += delta
	if _age >= spoil_seconds:
		queue_free()


## How rotten this item is, 0 fresh to 1 gone -- for callers that want to show
## it or refuse to eat it.
func spoilage() -> float:
	if spoil_seconds <= 0.0:
		return 1.0
	return clampf(_age / spoil_seconds, 0.0, 1.0)


## Merges this stack into the picker's inventory. Frees the node if it all fit;
## if the inventory was full, leaves the node on the ground with the
## remainder. Returns whether anything at all was picked up.
func pick_up(picker) -> bool:
	if item_stack == null or picker.inventory == null:
		return false
	var overflow: int = picker.inventory.add(item_stack.item, item_stack.count)
	if overflow == item_stack.count:
		return false  # nothing fit
	item_stack.count = overflow
	if item_stack.count <= 0:
		queue_free()
	return true


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	if item_stack == null:
		return ""
	return (
		"%s x%d" % [item_stack.item.display_name, item_stack.count]
		if item_stack.count > 1
		else item_stack.item.display_name
	)


## For World's mouse-hover tooltip (see HoverTargetFinder). Every dropped
## item can be picked up; one with a real, MODELED mass (item.gd's own
## "0.0 = not modeled yet" convention -- most food/material items still sit
## there) light enough for Kick.is_kickable can also be kicked -- the same
## "a real physical object, not just an inventory grant" LiftableStone
## already promises (docs/concept/stone.md), extended here so a pulled wild
## carrot/potato (docs/concept/wild_crops.md) is one too.
func get_hover_actions() -> Array:
	var actions := [{"verb": "Pick Up", "action": "pickup"}]
	if item_stack != null and item_stack.item.mass_kg > 0.0 and Kick.is_kickable(item_stack.item.mass_kg):
		actions.append({"verb": "Kick", "action": "kick"})
	return actions


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			pick_up(players[0])
