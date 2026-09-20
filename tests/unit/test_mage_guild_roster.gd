extends GutTest

## MageGuildRoster: docs/concept/mage_guild.md mechanism 3 -- a guild fills
## with masters over time.
##
## Pillar 1: a building is a house, not a faculty. A newly raised guild
## teaches nothing, and that is the point rather than a delay timer. One
## persisted number per guild (the days it has stood open) and the guild's
## own existing `seed`; everything else is derived.

const MageGuildRoster = preload("res://src/gameplay/mage_guild_roster.gd")
const MageMaster = preload("res://src/gameplay/mage_master.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

var book := SpellBook.new()

const GUILD := 987654


func _days_for(masters: int) -> float:
	return MageGuildRoster.DAYS_PER_MASTER * float(masters)


# -- a new guild is empty ---------------------------------------------------

func test_a_guild_raised_today_has_nobody_in_it():
	assert_eq(MageGuildRoster.arrived_at(0.0), 0)
	assert_eq(MageGuildRoster.master_seeds(GUILD, 0.0), [])


func test_a_guild_still_has_nobody_the_day_before_its_first_master():
	assert_eq(MageGuildRoster.arrived_at(MageGuildRoster.DAYS_PER_MASTER - 1.0), 0)


func test_the_first_master_arrives_after_a_full_wait():
	assert_eq(MageGuildRoster.arrived_at(MageGuildRoster.DAYS_PER_MASTER), 1)


func test_a_negative_or_nonsense_age_is_an_empty_guild_rather_than_a_crash():
	assert_eq(MageGuildRoster.arrived_at(-500.0), 0)


# -- filling ----------------------------------------------------------------

func test_masters_arrive_one_at_a_time():
	for wanted in range(0, MageGuildRoster.CAPACITY + 1):
		assert_eq(MageGuildRoster.arrived_at(_days_for(wanted)), wanted, "after %d waits" % wanted)


func test_a_guild_never_holds_more_than_its_capacity():
	assert_eq(MageGuildRoster.arrived_at(_days_for(MageGuildRoster.CAPACITY * 100)), MageGuildRoster.CAPACITY)


func test_more_than_one_master_hangs_around_inside():
	# Asked for directly: "multiple mages can move in and hang around
	# inside of the mage guild."
	assert_gt(MageGuildRoster.CAPACITY, 1)


func test_a_full_guild_still_cannot_teach_every_school():
	# The claim CAPACITY encodes. If one guild could hold every tradition,
	# every city's guild would be interchangeable and pillar 2 -- who came
	# decides what can be learned -- would be decoration.
	assert_lt(MageGuildRoster.CAPACITY, SpellSchools.SCHOOL_IDS.size())


func test_the_wait_is_a_season_not_a_new_number():
	# estate_ascension.gd already measures a person's decision to move in
	# seasons; a master deciding to move is the same kind of decision.
	assert_almost_eq(MageGuildRoster.DAYS_PER_MASTER, SeasonCycle.DAYS_PER_YEAR / 4.0, 0.0001)


# -- who is in there --------------------------------------------------------

func test_the_roster_grows_without_reshuffling_who_is_already_there():
	# A player who leaves and comes back finds the SAME people, with
	# perhaps one more -- nothing is rolled at visit time.
	var one: Array = MageGuildRoster.master_seeds(GUILD, _days_for(1))
	var two: Array = MageGuildRoster.master_seeds(GUILD, _days_for(2))
	var three: Array = MageGuildRoster.master_seeds(GUILD, _days_for(3))
	assert_eq(two.slice(0, 1), one)
	assert_eq(three.slice(0, 2), two)


func test_the_roster_is_a_pure_function_of_the_guild_and_its_age():
	assert_eq(
		MageGuildRoster.master_seeds(GUILD, _days_for(2)),
		MageGuildRoster.master_seeds(GUILD, _days_for(2))
	)


func test_two_different_guilds_draw_different_masters():
	assert_ne(
		MageGuildRoster.master_seeds(GUILD, _days_for(MageGuildRoster.CAPACITY)),
		MageGuildRoster.master_seeds(GUILD + 1, _days_for(MageGuildRoster.CAPACITY))
	)


func test_one_guild_never_draws_the_same_master_twice():
	var seeds: Array = MageGuildRoster.master_seeds(GUILD, _days_for(MageGuildRoster.CAPACITY))
	var seen := {}
	for seed_value in seeds:
		assert_false(seen.has(seed_value), "the same master arrived twice")
		seen[seed_value] = true


func test_a_full_roster_is_exactly_capacity_long():
	assert_eq(MageGuildRoster.master_seeds(GUILD, _days_for(999)).size(), MageGuildRoster.CAPACITY)


# -- who here teaches what --------------------------------------------------

func test_nobody_teaches_anything_in_an_empty_guild():
	assert_eq(MageGuildRoster.teachers_for(book, "fire_bolt", []), [])
	assert_eq(MageGuildRoster.teachable_here(book, []), [])


func test_a_guild_offers_exactly_the_union_of_what_its_masters_teach():
	var seeds: Array = MageGuildRoster.master_seeds(GUILD, _days_for(MageGuildRoster.CAPACITY))
	var expected := {}
	for seed_value in seeds:
		for spell_id in MageMaster.teachable(book, seed_value):
			expected[spell_id] = true
	var offered: Array = MageGuildRoster.teachable_here(book, seeds)
	assert_eq(offered.size(), expected.size())
	for spell_id in expected:
		assert_true(offered.has(spell_id), "%s is taught here but not offered" % spell_id)


func test_the_teachers_of_a_spell_are_exactly_those_who_teach_it():
	var seeds: Array = MageGuildRoster.master_seeds(GUILD, _days_for(MageGuildRoster.CAPACITY))
	for spell_id in book.known_ids():
		var teachers: Array = MageGuildRoster.teachers_for(book, spell_id, seeds)
		for seed_value in seeds:
			assert_eq(teachers.has(seed_value), MageMaster.teaches(book, spell_id, seed_value), "%s" % spell_id)


func test_an_offer_list_is_stable_in_order():
	var seeds: Array = MageGuildRoster.master_seeds(GUILD, _days_for(2))
	assert_eq(MageGuildRoster.teachable_here(book, seeds), MageGuildRoster.teachable_here(book, seeds))


## The whole reason a guild is worth travelling to: two of them are not the
## same place.
func test_two_full_guilds_do_not_offer_the_same_lessons():
	var differ := 0
	for i in 40:
		var a: Array = MageGuildRoster.teachable_here(
			book, MageGuildRoster.master_seeds(hash("guild_a_%d" % i), _days_for(999))
		)
		var b: Array = MageGuildRoster.teachable_here(
			book, MageGuildRoster.master_seeds(hash("guild_b_%d" % i), _days_for(999))
		)
		if a != b:
			differ += 1
	assert_gt(differ, 30, "guilds are near-interchangeable -- pillar 2 is decoration")
