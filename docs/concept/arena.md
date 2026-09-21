# Arena — staging a real fight on demand

A developer/testing verb, in the same family as `/spawn`, `/give` and
`/craft`: it puts a real fight in front of the player *now*, so the spell
and skill layers can be exercised without first arranging the circumstances
that would produce one naturally.

It exists because of a measurement, not a hunch.

## What was measured

`tests/unit/test_battle_loop.gd` asks the only question a player has — weave
a spell, press the key with something in front of you, does it die? — end to
end, with a real `Player` scene, a real `CreatureMarker` out of the real
`CreatureRenderer`, and the real cast path. It passes: a woven spell damages
a real boar, a two-atom weave lands, the learned spell lands, repeated
casting really kills, and a real predator really damages the player through
its own attack path for its own profile's figure.

**So the machinery was never the problem.** Three things stand between a
player and an encounter, and every one of them is a consequence of a
deliberate design decision elsewhere:

1. **A new character owns no motes**, so nothing can be woven at all
   ([spell_weaving.md](spell_weaving.md)). Motes come from *witnessing*
   phenomena, and only three of the seven have call sites today — one of
   which (`envenomated`) requires a venomous snake, which
   `MIN_DIFFICULTY_TIER_BY_SPECIES` restricts to HARD, 61+ chunks out.
2. **Mana is entirely the class lens.** `ClassArchetype`'s `max_mana` is
   0.0 for warrior and artisan, so those characters can never cast
   anything, ever.
3. **The hearth is safe on purpose** ([journey_rings.md](journey_rings.md)):
   *"nothing here kills you that you did not walk up to first"*. The nearest
   ground where predators hunt rather than pass through is the Marches, 16
   chunks out — minutes of walking before a fight is even possible.

Each of those is *right* for the game and wrong for a test loop. The arena
does not change any of them; it stands beside them.

## Design pillars

1. **It stages, it does not simulate.** The arena places real creatures out
   of the real renderer and hands the real player real motes. Every number
   that follows — damage, cost, windup, flee threshold — is the game's own.
   Delete this module and nothing about how a fight resolves changes.
2. **The opposition is placed by its own senses.** The ring radius is
   derived from the species' `SpeciesBite.sense_radius_tiles`, so whatever
   lands is certain to notice you, and from `CreatureMarker.ATTACK_RANGE`,
   so it is not already biting. Not a number somebody liked: a relationship,
   pinned at both ends by test for every species in the roster.
3. **What it lends, it declares.** A warrior with `max_mana` 0.0 is lent a
   pool, because a battletest that cannot cast cannot test casting — and the
   console line **says so**. A tester who does not know their mana was
   topped up will misread every result after it.
4. **A dev verb, and honest about it.** This is the same role `/give` and
   `/craft` already play (see [wayfinding.md](wayfinding.md)'s note on the
   dev console as a real, honest interim call site). It is not a game mode,
   not a progression path, and grants nothing that persists beyond the
   character it was run on.
5. **Capped, so a typo is not a catastrophe.** `MAX_OPPONENTS` bounds the
   count; `/arena wolf 9999` stages `MAX_OPPONENTS` wolves and says so.

## Mechanism

### `Arena` — pure, and the whole staging rule

`src/gameplay/arena.gd`, a `RefCounted` of static functions with no world,
no player and no scene tree, in the spirit of `errand_delivery.gd` and
`discovery.gd`.

- **`ring_radius_px_for(species)`** — where the opposition stands. Half the
  species' own sense radius in pixels, floored at a margin past
  `ATTACK_RANGE_PX` so even a short-sighted animal lands outside its own
  teeth. Both bounds are swept across `SpeciesBite.species_list()`.
- **`ring_offsets(count, radius)`** — evenly spaced around the circle,
  starting at `Vector2.RIGHT` so a single opponent stands where the camera
  is looking. Clamped to `MAX_OPPONENTS`; a count of zero or less places
  nothing.
- **`loadout_motes()`** — one of every atom `SpellAtomCatalog` knows, so
  every spell in the game is weavable immediately. Pinned two-way against
  the catalogue: a new atom joins the loadout automatically, and a mote for
  an atom that does not exist fails.
- **`mana_pool_for(current_max)`** — the character's own pool when they have
  one, and `LENT_MANA_POOL` when they have none. The lent figure is derived
  rather than chosen: enough to cast the most expensive atom in the
  catalogue several times running, so the pool is not a formality.
- **`report_line(species, count, lent_mana)`** — what the console says. A
  sentence, ending in a full stop, with no snake_case id in it — the same
  rule every refusal in this overhaul follows.

### The verb, in the dev console

`/arena [species] [count]` in `World`, beside `_handle_spawn_command` whose
species resolution (`ConsoleSpecies.resolve`, with its friendly aliases) and
`CreatureRenderer.spawn_single` call it reuses rather than duplicating.

## Interaction with other docs

- [spell_weaving.md](spell_weaving.md) — the motes the loadout hands over,
  and the Weave (**M**) they are arranged on.
- [predator_profiles.md](predator_profiles.md) — `SpeciesBite`, whose sense
  radius decides where the opposition stands and whose bite it lands with.
- [journey_rings.md](journey_rings.md) — the safe hearth this works around
  rather than against.
- [combat.md](combat.md) / [magic.md](magic.md) — the real resolution, which
  this module deliberately does not touch.
- [classes.md](classes.md) — the `max_mana` lens that makes a lent pool
  necessary for half the roster.

## Status

- ✅ **`Arena`, the staging rule** (2026-09-21). `ring_radius_px_for` /
  `ring_offsets` / `loadout_motes` / `mana_pool_for` / `lent_pool` /
  `report_line`, pure and pinned (`test_arena.gd`, 17): the ring swept
  against **every** species in `SpeciesBite.species_list()` at both ends —
  inside its own sense radius, outside its own teeth — the offsets evenly
  spaced with no two on one spot and a single opponent in front of the
  camera, the count capped so a typo cannot stage a thousand, the loadout
  pinned two-way against `SpellAtomCatalog`, a mage's own pool never
  overwritten, and the lent pool asserted to outlast the dearest atom three
  casts running.
- ✅ **The `/arena` verb** (2026-09-21). `World._handle_arena_command`,
  routed beside `/spawn` and listed in `/help`
  (`test_world_arena_command.gd`, 10). Reuses `ConsoleSpecies.resolve` and
  `CreatureRenderer.spawn_single`, so the opposition is real creatures and
  the aliases are the ones `/spawn` already understands.
- ✅ **Verified in a running game**, not only in tests. A `--solo` launch
  with the command invoked live reported 3 staged wolves among the
  creatures in the world, a **48**-mana pool lent (the dearest atom's 8.0 ×
  six casts, for a character whose class gave them none) and **25** motes
  in the pouch — one for every atom in the catalogue.
- ✅ **The fight it stages really resolves** — `test_battle_loop.gd` (8),
  end to end with no mocks: a woven spell damages and eventually kills a
  real creature, the learned spell lands, and a real predator damages the
  player for its own profile's figure.
- ⬜ **Nothing here makes the ordinary game produce more encounters.** That
  is separate work: the roster in [monsters.md](monsters.md) is designed and
  unbuilt, and the motes a character can come by in normal play are still
  limited to the three phenomena with call sites. The arena works around
  both; it does not fix either.
