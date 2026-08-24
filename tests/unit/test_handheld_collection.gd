extends GutTest

## HandheldCollection (docs/concept/easter_eggs.md's "hidden retro handheld"
## entry): the pure data model behind the "world's smallest Pokédex"-style
## catch-list screen -- which HandheldRoster species has this player caught
## on this handheld, this session. Deliberately in-memory/session-only, not
## persisted to PlayerSave -- the same "no persistence layer built for this
## family of Easter eggs yet" scope call every other module here already
## makes (SeaCaveGuardian's own win/loss state, AncientTerminal's
## has_been_found -- none of them survive a restart today either); see
## docs/progress.md for this documented as a scope choice, not an oversight.
##
## Zero mechanical weight (pillar 2): entries() below exists purely for a
## screen to render, never read by anything that affects real gameplay.

const HandheldCollection = preload("res://src/gameplay/handheld_collection.gd")
const HandheldRoster = preload("res://src/gameplay/handheld_roster.gd")

var collection: HandheldCollection


func before_each():
	collection = HandheldCollection.new()


func test_nothing_is_caught_initially():
	assert_eq(collection.caught_count(), 0)
	assert_false(collection.has_caught("deer"))


func test_mark_caught_records_the_species():
	collection.mark_caught("deer")
	assert_true(collection.has_caught("deer"))
	assert_eq(collection.caught_count(), 1)


func test_mark_caught_twice_does_not_double_count():
	collection.mark_caught("deer")
	collection.mark_caught("deer")
	assert_eq(collection.caught_count(), 1)


func test_mark_caught_multiple_species_counts_each_once():
	collection.mark_caught("deer")
	collection.mark_caught("wolf")
	collection.mark_caught("krampus")
	assert_eq(collection.caught_count(), 3)


func test_total_species_matches_the_full_roster_size():
	var roster := HandheldRoster.new()
	assert_eq(collection.total_species(), roster.all_species().size())


func test_caught_fraction_is_zero_when_nothing_is_caught():
	assert_eq(collection.caught_fraction(), 0.0)


func test_caught_fraction_reflects_progress_toward_the_full_roster():
	collection.mark_caught("deer")
	assert_almost_eq(collection.caught_fraction(), 1.0 / float(collection.total_species()), 0.0001)


func test_caught_fraction_is_one_once_every_species_is_caught():
	var roster := HandheldRoster.new()
	for species in roster.all_species():
		collection.mark_caught(species)
	assert_almost_eq(collection.caught_fraction(), 1.0, 0.0001)


## --- entries: the actual "Pokédex" screen's own data source ---


func test_entries_has_one_row_per_roster_species():
	var roster := HandheldRoster.new()
	assert_eq(collection.entries().size(), roster.all_species().size())


func test_entries_marks_an_uncaught_species_as_not_caught():
	var entries := collection.entries()
	var deer_entry: Dictionary = {}
	for entry in entries:
		if entry["species"] == "deer":
			deer_entry = entry
	assert_eq(deer_entry["caught"], false)


func test_entries_marks_a_caught_species_as_caught():
	collection.mark_caught("deer")
	var entries := collection.entries()
	var deer_entry: Dictionary = {}
	for entry in entries:
		if entry["species"] == "deer":
			deer_entry = entry
	assert_eq(deer_entry["caught"], true)


func test_entries_are_ordered_common_species_before_legendary_species():
	var roster := HandheldRoster.new()
	var entries := collection.entries()
	var seen_legendary := false
	var out_of_order := false
	for entry in entries:
		var is_legendary: bool = roster.is_legendary(entry["species"])
		if is_legendary:
			seen_legendary = true
		elif seen_legendary:
			out_of_order = true
	assert_false(out_of_order, "a common species entry appeared after a legendary one")
