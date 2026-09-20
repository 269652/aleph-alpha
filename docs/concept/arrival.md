# Arrival — the first ten seconds of a new character

A new character opens their eyes on a random bank of a real river,
holding an axe, at whatever hour it happens to be in the room the player
is sitting in. Shown to a friend on a September evening, the game begins
in the dark, in the cold, with nothing said.

Measured in the 2026-09-20 diagnosis pass:

- **The sky is the wall clock.** `World._process` reads
  `Time.get_datetime_dict_from_system(true)` and drives
  `SolarPosition.elevation_degrees` from it at the spawn's real latitude
  and longitude (`scenes/world.gd`, the `utc`/`day_of_year`/`utc_hour`
  block). That is a genuinely good decision for a game set on the real
  Earth — and it means an evening demo is a night demo, with
  `SurvivalMeters`' *Cold* chip on within minutes.
- **Nothing greets the player.** A repo-wide grep for
  *tutorial* / *onboarding* / *welcome* / *objective* across `scenes/`
  and `src/` hits exactly two lines: a loading-screen joke
  (`loading_tips.gd:321`) and one NPC greeting
  (`npc_greeting.gd:22`). There is no first line of text in this game.

Everything below the surface is already there — a real river with a real
name, a real season, real settlements, real households that are really
short of real recipe inputs ([errands.md](errands.md)). None of it is
said out loud at the one moment a new player is listening.

This doc specifies that moment: the hour the eyes open, and the three
sentences that are true when they do.

## Design pillars

1. **First light is a gift to the character, not a lie about the
   planet.** The sun is where the real sun is; what the dawn clause moves
   is *which real hour the new character's clock starts on*. Within a few
   in-game days it is the real local hour again, exactly, and from then
   on this module changes nothing at all. A world that quietly ran on an
   invented clock forever would break the one promise
   [world.md](world.md) makes.
2. **The clock never jumps and never runs backwards.** Converging by
   snapping would put a visible lurch in the sky. The offset decays
   smoothly to zero, which means the in-game clock simply runs a little
   slow or a little fast for four in-game days — bounded, derived, and
   pinned (`MIN_CLOCK_RATE`).
3. **A brand-new character gets the dawn; a loaded save does not.** A
   save resumes a character who has been living in this world — their
   clock already agrees with the sun, and shifting it on load would be
   the lurch pillar 2 forbids. The clause is keyed to *arrival*, not to
   *session start*: `in_game_days_elapsed` is measured from character
   creation, so a save made on day 9 loads on day 9 and the function is
   the identity.
4. **Three facts, and not a fourth.** Where you are, what is near you,
   one thing to do. A tutorial with six bullet points is a tutorial
   nobody reads; the diagnosis was not that the player wanted a manual,
   it was that nothing said anything at all.
5. **Every line is read off real state or is not printed.** The river
   name comes from `SpawnRiverPicker`'s own pick, the season from
   `SeasonCycle`, the bearing from `Compass`, the errand from
   `Quest.production_shortfall_quests_for`. No village nearby means no
   bearing line — not "null", not a placeholder village. This is
   [wayfinding.md](wayfinding.md)'s "read real state, invent nothing",
   applied to prose.
6. **Pure, and therefore testable.** Both modules are `RefCounted`
   statics with no scene tree, no world, no file access, in the spirit of
   `spell_cost.gd`, `journey_ring.gd` and `errand_delivery.gd`. The
   caller hands in facts; they hand back an hour and three strings.

## Real-world grounding

**First light is civil dawn.** The astronomical definition is the moment
the sun's centre reaches 6° below the horizon: the point at which the
horizon is distinguishable and work outdoors is possible without
artificial light. That is the hour a person who slept outside actually
opens their eyes, and it is the hour this game starts a character on.

The number is derived, not chosen:

- On an equinox the sun rises at **06:00 local solar time at every
  latitude on Earth** — with declination at zero, sunrise is an hour
  angle of exactly −90°, which is six hours before solar noon wherever
  you stand. This is the one sunrise hour the whole planet agrees on, and
  `SolarPosition.elevation_degrees` reproduces it to within a hundredth
  of a degree.
- The sun climbs at Earth's own rotation rate, **15° per hour** — the
  same factor `SolarPosition` already multiplies hour angles by. Six
  degrees of that is 0.4 h, or 24 minutes: the length of civil twilight
  at the equator, and the shortest it is anywhere.

So `FIRST_LIGHT_HOUR = 6.0 − 6.0/15.0 = 5.6`, i.e. **05:36 local solar
time**, and the two inputs are checked against the repo's own astronomy
rather than asserted (`test_dawn_clause.gd`: the elevation at 06:00 on an
equinox is ~0° across a sweep of latitudes, and the elevation at
`FIRST_LIGHT_HOUR` at the equator is ~−6°).

The world's season clock supplies the other half of the derivation.
`SeasonCycle.SECONDS_PER_DAY` is **four real hours**, so one in-game day
*is* four real hours of play, and the two arguments of the clause are
coupled by that figure rather than by a guess.

**Distance is said in the map's own unit.** The surface is
`Lithology.KM_PER_TILE` = 1 km per tile (pinned to
`EarthChunkGenerator.TILES_PER_DEGREE`), which `journey_ring.gd` already
restates for the same reason a small pure module always does. A village
eleven tiles away is eleven kilometres away, and the briefing says
kilometres, because that is the unit the map is actually in. (The
underground's 1.426 m per tile is the *play* scale and is not this;
`journey_ring.gd`'s own doc comment already warns about the confusion.)

## Mechanism

### `DawnClause` — the hour the eyes open

`src/gameplay/dawn_clause.gd`.

```
local_hour_for(real_local_hour, in_game_days_elapsed) -> float
```

- **Day 0 returns `FIRST_LIGHT_HOUR` for every one of the 24 real
  hours.** Whatever the wall clock says, a new character wakes at 05:36.
- **The offset decays linearly to zero over `CONVERGENCE_DAYS`**, and on
  that day the function returns `real_local_hour` *exactly*, for every
  hour, and goes on doing so for ever after.
- The result is always in `[0, 24)`.

The offset is anchored to the hour the character *arrived*, not to the
hour it is now. That is the whole design, and the reason is measurable: a
clause that re-derives its offset from the current hour makes the clock
run **backwards** for an evening arrival. Spawn at 20:00 and the shortest
way to 05:36 is +9.6 h; an hour later the real hour is 21:00 and the same
shortest-arc rule wants +8.6 h, so the displayed clock advances by
1 h − 1 h × (decay) − 1 h and moves the wrong way. Anchoring instead
gives a constant catch-up rate:

```
offset(0)  = wrapped(FIRST_LIGHT_HOUR − arrival_hour) ∈ [−12, +12]
rate       = 1 − offset(0) / (REAL_HOURS_PER_IN_GAME_DAY × CONVERGENCE_DAYS)
```

The arrival hour is recovered from the two arguments by the coupling
above (`arrival = real_local_hour − 4 × days`, wrapped), so the required
two-argument signature holds; a caller that has persisted the real
arrival hour can pass it as the optional third argument and be exact
across a reload, where the coupling is only an approximation (the world
clock does not tick while the game is closed — `WorldClockPersistence` —
but the wall clock does).

**`CONVERGENCE_DAYS` is derived from that rate, not picked.** The worst
possible offset is half a clock face, `MAX_OFFSET_HOURS` = 12. Converging
over `MAX_OFFSET_HOURS / REAL_HOURS_PER_IN_GAME_DAY` = 3 in-game days
would make that worst case a rate of exactly **zero** — a sun nailed to
the horizon for twelve hours. One day more is the smallest whole number
that keeps the clock moving, and it leaves `MIN_CLOCK_RATE` = 0.25: at
worst, the first four in-game days run at quarter speed and the sky still
climbs. Both the stall and the floor are pinned by tests.

There is one discontinuity and it is unavoidable: a map from the clock
face to itself cannot be continuous in the real hour *and* constant on
day 0 *and* the identity on day 4 (the three demands differ in winding
number). It is placed in the **arrival hour** — two characters created
either side of 17:36 get opposite offsets — where no single player can
ever see it, because a given character has exactly one arrival hour. In
the dimension the player actually lives in, elapsed time, the clause is
continuous everywhere.

### `ArrivalBriefing` — the three facts

`src/gameplay/arrival_briefing.gd`.

```
briefing_for(facts) -> {place_line, bearing_line, errand_line}
```

A pure function of a plain `facts` dictionary — no world object, no
player, no market:

| key | source | missing → |
|---|---|---|
| `river_name` | `SpawnRiverPicker.pick`'s `"river"` | line without the river |
| `season` | `SeasonCycle.season_at` | line without the season |
| `player_tile` / `settlement_tile` | real tile coordinates | no bearing line |
| `settlement_name` | the settlement's own name | "A village lies…" |
| `errands` | `Quest.production_shortfall_quests_for`'s array, unchanged | no errand line |

- **`place_line`** — *"You are on the Loire, in spring."* River only, or
  season only, still reads as a sentence; neither and it is the empty
  string.
- **`bearing_line`** — *"Aubance lies about 12 km northeast."* Built from
  `bearing_word` and `distance_phrase`; an unnamed settlement is still
  worth a line ("A village lies…"), a settlement on the player's own tile
  is not.
- **`errand_line`** — *"In Aubance, a potter needs 3 clay."* One errand,
  phrased the way `ErrandDelivery` phrases one (`3 rock and 1 wood`,
  count first, ids spoken as words — *plant fibre*, never
  `plant_fibre`), so the briefing and the villager's own door agree.

**Salience, for a newcomer, is not the biggest crisis.** `salient_errand`
picks the shortfall with the **fewest total units missing** — the one
errand a player with an axe and no reputation can actually finish today —
with ties broken by settlement, household and recipe id so the same world
always gives the same first errand, whatever order the projection
happened to list its households in. A crisis nobody can answer is not a
thread of action.

**`bearing_word(from, to)`** returns one of the eight compass points as a
word, and is `Compass`'s reading rather than a second opinion: it is
`Compass.rough_reading(Compass.bearing_degrees(...))` mapped to a name,
pinned against `Compass` itself at all eight boundaries (22.5°, 67.5°, …
— which round *outward*, since `roundf` takes a half away from zero).
North is this world's +Y, the convention `compass.gd` already documents.

**`distance_phrase(tiles)`** speaks in the map's unit: under half a tile
is *"a few hundred metres"*, under a tile and a half is *"about a
kilometre"*, up to ten is *"about N km"*, and beyond that it rounds to
the nearest five so a briefing never claims to know a 43-kilometre walk
to the kilometre.

## What this does NOT fix

Named here so nobody reads the arrival moment as solved, and so each
becomes its own piece of work:

- **The art-cache warm** on first launch (reported at ~52 s in the
  overhaul brief; not re-measured here). The briefing is text handed to a
  HUD; it does nothing about how long the player waits before there is a
  HUD to hand it to.
- **The double intro.** The boot sequence still shows two introductory
  screens before play begins; the dawn clause runs after both.
- **The 25-chunk first load.** `EarthChunkManager.LOAD_RADIUS` is 2, so
  the first frame streams a five-by-five neighbourhood — 25 chunks —
  before the player can move.
- **Wiring.** Both modules are pure and nothing calls them yet. The hour
  has to be threaded through `World`'s `utc_hour` (via
  `SolarPosition.utc_hour_for_local`, the same door `/time` already uses,
  so the sun, the hillshade and the readout move together), and the three
  lines have to land in a real HUD card. That is the lead's wiring pass,
  and until it happens this doc describes a moment the player still does
  not get.

## Related docs

- [world.md](world.md) — the real-Earth clock the dawn clause borrows
  against and pays back.
- [seasons.md](seasons.md) — `SeasonCycle`'s four-real-hour day, the
  figure the convergence is derived from, and the season the place line
  names.
- [rivers.md](rivers.md) — the curated river a new character is put on,
  and the name the place line uses.
- [wayfinding.md](wayfinding.md) — `Compass`, north as +Y, and the
  "read real state, invent nothing" rule.
- [journey_rings.md](journey_rings.md) — the map scale the distance
  phrase speaks in, and the rings the first walk crosses.
- [errands.md](errands.md) — the shortfall the errand line names, and
  the verb that ends it.
- [quests.md](quests.md) — projections, never authored content: the
  briefing shows a shortage because there is one.
- [hud.md](hud.md) — where the three lines have to land, and the rule
  that a refusal is a sentence about the world.

## Status

- ✅ **First light reaches the sky** (2026-09-20). `World` records a new
  character's arrival (`_record_arrival_for_first_light`, on the NEW-game
  spawn only) and routes the local hour the sun is computed from through
  `DawnClause.local_hour_for`. Whatever hour a player presses New Game at,
  the first frame is first light; the real-Earth clock returns on its own
  by `CONVERGENCE_DAYS`, measured in real time because the sky is.

  Three properties hold by construction and are pinned
  (`test_world_first_light.gd`): a **loaded save is never shifted** (it
  records no arrival, so the clause is the identity and a save made on day
  9 loads on day 9 under the real sky); a console-pinned clock (`/time`,
  `/day`, `/night`) **wins outright**, because the shift is in the `else`
  of that branch; and once converged the arrival is cleared so the call
  stops being made at all.

  Deliberately **not persisted**: the shift exists for a first impression,
  and a character old enough to have been saved has already had one.
- ✅ **The three lines are on screen** (2026-09-20).
  `World._show_arrival_briefing`, last in `_spawn_local_singleplayer` and
  after `player.setup` (the bearing is measured from `current_tile()`,
  which needs the tile size setup hands it). Every fact is live: the river
  is `SpawnRiverPicker.pick`'s own `"river"` — kept in `_spawn_river_name`
  now, where before it was printed to stdout and thrown away — the season
  is `EarthChunkManager.current_season()`, the bearing is to the nearest
  settlement the event store really recorded a `settlement_founded` for,
  and the errand is `production_shortfall_quests_for_settlement` for that
  settlement. `ArrivalBriefing.card_text` joins the lines, closing up the
  missing ones rather than leaving blank rows, and nothing known at all
  raises no card. It is shown for `Answerback.seconds_to_read` of its own
  text and clears itself.

  Pinned by `test_world_arrival_card.gd` (11) and
  `test_arrival_briefing.gd`'s own card tests (26 total): a **loaded save
  is never greeted as a newcomer** — the wiring is on the NEW-game path
  only, the same rule pillar 3 states for the clock — the season comes
  from the world's own clock rather than a literal, the errand from the
  live projection rather than authored content, and a briefing that knows
  nothing produces no card.


- ✅ **`DawnClause`, the hour itself** (2026-09-20).
  `local_hour_for` / `offset_at_arrival` / `decay_fraction` /
  `offset_hours` / `clock_rate_for` / `arrival_hour_for`, pure and pinned
  by the properties they produce (`test_dawn_clause.gd`, 15 tests: first
  light checked against `SolarPosition` itself across a latitude sweep,
  all 24 real hours waking at first light on day 0, the real hour back
  exactly on day 4 and for ever after, monotone decay, the hour always a
  real clock face, and the two that stop a later session getting there by
  cheating — the clock never runs backwards, never stalls, and never
  changes pace mid-convergence).
- ✅ **`ArrivalBriefing`, the three sentences** (2026-09-20).
  `briefing_for` / `salient_errand` / `bearing_word` / `word_for_degrees`
  / `distance_phrase`, pure and pinned (`test_arrival_briefing.gd`, 22
  tests: every degree of the circle agreeing with `Compass`, the eight
  boundaries either side of the halfway point, the distance phrase's
  error bound swept to 120 km, the errand worded exactly as
  `ErrandDelivery` words it at the villager's door, the same first errand
  from any order the projection listed its households in, and a battery
  of half-empty and broken facts that must never reach a player as
  "null", a raw id or a fragment).
- ✅ **Both modules are wired** (2026-09-20). The sun is driven through
  `DawnClause` and the three lines reach a real HUD card — see the two
  "reaches the sky" / "on screen" entries above for what each one reads
  and what each is pinned by. The *Wiring* bullet under **What this does
  NOT fix** is out of date in that respect only; the boot-sequence items
  beside it still stand.
- ⬜ Boot-sequence work (art-cache warm, double intro, 25-chunk first
  load) is untouched and is separate work, as above.
