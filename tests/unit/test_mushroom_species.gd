extends GutTest

## MushroomSpecies (see docs/concept/mushrooms.md's Species roster).
##
## Mirrors TreeSpecies' exact shape: an ordered IDS array, a SPECIES profile
## dict for real per-species data (display name, cap colour), and small
## per-trait lookup dicts (is_toxic, host_tree_for) rather than fields baked
## into the profile -- matching TreeSpecies.is_nut/needs_pollinators_for's
## own "one small dict per trait, an unlisted id falls back cleanly"
## convention, chosen specifically so a trait split can never silently drift
## out of sync with an index cutoff into IDS.
##
## Roster revised (see mushrooms.md's merge note) to match the real
## illustrated art actually delivered: Fly Agaric, Psilocybe ("psylo"),
## Black Trumpet, Champignon, Chanterelle, Parasol -- replacing the
## originally-designed Death Cap/Porcini/Puffball, which no art exists for.

const MushroomSpecies = preload("res://src/world/mushroom_species.gd")


# -- catalog contents ----------------------------------------------------

func test_ids_lists_every_named_species():
	assert_eq(
		MushroomSpecies.IDS,
		["fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol"]
	)


func test_every_species_has_a_display_name():
	for id in MushroomSpecies.IDS:
		assert_gt(MushroomSpecies.display_name_for(id).length(), 0)


func test_cap_colours_are_distinct_per_species():
	var seen := {}
	for id in MushroomSpecies.IDS:
		seen[MushroomSpecies.cap_color_for(id)] = true
	assert_eq(
		seen.size(), MushroomSpecies.IDS.size(), "every species should have its own cap colour"
	)


func test_an_unknown_species_falls_back_rather_than_crashing():
	assert_gt(MushroomSpecies.display_name_for("portobello").length(), 0)
	assert_false(MushroomSpecies.is_toxic("portobello"))
	assert_eq(MushroomSpecies.host_tree_for("portobello"), "")


# -- toxicity (see docs/concept/mushrooms.md's real-world grounding) -----
#
# Fly Agaric and Psilocybe are the roster's two real psychoactive species
# (neither typically lethal, unlike the original roster's Death Cap); the
# other four are real, commonly foraged edibles.

func test_fly_agaric_and_psylo_are_toxic():
	assert_true(MushroomSpecies.is_toxic("fly_agaric"))
	assert_true(MushroomSpecies.is_toxic("psylo"))


func test_the_edible_species_are_not_toxic():
	for id in ["black_trumpet", "champignon", "chanterelle", "parasol"]:
		assert_false(MushroomSpecies.is_toxic(id), "%s is a real edible, not toxic" % id)


# -- host tree: mycorrhizal partnership vs. saprotroph --------------------
#
# Fly Agaric real-partners with pine; Black Trumpet and Chanterelle with
# oak (this project's "acorn" tree) -- all three real mycorrhizal
# relationships. Psilocybe, Champignon, and Parasol are real saprotrophs --
# meadow/pasture/forest-edge species that decompose organic matter
# directly and need no living host tree at all.

func test_mycorrhizal_species_name_their_real_host_tree():
	assert_eq(MushroomSpecies.host_tree_for("fly_agaric"), "pine")
	assert_eq(MushroomSpecies.host_tree_for("black_trumpet"), "acorn")
	assert_eq(MushroomSpecies.host_tree_for("chanterelle"), "acorn")


func test_saprotroph_species_have_no_host_tree():
	for id in ["psylo", "champignon", "parasol"]:
		assert_eq(MushroomSpecies.host_tree_for(id), "", "%s should be a real saprotroph" % id)
		assert_true(MushroomSpecies.is_saprotroph(id))


func test_mycorrhizal_species_are_not_saprotrophs():
	for id in ["fly_agaric", "black_trumpet", "chanterelle"]:
		assert_false(MushroomSpecies.is_saprotroph(id))


func test_every_host_tree_is_a_real_tree_species():
	var tree_species = load("res://src/world/tree_species.gd")
	for id in MushroomSpecies.IDS:
		var host: String = MushroomSpecies.host_tree_for(id)
		if host.is_empty():
			continue
		assert_true(tree_species.IDS.has(host), "%s names an unknown host tree %s" % [id, host])


# -- item catalog (see docs/concept/mushrooms.md: picking one up always ---
# resolves to its real species id, which must survive save/load per
# item_identity.md -- an id ItemCatalog doesn't know evaporates on reload)

## Every species drops an item the game actually knows about -- a
## mushroom's species id IS the id of the item it drops, the same
## convention test_tree_species.gd's own test_every_species_drops_a_real_
## item already pins for TreeSpecies.
func test_every_species_drops_a_real_item():
	var catalog = load("res://src/gameplay/item_catalog.gd").new()
	for id in MushroomSpecies.IDS:
		assert_true(catalog.has(id), "%s has no item to drop" % id)


func test_every_species_item_is_food():
	var catalog = load("res://src/gameplay/item_catalog.gd").new()
	for id in MushroomSpecies.IDS:
		assert_eq(catalog.kind_of(id), "food", "%s should be a food item" % id)


# -- identification threshold (see docs/concept/mushrooms.md's -------------
# "Identification"): real foraging knowledge comes from direct field
# experience, not a purchased skill point -- derived from the roster's own
# size rather than a separately eyeballed literal, so a species added or
# removed later can't silently drift the threshold out of sync with it.

func test_identification_threshold_matches_the_roster_size():
	assert_eq(MushroomSpecies.MUSHROOMS_TO_LEARN_IDENTIFICATION, MushroomSpecies.IDS.size())
