extends GutTest

## FieldJournal (see src/emergence/field_journal.gd, docs/concept/
## player_citizenship.md's "Field Journal" item) -- a real-time reader over
## Why's existing explain_* functions, dispatched by EntityRef.kind_of(entity_id).
##
## The dispatch below is NOT the naive "kind X -> explain_X" guess: it is
## grounded in how real callers in this codebase actually key these stores
## (see src/world/earth_chunk_manager.gd/household.gd and test_why.gd's own
## examples). Concretely:
##   - HouseholdStore.household_for is keyed by a household's MEMBER, which
##     in every real call site is an "npc:" id (household.gd's
##     Household.for_founder, test_why.gd's own form_household("npc:1")).
##   - InstitutionStore.institutions_for is keyed by an institution's
##     MEMBER, which in every real call site (earth_chunk_manager.gd's
##     attempt_institution_formation, test_earth_chunk_manager.gd) is a
##     "household:" id, not an "npc:" id.
##   - WorldBossStore.bosses_for is keyed by individual_id, "the real
##     creature entity this boss IS" (world_boss.gd's own doc comment) --
##     test_why.gd's own convention for this is a "creature:" id, distinct
##     from "npc:". No real src/ call site produces "creature:" ids yet
##     (attempt_world_boss_promotion has no caller yet, a pre-existing,
##     documented gap) -- wiring it now costs nothing and matches this
##     project's own "ready the moment real data exists" precedent.
## A literal "household" kind therefore routes to explain_institutions, NOT
## explain_household -- routing it to explain_household would always print
## "no household" since no household is ever indexed by its own id.

const EntityRef = preload("res://src/emergence/entity_ref.gd")
const FieldJournal = preload("res://src/emergence/field_journal.gd")
const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")


# -- entry_for: "npc" kind routes through explain_household -------------------

func test_npc_kind_id_routes_through_explain_household_with_real_content():
	var household_store := HouseholdStore.new()
	var household := household_store.form_household("npc:1")
	household_store.grant_property(household.id, "house:0_0_0")

	var text: String = FieldJournal.entry_for("npc:1", {"household_store": household_store})

	assert_string_contains(text, household.id)
	assert_string_contains(text, "npc:1")
	assert_string_contains(text, "house:0_0_0")


# -- entry_for: "household" kind routes through explain_institutions ----------

func test_household_kind_id_routes_through_explain_institutions_with_real_content():
	var institution_store := InstitutionStore.new()
	var institution := institution_store.form("guild", ["household:1", "household:2"], 1.0)

	var text: String = FieldJournal.entry_for("household:1", {"institution_store": institution_store})

	assert_string_contains(text, institution.id)
	assert_string_contains(text, "guild")


# -- entry_for: "creature" kind routes through explain_world_boss -------------

func test_creature_kind_id_routes_through_explain_world_boss_with_real_content():
	var boss_store := WorldBossStore.new()
	var boss := boss_store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)

	var text: String = FieldJournal.entry_for("creature:1", {"world_boss_store": boss_store})

	assert_string_contains(text, boss.id)
	assert_string_contains(text, "predator")


# -- entry_for: unrecognized/generic kinds fall back to explain_entity --------

## "settlement" is a real EntityRef kind (see entity_ref.gd's for_settlement)
## but is deliberately NOT given its own explain_settlement route here (see
## field_journal.gd's own module doc comment on why) -- it must fall back to
## the generic, always-safe explain_entity.
func test_settlement_kind_id_falls_back_to_explain_entity_with_real_history():
	var event_store := EventStore.new()
	var event := Event.new("settlement_founded", 1.0)
	event.actors = ["settlement:0_0"]
	var event_id: String = event_store.append(event)

	var text: String = FieldJournal.entry_for("settlement:0_0", {"event_store": event_store})

	assert_string_contains(text, event_id)
	assert_string_contains(text, "settlement_founded")


## An id with no "<kind>:" separator at all (EntityRef.kind_of returns "")
## must still resolve cleanly through the same fallback, not error.
func test_id_with_no_kind_separator_falls_back_to_explain_entity():
	var event_store := EventStore.new()
	var text: String = FieldJournal.entry_for("nothing_here", {"event_store": event_store})
	assert_string_contains(text.to_lower(), "no recorded history")


# -- entry_for: a stores Dictionary missing unrelated keys never crashes ------

## The "npc" route only ever needs "household_store" -- a caller who hands
## in a Dictionary with ONLY that key (no "institution_store",
## "world_boss_store", or "event_store" at all) must not crash.
func test_npc_kind_lookup_does_not_crash_when_only_household_store_is_supplied():
	var household_store := HouseholdStore.new()
	var household := household_store.form_household("npc:9")

	var text: String = FieldJournal.entry_for("npc:9", {"household_store": household_store})

	assert_string_contains(text, household.id)


## The "household" route only ever needs "institution_store" -- a caller who
## hands in a Dictionary with ONLY that key (no "household_store",
## "world_boss_store", or "event_store" at all) must not crash.
func test_household_kind_lookup_does_not_crash_when_only_institution_store_is_supplied():
	var institution_store := InstitutionStore.new()
	institution_store.form("militia", ["household:5", "household:6"], 2.0)

	var text: String = FieldJournal.entry_for("household:5", {"institution_store": institution_store})

	assert_string_contains(text, "militia")
