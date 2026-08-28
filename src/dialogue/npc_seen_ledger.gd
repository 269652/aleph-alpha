extends RefCounted

## What this villager has already told the player, and when (see
## docs/concept/dialogue.md's pipeline, fourth stage, and its "the ledger
## burns topics" mechanism). DialogueMove multiplies every topic's salience
## by this module's decay, so talking to the same villager twice gives you
## the SECOND most salient thing rather than the same line again.
##
## Keyed by the villager's entity id -- "npc:<seed>", the same string
## EntityRef.for_npc already builds and every other emergence store already
## indexes a villager by. That is the whole reason this is a store and not a
## field on the NpcMarker: a marker is freed with its chunk, so a ledger held
## there forgets everything the moment you walk far enough for the chunk to
## unload, which is precisely the walk that would otherwise reset a
## conversation. A seed survives that; a node does not.
##
## The state is a plain nested Dictionary of String -> String -> float and
## nothing else, so the store_var/get_var convention PlayerSave,
## EventStorePersistence and WorldClockPersistence already share can take it
## whole (see to_dict/from_dict). Writing that file is someone else's module,
## the same way MemoryStore owns to_dicts and MemoryStorePersistence owns
## FileAccess.
##
## Pure: no Node, no scene, no clock of its own -- every tick is handed in by
## the caller, and it is the world clock (EarthChunkManager.
## world_age_seconds), the same one DialogueContext puts in the frame.

const EntityRef = preload("res://src/emergence/entity_ref.gd")

## What last_told answers for a topic this villager has never raised. A
## sentinel rather than 0.0 because 0.0 is a real tick -- the first moments of
## a fresh world -- and "never told" must not read as "told at world age
## zero", which decays to fully recovered and would be right by accident.
const NEVER_TOLD := -1.0

## Real seconds in one simulated in-game day -- EarthChunkManager.
## SECONDS_PER_SIMULATED_DAY and NpcMarker.SECONDS_PER_SIMULATED_DAY, which
## already agree on this number and are both pinned against it by
## test_npc_seen_ledger.gd. It is restated rather than preloaded because both
## declarations sit on Node scripts (a Node2D world manager and a Sprite2D
## marker) and a module that takes Dictionaries in and returns Dictionaries
## out must not drag the scene tree in behind a constant; the test is what
## keeps the restatement honest, and it fails if either declaration is
## retuned or if the two ever drift apart.
##
## Deliberately NOT SeasonCycle.SECONDS_PER_DAY. There are two days in this
## codebase and they mean different things: SeasonCycle's is four real hours,
## the calendar the slow biology is measured against (when a tree fruits
## again, how often a kingfisher eats), while this one is the day a VILLAGER
## lives -- what NpcSchedule's morning/midday/evening/night blocks advance
## on, and what DialogueContext divides the world clock by to get its
## hour_of_day. A burn measured on the calendar day would outlast most play
## sessions, so the ledger would be a "said it, never again" set in practice.
const SECONDS_PER_SIMULATED_DAY := 60.0

## How long a told topic takes to become worth saying again: one villager's
## day. The anchor is the claim, not the number -- "he told me that
## yesterday" is the point at which a fact is news again, and the day is the
## only unit in this simulation that means that. Anything shorter and the
## same line comes back inside one conversation; anything longer and a
## villager runs out of things to say while the facts underneath them have
## already moved (dialogue.md's "the facts move" mechanism turns over on this
## same clock -- hunger, wallet, stock, status).
const REPEAT_DECAY_SECONDS := SECONDS_PER_SIMULATED_DAY

## npc_id -> {topic_id: last_told_tick}. Plain values only.
var _seen: Dictionary = {}


## The ledger key for a villager, from the seed_value NpcIdentity already
## derives their whole identity from -- so a caller holding an identity, a
## frame or a memory's actor id all name the same row.
static func key_for_seed(seed_value: int) -> String:
	return EntityRef.for_npc(seed_value)


## Records that `topic_id` was said to the player at `tick` (world clock).
## The latest telling replaces any earlier one, the same "a later telling
## REPLACES the holder's existing record" rule MemoryStore._store follows:
## this row answers "how long since", and that question has one answer.
func mark_told(npc_id: String, topic_id: String, tick: float) -> void:
	if not _seen.has(npc_id):
		_seen[npc_id] = {}
	_seen[npc_id][topic_id] = tick


func has_told(npc_id: String, topic_id: String) -> bool:
	return _seen.get(npc_id, {}).has(topic_id)


## The world tick this villager last raised this topic, or NEVER_TOLD.
func last_told(npc_id: String, topic_id: String) -> float:
	return float(_seen.get(npc_id, {}).get(topic_id, NEVER_TOLD))


## How much of a topic's salience survives the fact that this villager
## already said it, in [0,1] -- DialogueMove multiplies by this, so 1.0 is
## "as if never said" and 0.0 removes the topic from consideration entirely.
##
## Linear in elapsed world age, reaching 1.0 exactly one villager-day after
## the telling. Linear because the ledger has nothing to say about the SHAPE
## of forgetting -- that curve would be an invented number with no measurement
## behind it, and dialogue.md's fourth pillar is that salience is measured,
## never authored. What the ledger really knows is one honest fact, "how far
## through a day are we since he last said this", and that fraction is
## exactly what it returns.
##
## Clamped at both ends. The floor matters: the world clock genuinely can run
## backwards under a restored ledger (New Game rolls a fresh world age), and
## an unclamped negative multiplier would not merely mis-rank topics, it
## would invert the ranking and lead with the least salient thing in the
## village.
func decay(npc_id: String, topic_id: String, now: float) -> float:
	var told_at := last_told(npc_id, topic_id)
	if told_at == NEVER_TOLD:
		return 1.0
	return clampf((now - told_at) / REPEAT_DECAY_SECONDS, 0.0, 1.0)


## Sorted, not insertion-ordered: a Dictionary's iteration order is an
## implementation detail, and anything downstream of this module has to be
## reproducible from the state alone rather than from the order a session
## happened to write it in.
func topics_told(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for topic_id in _seen.get(npc_id, {}):
		out.append(topic_id)
	out.sort()
	return out


func npc_ids() -> Array[String]:
	var out: Array[String] = []
	for npc_id in _seen:
		out.append(npc_id)
	out.sort()
	return out


## A deep copy, so a caller holding the snapshot (a save file, a test) can
## neither mutate the live ledger through it nor watch it change underneath
## them mid-write.
func to_dict() -> Dictionary:
	return _seen.duplicate(true)


## Rebuilds a ledger from to_dict()'s output, mirroring MemoryStore.
## from_dicts/EventStore.from_dicts. Fail-open on shape: a row that is not a
## topic map is skipped and a tick that is not a number reads as 0.0 rather
## than aborting the load, because a ledger is a convenience over the real
## simulation -- losing one row costs the player a repeated sentence, and
## refusing to load costs them the whole save.
static func from_dict(data: Dictionary) -> RefCounted:
	var ledger = new()
	for npc_id in data:
		var topics = data[npc_id]
		if typeof(topics) != TYPE_DICTIONARY:
			continue
		for topic_id in topics:
			ledger.mark_told(str(npc_id), str(topic_id), float(topics[topic_id]))
	return ledger
