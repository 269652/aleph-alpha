extends RefCounted

## What a kill leaves for a spellwright (docs/concept/spell_weaving.md).
##
## The last unbuilt half of the Magicraft loop, and the sharpest one.
## `SpellMote.drop_tier_cap_for_ring` and `droppable_atoms_at_ring` say
## exactly what is eligible where, and had ZERO callers: the only two ways
## an atom ever reached a pouch were the seven one-time `witness`
## phenomena and the `/arena` dev command. So a character had at most seven
## atoms for the whole game, and the four-socket Weave could never be full
## of anything they had chosen.
##
## A mote is a souvenir of something that nearly killed you. So the odds
## come from `SpeciesBite.threat_score` -- the same score the world's
## difficulty rings are ordered by, so the animals a ring gates you away
## from are exactly the ones worth hunting for parts -- and the eligible
## set comes from where you were standing when it died.
##
## Pure: a RefCounted of static functions over the two tables it reads. No
## world, no player, no RNG of its own -- the seed arrives from the caller,
## the same spatial-hash convention every other one-time world roll in this
## project already uses.

const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## The salt this module rolls under, so a mote roll and any other roll made
## from the same kill position can never be the same number.
const DROP_NOISE_SALT := 0x5E11B07E
const ATOM_NOISE_SALT := 0xA70113D5

## What the most dangerous animal in the world leaves, per kill. Every other
## species is this scaled by its own share of that threat, so a grazer --
## threat zero, because it never bit anybody -- leaves nothing at all.
##
## The one tuned value here, and it is pinned by what it MEANS rather than
## by taste (test_mote_drop.gd): `SpellDraft.MAX_SOCKETS / MAX_DROP_CHANCE`
## is how many kills of the world's worst animal fill a Weave, and that has
## to be a hunting trip -- not a handful of kills, which makes the Weave a
## vending machine, and not forty, which makes it a grind. It is also held
## below a coin flip: past that, motes stop being a souvenir of hunting and
## become the reason for it.
const MAX_DROP_CHANCE := 0.25

## The roster the ceiling is measured against: every species that really
## bites, so "the most dangerous animal in the world" is a fact about the
## live table rather than a name typed in here. Read through
## `SpeciesBite.has_profile` so a species added tomorrow joins it by
## existing.
static func _peak_threat() -> float:
	var peak := 0.0
	for species in SpeciesBite.species_list():
		peak = maxf(peak, SpeciesBite.threat_score(SpeciesBite.profile_for(String(species))))
	return peak


## How often killing `species` leaves a mote, 0.0 for anything that was
## never a threat and for anything this world does not know.
static func chance_for(species: String) -> float:
	if not SpeciesBite.has_profile(species):
		return 0.0
	var peak := _peak_threat()
	if peak <= 0.0:
		return 0.0
	var threat := SpeciesBite.threat_score(SpeciesBite.profile_for(species))
	return MAX_DROP_CHANCE * clampf(threat / peak, 0.0, 1.0)


## Which atom this ground yields for `seed_value` -- "" where nothing is
## eligible at all. Deterministic from the seed, so the same kill always
## leaves the same thing.
static func atom_for(ring_index: int, seed_value: int) -> String:
	var eligible: Array = SpellMote.droppable_atoms_at_ring(ring_index)
	if eligible.is_empty():
		return ""
	var pick := int(PixelNoise.unit(ATOM_NOISE_SALT, seed_value, 0) * float(eligible.size()))
	return String(eligible[clampi(pick, 0, eligible.size() - 1)])


## The whole roll: what killing `species` at `ring_index` leaves, or "".
static func drops(species: String, ring_index: int, seed_value: int) -> String:
	var chance := chance_for(species)
	if chance <= 0.0:
		return ""
	if PixelNoise.unit(DROP_NOISE_SALT, seed_value, 0) >= chance:
		return ""
	return atom_for(ring_index, seed_value)
