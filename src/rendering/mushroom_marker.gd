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

## "" for a live fruiting specimen, "crushed" for a lingering corpse (see
## WildMushroomPatch.is_corpse/corpse_kind, docs/concept/mushrooms.md's
## "Crushed underfoot") -- set before add_child by
## MushroomRenderer.sync_markers, same convention as species_id/cell. A
## crushed corpse is a FRESH marker built to replace the live one that was
## just crushed (see sync_markers); a bitten mushroom (see `bitten` below)
## is the opposite -- the ORIGINAL live marker, never replaced, so this
## stays "" for it.
var corpse_kind := ""

## How many real bite stages THIS live mushroom has taken so far, 0..
## MushroomBiting.MAX_BITE_STAGES (see take_mushroom_bite, docs/concept/
## mushrooms.md's fungivory section, docs/concept/soil_fauna.md's
## "Progressive, mass-scaled bites, and real toxic effects"). Unlike being
## picked or crushed, a PARTIAL bite (under the cap) does not remove this
## marker or replace it with a corpse marker -- it stays present and
## pickable, just diminished (a different look per stage, a different,
## lighter catalog item once picked up -- see MushroomBiting.gd). Was a
## plain bool before 2026-09-07 -- one bite from anyone was final; now a
## real step count, mirroring WildMushroomPatch._bite_stage on the sim
## side, so a second, later bite (same or different eater) can advance it
## further, each stage showing its own progressively-more-eaten art.
var bite_stage := 0

## Plain `bite_stage > 0` mirror, kept in sync on every change -- a real,
## deliberate backward-compatibility shim so every existing caller/test
## that reads or sets `bitten` directly keeps working unchanged.
## `bite_stage` is the authoritative field; this never diverges from it.
## Deliberately a separate field from corpse_kind, not a third corpse_kind
## value while still partial: a partially-bitten mushroom is not a corpse,
## it is still standing, still fruiting.
var bitten := false

var _sprite: Sprite2D

static var _procedural_generator := ProceduralMushroomSprite.new()
static var _illustrated_generator := IllustratedMushroomSprite.new()
static var _item_catalog := ItemCatalog.new()


## One-line hook World._ready() calls once, before any decomposer can
## possibly reach a mushroom -- see IllustratedMushroomSprite.warm_cache's
## own doc comment for why. Delegates to the same shared _illustrated_
## generator instance every MushroomMarker already reads its sprite from.
## Awaits warm_cache() in full -- it now yields internally across several
## real engine frames (see its own doc comment), so callers that need the
## cache genuinely warm before proceeding (World._ready()) must await this
## too, not just call it and move on.
static func warm_art_cache(on_progress: Callable = Callable()) -> void:
	await _illustrated_generator.warm_cache(on_progress)


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
## real species' own look -- see class doc comment. A crushed or fully-eaten
## corpse (corpse_kind == "crushed"/"eaten") or a partially-bitten live
## specimen (bite_stage > 0) prefers the matching crushed_frame_for/
## bitten_frame_for when the species has that art yet (see docs/concept/
## mushrooms.md's "Crushed underfoot"/"Bitten by a decomposer") -- falling
## through to the ordinary live look otherwise, the same has-or-doesn't
## gate, so a species still missing its crushed/bitten sheet never shows a
## blank texture, just its real live look a beat longer than the
## fully-delivered species do.
func _rebuild_sprite() -> void:
	if corpse_kind == "crushed" and _illustrated_generator.has_crushed_variant(species_id):
		_sprite.texture = _illustrated_generator.crushed_frame_for(species_id, mushroom_seed)
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species_id)
	elif corpse_kind == "eaten" and _illustrated_generator.has_bitten_variant(species_id):
		# A fully-consumed corpse shows the final bite stage's own art --
		# the mushroom read as most-eaten just before it was actually
		# finished off (see docs/concept/soil_fauna.md's "Progressive,
		# mass-scaled bites").
		_sprite.texture = _illustrated_generator.bitten_frame_for(
			species_id, mushroom_seed, MushroomBiting.MAX_BITE_STAGES
		)
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species_id)
	elif bite_stage > 0 and _illustrated_generator.has_bitten_variant(species_id):
		# The bitten look for THIS stage, when the species has real art for
		# it -- see IllustratedMushroomSprite._BITTEN_SHEETS' own doc
		# comment for which species do so far. Reuses the SAME
		# marker_scale(species_id) the ordinary look uses (a bug's bite
		# doesn't shrink the specimen enough to need its own
		# separately-measured scale).
		_sprite.texture = _illustrated_generator.bitten_frame_for(species_id, mushroom_seed, bite_stage)
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


## The real species name plus a state hint -- always, see class doc
## comment. A crushed corpse (corpse_kind == "crushed") takes priority over
## everything else, the same first-checked priority _rebuild_sprite's own
## sprite choice already gives it -- reported directly ("Champignons should
## show state in hover tooltip e.g. Parasol (Crushed); Parasol (Edible);
## Death Cap (Poisonous)"), closing the one state _rebuild_sprite already
## understood that this never did: a crushed corpse used to fall through to
## the ordinary toxic/edible hint, the same species-driven answer a live,
## untouched specimen shows -- flatly wrong for a corpse. Bitten is next
## (see take_mushroom_bite): the more salient thing to name once a
## decomposer has visibly marked a still-living specimen. In practice a
## marker is never both -- a crushed corpse is always a FRESH, unbitten
## replacement (see corpse_kind's own doc comment) -- but the ordering
## still matches _rebuild_sprite's so the two can't silently drift apart.
func get_display_name() -> String:
	var species_name := MushroomSpecies.display_name_for(species_id)
	if corpse_kind == "crushed":
		return "%s (Crushed)" % species_name
	if corpse_kind == "eaten":
		return "%s (Eaten)" % species_name
	if bite_stage > 0:
		return "%s (Bitten)" % species_name
	if MushroomSpecies.is_toxic(species_id):
		return "%s (Toxic)" % species_name
	return "%s (Edible)" % species_name


## Whether this live mushroom still has any real bite capacity left --
## true while bite_stage is under MushroomBiting.MAX_BITE_STAGES, false
## once it's been fully eaten. What DecomposerMarker._nearest_food checks
## (see its own doc comment) to decide whether a partially-bitten mushroom
## is still worth targeting for the NEXT bug, replacing the old flat
## "not bitten at all" exclusion that used to treat any bite as final.
func can_be_bitten() -> bool:
	return bite_stage < MushroomBiting.MAX_BITE_STAGES


## Bites this mushroom -- a decomposer bug's single nibble (default) or a
## bigger, mass-scaled eater's own bigger mouthful (see
## MushroomBiting.bites_per_visit_for) -- the take_bite-shaped verb
## DecomposerMarker._step_feeding's take_mushroom_bite branch and
## CreatureMarker's own boar-bite path both call. Deliberately its OWN
## method name, not take_bite(): a MushroomMarker must NOT answer
## has_method("take_bite") true, or DecomposerMarker would route it into
## the Carcass/CarcassGuts branch instead of the mushroom one. Unlike
## Carcass.take_bite, this never frees the marker while any capacity
## remains -- a partially-bitten mushroom stays present and pickable, just
## diminished (see _rebuild_sprite/get_display_name/pick_up).
##
## Delegates entirely to mushroom_world.bite(cell, bite_stages), which
## returns how many stages actually landed (0 if there was nothing
## fruiting, or it was already fully eaten -- see WildMushroomPatch.bite's
## own doc comment) -- this marker does NOT locally enforce the cap
## itself, it just mirrors whatever the sim (the one real source of truth)
## reports, accumulating bite_stage by exactly that much. Returns false
## (a no-op) when nothing landed, or there's no real sim to tell
## (mushroom_world unset -- e.g. a marker built standalone in a test) --
## the same false a decomposer relies on to know it's done here and
## should move on.
func take_mushroom_bite(bite_stages: int = 1) -> bool:
	if mushroom_world == null or not mushroom_world.has_method("bite"):
		return false
	var applied: int = mushroom_world.bite(cell, bite_stages)
	if applied <= 0:
		return false
	bite_stage += applied
	bitten = true
	_rebuild_sprite()
	return true


## Takes this mushroom into `picker`'s inventory. Same "return whether
## anything was collected" contract DroppedItem/LiftableStone/PickableSeed
## all keep. A bitten mushroom resolves to its OWN, lighter catalog item
## (see MushroomBiting.bitten_item_id_for) rather than the ordinary species
## one -- what it visibly is by the time it's picked up. Its own real
## `bite_stage` (not just whether it was bitten at all) is passed straight
## through to ItemCatalog.make so the item's mass genuinely reflects how
## much was actually eaten before pickup -- see docs/concept/metabolism.md's
## "the two named mushroom gaps" (a flat single-bite fraction used to apply
## no matter how many real stages had landed).
func pick_up(picker) -> bool:
	if picker == null or picker.inventory == null or species_id == "":
		return false
	var item_id := MushroomBiting.bitten_item_id_for(species_id) if bitten else species_id
	var item := _item_catalog.make(item_id, bite_stage)
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
