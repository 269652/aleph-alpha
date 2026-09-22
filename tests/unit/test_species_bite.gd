extends GutTest

## docs/concept/predator_profiles.md: one row per species, and the pure
## rules that generate and constrain it. Pure -- no world, no marker, no
## scene tree -- in the spirit of test_errand_delivery.gd.
##
## The point of this table is that the difficulty tier a species is gated
## to (RegionDifficulty via CreatureRenderer.MIN_DIFFICULTY_TIER_BY_SPECIES)
## is legible in what the animal DOES, so most of these tests read the real
## spawn rosters rather than a fixture: a species added to a pool without a
## profile, or a profile tuned until the world's order flattens, fails here.

const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const Dodge = preload("res://src/gameplay/dodge.gd")
const Player = preload("res://scenes/player.gd")

const REQUIRED_KEYS := [
	"bite_damage",
	"bite_cooldown_seconds",
	"windup_seconds",
	"sense_radius_tiles",
	"pursuit_speed_tiles_per_second",
	"release_distance_tiles",
	"tenacity",
]

## Today's one-size-fits-all animal, for the "did the stakes actually rise"
## regression: 6.0 damage every 0.8s is 7.5 dps, so 100 health lasts 13.3s
## no matter what is biting you.
const TODAYS_SECONDS_TO_KILL := 100.0 / (6.0 / 0.8)


# -- helpers: the REAL rosters, read from the renderer -------------------

func _all_spawnable_species() -> Array:
	var seen := {}
	var pools: Array = [
		CreatureRenderer.HERBIVORE_SPECIES_POOL, CreatureRenderer.PREDATOR_SPECIES_POOL
	]
	for biome in CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME:
		pools.append(CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME[biome])
	for biome in CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME:
		pools.append(CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME[biome])
	for pool in pools:
		for species in pool:
			seen[species] = true
	var names: Array = seen.keys()
	names.sort()
	return names


func _min_tier_of(species: String) -> int:
	return CreatureRenderer.MIN_DIFFICULTY_TIER_BY_SPECIES.get(
		species, RegionDifficulty.Tier.EASY
	)


func _species_gated_to(tier: int) -> Array:
	var gated: Array = []
	for species in _all_spawnable_species():
		if _min_tier_of(species) == tier:
			gated.append(species)
	return gated


func _species_available_at(tier: int) -> Array:
	var available: Array = []
	for species in _all_spawnable_species():
		if _min_tier_of(species) <= tier:
			available.append(species)
	return available


func _threat_of(species: String) -> float:
	return SpeciesBite.threat_score(SpeciesBite.profile_for(species))


func _player_tiles_per_second(pixels_per_second: float) -> float:
	return pixels_per_second / float(TerrainRenderer.TILE_SIZE)


# -- the roster: no profile without a species, no species without one ----

func test_every_spawnable_species_has_a_profile():
	var missing: Array = []
	for species in _all_spawnable_species():
		if not SpeciesBite.has_profile(species):
			missing.append(species)
	assert_eq(missing, [], "species in a real spawn pool with no bite profile")


func test_every_profile_is_a_species_that_really_spawns():
	var spawnable := _all_spawnable_species()
	var orphans: Array = []
	for species in SpeciesBite.species_list():
		if not spawnable.has(species):
			orphans.append(species)
	assert_eq(orphans, [], "profiles for species no pool can ever spawn")


func test_a_profile_carries_every_field_the_caller_needs():
	var profile: Dictionary = SpeciesBite.profile_for("bear")
	for key in REQUIRED_KEYS:
		assert_true(profile.has(key), "bear's profile is missing %s" % key)


func test_a_grazer_that_cannot_attack_still_gets_a_row():
	var profile: Dictionary = SpeciesBite.profile_for("sheep")
	assert_eq(profile["bite_damage"], 0.0, "a sheep does not bite")
	assert_gt(profile["pursuit_speed_tiles_per_second"], 0.0, "but it still runs")


# -- anchors: every tuned number is pinned to a real source --------------

func test_the_reference_bite_is_todays_universal_bite():
	assert_almost_eq(
		SpeciesBite.REFERENCE_BITE_DAMAGE, CreatureMarker.ATTACK_DAMAGE, 0.0001,
		"the table re-scales the roster around the shipped number, it does not inflate it"
	)
	assert_almost_eq(
		SpeciesBite.REFERENCE_BITE_COOLDOWN, CreatureMarker.ATTACK_COOLDOWN, 0.0001
	)


func test_the_reference_species_bite_is_unchanged_by_this_table():
	var wolf: Dictionary = SpeciesBite.profile_for(SpeciesBite.REFERENCE_SPECIES)
	assert_almost_eq(wolf["bite_damage"], CreatureMarker.ATTACK_DAMAGE, 0.0001)
	assert_almost_eq(wolf["bite_cooldown_seconds"], CreatureMarker.ATTACK_COOLDOWN, 0.0001)


func test_the_player_speed_anchors_are_the_players_real_speeds():
	assert_almost_eq(
		SpeciesBite.PLAYER_WALK_TILES_PER_SECOND,
		_player_tiles_per_second(Player.BASE_SPEED), 0.0001
	)
	assert_almost_eq(
		SpeciesBite.PLAYER_SPRINT_TILES_PER_SECOND,
		_player_tiles_per_second(Player.SPRINT_SPEED), 0.0001
	)


func test_the_release_ratio_is_the_engines_own_flee_hysteresis():
	assert_almost_eq(
		SpeciesBite.RELEASE_DISTANCE_RATIO,
		CreatureMarker.FLEE_RELEASE_RADIUS / CreatureMarker.SENSE_RADIUS, 0.0001
	)


func test_nothing_senses_further_than_the_engines_caution_radius():
	assert_almost_eq(
		SpeciesBite.MAX_SENSE_RADIUS_TILES,
		CreatureMarker.CAUTION_RADIUS / float(TerrainRenderer.TILE_SIZE), 0.0001
	)
	for species in SpeciesBite.species_list():
		var profile: Dictionary = SpeciesBite.profile_for(species)
		assert_lte(
			profile["sense_radius_tiles"], SpeciesBite.MAX_SENSE_RADIUS_TILES,
			"%s senses past the radius the avoidance system has already forgotten" % species
		)


func test_the_windup_anchors_come_from_the_players_own_dodge():
	assert_almost_eq(SpeciesBite.BASE_WINDUP_SECONDS, Dodge.INVINCIBLE_DURATION, 0.0001)
	assert_almost_eq(SpeciesBite.LETHAL_WINDUP_SECONDS, Dodge.COOLDOWN_DURATION, 0.0001)


func test_the_fair_bite_fraction_is_todays_bite_against_todays_player():
	assert_almost_eq(
		SpeciesBite.FAIR_BITE_HEALTH_FRACTION * SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH,
		SpeciesBite.REFERENCE_BITE_DAMAGE, 0.0001
	)


## Pillar 6: a species with no row behaves exactly as the game does today,
## so wiring this in can never regress a boss or an easter-egg cameo.
func test_an_unknown_species_gets_todays_engine_animal():
	var profile: Dictionary = SpeciesBite.profile_for("lindwurm")
	assert_almost_eq(profile["bite_damage"], CreatureMarker.ATTACK_DAMAGE, 0.0001)
	assert_almost_eq(profile["bite_cooldown_seconds"], CreatureMarker.ATTACK_COOLDOWN, 0.0001)
	assert_almost_eq(
		profile["sense_radius_tiles"],
		CreatureMarker.SENSE_RADIUS / float(TerrainRenderer.TILE_SIZE), 0.0001
	)
	assert_almost_eq(
		profile["release_distance_tiles"],
		CreatureMarker.FLEE_RELEASE_RADIUS / float(TerrainRenderer.TILE_SIZE), 0.0001
	)
	assert_almost_eq(
		profile["pursuit_speed_tiles_per_second"],
		CreatureMarker.HUNT_SPEED / float(TerrainRenderer.TILE_SIZE), 0.0001
	)
	assert_almost_eq(profile["tenacity"], CreatureBehavior.STRONG_HEALTH_FRACTION, 0.0001)


## ...except the windup, because today's engine has none at all.
func test_the_fallback_still_telegraphs_its_bite():
	var profile: Dictionary = SpeciesBite.profile_for("lindwurm")
	assert_almost_eq(profile["windup_seconds"], SpeciesBite.BASE_WINDUP_SECONDS, 0.0001)


# -- the derived columns -------------------------------------------------

func test_bite_damage_follows_real_mass_to_the_two_thirds():
	var expected := pow(
		CreatureMass.mass_kg_for("bear") / CreatureMass.mass_kg_for("wolf"), 2.0 / 3.0
	)
	assert_almost_eq(
		SpeciesBite.profile_for("bear")["bite_damage"] / SpeciesBite.REFERENCE_BITE_DAMAGE,
		expected, 0.001,
		"muscle force follows cross-section, not weight"
	)


func test_a_heavier_animal_bites_harder_and_recovers_slower():
	for pair in [["bear", "wolf"], ["wolf", "lynx"], ["lynx", "jackal"], ["jackal", "arctic_fox"]]:
		var heavy: Dictionary = SpeciesBite.profile_for(pair[0])
		var light: Dictionary = SpeciesBite.profile_for(pair[1])
		assert_gt(heavy["bite_damage"], light["bite_damage"], "%s bites harder than %s" % pair)
		assert_gt(
			heavy["bite_cooldown_seconds"], light["bite_cooldown_seconds"],
			"%s's jaw closes slower than %s's" % pair
		)


## Who bites at all is CreatureInfo's existing temperament table, not a
## second opinion invented here.
func test_only_an_aggressive_species_bites():
	for species in SpeciesBite.species_list():
		var aggressive: bool = (
			CreatureInfo.TEMPERAMENT_BY_SPECIES.get(species, "calm") == "aggressive"
		)
		var damage: float = SpeciesBite.profile_for(species)["bite_damage"]
		if aggressive:
			assert_gt(damage, 0.0, "%s is aggressive but cannot hurt anyone" % species)
		else:
			assert_eq(damage, 0.0, "%s is calm but bites" % species)


func test_the_pursuit_band_is_anchored_on_the_players_two_speeds():
	assert_almost_eq(
		SpeciesBite.SLOWEST_PURSUIT_TILES_PER_SECOND,
		SpeciesBite.PLAYER_WALK_TILES_PER_SECOND * SpeciesBite.SLOWEST_PURSUIT_FRACTION, 0.0001
	)
	assert_almost_eq(
		SpeciesBite.FASTEST_PURSUIT_TILES_PER_SECOND,
		SpeciesBite.PLAYER_SPRINT_TILES_PER_SECOND * SpeciesBite.OUTRUN_MARGIN, 0.0001
	)


func test_the_real_speed_range_actually_reaches_both_anchors():
	assert_almost_eq(
		SpeciesBite.pursuit_speed_for_real_top_speed(SpeciesBite.SLOWEST_REAL_TOP_SPEED_KMH),
		SpeciesBite.SLOWEST_PURSUIT_TILES_PER_SECOND, 0.0001
	)
	assert_almost_eq(
		SpeciesBite.pursuit_speed_for_real_top_speed(SpeciesBite.FASTEST_REAL_TOP_SPEED_KMH),
		SpeciesBite.FASTEST_PURSUIT_TILES_PER_SECOND, 0.0001
	)
	var slowest := 1000.0
	var fastest := 0.0
	for species in SpeciesBite.species_list():
		var kmh: float = SpeciesBite.real_top_speed_kmh(species)
		slowest = minf(slowest, kmh)
		fastest = maxf(fastest, kmh)
	assert_almost_eq(slowest, SpeciesBite.SLOWEST_REAL_TOP_SPEED_KMH, 0.0001)
	assert_almost_eq(fastest, SpeciesBite.FASTEST_REAL_TOP_SPEED_KMH, 0.0001)


func test_pursuit_speed_keeps_the_real_worlds_order():
	assert_gt(
		SpeciesBite.pursuit_speed_for_real_top_speed(80.0),
		SpeciesBite.pursuit_speed_for_real_top_speed(40.0)
	)
	# A bear really is faster than a boar, and a viper slower than both.
	assert_gt(
		SpeciesBite.profile_for("bear")["pursuit_speed_tiles_per_second"],
		SpeciesBite.profile_for("boar")["pursuit_speed_tiles_per_second"]
	)
	assert_lt(
		SpeciesBite.profile_for("venomous_snake")["pursuit_speed_tiles_per_second"],
		SpeciesBite.profile_for("boar")["pursuit_speed_tiles_per_second"]
	)


# -- fairness is structural ---------------------------------------------

func test_a_bite_no_worse_than_todays_needs_only_the_base_telegraph():
	assert_almost_eq(
		SpeciesBite.required_windup_seconds(SpeciesBite.REFERENCE_BITE_DAMAGE, 100.0),
		SpeciesBite.BASE_WINDUP_SECONDS, 0.0001
	)
	assert_almost_eq(
		SpeciesBite.required_windup_seconds(0.1, 100.0), SpeciesBite.BASE_WINDUP_SECONDS, 0.0001
	)


## ...and an animal with no bite is owed no telegraph at all.
func test_something_that_cannot_bite_has_nothing_to_telegraph():
	assert_eq(SpeciesBite.required_windup_seconds(0.0, 100.0), 0.0)
	assert_eq(SpeciesBite.windup_seconds_for("sheep", 100.0), 0.0)


func test_a_bite_that_kills_outright_carries_the_whole_dodge_cooldown():
	assert_almost_eq(
		SpeciesBite.required_windup_seconds(100.0, 100.0),
		SpeciesBite.LETHAL_WINDUP_SECONDS, 0.0001,
		"a player who just dodged must never die to a bite they could not avoid"
	)


func test_a_bigger_bite_always_needs_a_longer_windup():
	var previous := 0.0
	for damage in [10.0, 20.0, 40.0, 80.0, 100.0]:
		var required: float = SpeciesBite.required_windup_seconds(damage, 100.0)
		assert_gt(required, previous, "windup must keep growing with the damage")
		previous = required


func test_every_profile_clears_its_own_fairness_requirement():
	for species in SpeciesBite.species_list():
		var profile: Dictionary = SpeciesBite.profile_for(species)
		var required: float = SpeciesBite.required_windup_seconds(
			profile["bite_damage"], SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH
		)
		assert_gte(
			profile["windup_seconds"], required,
			"%s's bite is a cheap shot: %.2fs of windup for %.1f damage needs %.2fs" % [
				species, profile["windup_seconds"], profile["bite_damage"], required
			]
		)


## The authored column is a FLOOR, not the answer: a frailer character is
## warned more, automatically, for a build this table has never seen.
func test_a_frailer_player_is_always_warned_in_time():
	for max_health in [20.0, 50.0, 100.0, 250.0]:
		for species in SpeciesBite.species_list():
			var profile: Dictionary = SpeciesBite.profile_for(species)
			assert_gte(
				SpeciesBite.windup_seconds_for(species, max_health),
				SpeciesBite.required_windup_seconds(profile["bite_damage"], max_health),
				"%s at %.0f max health" % [species, max_health]
			)


func test_a_frail_character_sees_a_bear_coming_for_longer():
	assert_gt(
		SpeciesBite.windup_seconds_for("bear", 40.0),
		SpeciesBite.windup_seconds_for("bear", 100.0)
	)


func test_a_healthy_character_still_gets_the_authored_telegraph():
	assert_almost_eq(
		SpeciesBite.windup_seconds_for("bear", SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH),
		SpeciesBite.profile_for("bear")["windup_seconds"], 0.0001
	)


func test_nothing_in_the_roster_kills_a_full_health_player_in_one_bite():
	for species in SpeciesBite.species_list():
		assert_lt(
			SpeciesBite.profile_for(species)["bite_damage"],
			SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH,
			"%s one-shots a full-health player" % species
		)


func test_there_is_always_time_to_be_visibly_in_trouble():
	for species in SpeciesBite.species_list():
		var profile: Dictionary = SpeciesBite.profile_for(species)
		if profile["bite_damage"] <= 0.0:
			continue
		assert_gte(
			SpeciesBite.seconds_to_kill(profile, SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH),
			SpeciesBite.MINIMUM_TIME_TO_KILL_SECONDS, "%s kills too fast to read" % species
		)


## The brief's "nothing is at stake": today every animal takes 13.3s to
## kill you. The gated three must be strictly faster than that, or the
## table has changed nothing that matters.
func test_the_gated_species_actually_raised_the_stakes():
	for species in _species_gated_to(RegionDifficulty.Tier.HARD):
		assert_lt(
			SpeciesBite.seconds_to_kill(
				SpeciesBite.profile_for(species), SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH
			),
			TODAYS_SECONDS_TO_KILL, "%s is no deadlier than today's flat animal" % species
		)


func test_venom_is_counted_as_the_damage_one_bite_is_really_worth():
	assert_almost_eq(
		SpeciesBite.profile_for("venomous_snake")["venom_damage"],
		VenomModel.DAMAGE_PER_SECOND_PER_STACK * VenomModel.DURATION_SECONDS, 0.0001
	)
	assert_eq(SpeciesBite.profile_for("nonvenomous_snake")["venom_damage"], 0.0)


# -- a chase is a real decision -----------------------------------------

func test_every_profile_releases_further_out_than_it_senses():
	for species in SpeciesBite.species_list():
		var profile: Dictionary = SpeciesBite.profile_for(species)
		assert_gt(
			profile["release_distance_tiles"], profile["sense_radius_tiles"],
			"%s gives up inside its own sense radius" % species
		)
		assert_gte(
			profile["release_distance_tiles"] - profile["sense_radius_tiles"],
			SpeciesBite.MIN_RELEASE_HYSTERESIS_TILES,
			"%s: backing off one step breaks the chase" % species
		)


# -- pursuit against the player -----------------------------------------

func test_a_chase_decided_by_a_hair_is_not_an_escape():
	var walk: float = SpeciesBite.PLAYER_WALK_TILES_PER_SECOND
	assert_false(SpeciesBite.is_outrun_by(walk, walk), "matching speed is not escaping")
	assert_false(
		SpeciesBite.is_outrun_by(walk * 0.99, walk), "a 1% edge is frame timing, not a decision"
	)
	assert_true(SpeciesBite.is_outrun_by(walk * 0.5, walk))


## Pinned as a whole set, so a re-tune that quietly makes the early world
## unwalkable (or the late world strollable) fails here.
func test_what_can_be_outrun_at_a_walk():
	var outwalked: Array = []
	for species in SpeciesBite.species_list():
		if SpeciesBite.is_outrun_by(
			SpeciesBite.profile_for(species)["pursuit_speed_tiles_per_second"],
			SpeciesBite.PLAYER_WALK_TILES_PER_SECOND
		):
			outwalked.append(species)
	outwalked.sort()
	assert_eq(outwalked, ["alp", "mouse", "nonvenomous_snake", "venomous_snake"])
	var easy := _species_available_at(RegionDifficulty.Tier.EASY)
	var easy_outwalked: Array = []
	for species in outwalked:
		if easy.has(species):
			easy_outwalked.append(species)
	assert_gt(easy_outwalked.size(), 0, "early play must be forgiving somewhere")


func test_what_cannot_be_outrun_even_at_a_sprint():
	var uncatchable: Array = []
	for species in SpeciesBite.species_list():
		if not SpeciesBite.is_outrun_by(
			SpeciesBite.profile_for(species)["pursuit_speed_tiles_per_second"],
			SpeciesBite.PLAYER_SPRINT_TILES_PER_SECOND
		):
			uncatchable.append(species)
	uncatchable.sort()
	assert_eq(
		uncatchable,
		["camel", "horse", "jaguar", "lion", "lynx", "mountain_lion", "reindeer"]
	)
	var gated_and_uncatchable: Array = []
	for species in uncatchable:
		if _min_tier_of(species) >= RegionDifficulty.Tier.MEDIUM:
			gated_and_uncatchable.append(species)
	assert_gt(
		gated_and_uncatchable.size(), 0,
		"requirement 3: distance alone must stop saving you somewhere past the easy ring"
	)


func test_anything_you_can_outwalk_you_can_also_outsprint():
	for species in SpeciesBite.species_list():
		var pursuit: float = SpeciesBite.profile_for(species)["pursuit_speed_tiles_per_second"]
		if SpeciesBite.is_outrun_by(pursuit, SpeciesBite.PLAYER_WALK_TILES_PER_SECOND):
			assert_true(
				SpeciesBite.is_outrun_by(pursuit, SpeciesBite.PLAYER_SPRINT_TILES_PER_SECOND),
				"%s: sprinting must never be worse than walking" % species
			)


# -- the difficulty gradient is monotone --------------------------------

func test_a_harder_tier_is_strictly_more_dangerous_than_an_easier_one():
	var tiers: Array = [
		RegionDifficulty.Tier.EASY, RegionDifficulty.Tier.MEDIUM, RegionDifficulty.Tier.HARD
	]
	for harder_index in range(1, tiers.size()):
		var gated: Array = _species_gated_to(tiers[harder_index])
		if gated.is_empty():
			continue
		var easier: Array = _species_available_at(tiers[harder_index - 1])
		var worst_easier := 0.0
		var worst_easier_species := ""
		for species in easier:
			if _threat_of(species) > worst_easier:
				worst_easier = _threat_of(species)
				worst_easier_species = species
		for species in gated:
			assert_gt(
				_threat_of(species), worst_easier * SpeciesBite.TIER_THREAT_MARGIN,
				"%s (tier %d, threat %.1f) is not clear of %s (threat %.1f)" % [
					species, tiers[harder_index], _threat_of(species),
					worst_easier_species, worst_easier
				]
			)


func test_the_threat_score_reads_every_lever_that_makes_a_fight_hard():
	var bear: Dictionary = SpeciesBite.profile_for("bear")
	var base: float = SpeciesBite.threat_score(bear)
	var harder: Dictionary = bear.duplicate()
	harder["bite_damage"] = bear["bite_damage"] * 2.0
	assert_gt(SpeciesBite.threat_score(harder), base, "more damage is more dangerous")
	harder = bear.duplicate()
	harder["tenacity"] = bear["tenacity"] / 2.0
	assert_gt(SpeciesBite.threat_score(harder), base, "giving up later is more dangerous")
	harder = bear.duplicate()
	harder["pursuit_speed_tiles_per_second"] = bear["pursuit_speed_tiles_per_second"] * 2.0
	assert_gt(SpeciesBite.threat_score(harder), base, "being faster is more dangerous")
	harder = bear.duplicate()
	harder["windup_seconds"] = bear["windup_seconds"] * 2.0
	assert_lt(SpeciesBite.threat_score(harder), base, "a longer telegraph is less dangerous")


func test_a_grazer_is_no_threat_and_every_predator_is():
	for species in SpeciesBite.species_list():
		var threat: float = _threat_of(species)
		if SpeciesBite.profile_for(species)["bite_damage"] > 0.0:
			assert_gt(threat, 0.0, "%s bites but scores as harmless" % species)
		else:
			assert_eq(threat, 0.0, "%s cannot bite but scores as a threat" % species)


# -- tenacity: the flat half-health break-off is gone -------------------

func test_a_bear_does_not_break_off_at_half_health():
	assert_lt(
		SpeciesBite.profile_for("bear")["tenacity"], CreatureBehavior.STRONG_HEALTH_FRACTION,
		"the one number this table exists to replace"
	)
	assert_true(SpeciesBite.flees_at("bear", 0.10))
	assert_false(
		SpeciesBite.flees_at("bear", 0.45), "a half-hurt bear is still a bear"
	)


func test_the_roster_no_longer_shares_one_break_off_point():
	var distinct := {}
	for species in SpeciesBite.species_list():
		if SpeciesBite.profile_for(species)["bite_damage"] > 0.0:
			distinct[SpeciesBite.profile_for(species)["tenacity"]] = true
	assert_gt(distinct.size(), 1, "every aggressor still flees at the same health")


func test_a_grazer_flees_at_any_health_at_all():
	assert_true(SpeciesBite.flees_at("deer", 1.0), "a deer never stands")


# -- strengthening: what a weak version of this table would still pass ---

## The whole point of the module: a flattening "rebalance" back toward one
## stat block must fail here. Four of the seven columns have to carry a
## real spread, not just distinct decimals.
func test_the_roster_is_not_one_animal_in_different_sprites():
	var damages: Array = []
	var cooldowns: Array = []
	var senses: Array = []
	var pursuits: Array = []
	for species in SpeciesBite.species_list():
		var profile: Dictionary = SpeciesBite.profile_for(species)
		senses.append(profile["sense_radius_tiles"])
		pursuits.append(profile["pursuit_speed_tiles_per_second"])
		if profile["bite_damage"] > 0.0:
			damages.append(profile["bite_damage"])
			cooldowns.append(profile["bite_cooldown_seconds"])
	damages.sort()
	cooldowns.sort()
	senses.sort()
	pursuits.sort()
	assert_gt(
		damages[-1] / damages[0], 3.0,
		"the hardest bite in the world must be several times the softest"
	)
	assert_gt(cooldowns[-1] / cooldowns[0], 1.5, "a bear's jaw is not a fox's jaw")
	assert_gt(senses[-1] / senses[0], 2.0, "a bear's nose is not a mouse's nose")
	assert_gt(pursuits[-1] / pursuits[0], 2.0, "a lion does not run at a snake's pace")


## Guards the gradient test itself: if MIN_DIFFICULTY_TIER_BY_SPECIES were
## emptied, every tier comparison would be skipped and the monotonicity
## test would pass while checking nothing at all.
func test_there_really_is_a_gated_tier_to_compare_against():
	assert_gt(
		_species_gated_to(RegionDifficulty.Tier.HARD).size(), 0,
		"nothing is gated, so the danger gradient is testing an empty set"
	)


func test_the_venomous_roster_matches_the_engines_own():
	assert_eq(
		SpeciesBite.VENOMOUS_SPECIES.keys(), CreatureMarker.VENOMOUS_SPECIES.keys(),
		"the venom list drifted from the one that actually injects venom"
	)


## The one-tile hysteresis is a rule, not a coincidence of the radii that
## happen to be authored today: a close-range ambusher gets it too.
func test_a_close_range_ambusher_still_opens_a_real_gap():
	assert_almost_eq(SpeciesBite.release_distance_tiles_for(1.0), 2.0, 0.0001)
	assert_almost_eq(SpeciesBite.release_distance_tiles_for(10.0), 15.0, 0.0001)


## A caller that edits the dictionary it was handed must not edit the
## world's stat table.
func test_a_profile_is_a_copy_the_caller_may_scribble_on():
	var profile: Dictionary = SpeciesBite.profile_for("bear")
	profile["bite_damage"] = 0.0
	assert_gt(
		SpeciesBite.profile_for("bear")["bite_damage"], 0.0, "the table was mutated by a caller"
	)


func test_an_animal_exactly_as_fast_as_you_is_never_outrun():
	assert_false(SpeciesBite.is_outrun_by(5.0, 5.0))
	assert_true(SpeciesBite.is_outrun_by(5.0, 5.0 * SpeciesBite.OUTRUN_MARGIN))


## The one number in the windup rule with no assertion of its own.
##
## `WINDUP_SECONDS_PER_HEALTH_FRACTION` is not authored -- it is whatever
## slope joins the two anchors, and the two anchors plus monotonicity
## determine a line uniquely. This test says exactly that rather than
## restating the arithmetic: the slope really is the one that carries the
## curve from the base telegraph at a fair bite to the whole dodge cooldown
## at a bite that kills outright, so it cannot be nudged on its own.
func test_the_windup_slope_is_the_line_between_its_own_two_anchors():
	var fair := SpeciesBite.FAIR_BITE_HEALTH_FRACTION
	assert_almost_eq(
		SpeciesBite.WINDUP_SECONDS_PER_HEALTH_FRACTION,
		(SpeciesBite.LETHAL_WINDUP_SECONDS - SpeciesBite.BASE_WINDUP_SECONDS) / (1.0 - fair),
		0.000001,
		"the slope is derived from the anchors, never chosen beside them"
	)


## And the anchors themselves are the player's own dodge, not two numbers
## that happen to look like it -- which is what makes the whole fairness
## model a statement about a verb the player can really perform.
func test_both_anchors_are_the_dodge_itself():
	assert_eq(SpeciesBite.BASE_WINDUP_SECONDS, DodgeForWindup.INVINCIBLE_DURATION)
	assert_eq(SpeciesBite.LETHAL_WINDUP_SECONDS, DodgeForWindup.COOLDOWN_DURATION)


const DodgeForWindup = preload("res://src/gameplay/dodge.gd")
