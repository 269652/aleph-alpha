extends RefCounted

## Who is actually in a mage guild (docs/concept/mage_guild.md mechanism 3).
##
## Pillar 1, stated as code: **a building is a house, not a faculty.** A
## guild raised today holds nobody and teaches nothing. That is not a delay
## timer to be waited out -- it is what makes a guild that has stood for
## years a better guild than one raised last week, and what makes "who came
## here" a fact about a place rather than a property of the building id.
##
## **One persisted number per guild** -- the days it has stood open -- and
## the guild's own existing `seed` (place_building already writes one into
## every building record; no new identity is invented). Everything else,
## including which specific masters are in there, is derived from those two.
## The fraction is carried by the stored float itself, so unlike
## VillageImmigration there is no separate carry to keep in step, and a
## guild fills whether or not anyone is there to watch.

const MageMaster = preload("res://src/gameplay/mage_master.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How long a guild waits for its next master. A **season** -- the unit
## estate_ascension.gd already measures a person's decision to move by, and
## a master deciding to settle somewhere is the same kind of decision. Not
## a new number.
const DAYS_PER_MASTER := SeasonCycle.DAYS_PER_YEAR / 4.0

## How many masters one guild holds.
##
## Pinned by the claim it encodes rather than picked: **a full guild must
## still be unable to teach every school**, or every city's guild becomes
## interchangeable and mage_guild.md's pillar 2 is decoration. Three against
## SpellSchools' ten traditions guarantees that, and is enough for "multiple
## mages hang around inside" to be true rather than a figure of speech.
const CAPACITY := 3


## How many masters have arrived at a guild this old. Never more than
## CAPACITY, and never fewer than none for a nonsense age.
static func arrived_at(days_open: float) -> int:
	if days_open < DAYS_PER_MASTER:
		return 0
	return mini(CAPACITY, int(floor(days_open / DAYS_PER_MASTER)))


## The master seeds in residence, oldest arrival first.
##
## Derived per ARRIVAL INDEX, not re-rolled per visit, which is what makes
## the roster stable: a guild's first master is always that guild's first
## master, so a player who leaves and comes back finds the same people with
## perhaps one more beside them.
static func master_seeds(guild_seed: int, days_open: float) -> Array:
	var seeds: Array = []
	for index in arrived_at(days_open):
		seeds.append(hash("mage_guild_%d_master_%d" % [guild_seed, index]))
	return seeds


## Which of these masters will teach `spell_id`, so a refusal can name what
## is missing rather than say no.
static func teachers_for(book, spell_id: String, master_seeds_here: Array) -> Array:
	var teachers: Array = []
	for seed_value in master_seeds_here:
		if MageMaster.teaches(book, spell_id, seed_value):
			teachers.append(seed_value)
	return teachers


## Every spell that can be learned in THIS guild: the union of what its
## masters teach, in a stable order. Empty for a guild nobody has come to
## yet -- correct and deliberate, because the building is not the teacher.
static func teachable_here(book, master_seeds_here: Array) -> Array:
	var offered := {}
	for seed_value in master_seeds_here:
		for spell_id in MageMaster.teachable(book, seed_value):
			offered[spell_id] = true
	var ids: Array = offered.keys()
	ids.sort()
	return ids
