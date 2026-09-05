extends Node2D

## The visible marker over one fruiting WildMushroomPatch site -- see
## ProceduralMushroomSprite/IllustratedMushroomSprite,
## docs/concept/mushrooms.md. Deliberately inert, the same reasoning
## AntMoundMarker gives for its own mound: this is purely "stand here and
## be visible", not an individually-simulated creature.
##
## Carries the identification gate docs/concept/mushrooms.md specifies: an
## unidentified marker draws ONE shared, plain look regardless of its true
## species (ProceduralMushroomSprite's own generate_texture(species_id,
## identified) contract) -- only once `identified` is true does it draw
## the real species' own look, and only THEN does has_variants()-gated
## illustrated art even get a chance to apply. Identification gates FIRST,
## ahead of the has-art-or-doesn't fallback chain (see docs/concept/
## mushrooms.md's "Identification gate, checked before species art at
## all") -- an unidentified mushroom must read as unidentified even once
## real illustrated art exists for its true species.
##
## Joins DroppedItem.GROUP_NAME (ordinary E/click pickup, the same
## duck-typed pick_up(picker) contract PickableSeed/LiftableStone already
## use) and DroppedItem.FORAGEABLE_GROUP_NAME (a decomposer ant/bug can
## find and eat one too -- real fungivory, distinct from the invisible
## mycelium's own decomposition of dead wood/litter this system doesn't
## otherwise model). Picking one up always resolves to its REAL species
## item id, regardless of `identified` -- the ambiguity is about what a
## player SEES standing in the world, not what they end up holding.

const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")
const IllustratedMushroomSprite = preload("res://src/rendering/illustrated_mushroom_sprite.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")

## The real species this marker represents -- set before add_child, same
## per-instance-field convention as every other marker here (e.g.
## AntMoundMarker.mound_seed, DecomposerMarker.wander_seed).
var species_id := ""

## Which of the illustrated sheet's 25 variants this marker picks once
## identified (see IllustratedMushroomSprite.frame_for) -- set before
## add_child, same convention as AntMoundMarker.mound_seed.
var mushroom_seed := 0

## Whether the player has learned to identify mushrooms (see
## Player.knows_mushrooms) -- may be set before add_child, or changed later
## (this flips true mid-play the moment the player crosses the learning
## threshold, and an already-standing marker has to show that immediately,
## not wait for a respawn -- see the setter below). Gates BOTH the sprite
## AND the display name, never independently.
var identified := false:
	set(value):
		if identified == value:
			return
		identified = value
		if _sprite != null:
			_rebuild_sprite()

## The site cell this marker represents, and the sim it belongs to --
## duck-typed the same way PickableSeed.seed_world/cell are, so pick_up can
## tell the real WildMushroomPatch its mushroom was taken.
var cell := Vector2i.ZERO
var mushroom_world = null

var _sprite: Sprite2D

static var _procedural_generator := ProceduralMushroomSprite.new()
static var _illustrated_generator := IllustratedMushroomSprite.new()
static var _item_catalog := ItemCatalog.new()


func _ready() -> void:
	add_to_group(DroppedItem.GROUP_NAME)
	add_to_group(DroppedItem.FORAGEABLE_GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_rebuild_sprite()


## Identification gates FIRST, ahead of the has-art-or-doesn't fallback
## chain (see class doc comment) -- an unidentified mushroom must read as
## unidentified even once real illustrated art exists for its true
## species. Called once at spawn and again whenever `identified` changes.
func _rebuild_sprite() -> void:
	if identified and _illustrated_generator.has_variants(species_id):
		_sprite.texture = _illustrated_generator.frame_for(species_id, mushroom_seed)
		# Illustrated art's own canvas proportions don't match the
		# procedural generator's -- use its own measured-from-the-real-art
		# scale (IllustratedAntMoundSprite.marker_scale's same reasoning),
		# not the flat procedural MUSHROOM_WORLD_SCALE below.
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species_id)
	else:
		_sprite.texture = _procedural_generator.generate_texture(species_id, identified)
		_sprite.scale = Vector2.ONE * ProceduralMushroomSprite.MUSHROOM_WORLD_SCALE


## "Unidentified Mushroom" until the player knows better, then the real
## species name plus a toxic/edible hint -- the exact same `identified`
## condition as the sprite swap above.
func get_display_name() -> String:
	if not identified:
		return "Unidentified Mushroom"
	var species_name := MushroomSpecies.display_name_for(species_id)
	if MushroomSpecies.is_toxic(species_id):
		return "%s (Toxic)" % species_name
	return "%s (Edible)" % species_name


## Takes this mushroom into `picker`'s inventory -- always the REAL species
## item, whether or not the player has identified it yet (see class doc
## comment). Same "return whether anything was collected" contract
## DroppedItem/LiftableStone/PickableSeed all keep.
func pick_up(picker) -> bool:
	if picker == null or picker.inventory == null or species_id == "":
		return false
	var item := _item_catalog.make(species_id)
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
