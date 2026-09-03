## Disease: the trophic pressure nothing has applied yet

Every creature in this world currently dies only two ways: predation, or
the player. Real wildlife populations are shaped by a third force just as
strong as either — disease — and this project already has everything
disease needs to be *real* rather than scripted: a live population-vs-
carrying-capacity model, a real proximity/contact substrate (grazing,
predation, courtship all already resolve off real distance checks), a
carcass that persists and rots (`carrion.md`), and a debuff-stack model
already proven on the player (`VenomModel`). This spec is a brainstorm
compiled into a build-ready doc, not yet implemented — see Status.

Born from a design session, not a bug report: *"further emergent
mechanics... genuinely novel gameplay"* — disease was picked as the
highest-leverage next system because it plugs into existing data
structures with no new spatial dimension, and it closes an honest,
already-documented gap.

### Design pillars

- **A real epidemiological model, not a scripted outbreak event.**
  Susceptible → Infected → Recovered(-immune) → Susceptible again as
  immunity wanes (SIRS) — the standard model real epidemiology uses,
  reused rather than invented. An outbreak starts and ends because the
  math crossed a threshold, the same "drive vs. reluctance" shape
  `EarthwormPatch.surface_drive` already uses for something else entirely.
- **Density-dependent, because that's how it really works.** A crowded,
  stressed population is a fire waiting for a spark — real wildlife
  epidemiology is fundamentally a function of population density against
  carrying capacity, which is a number this project already computes
  (`HerbivorePopulationModel.carrying_capacity`,
  `PredatorPopulationModel`'s own sibling). Disease reads that same number
  rather than adding a parallel one.
- **Three real, distinct diseases, not one generic stat.** Different
  pathogens spread differently and do different things — modeling that
  difference is where the real richness (and the "genuinely novel" ask)
  actually lives, not in a single "disease meter."
- **What you see is what's real**, this project's load-bearing pillar
  everywhere else: a sick animal visibly reads as sick. An outbreak is
  something a player *notices happening*, not a hidden dice roll.
- **Closes the loop on carrion, doesn't sit beside it.** A disease death
  is a real death — it spawns a real `Carcass` exactly like a predation
  kill, and the anthrax-like archetype below is *fed by* an unburied
  carcass in the first place. Disease and carrion are two ends of the same
  chain, not two unrelated systems that happen to ship in the same month.
- **Fills a real, already-named gap instead of inventing a parallel one.**
  `survival.md`'s Sickness & medicine section already names "a bite from a
  disease-carrying creature" as a sickness trigger and leaves wildlife
  contagion as an explicit open question — this spec answers exactly that,
  reusing the real `sickness.gd` pure model rather than building a second
  player-illness system beside it (see Player spillover below).
- **Observer this pass, management later, by design.** This spec is
  scoped to the emergent simulation and its real, passive risk to the
  player and tamed animals — quarantine/cull/treatment tools are a
  deliberately separate, later layer (see Status), but the interfaces
  below are shaped so adding them is a small addition, not a redesign
  (the same "shape the seam now" move `carrion.md`'s `take_bite` contract
  already made for predator scavenging).

### Real-world grounding: three named diseases, three real transmission modes

#### 1. Herd disease — foot-and-mouth-like (contact/proximity)

Real foot-and-mouth disease spreads through herbivore herds by direct
contact and shared grazing ground, is rarely fatal by itself, but leaves
an animal weakened — real epidemiology's "the disease doesn't kill you, it
makes you prey" dynamic. Modeled here as: proximity-based transmission
between herbivore-role creatures (the same real distance check
`GrazerForaging`/courtship already resolve off), mild-to-moderate
severity, and its actual bite is a *secondary* effect — an infected animal
moves slower / tires faster, measurably raising its own predation risk
rather than damaging it directly.

#### 2. Predator disease — rabies-like (bite/direct contact)

Real rabies transmits through a bite from an already-infected carrier and
is severe, low-spread, and famously zoonotic. Modeled here as: transmission
riding the *existing* attack-resolution path — `CreatureMarker`'s own bite/
strike (`_try_attack`/`take_damage`) rolls a transmission chance when the
attacker is infected, no new proximity system needed, it reuses the
attack that already happens. Severe once contracted (real, meaningful
lethality, not a flavor debuff). **This is the zoonotic spillover path**:
if the biting predator is infected and the target is the player, the
player can catch it too.

#### 3. Carrion disease — anthrax-like (environmental + insect-vector)

Real anthrax is a soil/carcass-borne disease, and its documented spread
mechanism is genuinely stranger and more apt for this project than most
people expect: blowflies and carrion beetles feeding on an infected
carcass mechanically carry spores to nearby vegetation, which grazing
herbivores then ingest. This project already has exactly that insect —
`DecomposerMarker`'s ants/carrion bugs from `carrion.md`. Modeled here as:
an unburied `Carcass` past its `ROT_SECONDS` threshold has a real chance
to be contaminated; a decomposer that feeds on a contaminated carcass has
a chance to carry it to the next carcass or patch of grass it visits,
infecting herbivores that graze there afterward. Severe, genuinely
population-crash-capable (real anthrax die-offs — e.g. documented
wildebeest/hippo mass mortality events — are not exaggeration), and the
**second player spillover path**: butchering a contaminated carcass
without care carries real infection risk, directly taxing today's
butchering interaction with a real consequence for skipping caution.

### Mechanism spec

#### The SIRS model (`DiseaseModel`, pure, per creature/player)

Four states per individual, per disease: **Susceptible** → (transmission
roll succeeds) → **Infected** (for a real duration, symptomatic, can
transmit) → **Recovered** (immune) → (immunity wanes over a longer real
duration) → back to **Susceptible**. Every duration/rate is a tested pure
function, per this project's no-eyeballed-constants rule, not a comment.

#### Transmission (per archetype, per the real mode above)

- **Herd**: `EarthChunkManager`-scale proximity check between an infected
  and a susceptible herbivore-role creature within the tick that already
  runs the ecosystem step — density-weighted (transmission chance scales
  with local population density ÷ carrying capacity, so a crowded region
  is measurably a tinderbox and a sparse one mostly isn't).
- **Predator**: rolled inside the existing attack resolution, the instant
  an infected predator's strike lands (on a creature OR the player).
- **Carrion**: rolled when a `Carcass` first crosses `is_rotten()`
  (contamination chance), then again when a `DecomposerMarker` calls
  `take_bite` on a contaminated carcass (carry chance), then again the
  next time that same decomposer feeds elsewhere or a herbivore grazes a
  contaminated patch.

#### Region pressure (`RegionDifficulty`)

Base transmission/contamination chance is scaled by
`RegionDifficulty.tier_at(chunk_coord, spawn_chunk_coord)` — HARD-tier
(further-out, real-biome-plausible-for-danger) regions run hotter disease
pressure than EASY ones near spawn, mirroring real tropical/dense-biome
disease burden and reusing a signal this project already computes for an
unrelated reason (creature difficulty gating) rather than adding a new one.

#### Visible symptoms

An infected creature gets a real, visible tell — reusing
`CreatureMarker`'s existing rendering hooks the same way a restrained
animal already reads differently (a droop/limp cue, not a new animation
system). A tamed/kept animal specifically gets the readout `taming.md`
already gives hunger and trust — a third pip/indicator on UI the player
already watches, so a sick animal you've invested trust in is legible the
instant it happens (the "connection/responsibility" feel this session's
brainstorm named directly).

#### Player spillover (routes through the EXISTING `Sickness` model, not a new debuff)

`docs/concept/survival.md`'s own "Sickness & medicine" section already
names **"a bite from a disease-carrying creature"** as one of four
sickness triggers, and `src/gameplay/sickness.gd` already exists as the
real, tested, pure model for it — `infection_chance`/`attempt_infect`
(exposure vs. resistance), `progress`/`is_recovered` (worsens untreated,
recovers under treatment), and `diagnose` (skill- and severity-weighted,
matching `Taming.break_free_chance`'s own shape). That doc explicitly
scoped OUT wildlife-to-wildlife contagion as "an undecided open
question" — this spec is exactly that missing piece, not a competing
system: the SIRS wildlife model above is the real exposure SOURCE, and an
infected predator's landed bite (or handling a contaminated carcass
unsafely) is what calls `Sickness.attempt_infect` — implemented as
`Player.apply_disease_bite`/`Player._sickness_step`. Once infected, the
player's illness is an ordinary `Sickness` case from there — same
severity/diagnosis/treatment loop `survival.md` already describes — not a
parallel `DiseaseDebuff` mirroring `VenomModel`. `VenomModel`/
`DebuffStack` remain exactly what they are (an instant-bite DOT), a
different real shape from a diagnosable, treatable sickness.

#### Feeds carrion (`CreatureMarker`)

A creature that dies of disease (population crash, or the SIRS model
simply losing the fight) spawns a real `Carcass`, going through the exact
same `_spawn_carcass_if_eligible` path a predation kill already uses — a
disease-driven die-off is itself a fresh source of carrion, closing the
loop rather than the two systems merely coexisting.

### Status

- ✅ **The core SIRS model** (medium) — Done —
  `src/gameplay/disease_model.gd` (`DiseaseModel`), pure and fully tested
  (`tests/unit/test_disease_model.gd`, 27 tests): the full
  Susceptible→Infected→Recovered→Susceptible-again cycle
  (`advance_state`), all three archetypes' transmission-chance formulas
  (`herd_transmission_chance` density-weighted against real population ÷
  real carrying capacity, `predator_bite_transmission_chance`,
  `carcass_contamination_chance`/`decomposer_carry_chance`/
  `carrion_graze_transmission_chance`), region-pressure scaling
  (`region_pressure_multiplier`, keyed off `RegionDifficulty.Tier`), herd
  disease's real "makes you prey, not dead" secondary effect
  (`movement_speed_multiplier`), and per-archetype lethality
  (`is_lethal_capable`/`death_chance_per_second` — herd never kills
  directly, predator/carrion do). Deterministic hash-seeded rolls
  (`attempt_transmit`/`attempt_infect`), same pattern as `Sickness`/
  `Taming`.
- ✅ **Herd (foot-and-mouth-like)** (medium) — Done —
  `CreatureMarker._herd_disease_step`: runs on the existing throttled
  sensing tick, checks the nearest susceptible herbivore-role creature
  within sense range against real region population/capacity (new
  `EarthChunkManager.herbivore_capacity_at_chunk`/`herbivore_capacity_near`,
  mirroring the existing `herbivore_population_at_chunk`/`_near` pair).
  The real "moves slower / easier prey" secondary effect is wired into
  `CreatureMarker._advance` itself (`DiseaseModel.movement_speed_
  multiplier`) — the one choke point every intent's movement (wander,
  flee, seek, hunt, attack) already funnels through via `_advance_gated`/
  `_advance_avoided`, so a single multiplier there covers all of them.
- ✅ **Predator (rabies-like)** (small) — Done —
  `CreatureMarker._try_transmit_predator_disease`, riding the exact same
  bite `_try_attack` already resolves, mirroring `VENOMOUS_SPECIES`'s call
  shape exactly (`target.has_method("apply_disease_bite")`). Works
  identically whether the target is another creature or the player — the
  zoonotic spillover path is just this same duck-typed call landing on a
  `Player` instead.
- ✅ **Carrion (anthrax-like)** (medium) — Done — `Carcass` rolls
  `contaminated` once, the instant it first crosses `is_rotten()`
  (`region_tier`/`contaminated` fields, `_roll_contamination`).
  `DecomposerMarker` is the real insect carry-vector: picks up
  `carrying_disease` biting a contaminated carcass, spreads it to the next
  clean carcass it feeds on (`_step_disease_carry`). A nearby susceptible
  herbivore risks exposure grazing near a contaminated carcass
  (`CreatureMarker._carrion_disease_step`) — simplified to direct
  proximity to the carcass itself rather than a separately-tracked
  "contaminated patch of grass" object, which this project has no
  substrate for today (a documented simplification of the doc's literal
  insect→grass→herbivore chain, not the full three-hop version).
- ✅ **Visible symptoms** (small) — Done — `CreatureMarker` tints itself
  (`Sprite2D.modulate`) while `INFECTED`, on every creature, wild or tame,
  reusing the engine's own built-in property rather than a new rendering
  system. A tamed/kept animal additionally gets a third "sick" pip beside
  the existing hunger/trust readouts (`docs/concept/taming.md`), shown
  only while it's already "in the loop" with the player.
- ✅ **Player spillover** (medium) — Done — `Player.apply_disease_bite`/
  `_sickness_step`, routed entirely through the existing `Sickness` pure
  model (`src/gameplay/sickness.gd`) exactly as this doc specifies — NOT a
  `VenomModel`/`DebuffStack`-style module. Both spillover paths wired: a
  predator's bite (via `_try_transmit_predator_disease` above) and
  careless butchering of a contaminated carcass
  (`Player._butcher_step`). Untreated severity is a real, ongoing stamina
  tax (`SICKNESS_STAMINA_DRAIN_PER_SECOND`), never fatal outright, and —
  since no cure/treatment tool exists yet (see the management-tools cut
  below) — never naturally recovers either; that's `Sickness.progress`'s
  own existing, already-documented behavior, not a new gap this system
  introduced.
- ✅ **Feeds carrion** (small) — Done — a lethal disease death routes
  through a new shared `CreatureMarker._die()` (factored out of
  `take_damage`'s existing death branch), so it spawns a real `Carcass`
  through the EXACT same path a predation kill already uses, not a
  parallel one.
- ⬜ Management tools (quarantine, deliberate culling of a sick tamed
  animal, a craft-able treatment/cure — a natural target for the wild-crop
  work in `wild_crops.md` to eventually feed, a real medicinal-plant
  angle) remain explicitly out of scope, by design (see pillars) — the
  interfaces above (`DiseaseModel` state, `Sickness.diagnose`, the visible
  symptom readouts) are shaped so bolting these on later doesn't require
  touching the transmission math itself.
- ⬜ Resolved (diverging slightly from the open question as posed):
  immunity/SIRS state lives on the individual `CreatureMarker` in memory,
  the same as every other per-creature field here — it resets when that
  marker despawns/the chunk unloads, exactly like `carrion.md`'s own
  carcasses. There is no separate AGGREGATE population-level herd-immunity
  number layered on top of `EcosystemSimulation` — that would be a real,
  separate addition this pass didn't build, not an oversight.
- ⬜ Numeric transmission/severity/lethality rates are now real, tuned,
  test-pinned constants in `DiseaseModel` (see `test_disease_model.gd`),
  not the open question this doc used to pose — but they are first-pass
  numbers chosen to be internally consistent (e.g. region pressure at
  `HARD` deliberately saturates several chances to certain, for
  determinism and because "the most dangerous regions are a real hazard"
  is the intended shape) rather than balance-tested against real
  moment-to-moment play. Expect these to move once the system is actually
  played against.
