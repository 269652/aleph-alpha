extends Node2D

## The visible marker over one fruiting WildMushroomPatch site -- see
## ProceduralMushroomSprite/IllustratedMushroomSprite,
## docs/concept/mushrooms.md. Deliberately inert, the same reasoning
## AntMoundMarker gives for its own mound: this is purely "stand here and
## be visible", not an individually-simulated creature.
##
## Always shows its REAL species' own look and name -- there is no
## identification gate (see docs/concept/mushrooms.md's "Revised again:
## the identification gate is gone"). The illustrated art is drawn to
## directly resemble its real-world counterpart, so recognizing a mushroom
## on sight is meant to be immediate, the same way a real forager
## cross-checks against a physical field guide rather than starting from
## zero -- this project's version of that guide lives on the companion
## website, external to the game world, not as an in-game unlock.
##
## Joins DroppedItem.GROUP_NAME (ordinary E/click pickup, the same
## duck-typed pick_up(picker) contract PickableSeed/LiftableStone already
## use), DroppedItem.FORAGEABLE_GROUP_NAME (a decomposer ant/bug can find
## and eat one too -- real fungivory, distinct from the invisible
## mycelium's own decomposition of dead wood/litter this system doesn't
## otherwise model), and HoverTargetFinder.GROUP_NAME (reported live:
## "they need hover tooltips" -- World._update_hover_tooltip only scans
## THIS group, so get_display_name() alone was never enough on its own to
## make a marker's name show on mouse hover; get_hover_actions() mirrors
## DroppedItem/LiftableStone/WildCropMarker's own contract). Picking one
## up resolves to the same real species item id it was already showing.

const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")
const IllustratedMushroomSprite = preload("res://src/rendering/illustrated_mushroom_sprite.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

## The real species this marker represents -- set before add_child, same
## per-instance-field convention as every other marker here (e.g.
## AntMoundMarker.mound_seed, DecomposerMarker.wander_seed).
var species_id := ""

## Which of the illustrated sheet's 25 variants this marker picks (see
## IllustratedMushroomSprite.frame_for) -- set before add_child, same
## convention as AntMoundMarker.mound_seed.
var mushroom_seed := 0

## The site cell this marker represents, and the sim it belongs to --
## duck-typed the same way PickableSeed.seed_world/cell are, so pick_up can
## tell the real WildMushroomPatch its mushroom was taken.
var cell := Vector2i.ZERO
var mushroom_world = null

## Whether a decomposer bug has bitten this mushroom (see take_mushroom_bite,
## docs/concept/mushrooms.md's fungivory section). Unlike being picked or
## crushed, a bite does not remove it -- it stays present and pickable, just
## diminished (a different look, a different, lighter catalog item once
## picked up -- see MushroomBiting.gd).
var bitten := false

var _sprite: Sprite2D

static var _procedural_generator := ProceduralMushroomSprite.new()
static var _illustrated_generator := IllustratedMushroomSprite.new()
static var _item_catalog := ItemCatalog.new()


func _ready() -> void:
	add_to_group(DroppedItem.GROUP_NAME)
	add_to_group(DroppedItem.FORAGEABLE_GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_rebuild_sprite()


## For World's mouse-hover tooltip (see HoverTargetFinder) -- the same
## "Pick Up" verb DroppedItem's own generic pickup uses.
func get_hover_actions() -> Array:
	return [{"verb": "Pick Up", "action": "pickup"}]


## Real illustrated art if this species has any (has-art-or-doesn't
## fallback chain every optional illustrated-art seam in this codebase
## uses), the procedural species-coloured silhouette otherwise. Always the
## real species' own look -- see class doc comment.
func _rebuild_sprite() -> void:
	if bitten and _illustrated_generator.has_bitten_variant(species_id):
		# The bitten look, when the species has real art for it -- see
		# IllustratedMushroomSprite._BITTEN_SHEETS' own doc comment for
		# which species do so far. Reuses the SAME marker_scale(species_id)
		# the ordinary look uses (a bug's bite doesn't shrink the specimen
		# enough to need its own separately-measured scale).
		_sprite.texture = _illustrated_generator.bitten_frame_for(species_id, mushroom_seed)
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species_id)
	elif _illustrated_generator.has_variants(species_id):
		_sprite.texture = _illustrated_generator.frame_for(species_id, mushroom_seed)
		# Illustrated art's own canvas proportions don't match the
		# procedural generator's -- use its own measured-from-the-real-art
		# scale (IllustratedAntMoundSprite.marker_scale's same reasoning),
		# not the flat procedural MUSHROOM_WORLD_SCALE below.
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species_id)
	else:
		_sprite.texture = _procedural_generator.generate_texture(species_id, true)
		_sprite.scale = Vector2.ONE * ProceduralMushroomSprite.MUSHROOM_WORLD_SCALE


## The real species name plus a toxic/edible hint -- always, see class
## doc comment. Bitten takes priority over that hint once a decomposer has
## visibly marked it (see take_mushroom_bite): that is the more salient
## thing to name at that point.
func get_display_name() -> String:
	var species_name := MushroomSpecies.display_name_for(species_id)
	if bitten:
		return "%s (Bitten)" % species_name
	if MushroomSpecies.is_toxic(species_id):
		return "%s (Toxic)" % species_name
	return "%s (Edible)" % species_name


## Marks this mushroom bitten by a decomposer bug (see docs/concept/
## mushrooms.md's fungivory section, MushroomBiting.gd) -- the take_bite-
## shaped verb DecomposerMarker._step_feeding's take_mushroom_bite branch
## calls. Unlike Carcass.take_bite, this never frees the marker: a bitten
## mushroom stays present and pickable, just diminished (see
## _rebuild_sprite/get_display_name/pick_up). Returns false (a no-op) when
## already bitten, or there's no real sim to tell (mushroom_world unset --
## e.g. a marker built standalone in a test) -- the same false a
## decomposer relies on to know it's done here and should move on (see
## WildMushroomPatch.bite's own doc comment).
func take_mushroom_bite() -> bool:
	if bitten:
		return false
	if mushroom_world == null or not mushroom_world.has_method("bite"):
		return false
	if not mushroom_world.bite(cell):
		return false
	bitten = true
	_rebuild_sprite()
	return true


## Takes this mushroom into `picker`'s inventory. Same "return whether
## anything was collected" contract DroppedItem/LiftableStone/PickableSeed
## all keep. A bitten mushroom resolves to its OWN, lighter catalog item
## (see MushroomBiting.bitten_item_id_for) rather than the ordinary species
## one -- what it visibly is by the time it's picked up.
func pick_up(picker) -> bool:
	if picker == null or picker.inventory == null or species_id == "":
		return false
	var item_id := MushroomBiting.bitten_item_id_for(species_id) if bitten else species_id
	var item := _item_catalog.make(item_id)
	if picker.inventory.add(item, 1) > 0:
		return false
	# Taken from the sim as well as from the screen: a picked mushroom must
	# not still be there for a decomposer to eat or for the player to find
	# again (mirrors PickableSeed's seed_world.take_seed_at_cell). Calls
	# WildMushroomPatch.pick directly -- a live MushroomRenderer injects
	# the exact right per-chunk sim instance here, not a wrapper.
	if mushroom_world != null and mushroom_world.has_method("pick"):
		mushroom_world.pick(cell)
	queue_free()
	return true
