extends GutTest

## EntityRef (see docs/emergence/00-emergence-architecture.md "Entity model",
## docs/roadmap.md's "Emergence substrate" section).
##
## A canonical entity-reference ID: "<kind>:<key>". Built from whatever
## deterministic key an entity already has -- an NPC's seed_value, a
## settlement's chunk_coord -- rather than a newly-allocated counter, the same
## "deterministic key, not an allocated ID" idiom TreeGenome/CreatureInfo/
## NpcIdentity already use everywhere else in this codebase. That choice means
## no new counter has to be persisted or protected from collision just to hand
## out entity IDs.

const EntityRef = preload("res://src/emergence/entity_ref.gd")


func test_builds_a_colon_separated_reference():
	assert_eq(EntityRef.for_kind("npc", 483920), "npc:483920")


func test_the_same_kind_and_key_always_build_the_same_reference():
	assert_eq(EntityRef.for_kind("npc", 483920), EntityRef.for_kind("npc", 483920))


func test_different_kinds_never_collide_even_with_the_same_key():
	assert_ne(EntityRef.for_kind("npc", 1), EntityRef.for_kind("settlement", 1))


func test_settlement_keys_are_built_from_a_chunk_coordinate():
	assert_eq(
		EntityRef.for_settlement(Vector2i(3, -7)), "settlement:3_-7",
		"a settlement's key is its chunk coordinate, the same key settlement_generator already uses"
	)


func test_kind_of_reads_back_the_kind():
	assert_eq(EntityRef.kind_of("npc:483920"), "npc")
	assert_eq(EntityRef.kind_of("settlement:3_-7"), "settlement")


func test_key_of_reads_back_the_key():
	assert_eq(EntityRef.key_of("npc:483920"), "483920")
	assert_eq(EntityRef.key_of("settlement:3_-7"), "3_-7")


## A key can itself legitimately contain a colon-adjacent-looking value (a
## coordinate pair), so splitting only on the FIRST colon is what keeps
## kind_of/key_of correct rather than accidentally truncating the key.
func test_key_of_keeps_the_whole_remainder_past_the_first_colon():
	assert_eq(EntityRef.key_of("settlement:3_-7"), "3_-7")


func test_a_reference_with_no_colon_has_no_recoverable_kind_or_key():
	assert_eq(EntityRef.kind_of("garbage"), "")
	assert_eq(EntityRef.key_of("garbage"), "")


func test_is_valid_distinguishes_a_real_reference_from_garbage():
	assert_true(EntityRef.is_valid("npc:483920"))
	assert_false(EntityRef.is_valid("garbage"))
	assert_false(EntityRef.is_valid(""))
