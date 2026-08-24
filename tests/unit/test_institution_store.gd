extends GutTest

## InstitutionStore: forms, finds, and dissolves institutions (see
## docs/emergence/01-society-and-institutions.md "Invariants": "Institutions
## can fail, merge, split, migrate, or disappear").
##
## Same shape as EventStore/.../MarketStore: a plain RefCounted collection,
## no engine dependency, its own to_dicts/from_dicts.

const Institution = preload("res://src/emergence/institution.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")

var store: InstitutionStore


func before_each():
	store = InstitutionStore.new()


# -- forming ------------------------------------------------------------------

func test_form_assigns_a_deterministic_sortable_id():
	var institution := store.form("guild", ["household:1", "household:2"], 1.0)
	assert_eq(institution.id, "inst_0_guild")


func test_a_second_formation_gets_the_next_ordinal():
	store.form("guild", ["household:1"], 1.0)
	var second := store.form("militia", ["household:2"], 1.0)
	assert_eq(second.id, "inst_1_militia")


func test_get_institution_returns_the_formed_institution():
	var institution := store.form("guild", ["household:1"], 1.0)
	assert_eq(store.get_institution(institution.id).id, institution.id)


func test_institutions_for_finds_every_institution_a_member_belongs_to():
	var institution := store.form("guild", ["household:1", "household:2"], 1.0)
	assert_eq(store.institutions_for("household:1").size(), 1)
	assert_eq(store.institutions_for("household:1")[0].id, institution.id)
	assert_eq(store.institutions_for("household:2").size(), 1)


func test_institutions_for_an_uninvolved_entity_is_empty():
	store.form("guild", ["household:1"], 1.0)
	assert_eq(store.institutions_for("household:999"), [])


# -- finding an existing institution for an exact member set -----------------

## The dedup guard formation needs: an institution already covering exactly
## this member set (any order) must be found, not silently duplicated.
func test_active_institution_for_finds_an_exact_member_set_match():
	var institution := store.form("guild", ["household:1", "household:2"], 1.0)
	var found := store.active_institution_for(["household:2", "household:1"])
	assert_not_null(found)
	assert_eq(found.id, institution.id)


func test_active_institution_for_a_different_member_set_is_null():
	store.form("guild", ["household:1", "household:2"], 1.0)
	assert_null(store.active_institution_for(["household:1", "household:3"]))


## A DISSOLVED institution does not block re-forming the same member set --
## only an active one counts as "already exists."
func test_active_institution_for_ignores_dissolved_institutions():
	var institution := store.form("guild", ["household:1", "household:2"], 1.0)
	store.dissolve(institution.id, 2.0)
	assert_null(store.active_institution_for(["household:1", "household:2"]))


# -- dissolving -----------------------------------------------------------

func test_dissolve_marks_it_dissolved():
	var institution := store.form("guild", ["household:1"], 1.0)
	assert_true(store.dissolve(institution.id, 2.0))
	assert_eq(store.get_institution(institution.id).status, Institution.DISSOLVED)


## Dissolving does not remove it from the store -- history is kept, the same
## "a fulfilled/breached contract stays queryable" shape ContractStore
## already uses.
func test_a_dissolved_institution_is_still_findable_by_member():
	var institution := store.form("guild", ["household:1"], 1.0)
	store.dissolve(institution.id, 2.0)
	assert_eq(store.institutions_for("household:1").size(), 1)


func test_dissolving_an_already_dissolved_institution_is_refused():
	var institution := store.form("guild", ["household:1"], 1.0)
	store.dissolve(institution.id, 2.0)
	assert_false(store.dissolve(institution.id, 3.0))


func test_dissolving_an_unknown_institution_is_refused_not_an_error():
	assert_false(store.dissolve("inst_999_nothing", 1.0))


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_a_whole_store():
	var institution := store.form("guild", ["household:1", "household:2"], 1.0)
	institution.leader = "household:1"
	institution.goals.append("secure iron")

	var restored := InstitutionStore.from_dicts(store.to_dicts())

	var found = restored.get_institution(institution.id)
	assert_eq(found.members, ["household:1", "household:2"])
	assert_eq(found.leader, "household:1")
	assert_eq(found.goals, ["secure iron"])
	assert_eq(restored.institutions_for("household:1").size(), 1)


func test_a_restored_store_continues_the_id_sequence():
	store.form("guild", ["household:1"], 1.0)
	var restored := InstitutionStore.from_dicts(store.to_dicts())
	var new_institution: Institution = restored.form("militia", ["household:2"], 5.0)
	assert_eq(new_institution.id, "inst_1_militia")
