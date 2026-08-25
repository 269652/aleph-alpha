extends RefCounted
## Real-time reader over Why's existing explain_* functions, dispatched by
## entity-id kind -- docs/concept/player_citizenship.md's Field Journal
## item ("the Journal doesn't generate lore, it *reads* lore that the
## simulation already produced"). Deliberately does NOT cover
## explain_settlement (needs live household_count/active_institutions/
## production_counts context this pure module has no access to -- that
## composition is the console command's own job, not this module's) or
## explain_market (needs a live Market instance, same reason). Both are
## named gaps, not oversights.
##
## The kind->explain_* routing below is grounded in how real callers in
## this codebase actually key these stores, NOT in a naive
## "kind X routes to explain_X" guess:
##   - "npc" routes to explain_household, because HouseholdStore.
##     household_for is keyed by a household's MEMBER, and every real
##     member/founder id in this codebase is an "npc:" id (household.gd's
##     Household.for_founder).
##   - "household" routes to explain_institutions, because InstitutionStore.
##     institutions_for is likewise keyed by MEMBER, and every real
##     institution member in this codebase is a "household:" id (see
##     EarthChunkManager.attempt_institution_formation's real call sites) --
##     NOT explain_household, which would always read "no household" for a
##     household's own id, since no household is ever indexed by itself.
##   - "creature" routes to explain_world_boss, matching WorldBossStore.
##     bosses_for's individual_id -- "the real creature entity this boss
##     IS" (world_boss.gd's own doc comment). No real src/ call site
##     produces "creature:" ids yet (attempt_world_boss_promotion has no
##     caller yet, a pre-existing, documented gap in earth_chunk_manager.gd)
##     -- wiring the route now costs nothing and matches this project's own
##     "ready the moment real data exists" precedent.
## Any other kind (including "settlement", "house", "ruin", "path", and any
## id with no "<kind>:" separator at all) falls back to explain_entity,
## which is real, generic, and always safe.
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const Why = preload("res://src/emergence/why.gd")


static func entry_for(entity_id: String, stores: Dictionary) -> String:
	match EntityRef.kind_of(entity_id):
		"npc":
			return Why.explain_household(stores.get("household_store"), entity_id)
		"household":
			return Why.explain_institutions(stores.get("institution_store"), entity_id)
		"creature":
			return Why.explain_world_boss(stores.get("world_boss_store"), entity_id)
		_:
			return Why.explain_entity(stores.get("event_store"), entity_id)
