extends RefCounted

## A WILD mammal juvenile's own growth-in-progress, persisted as an
## INDIVIDUAL so its age survives a chunk unload (see docs/concept/
## ecosystem_dynamics.md's "Land-mammal courtship" subsection and
## src/gameplay/mammal_growth.gd for the 30/90/180-real-day maturity window
## this exists to make actually observable).
##
## ## Why this does NOT reopen KeptAnimals' "no unbounded per-animal saves" rule
##
## src/world/kept_animals.gd's own doc comment explains why ORDINARY wild
## animals are never individually persisted: away from the player a region's
## population is a number that grows/migrates/is capped by carrying
## capacity, and the specific animals behind that number are interchangeable
## -- individually saving a whole region's worth of wild deer "would be a
## save file that grows without bound". This module does not do that. It
## only ever covers markers that are ALREADY individually rendered at the
## moment of unload -- the same tier CreatureRenderer promotes a region's
## aggregate population INTO, which is already bounded globally (see
## World.MAX_LIVE_CREATURES) and per-chunk-per-species (see
## CreatureRenderer.MAX_MARKERS_PER_SPECIES). This module narrows that
## already-bounded set further still, to whichever of those markers are not
## yet fully grown (`is_worth_persisting` below, keyed off MammalGrowth.
## is_mature). That is a strict SUBSET of an existing bounded population, not
## a new unbounded cost: the moment a saved juvenile matures, the very next
## save simply omits it (its record does not linger the way KeptAnimals'
## clear-on-empty-list convention already establishes for its own file), and
## it goes right back to being exactly as interchangeable as any other wild
## adult.
##
## ## Why this is its own module, not folded into KeptAnimals
##
## KeptAnimals is "animals the player has a stake in" -- tamed or tied, a
## relationship the player created on purpose. A growing wild juvenile is
## neither of those: nobody tamed it, nobody tied it, it simply is not
## finished growing yet. That is a different REASON to persist an
## individual, the same distinction src/gameplay/mammal_growth.gd's own doc
## comment already draws for not reusing LifeCycle wholesale just because
## the shape looks adjacent. In `EarthChunkManager`, a creature already
## worth keeping by KeptAnimals (`KeptAnimals.is_worth_keeping`) is
## deliberately EXCLUDED from this module's own save pass, so a tamed
## juvenile is never written to (and so never re-spawned from) both files at
## once -- see `_save_growing_juveniles`. That does mean a TAMED juvenile's
## age is not yet separately preserved (it reloads at KeptAnimals' existing
## default adult age, unchanged by this module) -- named explicitly as a
## known remaining gap, not silently dropped; see docs/progress.md.
##
## ## Courtship pairing is explicitly NOT covered here
##
## A courting pair references its partner by live node instance id
## (`CreatureMarker._courting_partner_id`, via `instance_from_id`), which
## cannot itself be persisted, and reconstructing a cross-referenced pairing
## after both individuals independently respawn would need a new stable
## cross-reload identity nothing in this codebase has yet. This module only
## restores each juvenile's own age/growth; an in-progress courtship simply
## ends on unload as it already did before this module existed, and once
## reloaded (now at its real preserved age) that individual is free to pair
## again once mature and eligible.

const MammalGrowth = preload("res://src/gameplay/mammal_growth.gd")

## Bumped (not appended -- see KeptAnimals' own doc comment on why that
## trade is acceptable for a small, bounded set) if the record layout
## changes, so an old-format save is ignored rather than read as garbage.
const FORMAT_VERSION := 1


## Whether this individual is worth persisting on its own axis: still
## growing. A fully mature individual is exactly as interchangeable as any
## other wild adult and belongs back in the aggregate, not this file --
## mirrors KeptAnimals.is_worth_keeping's shape, gated on a different
## question ("still immature" instead of "the player's").
static func is_worth_persisting(age_seconds: float, species: String) -> bool:
	return not MammalGrowth.is_mature(age_seconds, species)


static func save_all(juveniles: Array, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_32(FORMAT_VERSION)
	file.store_32(juveniles.size())
	for juvenile in juveniles:
		file.store_pascal_string(String(juvenile.get("species", "")))
		var position: Vector2 = juvenile.get("position", Vector2.ZERO)
		file.store_float(position.x)
		file.store_float(position.y)
		file.store_float(float(juvenile.get("age_seconds", 0.0)))
		file.store_32(int(juvenile.get("wander_seed", 0)))
	file.close()


static func load_all(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var version := file.get_32()
	if version != FORMAT_VERSION:
		file.close()
		return out  # written by a different build; better nothing than nonsense
	var count := file.get_32()
	for _i in count:
		var species := file.get_pascal_string()
		var x := file.get_float()
		var y := file.get_float()
		var age_seconds := file.get_float()
		var wander_seed := file.get_32()
		out.append({
			"species": species,
			"position": Vector2(x, y),
			"age_seconds": age_seconds,
			"wander_seed": wander_seed,
		})
	file.close()
	return out
