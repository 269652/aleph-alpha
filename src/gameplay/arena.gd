extends RefCounted
## Staging a real fight on demand (docs/concept/arena.md) -- a dev verb in
## the same family as `/spawn`, `/give` and `/craft`.
##
## Measured first, in test_battle_loop.gd: the combat machinery is sound end
## to end. A woven spell really damages a real creature and really kills it,
## and a real predator really damages the player for its own profile's
## figure. What is missing is the ENCOUNTER, and three deliberate design
## decisions stand between a player and one:
##
##   1. A new character owns NO motes, so nothing can be woven at all. Only
##      three of the seven phenomena have call sites, and one of them needs
##      a venomous snake -- restricted to HARD, 61+ chunks out.
##   2. Mana is entirely the class lens: ClassArchetype's max_mana is 0.0
##      for warrior and artisan, who can therefore never cast anything.
##   3. The hearth is safe on purpose (journey_rings.md), so the nearest
##      ground where predators hunt is the Marches, 16 chunks out.
##
## Each of those is right for the game and wrong for a test loop. This
## module does not change any of them -- it stands beside them.
##
## It STAGES; it never simulates. Real creatures out of the real renderer,
## real motes in the real pouch, and every number that follows is the
## game's own. Delete this file and nothing about how a fight resolves
## changes.
##
## Pure: RefCounted, static functions, no world, no player, no scene tree.

const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

## The play-scale tile in pixels, and the reach of a creature's teeth
## (`CreatureMarker.ATTACK_RANGE`). Restated rather than preloading the
## renderer -- a pure gameplay rule must not drag rendering into every test
## that touches a number, the same reason `SprintCost` and `Discovery` give
## -- and held to their real sources by test.
const TILE_SIZE_PX := 16
const ATTACK_RANGE_PX := 16.0

## How much of its own sense radius away the opposition stands. A half: near
## enough that it is certain to notice you the moment it lands, far enough
## that there is still ground between you. Both ends are swept across the
## whole roster by test rather than asserted here.
const SENSE_FRACTION := 0.5

## The floor, for a short-sighted animal whose half-sense would put it
## inside its own bite. One tile past the teeth: the smallest gap that is
## still a gap at this world's scale.
const MIN_RING_RADIUS_PX := ATTACK_RANGE_PX + float(TILE_SIZE_PX)

## A typo must not be a catastrophe. `/arena wolf 9999` stages this many.
const MAX_OPPONENTS := 12

## What a character with no pool of their own is LENT, so a warrior can test
## a spell at all. Derived rather than chosen: enough to cast the most
## expensive atom in the catalogue this many times running, so the pool is
## not a formality. Pinned by test.
const LENT_POOL_CASTS_OF_THE_DEAREST_ATOM := 6


## Where the opposition stands, in pixels from the player.
##
## Derived from the species' OWN senses (`SpeciesBite.sense_radius_tiles`),
## never picked: inside its sense radius so it is certain to notice you,
## outside `ATTACK_RANGE_PX` so it is not already biting. A fight you have
## to walk into is not a battletest, and one that begins mid-bite is not a
## test of anything but reflexes.
static func ring_radius_px_for(species: String) -> float:
	var profile := SpeciesBite.profile_for(species)
	var sense_px := float(profile.get("sense_radius_tiles", 0.0)) * float(TILE_SIZE_PX)
	return maxf(MIN_RING_RADIUS_PX, sense_px * SENSE_FRACTION)


## Where each one goes: evenly spaced around the circle, starting at
## `Vector2.RIGHT` so a single opponent stands where the camera is looking
## rather than behind the player's head.
static func ring_offsets(count: int, radius: float) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var staged := mini(maxi(0, count), MAX_OPPONENTS)
	if staged <= 0:
		return offsets
	for index in staged:
		var angle := TAU * float(index) / float(staged)
		offsets.append(Vector2.RIGHT.rotated(angle) * radius)
	return offsets


## One of every atom the catalogue knows, as a `{atom_id: count}` pouch.
##
## Without this the arena could not test a single spell: a new character
## owns no motes, and the three phenomena that grant one are a fire, the
## cold, and a snake that lives 61 chunks out. Read from
## `SpellAtomCatalog.known_ids` rather than listed, so a new atom joins the
## loadout the day it is added.
static func loadout_motes() -> Dictionary:
	var motes: Dictionary = {}
	for atom_id in SpellAtomCatalog.new().known_ids():
		motes[String(atom_id)] = 1
	return motes


## The mana pool to test with: the character's own when they have one, and a
## lent pool when they have none.
##
## Overwriting a mage's 50 would be the arena lying about the character;
## leaving a warrior's 0.0 alone would make the command unable to test the
## thing it exists for. So it only ever fills a vacuum -- and the caller
## announces it (see `report_line`), because a tester who does not know
## their mana was topped up will misread every result after it.
static func mana_pool_for(current_max: float) -> float:
	if current_max > 0.0:
		return current_max
	return lent_pool()


## The lent figure, derived from the catalogue's own dearest atom rather
## than typed in, so it stays generous if the costs are ever retuned.
static func lent_pool() -> float:
	var catalog := SpellAtomCatalog.new()
	var dearest := 0.0
	for atom_id in catalog.known_ids():
		dearest = maxf(dearest, catalog.base_cost(String(atom_id)))
	return dearest * float(LENT_POOL_CASTS_OF_THE_DEAREST_ATOM)


## What the console says it did. A sentence, and no id reaches the player --
## the same rule every refusal in this overhaul follows.
static func report_line(species: String, count: int, lent_mana: bool) -> String:
	var spoken := species.strip_edges().replace("_", " ")
	var line := "Staged %d %s around you." % [count, spoken]
	if lent_mana:
		line += " Lent you a mana pool to test with."
	line += " Motes for every spell are in your pouch."
	return line
