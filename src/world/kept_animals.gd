extends RefCounted

## Animals the player has a stake in, persisted as INDIVIDUALS (see
## docs/concept/taming.md).
##
## ## Why these are not part of the aggregate
##
## A region's population is a number (see EcosystemSimulation): away from the
## player it grows, migrates and is capped by what the land supports, and the
## specific animals it stands for are interchangeable. That is the right model
## for a herd of deer, and it is why `record_birth` can add "one animal" to a
## region without caring which one.
##
## A horse the player spent an evening winning over is not interchangeable.
## It is a particular animal, in a particular place, carrying the trust it
## earned and whatever it was last told to do. Rolling it into a population
## count would lose all of that -- and the count is capped at carrying
## capacity, so a tamed animal could even be quietly culled to make room.
##
## So kept animals are stored individually and RE-SPAWNED on chunk load, on
## top of whatever the aggregate says the region holds. They are extra: the
## land's carrying capacity governs wild animals, not the ones the player is
## looking after.
##
## Deliberately bounded by how many animals a player can actually tame and
## tie up, which is a handful -- not by anything that scales with world size.

const Taming = preload("res://src/gameplay/taming.gd")

## Bumped if the record layout changes, so an old save is ignored rather than
## read as garbage.
##
## Bumped to 2 to add `wander_seed`: a tamed horse's individuality
## (AnimalFitness's strength/agility/coat_vibrancy phenotype, all
## deterministic from this one seed) used to be discarded on every reload --
## `_restore_kept_animals` respawned it via `spawn_single`, which always
## rolled a fresh `randi()` seed, silently re-rolling the exact animal this
## file's own doc comment says is "not interchangeable" the moment anything
## (taming, rendering) ever reads that phenotype. A save from before this
## field existed is simply dropped, matching this file's own convention for a
## small, bounded set of animals -- unlike chunk_serializer.gd's
## append-and-read-to-end-of-file approach, which exists because losing a
## whole region's ecology continuity is a much bigger loss than a player's
## handful of kept animals needing to be re-tamed once after an update.
const FORMAT_VERSION := 2


## Whether this animal is one the player would expect to still be there.
##
## Tamed, part-way tamed, or tied up. Trust above zero counts because the
## carrots already spent on a half-tamed horse are real effort; a tied animal
## counts at any trust because the player put it there on purpose. An
## ordinary wild animal does not -- it belongs to the aggregate, and keeping
## every deer individually would be a save file that grows without bound.
static func is_worth_keeping(trust: float, is_tied: bool) -> bool:
	return is_tied or trust > 0.0


static func save_all(animals: Array, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_32(FORMAT_VERSION)
	file.store_32(animals.size())
	for animal in animals:
		file.store_pascal_string(String(animal.get("species", "")))
		var position: Vector2 = animal.get("position", Vector2.ZERO)
		file.store_float(position.x)
		file.store_float(position.y)
		file.store_float(float(animal.get("trust", 0.0)))
		file.store_32(int(animal.get("order", Taming.ORDER_STAY)))
		file.store_8(1 if bool(animal.get("is_tied", false)) else 0)
		var tied_to: Vector2 = animal.get("tied_to", Vector2.ZERO)
		file.store_float(tied_to.x)
		file.store_float(tied_to.y)
		file.store_32(int(animal.get("wander_seed", 0)))
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
		var trust := file.get_float()
		var order := file.get_32()
		var is_tied := file.get_8() != 0
		var tied_x := file.get_float()
		var tied_y := file.get_float()
		var wander_seed := file.get_32()
		out.append({
			"species": species,
			"position": Vector2(x, y),
			"trust": trust,
			"order": order,
			"is_tied": is_tied,
			"tied_to": Vector2(tied_x, tied_y),
			"wander_seed": wander_seed,
		})
	file.close()
	return out
