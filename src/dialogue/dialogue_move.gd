extends RefCounted

## What the villager actually says next (see docs/concept/dialogue.md's
## pipeline, fifth stage): the scored topics come in, one -- or the top k --
## come out, ranked by `salience x NpcSeenLedger.decay`.
##
## The multiply is the whole design. Salience is measured by DialogueTopic
## from facts the simulation already computed (dialogue.md's fourth pillar:
## hunger, `1.0 - yield_signal`, `confidence x (1 - distortion)`), and decay
## is measured by the ledger from how long ago this villager last raised the
## topic. Neither factor is authored here, and this module adds no weight of
## its own to either -- it multiplies two real numbers and sorts. That is
## what makes "talk twice and you get the second most salient thing" a
## consequence rather than a special case: nothing about the world has to
## change between two conversations for the answer to change, because the
## first conversation wrote the ledger row that re-sorted the stack.
##
## -- Determinism, and why it is a hard requirement here --
##
## The same frame, ledger and clock must always produce the same move. This
## is not tidiness: the beat this feeds is cached under
## `(voice_key, topic_id, kind, fact_band)` (dialogue.md's AI seam), a save
## restores a ledger that has to keep meaning what it meant, and a villager
## whose opening line shuffled between two runs of the same world would make
## every one of this system's observable mechanisms unverifiable. So:
##
##   * The sort is TOTAL -- score descending, then topic_id ascending -- and
##     never falls through to input order. Array.sort_custom makes no
##     stability promise, and the topics arrive from an upstream that may
##     have iterated a Dictionary to build them, so input order is an
##     implementation detail that must not reach the player.
##   * The tie-break is the topic id itself, compared as a String. NOT
##     hash(topic_id): Godot's hash is an engine implementation detail with
##     no cross-version contract, and this decision is visible in a save.
##   * The villager's seed does NOT touch the ordering. It produces
##     `variant_seed` instead (see variant_seed_for), which is the seed's
##     entire job here -- a stable per-(villager, topic) index the renderer
##     can pick a phrasing with, so two villagers saying the same true thing
##     do not say it in the same words, without a hash deciding anything.
##
## Pure static module: Dictionaries and numbers in, Dictionaries out, no
## Node, no store of its own, and no writes -- selecting is a READ. Burning a
## topic is a separate, explicit NpcSeenLedger.mark_told by whoever actually
## said it, because a select() that burned would consume every topic it
## merely considered.

const NpcSeenLedger = preload("res://src/dialogue/npc_seen_ledger.gd")

## The two keys a scored topic must carry. DialogueTopic owns everything
## else on it, and everything else rides through to the beat untouched (see
## the `topic` field below) -- this module deliberately knows nothing about
## what a topic is ABOUT.
const TOPIC_ID_KEY := "topic_id"
const SALIENCE_KEY := "salience"

## How many moves a caller gets when they do not ask for a number. One,
## because a Beat carries exactly one `topic_id` (dialogue.md's beat
## contract) -- so this is the shape of the thing downstream, not a tuned
## quantity. A caller building choice labels out of the runners-up asks for
## the k it needs.
const DEFAULT_K := 1

## A move is dropped below this. Zero is the honest floor rather than a
## chosen threshold: `salience x decay` reaches 0 exactly when the facts are
## empty (dialogue.md's second pillar -- an empty topic is OMITTED, never
## filled with a fallback line) or when the villager has just said this and
## the ledger has not recovered yet. Silence is the correct output in both
## cases; a floor above zero would start discarding true things nobody
## measured as unsayable.
const MIN_SCORE := 0.0

## Every key on a move, so the beat builder can be written against a list
## rather than against whatever this module happened to emit.
const MOVE_FIELDS: Array[String] = [
	"topic_id",
	"salience",
	"decay",
	"score",
	"rank",
	"repeat",
	"last_told",
	"variant_seed",
	"topic",
]

## FNV-1a, 64-bit: offset basis 14695981039346656037 written as its int64
## two's complement (GDScript ints are signed) and the standard prime. An
## explicit, fully specified mixer rather than Godot's hash() precisely
## because its output is a promise -- see variant_seed_for.
const _MIX_OFFSET_BASIS := -3750763034362895579
const _MIX_PRIME := 1099511628211
const _SIGN_MASK := 0x7FFFFFFFFFFFFFFF


## The ranked moves, best first, at most `k` of them. `ledger` may be null --
## a villager with no history and a missing ledger are the same state, the
## same fail-open shape DialogueContext uses for every absent source.
static func select(
	topics: Array,
	ledger: NpcSeenLedger,
	npc_id: String,
	now: float,
	seed_value: int,
	k: int = DEFAULT_K
) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	if k <= 0:
		return chosen

	var scored := _scored_moves(topics, ledger, npc_id, now, seed_value)
	scored.sort_custom(_ranks_before)
	for move in scored:
		if chosen.size() >= k:
			break
		move["rank"] = chosen.size()
		chosen.append(move)
	return chosen


## The single move a Beat is built from, or an empty Dictionary when this
## villager has nothing to say -- which is a real answer, not an error.
static func select_one(
	topics: Array, ledger: NpcSeenLedger, npc_id: String, now: float, seed_value: int
) -> Dictionary:
	var moves := select(topics, ledger, npc_id, now, seed_value, 1)
	return moves[0] if not moves.is_empty() else {}


## What one topic is worth to this villager right now: the measured salience,
## discounted by how recently they said it. Exposed on its own so a caller
## can explain a ranking (and so a test can pin the multiply) without
## re-implementing it.
static func score_of(topic: Dictionary, ledger: NpcSeenLedger, npc_id: String, now: float) -> float:
	var salience := float(topic.get(SALIENCE_KEY, 0.0))
	return salience * _decay_of(ledger, npc_id, str(topic.get(TOPIC_ID_KEY, "")), now)


## A stable non-negative integer for this villager saying this topic --
## the renderer's index into a phrasing pool.
##
## FNV-1a over the seed's bytes and the topic id's, not hash(): a phrasing
## index that changed when the engine changed its hash would silently
## re-word every villager in the world on an engine upgrade, and the
## alternative that avoids that -- ordering by hash -- is exactly what this
## module must not do anywhere. Pinned by test_dialogue_move.gd, which is
## the point of writing the arithmetic out rather than borrowing it.
static func variant_seed_for(seed_value: int, topic_id: String) -> int:
	var mixed := _MIX_OFFSET_BASIS
	for byte_index in range(8):
		mixed = (mixed ^ ((seed_value >> (byte_index * 8)) & 0xFF)) * _MIX_PRIME
	for byte in topic_id.to_utf8_buffer():
		mixed = (mixed ^ byte) * _MIX_PRIME
	return mixed & _SIGN_MASK


## variant_seed_for folded into a pool of `pool_size` phrasings. An empty
## pool has no index to give and answers 0, the same fail-open contract the
## rest of the pipeline uses for an absent source.
static func variant_for(seed_value: int, topic_id: String, pool_size: int) -> int:
	if pool_size <= 0:
		return 0
	return variant_seed_for(seed_value, topic_id) % pool_size


static func _decay_of(ledger: NpcSeenLedger, npc_id: String, topic_id: String, now: float) -> float:
	if ledger == null:
		return 1.0
	return ledger.decay(npc_id, topic_id, now)


## Builds one move per distinct, sayable topic. Anything malformed is
## skipped rather than raised: the topics come from a module that reads a
## frame assembled out of half-loaded chunks, and one unreadable row must
## cost a sentence, never the conversation.
static func _scored_moves(
	topics: Array, ledger: NpcSeenLedger, npc_id: String, now: float, seed_value: int
) -> Array[Dictionary]:
	var by_topic_id := {}
	for topic in topics:
		if typeof(topic) != TYPE_DICTIONARY:
			continue
		var topic_id := str(topic.get(TOPIC_ID_KEY, ""))
		if topic_id == "":
			continue
		var move := _move_for(topic, topic_id, ledger, npc_id, now, seed_value)
		if move["score"] <= MIN_SCORE:
			continue
		# The same topic scored twice can only be one thing said once, and
		# it is said at the better of the two scores.
		if by_topic_id.has(topic_id) and by_topic_id[topic_id]["score"] >= move["score"]:
			continue
		by_topic_id[topic_id] = move

	var out: Array[Dictionary] = []
	for topic_id in by_topic_id:
		out.append(by_topic_id[topic_id])
	return out


static func _move_for(
	topic: Dictionary,
	topic_id: String,
	ledger: NpcSeenLedger,
	npc_id: String,
	now: float,
	seed_value: int
) -> Dictionary:
	var salience := float(topic.get(SALIENCE_KEY, 0.0))
	var decay := _decay_of(ledger, npc_id, topic_id, now)
	var told_at := NpcSeenLedger.NEVER_TOLD if ledger == null else ledger.last_told(npc_id, topic_id)
	return {
		"topic_id": topic_id,
		"salience": salience,
		"decay": decay,
		"score": salience * decay,
		"rank": -1,
		# Not `decay < 1.0`: a topic told a full day ago has recovered its
		# whole salience but is still something this villager has said to
		# this player before, which is what the renderer's opener needs to
		# know ("Like I said --").
		"repeat": told_at != NpcSeenLedger.NEVER_TOLD,
		"last_told": told_at,
		"variant_seed": variant_seed_for(seed_value, topic_id),
		"topic": topic,
	}


## Total by construction: two distinct moves always have distinct topic ids
## (see _scored_moves' dedupe), so this never falls through to input order.
static func _ranks_before(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	return a["topic_id"] < b["topic_id"]
