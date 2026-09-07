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
		[
			"fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol",
			"death_cap", "false_death_cap",
		]
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
# Fly Agaric and Psilocybe are two real psychoactive species (neither
# typically lethal); the other four original-roster species are real,
# commonly foraged edibles. Death Cap -- added later once real art
# surfaced for it -- is the roster's one genuinely, often-fatally toxic
# species (real amatoxin poisoning). False Death Cap, despite the name and
# its real visual resemblance to Death Cap (the actual reason foragers
# fear it), is not itself seriously toxic -- see is_toxic("false_death_
# cap")'s own test below.

func test_fly_agaric_and_psylo_are_toxic():
	assert_true(MushroomSpecies.is_toxic("fly_agaric"))
	assert_true(MushroomSpecies.is_toxic("psylo"))


func test_the_edible_species_are_not_toxic():
	for id in ["black_trumpet", "champignon", "chanterelle", "parasol"]:
		assert_false(MushroomSpecies.is_toxic(id), "%s is a real edible, not toxic" % id)


## Real: Amanita phalloides -- amatoxin poisoning, responsible for most
## fatal mushroom poisonings worldwide (delayed-onset liver/kidney
## failure). Unambiguously the roster's single most dangerous species; see
## MushroomToxin.severity_for's own doc comment for the actual severity
## ordering this implies.
func test_death_cap_is_toxic():
	assert_true(MushroomSpecies.is_toxic("death_cap"))


## Real: Amanita citrina. Despite its name and its genuine visual
## resemblance to true Death Cap (the actual, real reason it's treated
## with caution by foragers), modern mycological consensus is that it is
## not itself seriously toxic -- at most mildly unpalatable, never the
## amatoxin poisoning its namesake causes. Its danger in reality is being
## MISTAKEN for something deadly, not its own chemistry.
func test_false_death_cap_is_not_toxic():
	assert_false(MushroomSpecies.is_toxic("false_death_cap"))


# -- psychoactive vs. purely toxic: two genuinely different real hazards ----
#
# Reported live, directly: "i just saw a bug eat a psylo and it didn't do
# anything to it." Closing that gap (see docs/concept/soil_fauna.md's
# "Progressive, mass-scaled bites, and real toxic effects") needed telling
# apart two real, mechanistically DIFFERENT hazards `is_toxic` alone
# conflates: real psilocybin/ibotenic-acid mushrooms cause genuine
# motor-coordination impairment/disorientation, while Death Cap's real
# amatoxin poisoning is a progressive illness with no perceptual
# component at all. A new, second boolean trait, not a replacement for
# is_toxic -- every psychoactive species IS toxic, but not every toxic
# species is psychoactive.

func test_fly_agaric_and_psylo_are_psychoactive():
	assert_true(MushroomSpecies.is_psychoactive("fly_agaric"))
	assert_true(MushroomSpecies.is_psychoactive("psylo"))


## Real amatoxin poisoning (Death Cap) has no perceptual/psychoactive
## component -- a categorically different real hazard (progressive
## illness, not disorientation).
func test_death_cap_is_toxic_but_not_psychoactive():
	assert_true(MushroomSpecies.is_toxic("death_cap"))
	assert_false(MushroomSpecies.is_psychoactive("death_cap"))


func test_edible_species_are_not_psychoactive():
	for id in ["black_trumpet", "champignon", "chanterelle", "parasol"]:
		assert_false(MushroomSpecies.is_psychoactive(id), "%s is a real edible, not psychoactive" % id)


## Every psychoactive species is itself toxic -- there is no real mushroom
## that is psychoactive but not toxic in this roster.
func test_every_psychoactive_species_is_also_toxic():
	for id in MushroomSpecies.IDS:
		if MushroomSpecies.is_psychoactive(id):
			assert_true(MushroomSpecies.is_toxic(id), "%s is psychoactive -- it must also be toxic" % id)


func test_false_death_cap_is_not_psychoactive():
	assert_false(MushroomSpecies.is_psychoactive("false_death_cap"))


func test_an_unknown_species_is_not_psychoactive():
	assert_false(MushroomSpecies.is_psychoactive("portobello"))


# -- host tree: mycorrhizal partnership vs. saprotroph --------------------
#
# Fly Agaric real-partners with pine; Black Trumpet and Chanterelle with
# oak (this project's "acorn" tree) -- all three real mycorrhizal
# relationships. Psilocybe, Champignon, and Parasol are real saprotrophs --
# meadow/pasture/forest-edge species that decompose organic matter
# directly and need no living host tree at all. Death Cap and False Death
# Cap (both real Amanita, both genuinely mycorrhizal, never saprotrophic)
# join the mycorrhizal side: Death Cap classically oak-associated (like
# Black Trumpet/Chanterelle), False Death Cap classically conifer-
# associated (like Fly Agaric -- both real Amanita partnering with pine).

func test_mycorrhizal_species_name_their_real_host_tree():
	assert_eq(MushroomSpecies.host_tree_for("fly_agaric"), "pine")
	assert_eq(MushroomSpecies.host_tree_for("black_trumpet"), "acorn")
	assert_eq(MushroomSpecies.host_tree_for("chanterelle"), "acorn")
	assert_eq(MushroomSpecies.host_tree_for("death_cap"), "acorn")
	assert_eq(MushroomSpecies.host_tree_for("false_death_cap"), "pine")


func test_saprotroph_species_have_no_host_tree():
	for id in ["psylo", "champignon", "parasol"]:
		assert_eq(MushroomSpecies.host_tree_for(id), "", "%s should be a real saprotroph" % id)
		assert_true(MushroomSpecies.is_saprotroph(id))


func test_mycorrhizal_species_are_not_saprotrophs():
	for id in ["fly_agaric", "black_trumpet", "chanterelle", "death_cap", "false_death_cap"]:
		assert_false(MushroomSpecies.is_saprotroph(id))


func test_every_host_tree_is_a_real_tree_species():
	var tree_species = load("res://src/world/tree_species.gd")
	for id in MushroomSpecies.IDS:
		var host: String = MushroomSpecies.host_tree_for(id)
		if host.is_empty():
			continue
		assert_true(tree_species.IDS.has(host), "%s names an unknown host tree %s" % [id, host])


# -- real biome eligibility (see docs/concept/mushrooms.md) ----------------
#
# Reported live: "forest mushrooms should spawn in forests and e.g.
# champignons on pasture" -- the roster's real ecology is more specific
# than the old "mycorrhizal -> forest only, any saprotroph -> forest OR
# grassland" split let it read as. Champignon (Agaricus campestris, the
# real "field mushroom") is specifically a pasture/grassland species,
# genuinely uncommon in deep forest -- unlike Psilocybe/Parasol, both real
# mixed-habitat species kept eligible in forest AND grassland.

func test_mycorrhizal_species_only_allow_forest_and_rainforest():
	for id in ["fly_agaric", "black_trumpet", "chanterelle", "death_cap", "false_death_cap"]:
		assert_true(MushroomSpecies.allows_biome(id, "forest"), "%s should allow forest" % id)
		assert_true(MushroomSpecies.allows_biome(id, "rainforest"), "%s should allow rainforest" % id)
		assert_false(MushroomSpecies.allows_biome(id, "grassland"), "%s should not allow grassland" % id)
		assert_false(MushroomSpecies.allows_biome(id, "desert"), "%s should not allow desert" % id)


func test_champignon_is_pasture_only_not_forest():
	assert_true(MushroomSpecies.allows_biome("champignon", "grassland"))
	assert_false(MushroomSpecies.allows_biome("champignon", "forest"))
	assert_false(MushroomSpecies.allows_biome("champignon", "rainforest"))


func test_psylo_and_parasol_are_real_mixed_habitat_species():
	for id in ["psylo", "parasol"]:
		assert_true(MushroomSpecies.allows_biome(id, "forest"), "%s should allow forest" % id)
		assert_true(MushroomSpecies.allows_biome(id, "rainforest"), "%s should allow rainforest" % id)
		assert_true(MushroomSpecies.allows_biome(id, "grassland"), "%s should allow grassland" % id)


func test_no_species_allows_a_biome_with_no_real_mushroom_ecology():
	for id in MushroomSpecies.IDS:
		assert_false(MushroomSpecies.allows_biome(id, "desert"), "%s should not allow desert" % id)
		assert_false(MushroomSpecies.allows_biome(id, "mountain"), "%s should not allow mountain" % id)


# -- fruiting window: real per-species timing within autumn ---------------
# (see docs/concept/mushrooms.md "Fruiting times, aligned to real species")
#
# Asked directly: "mushrooms should fruit at their respective times ...
# research fruiting times for each mushroom and align them with ingame
# autumn." [start, end) is a fraction through SeasonCycle.progress_through_
# season while season == "autumn" -- 0.0 is autumn's first instant, 1.0 its
# last. Real months don't map onto one compressed in-game quarter directly;
# this instead ranks each species' REAL relative position against the
# others (does it start before others? does it linger after others taper
# off?) -- see each constant's own doc comment in mushroom_species.gd for
# the real-world source reasoning.

func test_every_species_has_its_own_pinned_fruiting_window():
	assert_eq(MushroomSpecies.fruiting_window_for("chanterelle"), Vector2(0.0, 0.55))
	assert_eq(MushroomSpecies.fruiting_window_for("champignon"), Vector2(0.0, 0.7))
	assert_eq(MushroomSpecies.fruiting_window_for("parasol"), Vector2(0.0, 0.6))
	assert_eq(MushroomSpecies.fruiting_window_for("false_death_cap"), Vector2(0.05, 0.65))
	assert_eq(MushroomSpecies.fruiting_window_for("fly_agaric"), Vector2(0.15, 0.85))
	assert_eq(MushroomSpecies.fruiting_window_for("death_cap"), Vector2(0.0, 1.0))
	assert_eq(MushroomSpecies.fruiting_window_for("psylo"), Vector2(0.35, 1.0))
	assert_eq(MushroomSpecies.fruiting_window_for("black_trumpet"), Vector2(0.45, 1.0))


## Real: chanterelle's own season starts as early as June/July (before most
## others even begin) and is "typically over by end of September" in
## Britain -- black trumpet's real peak is specifically October, with a
## real tail into what would be winter in a finer calendar (as late as
## January/February in mild Iberian years). The roster's earliest-starting
## species should be shifted earlier overall than the latest-peaking one --
## NOT necessarily zero overlap (real mushroom seasons do overlap; a very
## late chanterelle and a very early black trumpet genuinely can coincide).
func test_chanterelle_is_earlier_shifted_than_black_trumpet():
	var early: Vector2 = MushroomSpecies.fruiting_window_for("chanterelle")
	var late: Vector2 = MushroomSpecies.fruiting_window_for("black_trumpet")
	assert_lt(early.x, late.x, "chanterelle should start earlier than black trumpet")
	assert_lt(early.y, late.y, "chanterelle should also taper off earlier than black trumpet")


func test_an_unknown_species_gets_the_widest_window_rather_than_a_crash():
	assert_eq(MushroomSpecies.fruiting_window_for("portobello"), Vector2(0.0, 1.0))


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
