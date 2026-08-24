## World bosses: emergent apex predators

[evolution.md](evolution.md)'s fitness/rarity system already implies this —
formalizing it: the population/fitness simulation itself, not a scripted
spawner, occasionally produces a genuinely exceptional individual that
becomes a real world-boss-tier threat. See
[flora.md](flora.md#ancient-trees-emergent-legendary-flora) for the same
emergent-threshold pattern applied to flora instead of fauna — an ancient
tree is the non-combat, non-fauna equivalent of a world boss.

- **Emergent, not placed.** No hand-designed "boss room." An individual
  animal that has, through the ordinary sexual-selection/fitness sim
  ([evolution.md](evolution.md)), accumulated an extreme combination of
  fitness traits (age, size, combat stats, survived-many-generations
  lineage) crosses a threshold and becomes a named, unique, world-boss-tier
  creature — an ancient boar, an apex wolf that's outlived and outfought
  its whole pack. Monster Hunter apex / ARK Alpha energy, but the result of
  the same simulation that makes ordinary boars boars, not a separate
  system bolted on top.
- **Unique per world.** Because it's emergent from that world's actual
  population history, no two servers/save-files produce the same world
  boss at the same time or place — a genuinely unique, discoverable event
  rather than a fixed encounter every player eventually sees.
- **Real stakes both ways.** A world boss is both a major threat (very
  dangerous fight, real use for [combat.md](combat.md)'s tactical layers)
  and a major opportunity: best-in-slot [crafting.md](crafting.md)
  materials, and — per [pets.md](pets.md)'s DNA-sets-quality model — a
  tempting, high-risk taming target for a Beastmaster with the skill to
  attempt it, since a world boss's DNA is by definition exceptional.
  Killing it removes an extreme outlier from the breeding population
  ([evolution.md](evolution.md)'s phenotype-target drift applies here too:
  taking out the most-fit individual measurably affects the species going
  forward), taming it keeps that same genetic outlier in play as a
  companion instead.

### Encounter design: emergent stats + physics spectacle + prebaked authored phases

Resolves the open "special AI/behavior" question below with a specific
mechanism, decided in a 2026-07-16 brainstorm crossing this design against
WoW's raid-boss encounter language:

- **The fight is genuinely emergent, not scripted, at the base layer.** A
  world boss runs the exact same creature-AI and physics systems
  ([materials.md](materials.md)) as every other creature — its outlier stats
  (mass, speed, damage) just push those systems to extremes it alone reaches
  (shockwaves on impact, terrain cratering under its weight, momentum most
  creatures never generate). Nothing here is boss-specific code.
- **On top of that, one prebaked LLM authoring pass gives it real "encounter"
  texture.** The instant the fitness sim promotes an individual to
  world-boss status, an LLM is called **exactly once, offline** — never live
  during the fight, matching this project's NPC-planner architecture
  ([npc.md](npc.md): the LLM plans, an FSM executes with zero further calls)
  — with a natural-language description of that specific individual's
  emergent traits (species, size, age, lineage, temperament, notable
  mutations). It returns a small set of **telegraphed phase
  abilities/thresholds**, baked into that boss's data at promotion time. The
  result reads as a designed encounter (a real "phase 2 at 50% HP" moment)
  without a human ever hand-authoring it and without any inference cost
  during play.
- Net effect: three layers compose into one fight — real emergent stats,
  real emergent physics spectacle from those stats, and a thin authored-feeling
  telegraph layer generated once per unique boss. See
  [synthesis.md](synthesis.md) for how this mirrors the project's general
  "compose primitives, let simulation (or a one-shot LLM authoring pass)
  resolve the result" pattern.

### Era-gated bosses

A signature world boss can also gate an [era](eras.md) transition rather than
(or in addition to) a zone: defeating the right emergent apex individual is
one of the triggers that lets a reincarnating character (or, per
[eras.md](eras.md)'s open per-player/per-server question, the whole world)
advance to the next technological age. This keeps era transitions from being
a pure timer/milestone checklist — the last age's defining threat has to
actually fall first.

### Village endangerment: an attractor, not a spawner

Resolves the "server-wide visibility/tracking" open question below
(2026-08-13 design pass): a settlement's own net worth and population raise
the local odds this promotion threshold gets crossed nearby in the first
place — feeding as additional "opportunity biomass" into the same local
carrying-capacity term `predator_population_model.gd` already derives from
prey density, not a bespoke boss-seeks-village targeting system. Defender combat strength deliberately does not feed that
likelihood, only the outcome once a threat exists — a well-guarded
settlement isn't statistically punished for being well-guarded. Discovery
itself is both signaled (a real-time rumor from an endangered NPC's
need-threshold crossing, per [npc.md](npc.md)'s replan-interrupt
architecture, while the settlement's chunk is loaded) and sometimes purely
incidental (an unloaded settlement's whole threat-to-outcome arc can resolve
via catch-up simulation with zero warning). Full mechanism, including how
the quest itself is offered and what a settlement's success/failure
actually changes, in [quests.md](quests.md#village-endangerment-the-attractor-mechanism).

### Regional mythology: real-world folklore skins the emergent promotion

Real-world folklore gives a promoted individual a **regional identity** —
Fenrir in Scandinavia, a Kitsune in Japan — matched at promotion time by a
stricter "mythic tier" threshold and a species-affinity lookup against a
region's own curated roster, never a hand-placed fixed encounter (the
trigger stays the existing emergent promotion above; the myth names *what
kind of extraordinary thing this world's own population sim produced*, not
a thing waiting at fixed coordinates).

#### Why this doesn't repeat the "no manual per-country curation" rejection

[ecosystem_dynamics.md](ecosystem_dynamics.md#region-difficulty-gating-the-roster-by-player-readiness)
already rejected manually mapping real countries/cities to a *danger* tier,
for two specific reasons: (1) it asserts a real-world value claim about
actual places ("this country is dangerous") that has nothing to do with
this game's own sim, and (2) it doesn't scale — thousands of distinct
places, no natural stopping point. A folklore *identity* is a different
claim (creative/cultural flavor, not a danger ranking) and a differently
*shaped* problem — it maps onto a bounded set of **cultural/mythological
macro-regions** (a few dozen, not thousands of countries/cities), the same
shape [flora.md](flora.md#ancient-trees-emergent-legendary-flora)'s ancient
trees and this doc's own apex predators already use: **emergent and
discoverable, unique per world, never hand-placed.** A world's Kitsune is
still a specific fox that this specific world's population sim actually
produced — the myth names *what kind of extraordinary thing it turned out
to be*, not a fixed thing waiting at fixed coordinates.

#### Mechanism: a region classifier, a curated roster, a skin at promotion time

- **Real lat/lon already exists.** `GeoCoordinates`
  (`src/world/geo_coordinates.gd`, via `latitude_for_tile`/
  `longitude_for_tile`) already converts any tile to real-world
  coordinates — the same source `EarthChunkGenerator`'s climate model and
  the HUD's lat/lon readout already use. A new `MythicRegion` classifier
  (mirroring `BiomeClassifier`'s shape) maps that lat/lon into one of a
  bounded set of cultural/mythological macro-regions via a small,
  hand-curated table of coarse bounding boxes (some regions are
  non-contiguous — Polynesia is several island boxes, not one rectangle).
- **A curated roster, multiple entries per region.** A
  `MYTHIC_ROSTER_BY_REGION` table (mirroring the existing
  `HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME` shape):
  region name → array of `{name, species_affinity, domain, note}`. Multiple
  real folklore entries per region, not one flattened icon — see the
  starter roster below.
- **A second, stricter threshold, not a new trigger.** The existing
  `world_boss_fitness.gd` eligibility check is unchanged. A promoted
  individual additionally checks against a *stricter* "mythic tier"
  threshold; only individuals that clear it are eligible for a regional
  identity at all — most emergent world bosses stay flavor-generic ("an
  exceptional wolf"), and only the rarest, in a region with a matching
  roster entry, become "a Kitsune has emerged." This keeps the myth
  meaningful rather than routine.
- **Matched by species affinity, picked deterministically.** A mythic-tier
  individual's species narrows the region's roster to entries whose
  `species_affinity` fits (a promoted vulpine individual in the Japan
  region matches Kitsune, not Oni); the specific match among ties is
  chosen by hashing the individual's own seed/id, the same
  deterministic-not-RNG convention every other seeded system in this
  project already follows — same seed, same world, same myth, every time.
- **Feeds `trait_description`, no contract change.** The matched entry's
  folklore `note` is folded into the `trait_description` string already
  passed to `PhaseGenerator.generate_phases()` — the one-shot offline LLM
  call this doc already specs gets richer context (a real myth to draw
  telegraphed abilities from) with zero change to
  `world_boss_fitness.gd`'s existing, tested contract.
- **Phase abilities as spell-DSL compositions, not bespoke strings.** Per
  [magic.md](magic.md)'s atom catalog (physical/biological/perceptual/
  spatial domains), a myth-flavored phase ability should resolve to an
  actual DSL composition — Thor's storm-goat foes hit as `shock` + `push`
  atoms; a Kitsune's illusion hits as `illuminate` + `fear` + `ignite` —
  so a mythic boss's kit is a real, simulated force injection through the
  same primitives a player-crafted spell uses (Constraint layers 1-2 still
  govern how it resolves physically), not boss-specific scripted damage.
  The boss itself pays none of a player's mana/gold costs — it's authored
  once at promotion, not crafted by a player. (Krampus's own kit below is
  a concrete worked example of exactly this.)
- **Humanoid deities stay represented through their beast/monster lore,
  not as literal NPCs.** Thor himself isn't spawnable — there's no
  fitness/rarity concept for NPCs in this codebase, only for the animal
  population sim. His mythology is still represented through
  animal-form figures from the same tradition (Fenrir, Jörmungandr) that
  slot straight into the existing species-affinity match. Full humanoid
  mythic bosses (an NPC that "ascends") are a distinct, larger stretch
  goal — see open questions.

#### Starter roster (illustrative, not exhaustive)

A first pass across real, widely-documented folklore, biased toward
beast/monster-form figures so every entry has a natural `species_affinity`.
Each tagged with the [magic.md](magic.md) atom domain(s) its lore most
naturally maps to. Extending this list is an ongoing content task, not a
one-time completeness bar — the region set is what's bounded, not the
roster within it.

- **Japan** — Kitsune (nine-tailed fox spirit; perceptual/physical —
  illusion, fire), Tanuki (shapeshifting trickster; perceptual), Oni
  (ogre; physical — raw might).
- **Norse / Scandinavia** — Fenrir (giant wolf; physical), Jörmungandr
  (World Serpent; physical/spatial — coastal and aquatic regions), Nidhogg
  (root-gnawing dragon; biological — blight).
- **Germany / Central Europe** — distinct from Norse/Scandinavia above
  despite the shared Germanic root (its own folklore corpus): **Lindwurm**
  (a wingless, legless-or-two-legged serpentine dragon — heraldic and
  legendary across German-speaking lands, e.g. Klagenfurt's Lindwurm,
  visually distinct from a winged Western dragon; physical/biological —
  crushing coils, venom), **Rübezahl** (Riesengebirge mountain spirit,
  documented in his own folklore as shapeshifting into animal forms
  including a boar — represented here as a storm-wreathed giant boar
  rather than his humanoid form, per this section's beast-form-not-deity
  principle; physical/perceptual — storm winds, illusion), **Nix/
  Wasserfrau** (river and lake water spirit, often depicted fish-tailed;
  spatial/perceptual — drowning pull, alluring song), and **Krampus**
  (goat-horned chain-rattling companion of St. Nicholas, Alpine/Bavarian —
  Bavaria is part of Germany; physical/perceptual — chains, fear). All
  four are low-sensitivity register (widely documented folklore/heraldry,
  not tied to a living-worship tradition) per the content guideline below,
  and all four are currently reachable via the debug `/spawn <species>`
  console command (`illustrated_animal_sprite.gd`/`animal_anatomy.gd`/
  `creature_info.gd`) as a first, fightable slice — real, hand-authored
  stats, not yet produced by the emergent promotion pipeline above (see
  this doc's own Status section for that honest distinction). Krampus
  specifically has a full worked encounter — kit, aggro rules, attack
  art — below.
- **Greece / Mediterranean** — Hydra (regenerating many-headed serpent;
  biological — a natural fit for a real phase-reset mechanic), Nemean
  Lion (weapon-proof hide; physical — a real damage-mitigation mechanic),
  Cerberus (three-headed hound; physical).
- **Celtic / British Isles** — Cù Sìth (fairy hound; perceptual/physical),
  each-uisge / kelpie (shapeshifting water horse; spatial/perceptual —
  lures and drags into water).
- **Slavic / Eastern Europe** — Firebird (Zhar-ptitsa; perceptual — light,
  fire), Zmey (multi-headed dragon; physical/biological), Leshy (forest
  guardian; biological/spatial — roots, disorientation).
- **West Africa** — Anansi (spider trickster, literal animal form;
  perceptual — illusion, trickery).
- **East / Southern Africa** — Grootslang (elephant/serpent cryptid;
  physical), Chemosit (nocturnal hunter cryptid; perceptual — fear).
- **Egypt / North Africa** — Sphinx (riddling guardian; perceptual),
  Ammit (crocodile/lion/hippo composite; biological/physical).
- **Mesopotamia / Levant** — Anzu (storm-bird; physical/spatial), Mushussu
  (dragon-serpent; physical), Roc (giant bird, Arabian folklore; spatial).
- **South Asia** — Garuda (giant eagle; spatial/physical — extremely
  widely used in national/cultural iconography already), great serpent
  spirits of regional legend generically rather than one specific
  currently-worshipped deity (see content guideline below).
- **China** — Nian (New Year monster, folklore not worship; physical),
  Qilin (auspicious chimera; biological), the Four Symbols' beasts
  (directional dragon/tiger/phoenix/tortoise; any domain by which symbol).
- **Southeast Asia** — Barong (protective lion-spirit; physical/
  perceptual), Sigbin (blood-draining goat-like cryptid; biological).
- **Mesoamerica** — the feathered serpent of Aztec/Toltec/Maya legend
  generically rather than naming the deity directly (spatial/biological),
  Camazotz (bat-monster; physical), Chupacabra (modern cryptid folklore,
  lower-sensitivity register; biological).
- **Andes** — Amaru (two-headed serpent/dragon; physical/spatial), El
  Cuero (lake-monster cryptid; physical).

#### A content guideline, stated plainly rather than silently resolved

Not every real-world folklore figure sits at the same register. Ancient
Mediterranean/Norse/Egyptian myths and modern cryptids (chupacabra, El
Cuero) are widely adapted in global pop culture already and read as
low-risk creative reuse. Figures still tied to a **living, actively
practiced religion or a specific community's Dreaming/oral tradition**
(e.g. Wendigo in Anishinaabe/Algonquian tradition, Bunyip/Taniwha in
Aboriginal Australian/Māori tradition, actively-worshipped serpent deities
in some West African and South Asian traditions) sit differently — some
communities have specifically asked that these not be used as casual
commercial content. This doc names that distinction rather than picking a
side on every entry: default to the lower-sensitivity register above for a
first content pass, and treat anything closer to a living tradition as
"needs a sensitivity pass / community-sourced input before shipping," not
an outright exclusion.

### Krampus: a worked encounter (Germany region)

Resolves two open requests together — "bosses should not attack low-level
players on their own... only if they deal actual damage do they pull
aggro" and "scaffold his attack moves and behaviour" — using Krampus as
the concrete worked example the "Encounter design" section above always
needed. Both pieces are real, tested code, not just design prose.

#### Aggro: provoked, not proximity-triggered

Every other creature in this game reacts to the player purely by
proximity (`CreatureBehavior._will_fight`: aggressive + strong enough →
attack, on sight, unconditionally). A world boss needed to NOT do that —
Krampus one-shotting a level-1 player who wandered within sensing radius
reads as unfair, not as a boss fight. Resolved with a new, general
`is_world_boss` gate (`CreatureInfo.WORLD_BOSS_SPECIES`), not a
Krampus-specific hack, so every regional boss above gets it automatically:

- **A world boss perceives no threats at all — doesn't attack, doesn't
  flee either — until provoked.** `CreatureBehavior._perceives_threats`
  short-circuits the entire threat branch for an unaggroed boss, so it
  falls through to its ordinary hunger/thirst/wander behavior exactly like
  any other creature going about its day, oblivious to a nearby player.
  (A bare "skip only the attack branch" gate would have made an unaggroed
  boss *flee* a low-level player instead — worse, not better — hence a
  full perception gate rather than a narrower one.)
- **"Attacks" alone don't provoke it — only real damage does.** A weak
  hit against an unaggroed boss deals **zero damage and sets no state** —
  it bounces off entirely, as if it never happened, rather than merely
  being "not enough to anger it yet." `BossAggro.deals_real_damage` gates
  this: a hit must clear a threshold that's a **fraction of the boss's own
  max_health** (`MIN_DAMAGE_FRACTION_OF_MAX_HEALTH`, a first-pass
  placeholder pending real playtesting data) — not a flat number, and
  deliberately not a new player-level-vs-creature-level comparison system
  (nothing like that exists anywhere else in this codebase, and damage
  dealt is already the natural existing proxy for "how equipped/leveled is
  this attacker," since weapon tier and class/skill bonuses already feed
  the number). A tougher boss needs a bigger hit to register, automatically,
  with no per-boss tuning.
- **Once aggroed, it's aggroed for good and fights normally** — the same
  temperament/health-fraction rules as any other aggressive creature,
  `is_aggroed` is a permanent per-individual flag once set, and every
  subsequent hit (even a weak one) applies normally. No "de-aggro" is
  modeled; that's an open question below, not a decided no.

Real, tested: `src/gameplay/boss_aggro.gd`, `CreatureInfo.is_world_boss`/
`is_aggroed`, `CreatureBehavior._perceives_threats`,
`CreatureMarker.take_damage`'s boss-gating branch.

#### Kit: baseline + two escalating phases

Krampus's mythology — a goat-horned figure who drags a heavy chain and
punishes misbehaving children — maps directly onto real atoms already in
[magic.md](magic.md)'s catalog, per this doc's own "Encounter design"
principle that a boss's specials should be genuine force injections into
the shared sim, not bespoke scripted damage:

- **Chain Yank** (baseline, always available — not phase-gated: closing
  distance on a kiting player is a threat at any HP) — the `pull` atom.
  Drags a distant player in close; you cannot out-range Krampus forever.
- **Phase 2, at 50% HP — two abilities unlock together, not one:**
  **Chain Lash** (the `push` atom — a wide knockback swing, punishing
  melee crowding) and **Terrifying Roar** (the `fear` atom — the single
  most on-myth ability in the kit: the punisher of misbehaving children,
  making the player briefly flee against their own input).
- **Phase 3, at 20% HP — "The Reckoning":** **Chain Shackle** (the `root`
  atom) binds the player in place, opening them up for follow-up
  bare-handed strikes now that the chain itself is wrapped around the
  victim rather than swinging free.

This mirrors `WorldBossFitness.FakePhaseGenerator`'s own two-threshold
shape (0.5 / 0.2) deliberately — a hand-authored kit and a real, future
LLM-generated one are meant to be interchangeable to anything that reads
them. `BossPhase` (`src/gameplay/boss_phase.gd`) answers "which phase(s)
are active at this health fraction" from any `{hp_threshold, ability}`
array; `BossPhaseKits` (`src/gameplay/boss_phase_kits.gd`) is where
Krampus's kit above is actually written down, keyed by species so a future
regional boss's own hand-authored kit joins the same table. Both are pure,
tested lookups — **selecting** which ability should be active, not
**executing** one (see Status below for that real, honest gap).

#### Status

✅ Real and tested: the aggro gate (all four bullets above), `BossPhase`'s
phase-selection logic, and Krampus's specific 3-ability kit data in
`BossPhaseKits`.

⬜ Not built yet, the honest gap: nothing currently *executes* an
ability — applying `pull`/`push`/`fear`/`root`'s actual physics/status
effect to the player, on a cooldown, synced to a telegraph animation and
VFX. `BossPhase`/`BossPhaseKits` answer "what should be active"; nothing
yet asks them during a live fight or turns the answer into something that
actually happens to the player. This needs the spell-DSL runtime
(`docs/progress.md`'s Magic section — `spell_runtime`/`spell_compiler`
are themselves unbuilt) or, short of that, a narrower boss-only ability
executor as a smaller first step.

### Status

**The fitness/promotion math and the one-shot phase-authoring contract are
both real and built** (`src/gameplay/world_boss_fitness.gd`, pre-dating
this section): `fitness_score(level, kills, age_seconds)` (level ×10, each
kill ×5, age ×0.01/second — level and kills dominate at everyday scale,
age lets mere survival still climb toward boss tier), per-species
thresholds (predator 800, herbivore 400 — "becoming a boss should be rarer
for predators," per this doc's own words), and `attempt_promotion` (never
invokes the phase generator — the real, potentially-costly LLM call this
doc describes — for an ineligible individual). `PhaseGenerator`/
`FakePhaseGenerator` already mirror the exact "LLM plans once, offline,
never live" contract this doc's "Encounter design" section specifies,
matching `npc_planner.gd`'s own stubbed/fake-LLM testing convention.

**The emergence substrate (Emergence Phase 11) gave that pre-existing
mechanism a real causal identity on top, without changing its math**:
`EarthChunkManager.attempt_world_boss_promotion` wraps it and records a
real `world_boss_promoted` event (docs/emergence/05's own "Boss
emergence... must permanently affect the world," made concrete and
`/why`/`/boss`-inspectable); `defeat_world_boss` does the same for "Killing
a boss emits a major historical event." A `WorldBoss`/`WorldBossStore`
(mirrors `Institution`/`InstitutionStore`'s shape: active/defeated,
persisted, history kept after defeat) holds the promoted individual's real
score, threshold, and baked-in phases.

**No live gameplay trigger calls this yet.** This is the one real, honest
gap: nothing in this project currently tracks a creature's accumulated
kills or lifetime age — `CreatureInfo.level` is real but fixed at spawn
from the creature's own seed, not something that grows through play, so
there is no real per-individual data to attempt promotion FROM
automatically. The mechanism itself is real, tested, and ready to be
called the moment a real kill-counter/age-tracker exists on a creature —
matches Phase 4's own original, honestly-documented gap before Phase 5/6
gave it real data to work from. Territory effects, era-gating, village
endangerment (both explicitly depend on systems — quests.md's own
endangerment mechanism, the era system — that do not exist yet either),
taming a world boss, and the physics-spectacle combat layer are all
untouched by this slice.

### Open questions

- Exact cost/latency budget for the one-time promotion-triggered LLM call,
  and what the fallback behavior is if that call fails (a boss should never
  fail to spawn just because an API call did).
- What real per-individual signal should drive `attempt_world_boss_promotion`
  once one exists — a kill-counter and lifetime-age field added directly to
  the creature, most likely, but exact ownership/persistence isn't decided.
- The wealth→opportunity-biomass conversion (village endangerment, above)
  still needs its own numeric pass, separate from — and still open even
  though — the base fitness-threshold math is now resolved.
- Exact mythic-tier fitness threshold (stricter than
  `world_boss_fitness.gd`'s existing per-species threshold) — numeric
  design pass, same as every other threshold in this doc.
- Exact lat/lon boundary data per macro-region — coarse rectangles are a
  reasonable first pass; real (non-rectangular) boundaries are a later
  refinement, not a blocker.
- Should a region's *signature* myth specifically (rather than any
  mythic-tier promotion in that region) be what gates that region's
  [era](eras.md) transition, giving "Era-gated bosses" above a concrete
  regional flavor instead of an unnamed apex individual?
- Full humanoid mythic bosses (an NPC that "ascends" the way an animal
  does here) — needs an NPC-side fitness/rarity concept that doesn't
  exist yet; out of scope for this pass.
- Should non-fauna mythic identities exist too, matching
  [flora.md](flora.md)'s ancient-tree pattern (a region's legendary tree/
  spirit-of-place, not just its legendary beast)?
- Who actually reviews/extends the starter roster over time, and against
  what standard — the content guideline above names the axis but not a
  process.
- `BossAggro.MIN_DAMAGE_FRACTION_OF_MAX_HEALTH` is a first-pass placeholder
  (0.02) with no real playtesting data behind it yet — needs calibration
  once actual weapon-tier/level-scaling damage numbers exist to check it
  against.
- No "de-aggro" is modeled — `is_aggroed` is permanent once set. Is that
  actually right for a world boss (it reads correctly for Krampus — you
  don't get to un-anger him), or should a boss ever forget and reset,
  e.g. after enough time with no line of sight?
- Ability *execution* (see Krampus's own Status sub-section) is the real
  gap: does it want the full spell-DSL runtime once that exists, or a
  narrower boss-only executor built first as a smaller, sooner step?
- Should a player-dealt hit's provocation threshold also gate PvE loot/
  tame eligibility later (e.g. "did real damage" already gates aggro —
  does it also gate who's allowed to finish the kill, in a future
  multiplayer/tagging sense)? Not asked for; noting the seam exists.
