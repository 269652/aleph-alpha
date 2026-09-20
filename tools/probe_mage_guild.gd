extends SceneTree

## What a real mage guild actually looks like from the inside, season by
## season (docs/concept/mage_guild.md).
##
## The unit tests pin each piece; this puts the whole thing next to itself
## so the shape of the feature can be READ rather than argued about: how
## long a guild stands empty, who turns up, what each of them will teach,
## and how much of the world's catalogue a given city can therefore reach.
## Several guilds side by side is the point -- if they all offered the same
## lessons, pillar 2 would be decoration.
##
## Usage: godot --headless -s tools/probe_mage_guild.gd

const MageGuildRoster = preload("res://src/gameplay/mage_guild_roster.gd")
const MageMaster = preload("res://src/gameplay/mage_master.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellTuition = preload("res://src/gameplay/spell_tuition.gd")


func _initialize() -> void:
	var book := SpellBook.new()
	var tuition := SpellTuition.new()
	print("-- the world's catalogue: %d spells across %d schools --" % [
		book.known_ids().size(), SpellSchools.SCHOOL_IDS.size()
	])
	for school in SpellSchools.SCHOOL_IDS:
		var by_depth := {}
		for spell_id in book.known_ids():
			if SpellSchools.school_of_spell(book, spell_id) == school:
				var depth := SpellSchools.depth_of_spell(book, spell_id)
				by_depth[depth] = by_depth.get(depth, [])
				by_depth[depth].append(spell_id)
		var parts: Array[String] = []
		for depth in range(SpellSchools.MIN_DEPTH, SpellSchools.MAX_DEPTH + 1):
			if by_depth.has(depth):
				parts.append("d%d: %s" % [depth, ", ".join(by_depth[depth])])
		print("  %-12s %s" % [school, " | ".join(parts)])

	print("\n-- one guild, season by season (a master every %.0f days, %d at most) --" % [
		MageGuildRoster.DAYS_PER_MASTER, MageGuildRoster.CAPACITY
	])
	var guild_seed := hash("probe_guild")
	for seasons in range(0, MageGuildRoster.CAPACITY + 2):
		var days := MageGuildRoster.DAYS_PER_MASTER * float(seasons)
		var seeds := MageGuildRoster.master_seeds(guild_seed, days)
		var who: Array[String] = []
		for master_seed in seeds:
			who.append(MageMaster.display_name_for(master_seed))
		var offers := MageGuildRoster.teachable_here(book, seeds)
		print("  day %5.0f  %d in residence  %-58s teaches %d" % [
			days, seeds.size(), ", ".join(who) if not who.is_empty() else "(nobody -- the building is not the teacher)",
			offers.size(),
		])

	print("\n-- six full guilds, and what each can reach --")
	var reached := {}
	for i in 6:
		var other_seed := hash("probe_city_%d" % i)
		var seeds := MageGuildRoster.master_seeds(
			other_seed, MageGuildRoster.DAYS_PER_MASTER * float(MageGuildRoster.CAPACITY)
		)
		var schools: Array[String] = []
		for master_seed in seeds:
			schools.append("%s d%d" % [MageMaster.school_for(master_seed), MageMaster.depth_for(master_seed)])
		var offers := MageGuildRoster.teachable_here(book, seeds)
		for spell_id in offers:
			reached[spell_id] = true
		var priced: Array[String] = []
		for spell_id in offers:
			priced.append("%s %dg" % [spell_id, tuition.tuition_for(book, spell_id)])
		print("  city %d: %-46s -> %s" % [i, ", ".join(schools), ", ".join(priced) if not priced.is_empty() else "nothing"])
	print("  between them they reach %d of %d spells -- the rest are somewhere else."
		% [reached.size(), book.known_ids().size()])

	var unreachable: Array[String] = []
	for spell_id in book.known_ids():
		if not reached.has(spell_id):
			unreachable.append(spell_id)
	if not unreachable.is_empty():
		print("  still to find: %s" % ", ".join(unreachable))
	quit()
