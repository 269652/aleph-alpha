extends RefCounted

## The three principal body extents of every species a net might meet, in
## millimetres -- docs/concept/capture_dsl.md's "Mesh physics: what a net
## holds". Pure data, static lookups, no state.
##
## ## Why a body has three numbers and not a size class
##
## What a mesh holds is decided by geometry: a body passes a square opening
## when its two smaller extents both do, and it goes through a net's mouth
## only if its largest one does. Neither question can be answered by "small
## animal" -- a housefly and a honeybee are both small and only one of them
## is a problem for a 10 mm mesh -- so every species carries the three real
## extents and the physics (capture_physics.gd) sorts and compares them.
## Nothing here says what any net catches.
##
## ## The three extents, and what each means
##
##   length_mm   head to tail (or abdomen tip). PINNED equal to the
##               body_length_m WingbeatBounce.FLIGHT already flies every
##               flyer on, by test_the_length_is_the_length_the_wingbeat_model_
##               already_flies_on, so the two tables cannot disagree.
##   breadth_mm  side to side at rest: a butterfly's body with its wings
##               folded dorsally, a bird's body, a fish's width.
##   depth_mm    top to bottom at rest: a butterfly's FOLDED WINGS standing
##               up (nearly half the spread span -- the reason a butterfly
##               presents far more than its body to a mesh), a bird's body,
##               a fish's body depth.
##
## Every figure is a published adult measurement of the real species the
## roster stands for, named on its line. Fish are typical pond/river adults
## rather than record specimens.

const _EXTENTS_MM := {
	# -- butterflies (Lepidoptera) ------------------------------------------
	# Danaus plexippus: body ~25 mm, wingspan 89-102 mm -> folded ~48 mm tall.
	"monarch": {"length_mm": 25.0, "breadth_mm": 8.0, "depth_mm": 48.0},
	# Papilio machaon (the Old World swallowtail): body ~30 mm, span 65-86 mm.
	"swallowtail": {"length_mm": 30.0, "breadth_mm": 9.0, "depth_mm": 40.0},
	# Morpho peleides/menelaus: body ~35 mm, span 120-150 mm.
	"blue_morpho": {"length_mm": 35.0, "breadth_mm": 10.0, "depth_mm": 65.0},
	# -- the two that pass a coarse mesh -------------------------------------
	# Apis mellifera worker: 12-15 mm long, ~6 mm across the thorax.
	"bee": {"length_mm": 13.0, "breadth_mm": 6.0, "depth_mm": 5.0},
	# Musca domestica: 6-7 mm long, ~3 mm across.
	"fly": {"length_mm": 7.0, "breadth_mm": 3.0, "depth_mm": 3.0},
	# -- small birds ----------------------------------------------------------
	# Passer domesticus: 14-16 cm long, a body about 4.5 cm through.
	"sparrow": {"length_mm": 140.0, "breadth_mm": 45.0, "depth_mm": 45.0},
	# Erithacus rubecula: 12.5-14 cm; the wingbeat table already flies it at 14.
	"robin": {"length_mm": 140.0, "breadth_mm": 45.0, "depth_mm": 45.0},
	# Alcedo atthis: 16-17 cm, a stocky 5-5.5 cm body.
	"kingfisher": {"length_mm": 170.0, "breadth_mm": 50.0, "depth_mm": 55.0},
	# -- fish (FishRenderer.SPECIES_POOL) ---------------------------------------
	# A pond goldfish: ~15 cm, body depth about a third of its length.
	"goldfish": {"length_mm": 150.0, "breadth_mm": 30.0, "depth_mm": 50.0},
	# Lepomis macrochirus: ~19 cm, deep-bodied (depth ~0.4 of length).
	"bluegill": {"length_mm": 190.0, "breadth_mm": 35.0, "depth_mm": 75.0},
	# A river brown/rainbow trout: ~35 cm, depth ~0.23 of length.
	"trout": {"length_mm": 350.0, "breadth_mm": 45.0, "depth_mm": 80.0},
	# An adult koi: ~55 cm, depth ~0.3 of length.
	"koi": {"length_mm": 550.0, "breadth_mm": 90.0, "depth_mm": 160.0},
}

## Fixed order, kept explicitly.
const _IDS: Array[String] = [
	"monarch", "swallowtail", "blue_morpho", "bee", "fly",
	"sparrow", "robin", "kingfisher",
	"goldfish", "bluegill", "trout", "koi",
]


static func has(species: String) -> bool:
	return _EXTENTS_MM.has(species)


static func known_ids() -> Array:
	return _IDS.duplicate()


## Head-to-tail length, mm. 0.0 for an unmeasured species.
static func length_mm(species: String) -> float:
	return float(_EXTENTS_MM.get(species, {}).get("length_mm", 0.0))


## The three extents SORTED largest first, as a fresh Array -- [] for a
## species this table has not measured, so a caller can tell "unmeasured"
## from "tiny" rather than being handed a guess.
static func extents_mm(species: String) -> Array:
	if not _EXTENTS_MM.has(species):
		return []
	var row: Dictionary = _EXTENTS_MM[species]
	var extents: Array = [
		float(row["length_mm"]), float(row["breadth_mm"]), float(row["depth_mm"]),
	]
	extents.sort()
	extents.reverse()
	return extents


## The largest extent -- what has to go through a mouth. 0.0 if unmeasured.
static func largest_mm(species: String) -> float:
	var extents := extents_mm(species)
	return 0.0 if extents.is_empty() else float(extents[0])


## The middle extent -- what binds at a mesh (see capture_physics.gd). 0.0
## if unmeasured.
static func middle_mm(species: String) -> float:
	var extents := extents_mm(species)
	return 0.0 if extents.is_empty() else float(extents[1])
