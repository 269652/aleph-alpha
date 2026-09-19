# The Mage Guild: a house is not a teacher

Asked for directly: *"the player should have to enter into the mage guild and
find a master which teaches him. Building a mage guild still requires a mage
teacher to move in; the mage teacher's skills and teachable spells are in turn
based on the teacher's skills; so you might get a master proficient in fire
spells; there should be rare teachers which can teach special rare spells.
Multiple mages can move in and hang around inside of the mage guild."*

[settlement_charter.md](settlement_charter.md) gates the *building* behind a
city. [magic.md](magic.md)'s tuition section made the building teach. This doc
takes the teaching **off the building and puts it on the people inside it** —
which is the difference between a vending machine and a guild.

## Design pillars

1. **A building is a house, not a faculty.** Raising a mage guild builds
   somewhere for masters to be. It does not conjure masters. A newly raised
   guild teaches **nothing**, and that is not a bug or a delay timer — it is
   the point. A place earns its masters the way it earned its charter.
2. **Who came decides what can be learned.** A master's teachable set is
   derived from *their own proficiency*, never from a per-building table. Two
   cities with a guild each are not interchangeable: one has a pyromancer and
   a mender, the other a cryomancer, and the spells a player can learn differ
   accordingly. This is what makes a guild a **place worth travelling to**
   rather than a node to tick off.
3. **Proficiency is school plus depth, and both are derived.** A master knows
   one school of magic (a named set of atoms from
   `spell_atom_catalog.gd`) to a given depth (the atom catalog's own 1..3
   tier band). They teach exactly the spells every one of whose atoms is in
   their school and within their depth — no more, and no hand-authored
   "this master teaches these three spells" list anywhere.
4. **Rarity is the existing rarity.** A deep master is rare because
   `rarity_tier.roll_tier` says so — the same weighted roll (common 65% /
   uncommon 25% / rare 8% / legendary 2%) that already prices loot and gems.
   Mastery depth is that roll mapped onto the atom catalog's own tier band,
   so a tier-3 master (the only one who can teach a summoning or a gateway)
   turns up about one time in ten. **No new rarity numbers are introduced.**
5. **Masters accumulate; they do not spawn.** A guild fills over time, one
   master at a time, up to a real capacity — the same carry-the-fraction
   arrival idiom [village_estates.md](village_estates.md)'s immigration
   already uses, not a spawn table run once at construction. A guild that has
   stood for a year is a better guild than one raised last week.
6. **You go to them.** Tuition is refused unless the player is actually
   **inside** the guild with that master in residence. Standing outside is
   standing outside.
7. **No new tuned numbers where an existing one answers.** Schools are a
   partition of the atom catalog; depth is the catalog's own tier; rarity is
   `RarityTier`'s own roll; price stays `magic.md`'s derived tuition.

## Real-world grounding

A medieval guild hall was not a shop with a fixed catalogue. It was **the
place the masters of a trade happened to be**, and what you could learn in
one depended entirely on which masters that town had drawn and kept. A town
famous for its glaziers taught glazing; if the last master died or moved on,
that knowledge left with them. Apprenticeship was to a *person*, not to a
building, and the building's prestige was downstream of the people in it.

That is exactly pillar 1 and 2, and it is why a guild's roster — not its
existence — is the interesting object.

## Mechanism 1 — Schools: a partition of the atom catalog

`SpellSchools`, pure and static. `school -> [atom ids]`, covering **every**
atom in `spell_atom_catalog.gd` exactly once. Test-pinned in both directions
(exhaustive and disjoint), so a new atom cannot be added to the catalog
without being placed in a school — a master who could teach an atom nobody
owns would be a silent hole.

Ten schools, named for what they do rather than for the category field they
mostly follow, because a school is a *tradition* and the categories are a
cost-model grouping:

| school | atoms |
|---|---|
| pyromancy | `fire_damage`, `ignite` |
| cryomancy | `frost_damage`, `freeze`, `slow` |
| galvanism | `shock_damage`, `illuminate` |
| venefice | `poison_damage`, `blight` |
| mending | `minor_heal`, `major_heal`, `shield` |
| kinetics | `push`, `pull`, `root`, `gravity_shift` |
| wayfaring | `teleport`, `portal`, `reveal` |
| mentalism | `calm`, `fear` |
| vivimancy | `accelerate_growth`, `induce_mutation`, `suppress_mutation` |
| conjury | `summon_wisp` |

- `school_of(atom_id)` → the school, or `""` for an unknown atom.
- `school_of_spell(book, spell_id)` → the single school a spell belongs to,
  or `""` for a spell whose atoms **cross** schools. A cross-school spell has
  no single master who can teach it, which is a real and interesting
  category, not an error — see Open questions.
- `depth_of_spell(book, spell_id)` → the **highest** atom tier in the spell.
  A spell is exactly as deep as its deepest verb.

## Mechanism 2 — A master is a seed

`MageMaster`, pure and static: everything about a master is derived from one
integer seed, the same way `HeroDna`/`HeroAppearance` already derive a whole
character from one. Nothing is stored but the seed, so a master survives a
reload without a save format and cannot drift from the thing that generated
them.

- `school_for(seed)` → one of the ten, chosen by the seed.
- `rarity_for(seed)` → `RarityTier.roll_tier(seed)`, unchanged.
- `depth_for(seed)` → that rarity mapped onto the catalog's tier band:
  common → 1, uncommon → 2, rare and legendary → 3. A depth-3 master is
  therefore ~10% of masters, which is the rarity the existing roll already
  decided; this doc adds no weight of its own.
- `title_for(seed)` → the master's displayed name and style
  (*"Adept of Cryomancy"*, *"Archmage of Conjury"*), derived from school and
  depth so the readout can never disagree with the mechanics.
- `teaches(book, spell_id, seed)` → true when **every** atom of the spell is
  in this master's school and **every** atom's tier is within their depth.
  One rule; no list.

## Mechanism 3 — A guild fills with masters over time

`MageGuildRoster`, pure. **One persisted number per guild** — the days it has
stood open — and everything else is derived from it and the guild's own
existing `seed` (`place_building` already writes one into every building
record; no new identity is invented).

- `DAYS_PER_MASTER` — how long a guild waits for its next master. A
  **season** (`SeasonCycle.DAYS_PER_YEAR / 4`), the same unit
  `estate_ascension.gd` already uses for a dwell, rather than a new number:
  a master is a person deciding to move, and this game already measures
  those decisions in seasons.
- `CAPACITY` — how many masters one guild holds. **Three**, and the number is
  pinned by the claim it encodes rather than picked: a full guild must still
  be unable to teach every school, or pillar 2 collapses and every city's
  guild becomes interchangeable. Three against ten schools guarantees that,
  and is enough for "multiple mages hang around inside" to be true.
- `arrived_at(days_open)` → `min(CAPACITY, floor(days_open / DAYS_PER_MASTER))`.
  The fraction is carried by the stored float itself, so there is no separate
  carry to keep in step — and a guild fills whether or not anyone is there to
  watch.
- `master_seeds(guild_seed, days_open)` → the roster, a pure function of the
  two. **The first master of a guild is always that guild's first master**:
  a player who leaves and comes back finds the same people, with perhaps one
  more. Nothing is rolled at visit time.
- `teachers_for(book, spell_id, seeds)` → which masters present can teach a
  given spell, so a refusal can name what is missing rather than say no.

## Mechanism 4 — You have to be inside, and somebody has to be home

`magic.md`'s tuition gate was *"a mage guild is within reach"*. It becomes
*"you are **inside** a mage guild AND a master in residence there teaches
this spell"*.

The indoor half is not a new mechanism: `Player.is_indoors()` and
`_interior_building` (the `building_door_near` record, carrying the
building's `id`, `chunk_coord`, `origin_local` and `seed`) already exist for
[housing.md](housing.md)'s decorating, and the guild's identity for roster
purposes is that record's own `seed`. Standing on the doorstep is standing
outside.

Two refusals join `magic.md`'s three, and both teach:

- **`OUTSIDE`** — you are not inside a mage guild. Whether that is because
  you are in a field or on the guild's own doorstep, the answer is: go in.
- **`NO_MASTER`** — you are inside one, and nobody here teaches that.
  Carries the **school** the spell belongs to and the **depth** it needs, so
  the player leaves knowing what kind of master to go and look for. That is
  the sentence that turns a refusal into a reason to travel, which is the
  whole point of pillar 2.

An **empty** guild — newly raised, no master arrived yet — refuses with
`NO_MASTER` and an empty roster. Correct and deliberate: the building is not
the teacher.

## Status

(filled in as this is built)

## Interaction with other docs

- [magic.md](magic.md) — the tuition this gates, and the compile station the
  guild is.
- [settlement_charter.md](settlement_charter.md) — the gate on the building
  itself; this doc is the gate on what is inside it.
- [labor_skills.md](labor_skills.md) — its pillar 2, *"one shared mechanism
  for players and NPCs"*, is the same instinct; that doc deliberately
  **excludes** spell schools from its roster ("that power already lives in
  the PoE web"), which is why a master's proficiency is modelled here rather
  than as an eleventh labor skill.
- [npc.md](npc.md) — the villagers a guild's masters are drawn from.
