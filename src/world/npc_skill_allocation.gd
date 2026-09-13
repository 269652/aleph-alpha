extends RefCounted

## Deterministic, seed-derived skill-web allocation for NPCs. Requested
## directly: "there should be NPCs specializing in Carpentry and the Skill
## Web should also be available for NPCs where preference is based on
## personality and class."
##
## NPCs use the SAME real SkillWeb graph and allocation primitives
## (start_node_for/is_reachable/point_cost/nodes_in_ring/total_bonus) the
## player already does -- never a parallel reimplementation or a separate,
## lower ceiling. This is what makes the outcome real rather than
## decorative: an NPC who specializes deeply enough reaches the EXACT same
## numbers a player would, including the Artisan wedge's own real
## `master_joiner` notable (see NpcIdentity.carpentry_level's own doc
## comment -- this is what finally lets a hired carpenter clear the Manor
## recipe's own `carpentry_level` 3.0 requirement, which no NpcIdentity
## seed could ever reach under the older, direct-formula version of this
## field).
##
## No RandomNumberGenerator anywhere (this project's own "no RNG"
## convention -- see crafting_recipe_book.gd's own file header): every
## choice below is a deterministic function of seed_value alone, the same
## "same seed, same villager, every reload" philosophy NpcIdentity itself
## already documents.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Which archetype an occupation's own skill investment walks -- CLASS, in
## the request's own words. Grounded directly in the wedges' own real node
## names, not an arbitrary assignment: blacksmith already sits beside
## carpentry/masonry/smith nodes, merchant beside trade_margin/hire_
## capacity/contract_throughput, guard beside attack_damage/max_health,
## herbalist beside wound_recovery/disease_resistance/venom_resistance.
## farmer/fisher/hunter have no dedicated craft wedge of their own --
## ranger's own outdoor stamina/attack_damage/scent_range (and, for hunter
## specifically, its own real butchering_1/butchering_2 nodes) is the
## closest real fit among the seven. nurse shares herbalist's own healer
## theme rather than inventing an eighth wedge no occupation table has.
##
## Carpentry specifically is real ONLY for blacksmith NPCs today -- the one
## occupation this maps to "artisan," the one wedge carpentry lives in.
## Widening which occupations can specialize in it (a dedicated "carpenter"
## occupation, say) is a real, separate follow-up, not attempted here.
const ARCHETYPE_BY_OCCUPATION := {
	"farmer": "ranger",
	"blacksmith": "artisan",
	"merchant": "overseer",
	"guard": "warrior",
	"fisher": "ranger",
	"herbalist": "herbalist",
	"hunter": "ranger",
	"nurse": "herbalist",
}

## How many points a maximally-dedicated NPC ever spends. Deliberately
## small and bounded: this is a passive, background trait real gameplay
## reads (a hired carpenter's own skill, docs/concept/workforce.md section
## 4), not a played character grinding a real web one node at a time.
## Reaching a real ring-3 notable (e.g. master_joiner) costs 1 + 2 + 3 = 6
## points at neutral resonance (see SkillWeb.point_cost) -- MAX_POINTS is
## pinned to exactly that, so only the MOST dedicated NPCs (dedication near
## 1.0) ever reach one, and none reach a ring-4 keystone at all. A real,
## explicit number a future pass could widen, not an accident of whatever
## was left over.
const MAX_POINTS := 6


## The real allocated_nodes Dictionary for an NPC of this archetype/seed --
## the start node always free (the same "your class's own start node comes
## free" rule Player._grant_class_start_node already applies), then as many
## further real nodes as `dedication` (a continuous genome trait, see
## NpcIdentity.SKILL_TRAITS) affords, walking outward one ring at a time
## and, at every ring offering more than one real choice, preferring
## whichever node's own stat matches this NPC's own deterministic
## specialty (see _specialty_stat_for) -- CLASS picks the wedge, the seed-
## derived specialty (this NPC's own "personality," in the sense of an
## innate leaning rather than the friendly/gruff/... trait list) picks
## WHICH node within it. `skill_web`: the shared instance
## (SkillWeb.shared()), injected rather than constructed here so the one
## real graph-building cost is paid once, not once per NPC.
static func allocate(skill_web, archetype: String, seed_value: int, dedication: float) -> Dictionary:
	var allocated := {}
	var start: String = skill_web.start_node_for(archetype)
	if start == "":
		return allocated
	allocated[start] = true

	var specialty := _specialty_stat_for(skill_web, archetype, seed_value)
	var points_left := int(round(dedication * MAX_POINTS))
	var ring := 1
	while points_left > 0 and ring <= int(skill_web.OUTER_RING):
		var candidates: Array = skill_web.nodes_in_ring(archetype, ring)
		var reachable: Array = []
		for node_id in candidates:
			if skill_web.is_reachable(node_id, allocated, archetype):
				reachable.append(node_id)
		if reachable.is_empty():
			break
		var pick := _pick_node(skill_web, reachable, specialty, seed_value, ring)
		var cost: int = skill_web.point_cost(pick, {})
		if cost > points_left:
			break
		allocated[pick] = true
		points_left -= cost
		ring += 1
	return allocated


## This NPC's own deterministic "favorite" stat within their class's own
## themed pool (SkillWeb.ARCHETYPE_STAT_POOL) -- e.g. an Artisan's specialty
## is one of mining_yield/smelting_yield/carpentry_level, rolled once per
## seed the same real way HouseBlueprint.choose_blueprint_id already rolls
## a house shape (a seeded index into a small real pool, no RNG).
static func _specialty_stat_for(skill_web, archetype: String, seed_value: int) -> String:
	var pool: Array = skill_web.ARCHETYPE_STAT_POOL.get(archetype, [])
	if pool.is_empty():
		return ""
	return String(pool[PixelNoise.range_index(seed_value, 101, 103, pool.size())])


## Whichever reachable candidate's own stat matches `specialty`, or -- when
## none of this ring's real choices happen to be it -- a deterministic,
## seeded pick among them, so an NPC without a matching option this ring
## still invests SOMEWHERE rather than stalling (the same "soft class, not
## a cage" shape docs/concept/classes.md already establishes for the
## player: a specialty is a strong lean, never a hard gate on the other
## real nodes in the same wedge).
static func _pick_node(skill_web, reachable: Array, specialty: String, seed_value: int, ring: int) -> String:
	for node_id in reachable:
		if String(skill_web.node_info(node_id).get("stat_name", "")) == specialty:
			return node_id
	return String(reachable[PixelNoise.range_index(seed_value, 107 + ring, 109, reachable.size())])
