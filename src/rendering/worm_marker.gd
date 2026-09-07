extends Sprite2D

## The visible marker over one earthworm burrow -- crawling/surfaced while
## alive, holding the die animation's last frame once crushed (see
## EarthwormPatch.is_corpse/corpse_age_seconds, docs/concept/soil_fauna.md's
## "A corpse is new ground"). EarthChunkManager._sync_worm_sprites sets
## `.texture`/`.scale`/`.offset`/`.position` directly, the same externally-
## driven-visuals shape every other ground marker in this file's sibling
## classes already uses -- this class only ADDS pickup on top of that.
##
## Reported live: "crushing worms doesn't display their crushed sprite last
## frame; instead they vanish.. they should stay in world and still be able
## to picked up". The vanish half was already fixed (2026-09-05, see
## EarthwormPatch.is_corpse/_sync_worm_sprites); this class is the still-
## missing pickup half.
##
## Deliberately NOT pickable while alive -- a live worm is docs/concept/
## aquatic_foraging.md's own separate, still-⬜ "Worms as fish bait" pass,
## not this one. Joins DroppedItem.GROUP_NAME only (no HoverTargetFinder --
## mirrors PickableSeed's own no-tooltip precedent), so the existing pickup
## sweep (Player.pickup_nearby, default E) reaches it with no special case,
## and pick_up itself is what gates "nothing to take" while alive.

const Item = preload("res://src/gameplay/item.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## Which burrow this marker sits over, so the world can be told the corpse
## was taken. Duck-typed the same way PickableSeed.seed_world/
## MushroomMarker.mushroom_world are -- the actual worm_world a live
## EarthChunkManager injects is the per-chunk EarthwormPatch directly.
var cell := Vector2i.ZERO
var worm_world = null

static var _item_catalog := ItemCatalog.new()


func _ready() -> void:
	add_to_group(DroppedItem.GROUP_NAME)


## Takes this worm's corpse into `picker`'s inventory. Returns false (a
## no-op, same "just try, sim decides" contract as take()/crush()/pick())
## while the worm is still alive -- only a corpse is a takeable item here.
func pick_up(picker) -> bool:
	if picker == null or picker.inventory == null:
		return false
	if worm_world == null or not worm_world.has_method("is_corpse") or not worm_world.is_corpse(cell):
		return false
	var item := _item_catalog.make("worm")
	if picker.inventory.add(item, 1) > 0:
		return false
	# Taken from the sim as well as from the screen: a picked-up corpse
	# must not still be there to render or for a new worm to (eventually)
	# occupy the burrow before its own recovery is up (mirrors
	# PickableSeed.seed_world.take_seed_at_cell / MushroomMarker.
	# mushroom_world.pick).
	if worm_world.has_method("take_corpse"):
		worm_world.take_corpse(cell)
	queue_free()
	return true
