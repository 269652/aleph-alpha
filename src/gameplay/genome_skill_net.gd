extends RefCounted

## The per-character UNIQUE skill net (docs/concept/skills.md "The genome net").
##
## skills.md asks for "exactly one procedurally-generated skill/spell, seeded
## from their DNA, that no other player has -- a genuine 'this is MY character'
## hook, not just a reskin". This generates that, plus (for a rarer roll) a small
## cluster of satellites around it, and grafts the whole thing onto the deepest
## notable of the character's MOST-RESONANT wedge -- so the unique part of your
## web sits at the end of the path your DNA was already pushing you down.
##
## Balance is a BUDGET, not a roll. A net divides exactly NET_BUDGET_UNITS[rarity]
## between its nodes; there is no number to roll high on. The unit is deliberately
## not a raw stat amount -- it is "one of the biggest single node the shared web
## already grants for that same stat", so 40 max health and 4 taming affinity
## come out as the same investment without this file holding a per-stat table
## that could drift from skill_web.gd's. This is the same discipline hero_dna.gd
## already applies to its own stat modifiers, and skills.md's "constrained ... so
## a signature skill can be flavourful without being able to roll overpowered".

const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## The one node every character has, whatever they rolled.
const CORE_NODE_ID := "signature_core"
const SATELLITE_ID_PREFIX := "signature_"

## How many nodes the net holds, by dna.md rarity tier. Common is the core alone
## -- the hook is universal; only its SIZE is the rare-roll payoff.
const NET_NODE_COUNT := {
	HeroDna.RARITY_COMMON: 1,
	HeroDna.RARITY_RARE: 3,
	HeroDna.RARITY_LEGENDARY: 5,
}

## Total worth of a net, in reference units (see the class doc comment: 1.0 unit
## is the strongest node the shared web has for that stat). Common is calibrated
## against the web's own notable tier -- pinned from both sides by
## test_a_common_net_is_worth_about_one_of_the_webs_own_notables, so it cannot
## drift into a trinket or a trap. Rare and legendary buy BREADTH: more total
## worth spread over more nodes, never a single node that eclipses a keystone
## (see the per-node cap test).
const NET_BUDGET_UNITS := {
	HeroDna.RARITY_COMMON: 0.6,
	HeroDna.RARITY_RARE: 1.2,
	HeroDna.RARITY_LEGENDARY: 2.0,
}

## Floor on a node's share weight, as a fraction of an even split. Without it a
## five-node legendary net can hand a node a share so small the node reads as
## broken; same reasoning (and same 0.4) as hero_dna.gd's legendary weighting.
const MIN_SHARE_WEIGHT := 0.4

## How far beyond the shared web's outermost ring the net sits, in ring steps.
## The net is the last thing in its wedge, so it never lands on top of the
## keystones it hangs past.
const CORE_RING_OFFSET := 1
const SATELLITE_RING_OFFSET := 2

## How wide the satellite fan opens around the anchor's own angle. A fraction of
## a wedge, so a net stays visibly part of the wedge it grew out of.
const SATELLITE_FAN := SkillWeb.WEDGE_SPAN * 0.6

## Name parts. Purely presentational -- the mechanics are entirely in the budget
## split above -- but this is the half the player actually remembers, so it gets
## a real vocabulary rather than "Signature Node #3".
const _NAME_PREFIXES := [
	"Ember", "Frost", "Thorn", "Tide", "Ash", "Gale", "Loam", "Star",
	"Iron", "Hollow", "Kiln", "Moss", "Rime", "Sable", "Vellum", "Wyrm",
]
const _CORE_NOUNS := [
	"weave", "blood", "sigil", "heart", "mark", "crown", "wake", "vow",
]
const _SATELLITE_NOUNS := ["Echo", "Thread", "Shard", "Vein"]

var _web := SkillWeb.new()


## The whole net for one HeroDna.roll() genome. Reads only `seed_value`,
## `rarity` and `resonance`, so a caller can hand it a genome from anywhere.
func generate(genome: Dictionary) -> Dictionary:
	var seed_value := int(genome.get("seed_value", 0))
	var rarity := String(genome.get("rarity", HeroDna.RARITY_COMMON))
	var resonance: Dictionary = genome.get("resonance", {})

	var anchor_archetype := _anchor_archetype_for(resonance, seed_value)
	var anchor_node_id := _anchor_node_for(anchor_archetype, seed_value)
	var node_count := int(NET_NODE_COUNT.get(rarity, NET_NODE_COUNT[HeroDna.RARITY_COMMON]))
	var budget := float(NET_BUDGET_UNITS.get(rarity, NET_BUDGET_UNITS[HeroDna.RARITY_COMMON]))
	var shares := _budget_shares(seed_value, node_count, budget)

	var anchor_position := _web.position_of(anchor_node_id)
	var anchor_angle := anchor_position.angle()
	var prefix: String = _NAME_PREFIXES[int(PixelNoise.unit(seed_value, 7701, 0) * _NAME_PREFIXES.size()) % _NAME_PREFIXES.size()]
	var core_noun: String = _CORE_NOUNS[int(PixelNoise.unit(seed_value, 7702, 0) * _CORE_NOUNS.size()) % _CORE_NOUNS.size()]
	var net_name := "%s%s" % [prefix, core_noun]

	var node_ids := []
	var nodes := {}
	var edges := {}
	for index in node_count:
		var node_id := CORE_NODE_ID if index == 0 else "%s%d" % [SATELLITE_ID_PREFIX, index]
		var stat := _stat_for(anchor_archetype, seed_value, index)
		var units: float = shares[index]
		node_ids.append(node_id)
		nodes[node_id] = {
			"stat_name": stat,
			"budget_units": units,
			"bonus_amount": units * reference_bonus_for(stat),
			"point_cost": _point_cost_for(index),
			"title": net_name if index == 0 else "%s %s" % [
				prefix, _SATELLITE_NOUNS[(index - 1) % _SATELLITE_NOUNS.size()]],
			"position": _position_for(index, node_count, anchor_angle),
		}
		_connect(edges, node_id, _parent_of(index, anchor_node_id))

	return {
		"name": net_name,
		"rarity": rarity,
		"seed_value": seed_value,
		"anchor_archetype": anchor_archetype,
		"anchor_node_id": anchor_node_id,
		"node_ids": node_ids,
		"nodes": nodes,
		"edges": edges,
	}


## One budget unit for `stat_name`: the biggest single bonus the shared web
## already grants for it. Zero for a stat the web never grants, which is a real
## answer rather than a guess -- a net node can then never be sized against a
## scale nothing else in the game uses.
func reference_bonus_for(stat_name: String) -> float:
	var best := 0.0
	for node_id in _web.node_ids():
		var info := _web.node_info(node_id)
		if info["stat_name"] != stat_name:
			continue
		best = maxf(best, float(info["bonus_amount"]))
	return best


## The wedge the genome resonates with most. Ties (and a genome with no
## resonance at all, e.g. a dedicated-server spawn) fall back to a deterministic
## pick from the seed rather than to whichever key the Dictionary happened to
## iterate first.
func _anchor_archetype_for(resonance: Dictionary, seed_value: int) -> String:
	var archetypes: Array = SkillWeb.ARCHETYPE_STAT_POOL.keys()
	var best := ""
	var best_score := -INF
	for archetype in archetypes:
		var score := float(resonance.get(archetype, -INF))
		if score > best_score:
			best_score = score
			best = archetype
	if best == "":
		best = archetypes[int(PixelNoise.unit(seed_value, 7801, 0) * archetypes.size()) % archetypes.size()]
	return best


## Which of the wedge's notables the net grows out of -- the deepest tier that is
## not itself a keystone, so reaching your unique node means having walked your
## own wedge nearly to its end.
func _anchor_node_for(archetype: String, seed_value: int) -> String:
	var notables := _web.nodes_in_ring(archetype, SkillWeb.OUTER_RING - 1)
	if notables.is_empty():
		return _web.start_node_for(archetype)
	return String(notables[int(PixelNoise.unit(seed_value, 7802, 0) * notables.size()) % notables.size()])


func _stat_for(archetype: String, seed_value: int, index: int) -> String:
	var pool: Array = SkillWeb.ARCHETYPE_STAT_POOL.get(archetype, [])
	if pool.is_empty():
		return ""
	return String(pool[int(PixelNoise.unit(seed_value, 7803, index) * pool.size()) % pool.size()])


## Divides `budget` between `count` nodes with deterministic uneven weights, so a
## net reads as a shaped cluster rather than a flat split -- but sums to exactly
## `budget`, which is the invariant the whole balance argument rests on.
func _budget_shares(seed_value: int, count: int, budget: float) -> Array:
	var weights := []
	var total := 0.0
	for index in count:
		var weight := MIN_SHARE_WEIGHT + PixelNoise.unit(seed_value, 7804, index)
		weights.append(weight)
		total += weight
	var shares := []
	var assigned := 0.0
	for index in count:
		if index == count - 1:
			# The last share takes the remainder rather than its own rounded
			# quotient, so float error can never leak past the budget.
			shares.append(budget - assigned)
			continue
		var share: float = budget * float(weights[index]) / total
		shares.append(share)
		assigned += share
	return shares


## Core sits at notable cost, satellites one tier below -- read off the web's own
## ring costs rather than restated, so a repricing of the web reprices nets too.
func _point_cost_for(index: int) -> int:
	var ring := SkillWeb.OUTER_RING - (1 if index == 0 else 2)
	return int(SkillWeb.RING_POINT_COST[clampi(ring, 0, SkillWeb.RING_POINT_COST.size() - 1)])


## The core chains to the anchor; the first two satellites chain to the core, and
## any beyond that chain to the satellite two before them -- a small branching
## cluster, always one connected piece.
func _parent_of(index: int, anchor_node_id: String) -> String:
	if index == 0:
		return anchor_node_id
	if index <= 2:
		return CORE_NODE_ID
	return "%s%d" % [SATELLITE_ID_PREFIX, index - 2]


func _position_for(index: int, count: int, anchor_angle: float) -> Vector2:
	var rim := SkillWeb.START_RADIUS + SkillWeb.RING_STEP * float(SkillWeb.OUTER_RING)
	if index == 0:
		return Vector2(rim + SkillWeb.RING_STEP * CORE_RING_OFFSET, 0.0).rotated(anchor_angle)
	var satellite_count := count - 1
	var offset := 0.0
	if satellite_count > 1:
		offset = SATELLITE_FAN * (float(index - 1) / float(satellite_count - 1) - 0.5)
	return Vector2(rim + SkillWeb.RING_STEP * SATELLITE_RING_OFFSET, 0.0).rotated(anchor_angle + offset)


func _connect(edges: Dictionary, a: String, b: String) -> void:
	if not edges.has(a):
		edges[a] = []
	if not edges.has(b):
		edges[b] = []
	if not edges[a].has(b):
		edges[a].append(b)
	if not edges[b].has(a):
		edges[b].append(a)
