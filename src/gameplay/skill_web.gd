extends RefCounted

## The Path-of-Exile-style passive WEB (docs/concept/skills.md).
##
## One connected graph, not seven trees: each of ClassArchetype's archetypes
## owns an angular WEDGE radiating from a shared centre, and the only edges
## crossing between wedges run through the GATEWAY ring that sits between
## adjacent wedge centres. Your class decides where you START; it never decides
## where you may go. Pathing -- "a node is allocable only when a neighbour is
## already allocated" -- is what makes another archetype's keystone expensive
## rather than forbidden, which is classes.md's "class is a lens, not a cage"
## expressed as a graph instead of a permission check.
##
## DNA resonance (dna.md) changes the EXCHANGE RATE and nothing else: a resonant
## wedge's nodes cost fewer points and grant bigger bonuses, a dissonant wedge's
## cost more and grant less. No edge is ever removed and no node is ever hidden,
## so a bad roll lengthens the road without closing it -- the arithmetic form of
## classes.md's soft/efficiency-only resolution. Both multipliers are anchored at
## NEUTRAL_RESONANCE so a neutral genome pays and receives EXACTLY the authored
## numbers, making DNA a visible deviation from the tables rather than a hidden
## scale factor on them.
##
## Node coordinates are DERIVED from (wedge index, ring, slot) by position_of --
## there is not one hand-placed pixel in the tables below, so the layout can't
## drift out of agreement with the graph it is drawing.
##
## Bonuses for the nodes that already existed as a flat list are NOT re-declared
## here: skill_tree.gd and keystone_passive.gd stay the single owner of those
## numbers and this file only says where in the web they sit (a String entry in
## _WEDGES means exactly that; the drift tests in test_skill_web.gd hold the two
## tables to it).

const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const KIND_START := "start"
const KIND_MINOR := "minor"
const KIND_NOTABLE := "notable"
const KIND_KEYSTONE := "keystone"
const KIND_GATEWAY := "gateway"
## A node from the character's own DNA-generated net (see genome_skill_net.gd),
## grafted in per character rather than declared in the tables below.
const KIND_SIGNATURE := "signature"

## How many wedges the circle is divided into. A const (rather than a call into
## ClassArchetype) because WEDGE_SPAN has to be one too; the two are pinned as
## agreeing by test_the_layout_declares_one_wedge_per_archetype_the_class_table_holds.
const WEDGE_COUNT := 7

## Fraction of its 1/WEDGE_COUNT slice a wedge actually fills. Below 1.0 so
## neighbouring wedges never touch -- the gutter is what makes seven
## neighbourhoods legible as seven, and it is where the gateway ring shows
## through.
const WEDGE_FILL := 0.8
const WEDGE_SPAN := TAU / float(WEDGE_COUNT) * WEDGE_FILL

## Radius of the start ring, and how much further out each subsequent ring sits.
## Pixel-ish units consumed only by the view; every relationship the rules care
## about (which ring is further out) is ordinal, not metric.
const START_RADIUS := 120.0
const RING_STEP := 110.0
const OUTER_RING := 4

## Where a wedge's ARCHETYPE NAME is drawn, in ring steps out from the centre --
## half a step past the keystone rim, so a name never lands on top of the nodes
## it is naming, and comfortably short of where a genome net grafts (a whole step
## further out). Reported live against the first web view: the map showed which
## nodes existed but not which direction was which archetype, so "it's pretty
## unclear what paths do what".
const WEDGE_LABEL_RING := OUTER_RING + 0.5

## Base point cost by ring -- index IS the ring. Deliberately equal to what the
## legacy flat table already charged for the same nodes (a `_1` node cost 1 and
## sits on ring 1, a `_2` node cost 2 and sits on ring 2), so folding the old
## list into the web changed no price.
const RING_POINT_COST := [1, 1, 2, 3, 4]

## How many nodes each ring holds per wedge -- index IS the ring.
const RING_SLOT_COUNT := [1, 3, 3, 2, 2]

## The travel tax. Charged at neutral for everyone (see point_cost): crossing
## into another archetype is a cost you can PLAN, not a second DNA lottery
## stacked on the first.
const GATEWAY_POINT_COST := 2

## The resonance at which DNA does nothing at all. Both multipliers below pass
## through 1.0 here, which is what lets the tables in this file mean literally
## what they say.
const NEUTRAL_RESONANCE := 0.5

## Total swing of the point-cost multiplier across the full 0..1 resonance
## range, centred on NEUTRAL_RESONANCE: cost x (1 + (NEUTRAL - resonance) *
## COST_SPREAD). 1.0 puts the worst case at 1.5x and the best at 0.5x -- small
## enough that dissonance is a longer road rather than a wall, which is the
## whole of classes.md's resolution.
const COST_SPREAD := 1.0

## The worst multiple of face value dissonance can ever charge. Derived from
## COST_SPREAD rather than written twice; tests assert against THIS, so the
## ceiling can never quietly grow.
const MAX_COST_MULTIPLIER := 1.0 + COST_SPREAD * 0.5

## Same shape for the bonus a node grants: gain x (1 + (resonance - NEUTRAL) *
## GAIN_SPREAD). Half the cost spread, deliberately -- DNA should mostly change
## how FAST you get there (classes.md's "faster leveling"), and only secondarily
## how much the destination is worth.
const GAIN_SPREAD := 0.5

## Every archetype's own themed stat pool, outermost-first. Read by
## genome_skill_net.gd so a generated signature node grants something its anchor
## wedge is actually ABOUT, and by nothing else -- the web's own nodes name their
## stats directly.
const ARCHETYPE_STAT_POOL := {
	"warrior": ["max_health", "attack_damage", "knockback_resist"],
	"mage": ["max_mana", "spell_efficiency", "spell_power"],
	"ranger": ["max_stamina", "attack_damage", "scent_range"],
	"beastmaster": ["pet_loyalty", "taming_affinity", "pet_health"],
	"artisan": ["mining_yield", "smelting_yield", "carpentry_level"],
	"herbalist": ["wound_recovery", "disease_resistance", "venom_resistance"],
	"overseer": ["hire_capacity", "trade_margin", "contract_throughput"],
}

## Wedge contents, ring by ring (index IS the ring, matching RING_SLOT_COUNT).
##
## An entry is either a String -- the id of a node skill_tree.gd or
## keystone_passive.gd already owns, whose stat/bonus/cost are read from THERE,
## never restated here -- or a Dictionary declaring a node this file owns:
##   {id, stat, bonus} and optionally {variants: [stat, stat]} for a
##   DNA-flavoured node (see flavored_variant) or {description} for a reveal.
##
## Every stat key names a system this project actually runs (butchering, mining,
## smelting, taming, spell cost, disease, trade), per skills.md's "webs connect
## outward into their domain's system" -- see that doc for which are read live
## today and which are summed but not yet consumed.
const _WEDGES := {
	"warrior": [
		[{"id": "warrior_start", "stat": "max_health", "bonus": 5.0}],
		["vitality_1", "strength_1", {"id": "bulwark_1", "stat": "knockback_resist", "bonus": 1.0}],
		["vitality_2", "strength_2",
			{"id": "bulwark_2", "stat": "knockback_resist", "bonus": 2.0,
				"variants": ["knockback_resist", "wound_recovery"]}],
		[{"id": "juggernaut", "stat": "max_health", "bonus": 35.0},
			{"id": "executioner", "stat": "attack_damage", "bonus": 7.0}],
		["iron_skin", "berserkers_fury"],
	],
	"mage": [
		[{"id": "mage_start", "stat": "max_mana", "bonus": 5.0}],
		[{"id": "attunement_1", "stat": "max_mana", "bonus": 10.0},
			{"id": "focus_1", "stat": "spell_efficiency", "bonus": 1.0},
			{"id": "evocation_1", "stat": "spell_power", "bonus": 2.0}],
		[{"id": "attunement_2", "stat": "max_mana", "bonus": 20.0},
			{"id": "focus_2", "stat": "spell_efficiency", "bonus": 2.0},
			{"id": "evocation_2", "stat": "spell_power", "bonus": 4.0,
				"variants": ["spell_power", "spell_efficiency"]}],
		[{"id": "arcane_reservoir", "stat": "max_mana", "bonus": 40.0},
			{"id": "spell_weaver", "stat": "spell_atom_tier", "bonus": 1.0}],
		[{"id": "archmage", "stat": "spell_efficiency", "bonus": 8.0},
			{"id": "deep_lore", "stat": "spell_atom_tier", "bonus": 1.0}],
	],
	"ranger": [
		[{"id": "ranger_start", "stat": "max_stamina", "bonus": 5.0}],
		["endurance_1", {"id": "marksman_1", "stat": "attack_damage", "bonus": 2.0}, "butchering_1"],
		["endurance_2",
			{"id": "marksman_2", "stat": "attack_damage", "bonus": 4.0,
				"variants": ["attack_damage", "throw_force"]},
			"butchering_2"],
		[{"id": "tracker", "stat": "scent_range", "bonus": 12.0},
			{"id": "windrunner", "stat": "max_stamina", "bonus": 25.0}],
		["swift_current", {"id": "apex_predator", "stat": "attack_damage", "bonus": 12.0}],
	],
	"beastmaster": [
		[{"id": "beastmaster_start", "stat": "pet_loyalty", "bonus": 1.0}],
		[{"id": "bonding_1", "stat": "pet_loyalty", "bonus": 2.0},
			{"id": "handler_1", "stat": "taming_affinity", "bonus": 2.0},
			{"id": "kennel_1", "stat": "pet_health", "bonus": 8.0}],
		[{"id": "bonding_2", "stat": "pet_loyalty", "bonus": 4.0},
			{"id": "handler_2", "stat": "taming_affinity", "bonus": 4.0},
			{"id": "kennel_2", "stat": "pet_health", "bonus": 16.0,
				"variants": ["pet_health", "pet_loyalty"]}],
		[{"id": "pack_leader", "stat": "pet_health", "bonus": 30.0},
			{"id": "beast_whisperer", "stat": "taming_affinity", "bonus": 9.0}],
		[{"id": "alpha_bond", "stat": "pet_loyalty", "bonus": 15.0},
			{"id": "menagerie", "stat": "taming_affinity", "bonus": 15.0}],
	],
	"artisan": [
		[{"id": "artisan_start", "stat": "max_stamina", "bonus": 5.0}],
		["carpentry_1", {"id": "masonry_1", "stat": "mining_yield", "bonus": 1.0},
			{"id": "smith_1", "stat": "smelting_yield", "bonus": 1.0}],
		["carpentry_2", {"id": "masonry_2", "stat": "mining_yield", "bonus": 2.0},
			{"id": "smith_2", "stat": "smelting_yield", "bonus": 2.0,
				"variants": ["smelting_yield", "ore_yield"]}],
		[{"id": "master_joiner", "stat": "carpentry_level", "bonus": 1.0},
			{"id": "forgewright", "stat": "smelting_yield", "bonus": 4.0}],
		[{"id": "grand_workshop", "stat": "craft_quality", "bonus": 10.0},
			{"id": "deep_delver", "stat": "mining_yield", "bonus": 8.0}],
	],
	"herbalist": [
		[{"id": "herbalist_start", "stat": "max_mana", "bonus": 5.0}],
		["naturalist_1", {"id": "remedy_1", "stat": "wound_recovery", "bonus": 1.0},
			{"id": "soothe_1", "stat": "disease_resistance", "bonus": 1.0}],
		["naturalist_2", {"id": "remedy_2", "stat": "wound_recovery", "bonus": 2.0},
			{"id": "soothe_2", "stat": "disease_resistance", "bonus": 2.0,
				"variants": ["disease_resistance", "venom_resistance"]}],
		[{"id": "field_surgeon", "stat": "wound_recovery", "bonus": 5.0},
			{"id": "antivenin", "stat": "venom_resistance", "bonus": 6.0}],
		["land_sense", {"id": "lifebloom", "stat": "max_health", "bonus": 40.0}],
	],
	"overseer": [
		[{"id": "overseer_start", "stat": "max_mana", "bonus": 5.0}],
		[{"id": "logistics_1", "stat": "hire_capacity", "bonus": 1.0},
			{"id": "command_1", "stat": "contract_throughput", "bonus": 1.0},
			{"id": "ledger_1", "stat": "trade_margin", "bonus": 1.0}],
		[{"id": "logistics_2", "stat": "hire_capacity", "bonus": 2.0},
			{"id": "command_2", "stat": "contract_throughput", "bonus": 2.0},
			{"id": "ledger_2", "stat": "trade_margin", "bonus": 2.0,
				"variants": ["trade_margin", "hire_capacity"]}],
		[{"id": "quartermaster", "stat": "hire_capacity", "bonus": 4.0},
			{"id": "magistrate", "stat": "contract_throughput", "bonus": 4.0}],
		[{"id": "guildmaster", "stat": "hire_capacity", "bonus": 10.0},
			{"id": "grand_charter", "stat": "trade_margin", "bonus": 10.0}],
	],
}

## node_id -> full spec. Built once in _init from _WEDGES + the legacy tables.
var _nodes: Dictionary = {}
## node_id -> Array[String] of neighbour ids. Symmetric by construction.
var _edges: Dictionary = {}
## archetype -> start node id.
var _starts: Dictionary = {}
## archetype -> ring -> Array[String] of node ids in slot order.
var _rings: Dictionary = {}
## Nodes carrying a `variants` list, in table order.
var _flavored: Array = []


func _init() -> void:
	var archetypes := ClassArchetype.new().archetype_names()
	var legacy_tree := SkillTree.new()
	var legacy_keystones := KeystonePassive.new()
	for wedge_index in archetypes.size():
		var archetype: String = archetypes[wedge_index]
		_build_wedge(archetype, wedge_index, legacy_tree, legacy_keystones)
	_build_gateways(archetypes)


func _build_wedge(archetype: String, wedge_index: int, legacy_tree: SkillTree,
		legacy_keystones: KeystonePassive) -> void:
	var rings: Array = _WEDGES.get(archetype, [])
	_rings[archetype] = {}
	for ring in rings.size():
		var slots: Array = rings[ring]
		var ids := []
		for slot in slots.size():
			var node_id := _register(slots[slot], archetype, wedge_index, ring, slot,
				legacy_tree, legacy_keystones)
			ids.append(node_id)
		_rings[archetype][ring] = ids
		if ring == 0:
			_starts[archetype] = ids[0]
	_link_wedge(archetype, rings.size())


## Adds one node from a wedge table entry. A String entry defers its
## stat/bonus/cost entirely to whichever legacy table owns it, so those numbers
## exist in exactly one place; a Dictionary entry owns its own.
func _register(entry: Variant, archetype: String, wedge_index: int, ring: int, slot: int,
		legacy_tree: SkillTree, legacy_keystones: KeystonePassive) -> String:
	var node_id := ""
	var stat_name := ""
	var bonus_amount := 0.0
	var point_cost := int(RING_POINT_COST[ring])
	var description := ""
	var variants := []

	if entry is String:
		node_id = entry
		var legacy: Dictionary = legacy_tree.node_info(node_id)
		if legacy.is_empty():
			legacy = legacy_keystones.keystone_info(node_id)
		stat_name = String(legacy.get("stat_name", ""))
		bonus_amount = float(legacy.get("bonus_amount", 0.0))
		point_cost = int(legacy.get("point_cost", point_cost))
		description = String(legacy.get("description", ""))
	else:
		var spec: Dictionary = entry
		node_id = String(spec["id"])
		stat_name = String(spec["stat"])
		bonus_amount = float(spec["bonus"])
		description = String(spec.get("description", ""))
		for variant_stat in spec.get("variants", []):
			variants.append({"stat_name": String(variant_stat), "bonus_amount": bonus_amount})

	var kind := KIND_MINOR
	if ring == 0:
		kind = KIND_START
	elif ring == OUTER_RING:
		kind = KIND_KEYSTONE
	elif ring == OUTER_RING - 1:
		kind = KIND_NOTABLE

	_nodes[node_id] = {
		"archetype": archetype,
		"wedge_index": wedge_index,
		"ring": ring,
		"slot": slot,
		"kind": kind,
		"stat_name": stat_name,
		"bonus_amount": bonus_amount,
		"point_cost": point_cost,
		"description": description,
		"variants": variants,
	}
	_edges[node_id] = []
	if not variants.is_empty():
		_flavored.append(node_id)
	return node_id


## Intra-wedge lattice. The start fans out to the WHOLE of ring 1 (it is the one
## node the wedge hangs off, so a single edge would make two thirds of ring 1
## unreachable without a detour); from there ring r slot i reaches ring r+1 slots
## i and i-1, clamped. That double edge -- rather than a strict tree -- is what
## gives most notables more than one approach route, which is what makes "where
## does the next point go" a decision instead of a queue.
func _link_wedge(archetype: String, ring_count: int) -> void:
	for ring in range(0, ring_count - 1):
		var here: Array = _rings[archetype][ring]
		var out: Array = _rings[archetype][ring + 1]
		if ring == 0:
			for target in out:
				_connect(here[0], target)
			continue
		for slot in here.size():
			_connect(here[slot], out[clampi(slot, 0, out.size() - 1)])
			_connect(here[slot], out[clampi(slot - 1, 0, out.size() - 1)])


## One gateway per adjacent wedge pair, sitting in the gutter between their
## centres at start radius, joined to both start nodes -- the only cross-wedge
## edges in the graph.
func _build_gateways(archetypes: Array) -> void:
	for wedge_index in archetypes.size():
		var next_index := (wedge_index + 1) % archetypes.size()
		var gateway_id := "gateway_%s_%s" % [archetypes[wedge_index], archetypes[next_index]]
		_nodes[gateway_id] = {
			"archetype": "",
			"wedge_index": wedge_index,
			"ring": 0,
			"slot": 0,
			"kind": KIND_GATEWAY,
			"stat_name": "",
			"bonus_amount": 0.0,
			"point_cost": GATEWAY_POINT_COST,
			"description": "Passage between the %s and %s wedges" % [
				archetypes[wedge_index], archetypes[next_index]],
			"variants": [],
		}
		_edges[gateway_id] = []
		_connect(gateway_id, _starts[archetypes[wedge_index]])
		_connect(gateway_id, _starts[archetypes[next_index]])


func _connect(a: String, b: String) -> void:
	if a == b:
		return
	if not _edges[a].has(b):
		_edges[a].append(b)
	if not _edges[b].has(a):
		_edges[b].append(a)


# --- structure ------------------------------------------------------------

func has(node_id: String) -> bool:
	return _nodes.has(node_id)


func node_ids() -> Array:
	return _nodes.keys()


## A node's full spec for the view and the rules. Empty Dictionary for an
## unknown node, matching skill_tree.gd's own convention.
func node_info(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	return _nodes[node_id].duplicate(true)


func neighbors(node_id: String) -> Array:
	return _edges.get(node_id, []).duplicate()


func start_node_for(archetype: String) -> String:
	return String(_starts.get(archetype, ""))


func nodes_in_ring(archetype: String, ring: int) -> Array:
	var wedge: Dictionary = _rings.get(archetype, {})
	return (wedge.get(ring, []) as Array).duplicate()


## Centre angle of wedge `wedge_index`, evenly dividing the circle.
func wedge_angle(wedge_index: int) -> float:
	return float(wedge_index) * TAU / float(WEDGE_COUNT)


## A node's position, DERIVED from (wedge, ring, slot) -- never stored. Ring
## fixes the radius; the slot spreads evenly across the wedge's angular span, so
## a wedge widens as it goes outward. Gateways sit at start radius, half a wedge
## step around, which is exactly the gutter WEDGE_FILL leaves open.
func position_of(node_id: String) -> Vector2:
	if not _nodes.has(node_id):
		return Vector2.ZERO
	var info: Dictionary = _nodes[node_id]
	# Grafted genome-net nodes are the one exception to "position is derived":
	# they exist per character, so no shared layout function can place them and
	# they carry the position their generator computed (see graft).
	if info.has("position"):
		return info["position"]
	var centre := wedge_angle(int(info["wedge_index"]))
	if info["kind"] == KIND_GATEWAY:
		return Vector2(START_RADIUS, 0.0).rotated(centre + TAU / float(WEDGE_COUNT) * 0.5)
	var ring := int(info["ring"])
	var slot_count := int(RING_SLOT_COUNT[ring])
	var offset := 0.0
	if slot_count > 1:
		offset = WEDGE_SPAN * (float(info["slot"]) / float(slot_count - 1) - 0.5)
	return Vector2(START_RADIUS + RING_STEP * float(ring), 0.0).rotated(centre + offset)


# --- route finding --------------------------------------------------------

## The cheapest sequence of nodes to buy, in order, to end up owning
## `target` -- the answer to "what would it take to get THERE from here", which
## is what a web of 84 circles otherwise refuses to tell you. Already-owned
## nodes are free and never appear in the result; everything else costs
## point_cost at this genome's rate. Empty for an unknown node, one you already
## own, or one nothing connects to.
##
## Dijkstra with the weight on the NODE rather than the edge (you pay to own a
## node, not to traverse an edge), seeded from the whole owned frontier at once
## -- or, for a character who owns nothing yet, from their own class start,
## which is the one node they may always take first.
func cheapest_path(target: String, allocated: Dictionary, archetype: String,
		resonance: Dictionary) -> Array:
	if not _nodes.has(target) or allocated.get(target, false):
		return []
	var distance := {}
	var came_from := {}
	var frontier := []
	for node_id in allocated:
		if allocated[node_id] and _nodes.has(node_id):
			distance[node_id] = 0
			frontier.append(node_id)
	var start := start_node_for(archetype)
	if frontier.is_empty() and start != "":
		distance[start] = point_cost(start, resonance)
		frontier.append(start)
	if frontier.is_empty():
		return []

	# Small graph (under a hundred nodes), so a linear scan for the nearest
	# unvisited node is cheaper than maintaining a heap and much easier to read.
	var visited := {}
	while true:
		var current := ""
		var best := INF
		for node_id in distance:
			if visited.has(node_id):
				continue
			if float(distance[node_id]) < best:
				best = float(distance[node_id])
				current = node_id
		if current == "":
			break
		if current == target:
			break
		visited[current] = true
		for neighbour in _edges[current]:
			var step := 0 if allocated.get(neighbour, false) else point_cost(neighbour, resonance)
			var through := int(distance[current]) + step
			if not distance.has(neighbour) or through < int(distance[neighbour]):
				distance[neighbour] = through
				came_from[neighbour] = current
	if not distance.has(target):
		return []

	var route := []
	var walk := target
	while walk != "":
		if not allocated.get(walk, false):
			route.push_front(walk)
		walk = String(came_from.get(walk, ""))
	return route


## What `route` (from cheapest_path) costs this genome, all steps together.
func route_cost(route: Array, resonance: Dictionary) -> int:
	var total := 0
	for node_id in route:
		total += point_cost(node_id, resonance)
	return total


## Where wedge `wedge_index`'s archetype name is drawn -- on its own centre
## line, out past its keystones (see WEDGE_LABEL_RING).
func wedge_label_position(wedge_index: int) -> Vector2:
	return Vector2(START_RADIUS + RING_STEP * WEDGE_LABEL_RING, 0.0).rotated(
		wedge_angle(wedge_index))


## The rectangle one archetype's nodes occupy, in web space.
##
## Exists so a view can show the web FOR A CLASS rather than the whole wheel.
## At the size of a dialog tab the full seven-wedge circle is a smudge, and six
## sevenths of it belongs to somebody else's class -- see the character
## creator's Skills tab, which frames the wedge of whichever class is being
## picked.
##
## Derived from position_of() rather than stored, exactly like the positions
## themselves, so a layout change (RING_STEP, WEDGE_COUNT, a grafted genome
## node) moves the frame with it and cannot go stale.
##
## `archetype` empty means every node -- the whole wheel -- which is both what a
## caller wanting the full view asks for and the baseline
## test_one_wedge_is_smaller_than_the_whole_web measures a single wedge against.
## An unknown archetype has no nodes and therefore no area.
func archetype_bounds(archetype: String = "") -> Rect2:
	var bounds := Rect2()
	var found := false
	for node_id in _nodes:
		if archetype != "" and String(_nodes[node_id].get("archetype", "")) != archetype:
			continue
		var point := position_of(node_id)
		if not found:
			bounds = Rect2(point, Vector2.ZERO)
			found = true
		else:
			bounds = bounds.expand(point)
	return bounds


# --- genome net -----------------------------------------------------------

## Grafts one character's generated net (see genome_skill_net.gd) into THIS web
## instance -- every Player owns its own SkillWeb, so a graft is per character
## and never leaks between them. Net nodes join their anchor's archetype rather
## than standing outside the wedges, which is what makes the character's own
## resonance apply to them: the unique cluster sits at the end of the pathway
## DNA was already making cheap, so it reads as "my genome boosted this route"
## and not as a bolted-on bonus.
##
## Idempotent: re-grafting the same net (a reload, a respec rebuild) adds
## nothing, so a web can be rebuilt without accumulating copies.
func graft(net: Dictionary) -> void:
	var archetype := String(net.get("anchor_archetype", ""))
	var wedge_index := ClassArchetype.new().archetype_names().find(archetype)
	var nodes: Dictionary = net.get("nodes", {})
	for node_id in net.get("node_ids", []):
		if _nodes.has(node_id):
			continue
		var spec: Dictionary = nodes[node_id]
		_nodes[node_id] = {
			"archetype": archetype,
			"wedge_index": maxi(0, wedge_index),
			"ring": OUTER_RING + 1,
			"slot": 0,
			"kind": KIND_SIGNATURE,
			"stat_name": String(spec["stat_name"]),
			"bonus_amount": float(spec["bonus_amount"]),
			"point_cost": int(spec["point_cost"]),
			"description": String(spec.get("title", "")),
			"variants": [],
			"position": spec["position"],
		}
		_edges[node_id] = []
	for node_id in net.get("edges", {}):
		if not _edges.has(node_id):
			continue
		for neighbour in net["edges"][node_id]:
			if _edges.has(neighbour):
				_connect(node_id, neighbour)


# --- resonance ------------------------------------------------------------

## `resonance` is HeroDna.roll()'s per-archetype 0..1 map. A missing entry means
## neutral, so an un-rolled character (tests, dedicated-server spawns) simply
## pays face value rather than being penalised for having no genome.
func resonance_for(archetype: String, resonance: Dictionary) -> float:
	if archetype == "":
		return NEUTRAL_RESONANCE
	return clampf(float(resonance.get(archetype, NEUTRAL_RESONANCE)), 0.0, 1.0)


## Points this genome pays for `node_id`. Rounded UP and floored at 1 -- a node
## can get cheaper but never free, and the ceiling (MAX_COST_MULTIPLIER) is
## small and finite so dissonance never becomes a gate.
func point_cost(node_id: String, resonance: Dictionary) -> int:
	if not _nodes.has(node_id):
		return 0
	var info: Dictionary = _nodes[node_id]
	var base := int(info["point_cost"])
	var affinity := resonance_for(String(info["archetype"]), resonance)
	var multiplier := 1.0 + (NEUTRAL_RESONANCE - affinity) * COST_SPREAD
	return maxi(1, int(ceil(float(base) * multiplier)))


## What `node_id` is actually worth to this genome. Scaling a reveal node's zero
## bonus is still zero, so land_sense-style nodes need no special case.
func effective_bonus(node_id: String, resonance: Dictionary) -> float:
	if not _nodes.has(node_id):
		return 0.0
	var info: Dictionary = _nodes[node_id]
	var affinity := resonance_for(String(info["archetype"]), resonance)
	return float(info["bonus_amount"]) * (1.0 + (affinity - NEUTRAL_RESONANCE) * GAIN_SPREAD)


# --- DNA-flavoured nodes --------------------------------------------------

func flavored_node_ids() -> Array:
	return _flavored.duplicate()


## Which of a flavoured node's themed variants this DNA seed grants. Same place
## on the map, same cost, same worth (every variant carries the node's own bonus
## amount, so the flavour roll is never a second power lottery) -- only the stat
## differs. An unflavoured node resolves to its own plain stat, so callers never
## need to ask whether a node is flavoured first.
func flavored_variant(node_id: String, dna_seed: int) -> Dictionary:
	if not _nodes.has(node_id):
		return {"stat_name": "", "bonus_amount": 0.0}
	var info: Dictionary = _nodes[node_id]
	var variants: Array = info["variants"]
	if variants.is_empty():
		return {"stat_name": info["stat_name"], "bonus_amount": float(info["bonus_amount"])}
	# Salted per node so two flavoured nodes don't flip together for one genome.
	var pick := int(PixelNoise.unit(dna_seed, node_id.hash(), 0) * variants.size())
	return (variants[clampi(pick, 0, variants.size() - 1)] as Dictionary).duplicate()


# --- allocation -----------------------------------------------------------

## True when `node_id` is your own start node, or a neighbour of it is already
## allocated -- the pathing rule the whole design hangs off.
func is_reachable(node_id: String, allocated: Dictionary, archetype: String) -> bool:
	if not _nodes.has(node_id):
		return false
	if node_id == start_node_for(archetype):
		return true
	for neighbour in _edges[node_id]:
		if allocated.get(neighbour, false):
			return true
	return false


func can_allocate(node_id: String, allocated: Dictionary, available_points: int,
		archetype: String, resonance: Dictionary) -> bool:
	if not _nodes.has(node_id):
		return false
	if allocated.get(node_id, false):
		return false
	if not is_reachable(node_id, allocated, archetype):
		return false
	return point_cost(node_id, resonance) <= available_points


func allocate(node_id: String, allocated: Dictionary) -> Dictionary:
	var result: Dictionary = allocated.duplicate()
	if not _nodes.has(node_id):
		return result
	result[node_id] = true
	return result


# --- refund / respec ------------------------------------------------------

## Refunding may not ORPHAN the build: everything still allocated afterwards has
## to remain connected to your start node through allocated nodes only. Without
## this, free respec (classes.md) would let a player keep a keystone while
## refunding the road they walked to reach it.
func can_refund(node_id: String, allocated: Dictionary, archetype: String) -> bool:
	if not allocated.get(node_id, false):
		return false
	var remaining := refund(node_id, allocated)
	var live := []
	for id in remaining:
		if remaining[id]:
			live.append(id)
	if live.is_empty():
		return true
	var start := start_node_for(archetype)
	if not remaining.get(start, false):
		return false
	var reached := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for neighbour in _edges[current]:
			if reached.has(neighbour) or not remaining.get(neighbour, false):
				continue
			reached[neighbour] = true
			frontier.append(neighbour)
	return reached.size() == live.size()


func refund(node_id: String, allocated: Dictionary) -> Dictionary:
	var result: Dictionary = allocated.duplicate()
	result.erase(node_id)
	return result


# --- totals ---------------------------------------------------------------

## Sum of `stat_name` across everything allocated, at this genome's exchange
## rate. `dna_seed` resolves DNA-flavoured nodes (see flavored_variant); every
## real character has one, and any value is a valid seed.
func total_bonus(stat_name: String, allocated: Dictionary, resonance: Dictionary,
		dna_seed: int = 0) -> float:
	var total := 0.0
	for node_id in allocated:
		if not allocated[node_id]:
			continue
		if not _nodes.has(node_id):
			continue
		if flavored_variant(node_id, dna_seed)["stat_name"] != stat_name:
			continue
		total += effective_bonus(node_id, resonance)
	return total
