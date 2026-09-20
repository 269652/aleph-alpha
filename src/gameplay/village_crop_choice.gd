extends RefCounted

## What a field sows (docs/concept/village_farms.md, "What a field sows
## follows the village's need").
##
## Reported with the village's own panels open: *"they have 0 Herbs even
## though there are 3 farm houses... so deciding what to plant must be based
## on demand"*, and beside it *"The warehouse shows 205 Wheat but the
## Villagers show 50% food"*.
##
## Those are one defect seen twice, and the second explains the first.
## **Wheat is ItemCatalog kind "material", not "food"** -- docs/concept/
## milling_and_baking.md's own first pillar, "grain is not food until it is
## milled and baked" -- so every filter that decides whether a village is
## fed (SettlementFood, VillageMarket, VillageEstates' kind:food token)
## counts a granary full of wheat as ZERO food. A village whose every field
## sows wheat, with no mill standing, starves beside it. That is a cropping
## failure, not a distribution one.
##
## Pure and static, a reading in and a crop id out -- the same shape
## VillageFarm's own rule set keeps, and testable without a world.

const VillageEstates = preload("res://src/emergence/village_estates.gd")

## Each sowable crop and the goods sowing it would relieve.
##
## Deliberately small, and every entry earns its place: a crop is here only
## if the world can really grow it (real art, a real ItemCatalog item) AND
## it answers a good some estate really asks for -- both test-pinned. A crop
## answering an invented good would be a field sown for nothing.
##
## Ordered, because the order is the deterministic tie-break of last resort.
const SOWABLE := {
	"herb": ["herb", VillageEstates.FOOD_KIND_TOKEN],
	"carrot": [VillageEstates.FOOD_KIND_TOKEN],
	"potato": [VillageEstates.FOOD_KIND_TOKEN],
	"wheat": ["bread"],
}

## The one crop that is not itself food.
##
## It answers `bread`, and only through a mill and a bakery -- so it is
## offered ONLY where the village can really bake it (see `can_bake`).
## Everywhere else it answers nothing at all, which is exactly the reported
## warehouse: 205 wheat, and everybody at half rations.
const MILLED_CROP := "wheat"


static func sowable_crops() -> Array:
	return SOWABLE.keys()


## The goods sowing this crop would relieve, [] for something not sowable.
static func goods_answered_by(crop_id: String) -> Array:
	return (SOWABLE.get(crop_id, []) as Array).duplicate()


## The crop to put in the ground, given `satisfaction` -- VillageAssembly's
## own per-good reading, straight off the real EstateConsumption.draw, the
## same number the needs panel shows -- and whether this village can really
## bake.
##
## Scored by the WORST-supplied good a crop answers, never the mean: a crop
## that would relieve a good sitting at 0.0 is worth more than one relieving
## a good at 0.9. That is the same minimum rule EstateConsumption already
## applies to an estate's own verdict, and for the same reason -- a village
## with all the bread in the world and no herbs is short of herbs.
##
## `default_crop` is the occupation's own traditional one. It breaks a tie
## and nothing more, and it is the whole answer when there is no reading to
## go on (a marker with no world to ask, a village nobody has assessed) or
## when nothing sowable answers any good asked for -- the same fail-open
## shape every other world hook in the farm path already uses.
static func choose(satisfaction: Dictionary, can_bake: bool, default_crop: String) -> String:
	var best := ""
	var best_score := INF
	for crop_id in SOWABLE:
		if crop_id == MILLED_CROP and not can_bake:
			continue
		var score := _score_of(crop_id, satisfaction)
		if score == INF:
			continue  # answers nothing this village is asking for
		if score < best_score:
			best_score = score
			best = crop_id
		elif score == best_score and crop_id == default_crop:
			best = crop_id  # tied, and it is the one already in this farmer's hands
	return best if best != "" else default_crop


## The worst satisfaction among the goods this crop answers that the village
## is really asking for; INF when it answers none of them.
static func _score_of(crop_id: String, satisfaction: Dictionary) -> float:
	var worst := INF
	for good in SOWABLE[crop_id]:
		if not satisfaction.has(good):
			continue
		worst = minf(worst, float(satisfaction[good]))
	return worst
