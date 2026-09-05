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

const MushroomSpecies = preload("res://src/world/mushroom_species.gd")


# -- catalog contents ----------------------------------------------------

func test_ids_lists_every_named_species():
	assert_eq(
		MushroomSpecies.IDS,
		["fly_agaric", "death_cap", "chanterelle", "porcini", "puffball"]
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
# Fly Agaric and Death Cap are the roster's two real toxic species; the
# other three are real, commonly foraged edibles.

func test_fly_agaric_and_death_cap_are_toxic():
	assert_true(MushroomSpecies.is_toxic("fly_agaric"))
	assert_true(MushroomSpecies.is_toxic("death_cap"))


func test_chanterelle_porcini_and_puffball_are_not_toxic():
	for id in ["chanterelle", "porcini", "puffball"]:
		assert_false(MushroomSpecies.is_toxic(id), "%s is a real edible, not toxic" % id)


# -- host tree: mycorrhizal partnership vs. saprotroph --------------------
#
# Fly Agaric/Porcini real-partner with pine; Death Cap/Chanterelle with oak
# (this project's "acorn" tree). Puffball is a real saprotroph -- it
# decomposes litter directly and needs no living host tree at all.

func test_mycorrhizal_species_name_their_real_host_tree():
	assert_eq(MushroomSpecies.host_tree_for("fly_agaric"), "pine")
	assert_eq(MushroomSpecies.host_tree_for("porcini"), "pine")
	assert_eq(MushroomSpecies.host_tree_for("death_cap"), "acorn")
	assert_eq(MushroomSpecies.host_tree_for("chanterelle"), "acorn")


func test_puffball_is_a_saprotroph_with_no_host_tree():
	assert_eq(MushroomSpecies.host_tree_for("puffball"), "")
	assert_true(MushroomSpecies.is_saprotroph("puffball"))


func test_mycorrhizal_species_are_not_saprotrophs():
	for id in ["fly_agaric", "death_cap", "chanterelle", "porcini"]:
		assert_false(MushroomSpecies.is_saprotroph(id))


func test_every_host_tree_is_a_real_tree_species():
	var tree_species = load("res://src/world/tree_species.gd")
	for id in MushroomSpecies.IDS:
		var host: String = MushroomSpecies.host_tree_for(id)
		if host.is_empty():
			continue
		assert_true(tree_species.IDS.has(host), "%s names an unknown host tree %s" % [id, host])
