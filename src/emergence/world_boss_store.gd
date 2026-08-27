extends RefCounted

## Promotes, finds, and defeats world bosses (see docs/concept/
## worldbosses.md "World bosses: emergent apex predators").
##
## Same shape as ContractStore/InstitutionStore: a plain RefCounted
## collection, no engine dependency, own to_dicts/from_dicts for
## WorldBossStorePersistence to wrap. Deliberately does not decide WHETHER
## a promotion is warranted -- that is WorldBossFitness's job (see
## EarthChunkManager.attempt_world_boss_promotion, the same coordinator
## split ContractStore/InstitutionFormation already establishes) -- this
## store only manages boss state once that decision is made.

const WorldBoss = preload("res://src/emergence/world_boss.gd")

var _bosses: Dictionary = {}         # id -> WorldBoss
var _order: Array[String] = []       # insertion order
var _by_individual: Dictionary = {}  # individual_id -> Array[String] (boss ids)
var _next_ordinal := 0


func promote(
	individual_id: String, species: String, score: float, threshold: float, phases: Array, tick: float
) -> WorldBoss:
	var boss := WorldBoss.new(individual_id, species, score, threshold, phases, tick)
	var id := "boss_%d_%s" % [_next_ordinal, species]
	_next_ordinal += 1
	boss.id = id
	_bosses[id] = boss
	_order.append(id)
	if not _by_individual.has(individual_id):
		_by_individual[individual_id] = []
	_by_individual[individual_id].append(id)
	return boss


func get_boss(boss_id: String) -> WorldBoss:
	return _bosses.get(boss_id)


## Every promotion this individual has ever had, active or defeated -- the
## same "history is kept" shape InstitutionStore.institutions_for already
## uses, so a defeated boss stays queryable rather than disappearing.
func bosses_for(individual_id: String) -> Array[WorldBoss]:
	var out: Array[WorldBoss] = []
	for id in _by_individual.get(individual_id, []):
		out.append(_bosses[id])
	return out


## An ACTIVE promotion for this individual, or null -- the dedup guard
## attempt_world_boss_promotion needs so re-checking an already-promoted
## individual does not silently duplicate it. A DEFEATED promotion does not
## count as "already promoted" -- the same "dissolved does not block
## re-forming" reasoning InstitutionStore.active_institution_for already
## establishes (a defeated boss's line could, in principle, produce another
## exceptional individual later).
func active_boss_for(individual_id: String) -> WorldBoss:
	for id in _by_individual.get(individual_id, []):
		var boss: WorldBoss = _bosses[id]
		if boss.status == WorldBoss.ACTIVE:
			return boss
	return null


func defeat(boss_id: String, _tick: float) -> bool:
	var boss: WorldBoss = _bosses.get(boss_id)
	if boss == null or boss.status != WorldBoss.ACTIVE:
		return false
	boss.status = WorldBoss.DEFEATED
	return true


## For WorldBossStorePersistence -- pure serialization, no FileAccess (same
## split EventStore/EventStorePersistence already use).
func to_dicts() -> Array:
	var out: Array = []
	for id in _order:
		var boss: WorldBoss = _bosses[id]
		out.append({
			"id": boss.id,
			"individual_id": boss.individual_id,
			"species": boss.species,
			"score": boss.score,
			"threshold": boss.threshold,
			"phases": boss.phases,
			"status": boss.status,
			"created_at": boss.created_at,
		})
	return out


static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	var highest_ordinal := -1
	for d in dicts:
		var boss := WorldBoss.new(
			d.get("individual_id", ""), d.get("species", ""), d.get("score", 0.0),
			d.get("threshold", 0.0), d.get("phases", []), d.get("created_at", 0.0)
		)
		boss.id = d.get("id", "")
		boss.status = d.get("status", WorldBoss.ACTIVE)

		store._bosses[boss.id] = boss
		store._order.append(boss.id)
		if not store._by_individual.has(boss.individual_id):
			store._by_individual[boss.individual_id] = []
		store._by_individual[boss.individual_id].append(boss.id)

		var ordinal := _ordinal_of(boss.id)
		if ordinal > highest_ordinal:
			highest_ordinal = ordinal
	store._next_ordinal = highest_ordinal + 1
	return store


## "boss_<ordinal>_<species>" -> ordinal, same convention EventStore/
## ContractStore/InstitutionStore's own _ordinal_of already establish.
static func _ordinal_of(boss_id: String) -> int:
	var parts := boss_id.split("_", true, 2)
	if parts.size() < 2:
		return -1
	return int(parts[1])
