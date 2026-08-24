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

#### Player spillover (`DiseaseDebuff`, mirrors `VenomModel` exactly)

A `DiseaseDebuff` module shaped identically to the existing `VenomModel`
(`DEBUFF_ID`, `DURATION_SECONDS`, effect-per-stack), applied through the
SAME generic `DebuffStack.apply`/`advance`/`stacks_of` contract
`Player.active_venom_debuffs` already uses — a sick player is a real,
visible, ongoing cost (not fatal outright, a real tax: stamina regen,
attack strength, or similar), not a new debuff system built from scratch.

#### Feeds carrion (`CreatureMarker`)

A creature that dies of disease (population crash, or the SIRS model
simply losing the fight) spawns a real `Carcass`, going through the exact
same `_spawn_carcass_if_eligible` path a predation kill already uses — a
disease-driven die-off is itself a fresh source of carrion, closing the
loop rather than the two systems merely coexisting.

### Status

- ⬜ Not yet implemented — this is a compiled design spec from a
  brainstorming session, the deliverable of that conversation, not code.
- ⬜ Management tools (quarantine, deliberate culling of a sick tamed
  animal, a craft-able treatment/cure — a natural target for the wild-crop
  work in `wild_crops.md` to eventually feed, a real medicinal-plant
  angle) are explicitly out of scope for the first pass, by design (see
  pillars) — the interfaces above (a per-creature/player `DiseaseModel`
  state, a visible symptom readout) are shaped so bolting these on later
  doesn't require touching the transmission math itself.
- ⬜ Open question, not yet decided: does a recovering wild POPULATION
  (not just an individual) carry aggregate herd immunity across a
  region-level reload, the same way `carrion.md` deliberately left
  carcasses chunk-local/ephemeral — or does immunity, like everything else
  in the population-aggregate layer, reset on chunk unload? Worth
  resolving before implementation, not guessed at here.
- ⬜ Open question: exact numeric transmission/severity rates — this doc
  specifies the REAL SHAPE (SIRS, density-dependent, three real
  archetypes) but not the tuned constants themselves, which per this
  project's own rule need to be pinned by test at implementation time, not
  guessed at in a design doc.
