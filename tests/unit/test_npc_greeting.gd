extends GutTest

## NpcGreeting: the minimal talk-interaction stand-in (see
## docs/concept/npc.md's "Minimal talk interaction" section) -- turns an
## NpcIdentity into one deterministic, personality/need-flavored line. Not
## the real Live Dialogue System (no branching, no memory, no quest hooks);
## just enough that pressing "talk" near a villager produces something that
## reads like that individual, not a generic string.

const NpcGreeting = preload("res://src/world/npc_greeting.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

var greeting: NpcGreeting


func before_each():
	greeting = NpcGreeting.new()


func test_includes_the_npcs_own_name():
	var identity := NpcIdentity.new(1)
	assert_string_contains(greeting.greeting_for(identity), identity.npc_name)


func test_is_deterministic_for_the_same_identity():
	var identity := NpcIdentity.new(42)
	var first := greeting.greeting_for(identity)
	var second := greeting.greeting_for(NpcIdentity.new(42))
	assert_eq(first, second)


func test_never_returns_an_empty_line():
	for seed_value in range(30):
		var identity := NpcIdentity.new(seed_value)
		assert_ne(greeting.greeting_for(identity), "", "empty greeting for seed %d" % seed_value)


## Not every villager should say the literal same sentence -- personality/
## need should actually flavor the line, not just the name prefix.
func test_produces_more_than_one_distinct_line_across_many_villagers():
	var lines := {}
	for seed_value in range(30):
		lines[greeting.greeting_for(NpcIdentity.new(seed_value))] = true
	assert_gt(lines.size(), 1, "every villager produced the exact same line")
