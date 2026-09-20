# Discovery — what going out there records, pays and says

*Erkundung*, the fourth of the eight things the game was measured against
in the 2026-09-20 overhaul pass, and the last of them with no player-facing
half at all.

Underneath, the planet is already worth exploring: a real Earth streamed in
32-tile chunks, real biome banding, real rivers with real names, real
settlements founded by a real simulation, caves whose *shape* comes from
real speleogenesis ([underground.md](underground.md)), and a danger
gradient that really does decide which species may exist where
([journey_rings.md](journey_rings.md)). What is missing is everything that
would make a player *notice* any of it.

Measured before this doc existed:

- **Walking records nothing.** `EarthChunkManager.mark_chunk_explored` and
  `ExploredTiles` are real and tested; `MapProjection.landmarks_visible_on_
  map` and `/map` really read them. And a repo-wide grep for callers of
  `mark_chunk_explored` outside the manager and its tests finds **exactly
  one**: `Player._cast_reveal`, the `reveal` spell atom. Walk across a
  continent and the map stays empty, because nothing marks ground you have
  actually stood on. [wayfinding.md](wayfinding.md) names this as its own
  open gap ("nothing calls `mark_chunk_explored` from the player's actual
  movement path yet").
- **Going further pays nothing.** All three `Player.gain_experience`
  callers are a kill, a fruit harvest and a village sale. Distance from
  spawn appears in no XP formula anywhere. The far country is strictly more
  dangerous and strictly no more rewarding, which makes the whole ring
  gradient a tax.
- **Crossing a boundary says nothing.** `JourneyRing.crossing_between` was
  written for a card that does not exist; its own status list says so.

So the loop the friend asked for — go somewhere, find out something, come
back better for it — has a world, a risk gradient and a ledger, and no
connection between them. This doc specifies that connection.

## Design pillars

1. **Ground is recorded because you stood on it.** The explored set is a
   record of where the character's feet have been, not of what a spell
   revealed or what the streamer happened to load. `EarthChunkManager`
   streams a 5×5 neighbourhood around the player (`LOAD_RADIUS` 2) and the
   camera shows a fraction of one chunk; marking all 25 would be the map
   claiming knowledge the player never had. **One chunk per footfall: the
   one under the player.**
2. **The payoff is the ring's own price.** What a newly-walked chunk is
   worth is read off `JourneyRing.demands_at` — the packing list that ring
   already declares, already cumulative, already test-pinned. Ground that
   demands a weapon, warmth and a light pays more than ground that demands
   nothing, because the demands *are* the risk, stated by the module that
   owns the risk. No second difficulty model.
3. **Once, and only once, per chunk.** `ExploredTiles.mark_visited` is
   idempotent and returns true only on the first mark, so the reward cannot
   be farmed by pacing over a boundary. The total XP exploration can ever
   pay is bounded by how much of the planet the character has really
   walked.
4. **A crossing is news; a chunk is a receipt.** Crossing into a new ring
   raises a card that names the ring, says what is new and lethal there,
   and lists what it expects you to be carrying. An ordinary new chunk gets
   the floating receipt and nothing else — at walking speed a chunk edge
   arrives every ~13 s, and a banner at that rate teaches a player to stop
   reading banners ([feedback.md](feedback.md)'s own reasoning:
   an unread line is worse than a line not shown).
5. **It still cannot refuse entry.** `JourneyRing` deliberately exposes no
   `can_enter`, and this module adds none. The card is a warning, never a
   fence. Walking to the far country at hour one stays allowed; walking
   back is the part that isn't.
6. **Pure, and therefore testable.** `Discovery` is a `RefCounted` of
   static functions — no world, no player, no scene tree, no clock — in the
   spirit of `journey_ring.gd`, `errand_delivery.gd` and
   `arrival_briefing.gd`. It decides the whole step from three plain
   numbers and hands back what happened; the caller performs it.

## Real-world grounding, and where there deliberately is none

**The chunk is the unit of "somewhere else".** A chunk is
`EarthChunkManager.CHUNK_SIZE` = 32 tiles square. On the *map* scale that
is 32 km (`Lithology.KM_PER_TILE`, pinned to
`EarthChunkGenerator.TILES_PER_DEGREE`); at *play* scale it is 512 px, or
about 45 m of ground underfoot (`GroundSlide.PX_PER_METER`). This project
carries that scale fiction deliberately and `journey_ring.gd` documents it;
discovery speaks in neither, because "a chunk" is exactly the granularity
the explored-tiles record already has.

**The XP number has no real-world anchor, and is not pretended to have
one.** `EcologicalLiteracy` states the same thing for the same reason: a
game-balance XP figure is in the same category as `Player.XP_PER_KILL` and
`HEALTH_PER_LEVEL` themselves. So the anchor here is *internal consistency*
with the XP economy that already exists, and the number is **derived from
that anchor rather than chosen**:

```
DISCOVERY_XP_BASE  = EcologicalLiteracy.HARVEST_XP_BASE          (2)
FAR_COUNTRY_KILLS  = 2                       ← the one tuned number
XP_PER_DEMAND      = (XP_PER_KILL × FAR_COUNTRY_KILLS − DISCOVERY_XP_BASE)
                     ÷ demands_at(the outermost ring).size()
```

Read out: **first setting foot in a chunk of the hearth is worth what an
off-peak harvest is worth** (2 — "engaging a real system at all", which is
`EcologicalLiteracy`'s own words for its own baseline), and **first setting
foot in a chunk of the far country is worth exactly two level-1 kills**
(12) — the hardest ground on the planet, where bear, lion and venomous
snake are the only place they exist. Everything between falls out of the
ring's own packing list: 2 / 4 / 6 / 8 / 12 outward.

The division is exact for the real table and a test asserts that it is, so
a later retune of the ring demands fails loudly rather than silently
rounding the payoff away.

## Mechanism

### `Discovery` — pure, and the whole step

`src/gameplay/discovery.gd`.

```
report_for(from_distance, to_distance, is_new_ground) -> {
  "xp":         2,                    # 0 unless this chunk is newly walked
  "crossing":   { ...a JourneyRing ring... },   # {} unless a boundary was crossed
  "outward":    true,                 # which way across it
  "message":    "The Marches\n...",   # the crossing card, or ""
  "float_text": "New ground  +2 XP",  # the receipt, or ""
}
```

- **`chunk_of(tile)`** — the chunk a global tile sits in. The formula
  `Player._cast_reveal` open-codes, in one place, with `CHUNK_SIZE_TILES`
  held to `EarthChunkManager.CHUNK_SIZE` by test.
- **`xp_for_distance(distance)`** — the derivation above, read through
  `JourneyRing.demands_at`.
- **`demand_phrase(demand_id)`** — a `JourneyRing` demand id as a player
  reads it (`a_weapon_that_kills` → *a weapon that kills*), the same
  snake-case-to-words rule `ArrivalBriefing._spoken` and
  `ErrandDelivery._item_word` already apply. Pinned two-way against the
  real table, so a new demand cannot ship unreadable.
- **`packing_line(ring)`** — *"Carry: provisions, a weapon that kills."*,
  or the empty string for a ring that demands nothing.
- **`crossing_card(ring, outward)`** — three lines: *"You are entering the
  Marches."* (or *"You are back in the Commons."*), the ring's own
  `description`, and the packing line when it has one.
- **`report_for(...)`** — the whole step. `from_distance` of
  `NO_PREVIOUS_DISTANCE` (−1) is a character who has not moved yet and
  reports no crossing; a jump of several rings reports the ring actually
  landed in, exactly as `JourneyRing.crossing_between` decides.

Every one of those is a pure assertion a test makes before the module
exists, per this repo's `CLAUDE.md`. Every constant is either read from its
real source or test-pinned to it.

### The step, in `World`

`World._discovery_step(local_player)`, once per client frame, next to the
other per-frame reads of the local player:

1. `Discovery.chunk_of(local_player.current_tile())`. Unchanged since last
   frame → return immediately. A chunk edge is crossed every ~13 s of
   walking, so this is a `Vector2i` compare on all but a handful of frames.
2. `_chunk_manager.mark_chunk_explored(chunk)` — the real, live
   `ExploredTiles`, the same one `/map` and `MapProjection` read. Its
   return value **is** "this ground is new".
3. `JourneyRing.distance_chunks(chunk, _chunk_manager.spawn_chunk_coord())`
   — the same Chebyshev distance `RegionDifficulty` tiers by, from the same
   spawn the world set at `set_spawn_tile`.
4. `Discovery.report_for(...)` decides; `World` performs: `gain_experience`
   for the XP, `_float_answer_text` for the receipt (the same rising label
   every other act uses, see [feedback.md](feedback.md)), and the shared
   message stack for the crossing card.

`Player` is not touched. The explored record lives on the manager, the XP
on the player, and the decision in a pure module none of them own — the
same division `ConversationWindow`/`World`/`EarthChunkManager` keep for the
give verb.

### What the map now means

With walking marking ground, `/map`'s *"N chunk(s) explored"* and
`MapProjection.landmarks_visible_on_map` become a record of a real journey
rather than of whether a `reveal` was ever cast. The settlements a player
can see on their map are the settlements whose ground they actually walked
near — which is `wayfinding.md`'s design ("a Map is a pure, honest reader
of it — never a hint marker for something the player hasn't found") finally
reading something real.

## Interaction with other docs

- [journey_rings.md](journey_rings.md) — the rings, the demands and
  `crossing_between`. This is the caller its status list is missing, and
  the demands are the only difficulty input here.
- [wayfinding.md](wayfinding.md) — the Map, `ExploredTiles`, and the
  "nothing calls `mark_chunk_explored` from the player's movement path"
  gap this closes.
- [progression.md](progression.md) — XP from reading the world rather than
  fighting it; `EcologicalLiteracy` is the precedent and the baseline this
  anchors to.
- [feedback.md](feedback.md) — the floating receipt, the message stack, and
  the rule that decides a chunk gets a float and a crossing gets a card.
- [arrival.md](arrival.md) — the three sentences a new character opens on,
  raised by the same wiring pass.
- [exploration.md](exploration.md) — what is eventually out there to find
  (ruins, lairs, ancient groves). This doc is the act of going; that one is
  the destination.
- [survival.md](survival.md) / [ecosystem_dynamics.md](ecosystem_dynamics.md)
  — the cold and the species that make a ring's demands real rather than
  advisory.

## Status

- ⬜ `Discovery` pure module.
- ⬜ Walking marks ground explored.
- ⬜ New ground pays, once, at the ring's own price.
- ⬜ The crossing card.
