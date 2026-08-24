extends GutTest

## Institution (see docs/emergence/01-society-and-institutions.md
## "Institutions": "a persistent organization with membership, shared
## purpose, leadership, resources, assets, rules, reputation, obligations,
## external relationships, territory/influence, and historical memory").
##
## Deliberately does NOT duplicate factions.md's aggregate-reputation model
## (see docs/roadmap.md's Emergence Phase 6 note) -- an institution is a new
## organizational ENTITY with its own membership, existing alongside
## factions.md's reputation, which stays a PROJECTION over individual
## relationships, not something an institution overrides or replaces.

const Institution = preload("res://src/emergence/institution.gd")


func test_carries_its_type_and_members():
	var institution := Institution.new("guild", ["household:1", "household:2"], 10.0)
	assert_eq(institution.type, "guild")
	assert_eq(institution.members, ["household:1", "household:2"])
	assert_eq(institution.created_at, 10.0)


func test_starts_active():
	var institution := Institution.new("guild", ["household:1"], 10.0)
	assert_eq(institution.status, Institution.ACTIVE)


## No leader by default -- "Informal leaders can precede formal leadership"
## (docs/emergence/01), and there is no trust/reputation/social-centrality
## data yet to pick one from, so assigning one automatically would be an
## invented choice with nothing grounding it.
func test_starts_with_no_leader():
	var institution := Institution.new("guild", ["household:1"], 10.0)
	assert_eq(institution.leader, "")


func test_starts_with_no_goals():
	var institution := Institution.new("guild", ["household:1"], 10.0)
	assert_eq(institution.goals, [])


## The documented "start with" roster (docs/emergence/07-implementation-
## roadmap.md Phase 6: "Start with guilds, cooperatives, militias, merchant
## companies, and criminal groups").
func test_every_documented_starting_type_exists():
	var expected := ["guild", "cooperative", "militia", "merchant_company", "criminal_group"]
	for type in expected:
		assert_true(Institution.TYPES.has(type), "missing documented starting type: %s" % type)
