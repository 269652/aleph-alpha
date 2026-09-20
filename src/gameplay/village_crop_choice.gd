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


## What has to be STANDING before wheat is worth putting in the ground.
##
## Both links, because the chain is grain -> flour -> bread
## (docs/concept/milling_and_baking.md) and a village with only half of it
## still cannot eat: a mill with no bakery makes flour nobody bakes, a
## bakery with no mill is an oven with no flour. Real placeable ids, so a
## chain named after something the world cannot raise could never gate
## wheat for ever (both test-pinned).
const BAKING_CHAIN: Array[String] = ["mill", "bakery"]


## Whether this village can really turn grain into a meal.
## `present_building_ids` is EarthChunkManager._settlement_present_building_
## ids' own answer -- what actually stands here.
static func can_bake(present_building_ids) -> bool:
	for required in BAKING_CHAIN:
		if not (required in present_building_ids):
			return false
	return true


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
## How much one harvest of each food crop really weighs, in kilograms --
## the ItemCatalog's own real produce masses (a medium potato 150-200g, a
## medium carrot 60-70g, a cut bunch of herbs 20-25g), pinned against them
## by test_the_crop_food_weights_are_the_catalogs_own_real_masses rather
## than restated here as numbers of their own.
##
## This is the tie-break, and the tie is the NORMAL state of a village that
## needs feeding. Measured on three real villages
## (tools/probe_village_cropping.gd):
##
##     satisfaction: { "wood": 1.0, "herb": 0.0, "kind:food": 0.0 }
##     scores:       { "herb": 0.0, "carrot": 0.0, "potato": 0.0 }
##     a wheat-farmer sows: herb
##
## Both goods at 0.0 means every food crop scores identically, and the tie
## used to fall to declaration order -- `herb` is declared first, so every
## field in a starving village sowed the crop that feeds it least: eight and
## a half herb bunches to one potato. Reported as "The farmers produce
## mostly herbs even though it says it can feed 0 / 10".
const FOOD_WEIGHT_KG := {
	"herb": 0.02,
	"carrot": 0.07,
	"potato": 0.17,
}


## How well fed a village has to be before what a farmer traditionally
## grows may decide a tie at all.
##
## Below it the village is going hungry, and feeding it comes before
## flavouring it: a tie is then broken by the heavier harvest. Above it the
## occupation tie-break stands exactly as documented -- among crops the
## village needs equally, an herbalist reaches for herbs.
##
## Half, and the measurement is what puts it there rather than taste: every
## real village measured was at 0.0 (tools/probe_village_cropping.gd), and
## the case the occupation rule was written for sits at 0.5 -- half fed,
## half herbed, nobody starving (test_the_traditional_crop_breaks_a_tie_but_
## does_not_decide). A floor between them has to be strictly above 0.0 and
## no higher than 0.5, and both bounds are test-pinned rather than asserted
## here.
const HUNGRY_BELOW := 0.5


## The crop to sow for this reading.
##
## The SCORE decides first and is unchanged: a crop relieving a good at 0.0
## beats one relieving a good at 0.9. What follows it is what happens when
## two crops are equally needed -- and that tie is the normal state of a
## village that needs feeding, not an edge case.
static func choose(satisfaction: Dictionary, can_bake: bool, default_crop: String) -> String:
	var hungry := float(satisfaction.get(VillageEstates.FOOD_KIND_TOKEN, 1.0)) < HUNGRY_BELOW
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
		elif score == best_score and _breaks_the_tie(crop_id, best, default_crop, hungry):
			best = crop_id
	return best if best != "" else default_crop


## Between two crops the village needs exactly as much, which goes in the
## ground.
##
## A HUNGRY village asks the harvest first: the crop that really feeds more
## wins, and the farmer's own crop only settles it between two that feed the
## same. A fed one asks the farmer first, which is the occupation tie-break
## exactly as it was. A crop with no weight (one that answers no food good)
## never wins on weight -- this tie-break is about feeding, and a crop that
## does not feed has nothing to win it with.
static func _breaks_the_tie(
	crop_id: String, incumbent: String, default_crop: String, hungry: bool
) -> bool:
	if not hungry:
		return crop_id == default_crop
	var mine := float(FOOD_WEIGHT_KG.get(crop_id, 0.0))
	var theirs := float(FOOD_WEIGHT_KG.get(incumbent, 0.0))
	if mine != theirs:
		return mine > theirs
	return crop_id == default_crop


## The worst satisfaction among the goods this crop answers that the village
## is really asking for; INF when it answers none of them.
static func _score_of(crop_id: String, satisfaction: Dictionary) -> float:
	var worst := INF
	for good in SOWABLE[crop_id]:
		if not satisfaction.has(good):
			continue
		worst = minf(worst, float(satisfaction[good]))
	return worst
