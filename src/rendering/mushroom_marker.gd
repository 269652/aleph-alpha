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

## "" for a live fruiting specimen, "crushed" or "bitten" for a lingering
## corpse (see WildMushroomPatch.is_corpse/corpse_kind, docs/concept/
## mushrooms.md's "Crushed underfoot") -- set before add_child by
## MushroomRenderer.sync_markers, same convention as species_id/cell.
var corpse_kind := ""

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
## real species' own look -- see class doc comment. A corpse (corpse_kind
## != "") prefers the matching crushed_frame_for/bitten_frame_for when the
## species has that art yet (see docs/concept/mushrooms.md's "Crushed
## underfoot") -- falling through to the ordinary live look otherwise, the
## same has-or-doesn't gate, so a species still missing its crushed/bitten
## sheet (reported live: "some are still missing but I'll add while you
## wire") never shows a blank texture, just its real live look a beat
## longer than the fully-delivered species do.
func _rebuild_sprite() -> void:
	if corpse_kind == "crushed" and _illustrated_generator.has_crushed_variant(species_id):
		_sprite.texture = _illustrated_generator.crushed_frame_for(species_id, mushroom_seed)
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species_id)
	elif corpse_kind == "bitten" and _illustrated_generator.has_bitten_variant(species_id):
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
## doc comment.
func get_display_name() -> String:
	var species_name := MushroomSpecies.display_name_for(species_id)
	if MushroomSpecies.is_toxic(species_id):
		return "%s (Toxic)" % species_name
	return "%s (Edible)" % species_name


## Takes this mushroom into `picker`'s inventory. Same "return whether
## anything was collected" contract DroppedItem/LiftableStone/PickableSeed
## all keep.
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


## A decomposer's single bite (see DecomposerMarker._step_feeding's
## has_method("take_bite") branch, docs/concept/soil_fauna.md's fungivory
## follow-up) -- reported live: "1 bite is enough for when a bug takes a
## bite." `amount` is unused -- unlike Carcass/CarcassGuts' numeric health
## pool, a mushroom has no multi-visit health to whittle down (only one
## bitten-art stage exists today; more are explicitly planned later per
## the user's own words) -- kept only so this duck-types identically into
## DecomposerMarker's existing take_bite branch. No-op (returns false) on
## a marker that is already a corpse -- a decomposer doesn't re-bite what
## something already finished (mirrors Carcass.take_bite's own "no-op
## until/unless a real gate condition holds" contract shape), and never
## even asks the sim in that case. Otherwise defers to
## WildMushroomPatch.bite (this marker's own live cell may already be
## spent by the time the bite lands -- e.g. picked or crushed a moment
## earlier -- in which case bite() itself reports false and this marker is
## left exactly as it was, for sync_markers to reconcile on its own next
## tick). On a real bite, this marker -- the LIVE one -- is freed; the
## corpse the player then sees is a fresh marker MushroomRenderer.
## sync_markers builds from the sim's own corpse_kind, the same "the sim
## is the truth, the marker just mirrors it" shape pick_up already uses.
func take_bite(_amount: float) -> bool:
	if corpse_kind != "":
		return false
	if mushroom_world == null or not mushroom_world.has_method("bite"):
		return false
	if not mushroom_world.bite(cell):
		return false
	queue_free()
	return true
