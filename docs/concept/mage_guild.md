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
4. **Rarity is the existing rarity, and a tradition's own floor is the
   other half of it.** How deep a master runs beyond their school's entry
   is decided by `rarity_tier.roll_tier` — the same weighted roll (common
   65% / uncommon 25% / rare 8% / legendary 2%) that already prices loot
   and gems, mapped onto the atom catalog's own tier band. **No new rarity
   numbers are introduced.** But a school with no shallow work floors every
   master who holds it (mechanism 2), and that gives two different kinds of
   rare: a *gateway* needs a wayfarer who happens to have rolled deep,
   while a *summoning* needs only a conjurer — of whom there are no shallow
   ones, and who are one master in ten to begin with. Rare by depth, or
   rare by tradition.
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
- `depth_for(seed)` → that rarity mapped onto the catalog's tier band
  (common → 1, uncommon → 2, rare and legendary → 3), **floored by the
  master's own school's entry depth**.

  That floor was measured rather than reasoned about
  (`tools/probe_mage_guild.gd`): without it an *Adept of Conjury* taught
  **nothing at all**, because conjury's only spell is depth 3 while a
  common master ran to depth 1 — and a guild of three such masters taught
  one spell between them. A master who cannot pass on a single thing is a
  person standing in a room for no reason.

  The fix is not a patch but the honest reading: **you cannot hold a
  tradition whose shallowest work is beyond you.** If you are of a school
  at all, you can teach its entry; what rarity buys is running *deeper*
  than that, which stays rare in every school with shallow work to be rare
  against. Nobody dabbles in calling things into being, so every conjurer
  is an Archmage of it — and *finding a conjurer at all* becomes the gate,
  which is its own kind of rare. `SpellSchools.entry_depth_of` reads that
  floor off the book rather than a table, so authoring a shallower spell
  into a school changes it for free.
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

- ✅ **Schools** — `spell_schools.gd`: ten traditions partitioning all 25
  atoms, exhaustive and disjoint, test-pinned both ways so a new atom
  cannot escape into no school. A spell's school is the one its atoms
  share (`""` when they cross, which is the intended cost of braiding two
  traditions); its depth is its deepest atom.
- ✅ **A book worth having a school in** — `spell_book.gd` grew from 3
  spells across 2 schools to 21 across all 10, laid out by tradition, with
  depth following the atom catalog's own tiers. Three spells would have
  made every master either everything or nothing.
- ✅ **A master is a seed** — `mage_master.gd`: school, depth, rarity,
  title, and a real `NpcIdentity` with a name, a genome, a personality, an
  appearance and a real allocation on the same skill web every other NPC
  and the player walk. `teaches()` is one rule (in my school, within my
  depth), never a list.
- ✅ **Every master can teach something** — depth is floored by their own
  school's entry (see mechanism 2). Found by probe, not by review: three
  masters used to share a guild that taught one spell between them.
- ✅ **A mage is a trade that arrives, not one a village produces** —
  `NpcIdentity.FORCED_ONLY_OCCUPATIONS`: forcible by a caller, never rolled
  by a seed, so no wizard turns up in a cottage with a field to stand at.
- ✅ **A guild fills over time and starts empty** — `mage_guild_roster.gd`
  + `EarthChunkManager.age_mage_guilds_in`. One persisted number per guild
  (days open) on the player-felt clock beside immigration, ageing per
  CHUNK rather than globally, because the settlement step runs once per
  settlement. Survives a chunk round trip.
- ✅ **You have to be inside, and somebody has to be home** —
  `SpellTuition`'s gate is `{inside, masters}`; `Player.guild_here()`
  reads the interior record it already carries for decorating. `OUTSIDE`
  and `NO_MASTER` refusals, the latter naming the school and depth to go
  looking for.
- ✅ **Several masters really stand around in there** —
  `HouseInteriorView.place_occupants` / `standing_cells`, spread through
  the room rather than queued by the door. The first of them is the room's
  `_resident`, so Talk and the indoor prompt keep working unchanged.
- ✅ **`/learn` names the people, not the building** — who is in residence,
  what each lesson costs, who gave the lesson you took.

### Known gaps, stated rather than papered over

- 🚧 **A master's DEPTH is not read off their skill web, though their
  identity is.** The honest version of "the teacher's skills decide what
  they teach" would read `spell_atom_tier` off the master's own
  `allocated_nodes` — the stat exists, on the mage wedge, on the exact
  graph the player walks. Three things stop it today, all of them real:
  `NpcSkillAllocation.MAX_POINTS` is pinned at exactly a ring-3 notable so
  no NPC ever reaches ring 4, the mage wedge's two `spell_atom_tier` nodes
  sit at rings 3 and 4, and `ARCHETYPE_STAT_POOL["mage"]` does not name
  that stat, so the allocator actively steers away from it. Every master
  would come out depth 1. Closing it means widening a point budget, adding
  a stat to a pool and threading a specialty override — three edits to
  tested systems for one derived number — so depth uses
  `rarity_tier.roll_tier` instead, which is an existing weighted roll
  rather than an invented one. **The divergence is recorded here rather
  than hidden, and the exact change that would close it is named above.**
- 🚧 **A guild's interior is still a cottage.** `InteriorTemplates` has no
  `hall` plan, so `hall`/`workshop`/`farmstead` all silently fall back to
  the cottage variants — a pre-existing gap this feature now makes
  visible, since the guild is the first hall a player will spend time in.
  The masters stand in a cottage.
- 🚧 **You cannot talk to a specific master.** Indoor Talk reaches the
  room's `_resident`, which is the first master; the others are scenery
  until the Talk verb learns about groups.
- 🚧 **Masters never leave, age, or die**, and a guild's roster only grows.
  A tradition lost when its last master dies is the obvious next
  mechanism, and the real-world grounding above already argues for it.
- 🚧 **A guild ages only while its chunk is loaded** — the same honest
  limitation `_step_village_immigration` already carries.
- ⬜ **No guild interaction UI.** `/learn` is the hand on it.

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
