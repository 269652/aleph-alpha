# NPC Role Consensus: Theory of Mind, Not a Dice Roll

Reported directly: "as soon as they build a city hall the city hall should
compute demands and NPCs determine through a consensus mechanism who is
going to be in charge of e.g. wood. Then one player gets selected and he's
going to work in the sawmill." Follow-up: "use theory of mind algorithms."

This doc specs the full pipeline that request describes — a civic building
surfacing a real settlement need, villagers reaching a real social consensus
about who takes it on, and that villager actually going to work the
building — and is explicit about which piece of it this pass actually
builds versus which pieces stay honestly unimplemented. See "Status" at the
end. It does not replace anything: it is new synthesis across three
existing, currently-separate concept docs (their own gaps, not invented
here) —
[civic_construction.md](civic_construction.md)'s unbuilt Meeting Hall,
[timber_construction.md](timber_construction.md)/[npc.md](npc.md)'s named
but unbuilt "who becomes a Builder"/replan-interrupt reassignment gap, and
[governance.md](governance.md)'s explicitly NPC-decision-free aggregate
stat.

**Naming note**: [civic_construction.md](civic_construction.md)'s own
design-only civic-building concept is named "Meeting Hall"; this doc
treats "City Hall" as that same building, and the real, buildable id this
pass ships (`ItemCatalog`'s `"city_hall"`, real art at `assets/sprites/
buildings/city_hall.png`) uses the "City Hall" name directly — the two
names refer to one building, not two competing concepts.

## Design pillars

1. **A belief about someone else is only as good as how well you know
   them.** This is the actual content of "theory of mind" here, not a
   buzzword: an NPC's model of what ANOTHER npc wants is never a peek at
   that NPC's real internal state. It degrades toward an uninformative
   population-average prior the less the two have actually interacted,
   grounded in the same real familiarity/confidence-decay shape
   [dialogue.md](dialogue.md)'s recognition ladder and the memory/rumor
   system already use elsewhere — never omniscient, and never a flat
   coin-flip either.
2. **Consensus is what most people's models converge on, not a vote
   tally.** No NPC casts a ballot. Each candidate has a real self-preference
   (grounded in their own real DNA-derived personality, per
   `NpcGenome`/`NpcIdentity`); every OTHER candidate separately models what
   THAT candidate's preference probably is; the candidate whose own
   preference and the group's collective belief about them align highest
   is who the settlement converges on — the same "a role tends to go to
   whoever obviously wants it and is visibly known to want it" social
   dynamic real small communities actually show, not an authored dice roll.
3. **One shared reusable mechanism, not a wood-specific one.** The
   consensus function takes a role id and a candidate pool; it has no
   sawmill-specific logic. The Sägewerk/Farm case is its first real
   caller, not its only conceivable one — any future "settlement needs a
   volunteer for X" moment (a Builder, a Watchtower guard) is the same
   function with a different candidate pool.
4. **Reuse the existing demand machinery; do not fork it.** A City
   Hall's own "compute demands" step is not a new needs system — it is
   `NeedResolver`/`ConstructionPriority`'s already-real recipe-graph walk
   ([production_chains.md](production_chains.md)), read by a new civic
   building the same way `SettlementBuildDecision` already reads it. Where
   that walk still can't find an actionable real shortfall (the
   already-documented "essentially never finds one in live play yet" gap
   — see [timber_construction.md](timber_construction.md)'s own "What's
   honestly still a stand-in here" section), a City Hall inherits that same
   honest limitation rather than inventing a second, parallel needs
   computation to paper over it.
5. **Tuned values are tested functions, not eyeballed comments** — every
   trait weight below is illustrative, grounded in the real-world reasoning
   that produced it, and pinned by a calibration test, per this project's
   no-manual-tuning rule.

## Real-world grounding

- **Theory of mind, the actual cognitive-science term.** Humans routinely
  reason not just about what they themselves want, but about what OTHER
  people want and believe — and that second-order modeling is what lets a
  group informally converge on "obviously, Astrid should run the mill, she's
  been wanting a real trade to learn" without anyone holding a vote. Nobody
  has direct access to another person's actual mental state; the model is
  always inferred from observed behavior and history, and is more accurate
  for people you actually know well.
- **A stranger is modeled as average, not as unknown-therefore-zero.** A
  villager with no real history with a given candidate doesn't assume that
  candidate wants nothing — they fall back to "probably about as keen as
  anyone else," the same reasoning a real person uses about someone they've
  never spoken to. This grounds the population-average fallback below.
- **Willingness to take on demanding new communal work.** Someone who
  volunteers for a new, visible role tends to be bold enough to put
  themselves forward, motivated by what the role visibly earns them, and
  not so change-averse that leaving their routine feels threatening. This
  grounds the three real personality traits the self-preference formula
  below actually uses (of `NpcGenome`'s existing eight).
- **A civic building as a real, physical seat for a settlement's own
  decisions** — the same real-world grounding
  [civic_construction.md](civic_construction.md) already gives its Meeting
  Hall: a town doesn't compute its own needs and pick its own worker inside
  someone's head, it does so at a real, discoverable place other residents
  (and a curious player) can find.

## Mechanism

### NpcRoleConsensus: the pure theory-of-mind decision (this pass builds this)

A new pure-logic module, `src/emergence/npc_role_consensus.gd` (no engine
dependency, unit-testable headlessly, matching this project's "pure logic +
thin Node glue" split everywhere else):

```
static func decide(candidates: Array, familiarity: Dictionary) -> String
```

- `candidates`: `[{"id": String, "traits": Dictionary (trait_name -> float
  in [0,1], the SAME shape NpcGenome.traits already is)}, ...]`.
- `familiarity`: `observer_id -> {subject_id -> float in [0,1]}` — how well
  `observer_id` actually knows `subject_id`. Missing entries default to
  `0.0` (a total stranger) rather than erroring, the same
  fail-open-to-the-least-informed-case convention `NpcProduction.
  yield_per_second` already uses for a missing world accessor. Injected by
  the caller exactly like `NpcProduction.yield_per_second` takes a
  duck-typed `world` — this pass does not yet wire it to the real
  `MemoryStore`/`NpcEncounter` system (see "Open questions").

**Self-preference** (`self_preference(traits) -> float`): grounded in
three of `NpcGenome`'s existing eight traits (`bold`, `greedy`, `cautious`)
— weights sum to 1.0 so a uniformly-random genome's expected
self-preference is exactly 0.5, which is what makes 0.5 the mathematically
correct "average stranger" prior below, not an arbitrary round number:

```
self_preference := clamp(0.4*bold + 0.35*greedy + 0.25*(1.0 - cautious), 0, 1)
```

Real-world reasoning per trait: `bold` — willing to put yourself forward
for a new, visible role. `greedy` — motivated by what running a production
building visibly earns. `cautious`, inverted — the LESS change-averse
someone is, the more open to leaving their routine for a new job. The other
five traits (`friendly`, `gruff`, `curious`, `stoic`, `kind`) are
deliberately not in this pass's formula — see "Open questions" for why a
single shared formula rather than five is today's real scope.

**Believed preference** (`believed_preference(observer_id, subject_id,
subject_true_preference, familiarity) -> float`): the theory-of-mind step
itself — never the subject's real preference, always this lerp toward the
population-average prior:

```
believed := lerp(0.5, subject_true_preference, familiarity.get(observer_id, {}).get(subject_id, 0.0))
```

A total stranger (`familiarity == 0.0`) is modeled as exactly the
population average (`0.5`); a perfectly well-known neighbor
(`familiarity == 1.0`) is modeled with their real, true preference; anyone
between blends proportionally. This is the one formula in this doc that IS
"theory of mind" in the literal sense — it is a real, fallible model of
another mind, not a read of it.

**Consensus score** (`consensus_score(candidate_id, candidates,
familiarity) -> float`): the candidate's own self-preference, averaged
evenly with what every OTHER candidate's own theory-of-mind model believes
about them:

```
consensus_score := 0.5 * self_preference(candidate.traits)
    + 0.5 * mean_over_other_candidates(believed_preference(other.id, candidate.id, self_preference(candidate.traits), familiarity))
```

With zero other candidates, `consensus_score := self_preference(candidate.
traits)` (no one else exists to hold a belief about them).

**Decide**: the candidate with the highest `consensus_score` wins;
ties break by candidate id, ascending (deterministic, no
`RandomNumberGenerator`, the same discipline `tall_grass.gd`'s own hash-seed
convention already requires everywhere in this codebase).

### City Hall: a real civic building surfacing a real demand

**The demand computation itself is real and tested** (`src/emergence/
settlement_demand.gd`, `SettlementDemand.demands_for`): reads
`ConstructionPriority`/`NeedResolver`'s real recipe-graph walk (the SAME
one `SettlementBuildDecision` already calls, see pillar 4) over every real
recipe the book itself declares `requires_structure` for, and reports
every one currently blocked as a real demand — e.g. "beam"/"plank"
resolving `missing_structure_id == "sagewerk"` names the settlement's real
demand as a `wood` role. Where that walk still can't find an actionable
shortfall in today's real recipe book (see pillar 4's own honest
inheritance of that gap), `demands_for` simply returns an empty list — a
silent, discoverable absence, not an invented placeholder demand.

**Now wired**: `"city_hall"` is a real, buildable `ItemCatalog` placeable,
with real illustrated art (see `civic_construction.md`'s own
honestly-noted divergence — the simple single-tile path, not yet the
richer institution-formation-triggered multi-piece one that doc still
specs). `EarthChunkManager.city_hall_demands_near(global_x, global_y)`
returns `[]` when no real City Hall stands within
`CITY_HALL_DEMAND_RADIUS_TILES`, and otherwise calls `SettlementDemand.
demands_for` against the SAME real settlement state (`market.stock`,
`_present_structure_ids_for_settlement_chunk`)
`_apply_settlement_build_decision` already reads — a City Hall now
genuinely computes a real demand once built, not just in theory.

### Redirecting a real villager into the winning role (named follow-up, not this pass)

The genuinely hard, still-unspecified-in-detail piece: today, `_spawn_
lumberjack_for`/`_spawn_farmer_for` (`earth_chunk_manager.gd`) spawn a
fresh, anonymous, purpose-built Marker with no identity, no household, no
personality — "an NPC moves in" is a figure of speech today, not a real
named villager leaving their normal schedule. Making `NpcRoleConsensus`'s
winning candidate ACTUALLY be a real `NpcIdentity`/`NpcMarker` who then
works the sawmill needs the "replan-interrupt" architecture
[npc.md](npc.md)'s migration section and
[timber_construction.md](timber_construction.md)'s own "Builder is ad hoc"
section both already name as the right shape and both already confirm is
genuinely unimplemented (not even stubbed) anywhere in this codebase today
— see `docs/progress.md`'s own "Who becomes a Builder" gap note. This doc
does not attempt to build that architecture; `NpcRoleConsensus.decide`
returns a winning candidate id, and wiring that id to a real schedule
override is the concrete, scoped follow-up this doc's Status section names.

## Interaction with other docs

- **[civic_construction.md](civic_construction.md)** — this doc's City
  Hall section is the concrete "what happens once a Meeting Hall exists"
  payoff that doc's own Meeting Hall spec left unaddressed (it covers the
  building's construction trigger, not what it DOES once built).
- **[npc.md](npc.md)** — the replan-interrupt reassignment section above is
  the same mechanism that doc's migration section already names as the
  right shape for pulling an NPC out of its ordinary schedule; this doc
  does not build it, only names it as the concrete next real consumer for
  it, alongside Builder assignment.
- **[timber_construction.md](timber_construction.md)** — `NpcRoleConsensus`
  is a real, reusable answer to that doc's own still-open "who becomes a
  Builder?" question (settled there by design as "ad hoc, not a fixed
  occupation" — this doc's consensus mechanism is a real candidate for HOW
  that ad hoc pick gets made, once the replan-interrupt wiring above
  exists), not a competing mechanism.
- **[governance.md](governance.md)** — deliberately distinct: that doc's
  own pillar 1 is explicit that a settlement's governance FORM is inferred
  from history, never chosen by anyone. `NpcRoleConsensus` is the opposite
  kind of decision — a concrete, real choice about who does a specific
  job — and the two are not meant to merge into one mechanism.
- **[dialogue.md](dialogue.md)** / memory-and-rumor (`memory_record.gd`,
  `memory_store.gd`, `npc_encounter.gd`) — the real, tested source
  `familiarity` is meant to eventually read from (see "Open questions");
  this pass injects `familiarity` directly rather than wiring that read,
  the same "duck-typed dependency, wire the real source later" shape
  `NpcProduction.yield_per_second`'s own `world` parameter already
  established.

## Worked example

A settlement's Meeting Hall names a real "wood" demand. Three villagers are
idle: Astrid (bold 0.9, greedy 0.7, cautious 0.1 — self-preference ≈ 0.86),
Bram (bold 0.2, greedy 0.3, cautious 0.8 — self-preference ≈ 0.29), and
Corvin (bold 0.5, greedy 0.5, cautious 0.5 — self-preference = 0.5, exactly
the population average by construction). Astrid and Bram have worked
alongside each other for years (familiarity 0.9 both ways); Corvin is new
to the settlement and barely known to either (familiarity 0.1 both ways).
Astrid's real desire is highly visible to Bram (who correctly models her at
≈0.83, close to her true 0.86) but barely legible to Corvin (who,
barely knowing her, models her near the 0.5 average). Astrid's own
self-preference alone already leads the field, and what Bram — who
actually knows her — believes about her only reinforces it; she wins the
consensus, walks to the Sägewerk, and starts working it.

## Status

✅ `NpcRoleConsensus.decide` — the pure theory-of-mind consensus function
(self-preference, believed-preference, consensus score, deterministic
tie-break) — real and tested.

✅ `SettlementDemand.demands_for` — City Hall's own real "compute demands"
step, reusing `ConstructionPriority`/`NeedResolver` over every real
`requires_structure`-gated recipe in the book — real and tested (7/7),
including the real "wood" (sagewerk) case and the abstract "heat_source"
case, honestly reported rather than resolved.

✅ `city_hall` is a real, buildable `ItemCatalog` placeable with real
illustrated art, and `EarthChunkManager.city_hall_demands_near` gates
`SettlementDemand.demands_for` behind a real one standing nearby — real
and tested. See
`civic_construction.md`'s own honestly-noted divergence: this is the
simple single-tile buildable path, not yet that doc's richer
institution-formation-triggered multi-piece `CivicBlueprint` construction
— which stays a genuine, unbuilt follow-up.

⬜ Redirecting the winning candidate into an actual real `NpcIdentity`/
`NpcMarker` doing the job — blocked on the same not-yet-real
replan-interrupt architecture [npc.md](npc.md)/[timber_construction.md](timber_construction.md)
already named as unimplemented before this doc existed. `NpcRoleConsensus`
returns a winning id; nothing yet acts on it.

⬜ `familiarity` wired to the real `MemoryStore`/`NpcEncounter`
confidence/co-location system — injected directly for now (see "Open
questions").

⬜ Direct Builder mode (the player-facing half above): the real toggle,
the blueprint-placement ghost cursor, the per-step "Build (R)" action, and
generalizing self-build beyond the instant one-shot `craft()` path. None
of this pass builds any of it yet -- named here so a future session
building the toggle first (the smallest real slice, per this doc's own
"one building, two roles" section) has a real spec to build against
rather than starting from the raw player request again.

## One building, two roles: NPCs read it, the player enters it

Reported directly: *"Combine them... NPCs use it for consensus and the
Player get's the ANNO world building mode."* One real `city_hall`
structure, not two competing buildings sharing a name by accident (the
naming note at the top of this doc already establishes there is exactly
one) — NPCs read it for the consensus pipeline above; the player instead
ENTERS it, which is this doc's own new material.

**What "enter" means for a single-tile structure.** `city_hall` is a
one-tile placeable (`item_catalog.gd`, same shape as `campfire`/`furnace`/
`storage`/`sagewerk`), not a multi-piece enterable house — so "entering"
cannot mean walking through a door the way a `HouseBlueprint` house works.
It means standing within real interaction range of a real, standing
`city_hall` and triggering a real toggle, the same "near a real structure"
proximity check `BuilderMarker`/`LogisticsMarker` already use via
`EarthChunkManager.nearest_structure_position` — reused here, not
reinvented, for consistency with every other "near a structure" query in
this codebase.

**What the mode changes.** Toggling `Player.direct_builder_mode` on is the
real, minimal gate this pass ships: a boolean the player can be in or out
of, flipped only while genuinely near a real `city_hall`. Everything the
mode is FOR — a blueprint-placement cursor showing ghost footprints on the
map, a per-step "Build (R)" contextual action that spends real material
and takes real time (reusing `ConstructionLabor`/`ConstructionProject`'s
already-real labor-hours accumulation, the SAME field a hired
`BuilderMarker` already advances, so a player's own step and a hired
carpenter's own step credit the identical pool rather than two parallel
ledgers), and generalizing self-build beyond the instant, one-shot
`craft()` path `workforce.md` section 2 ships today — is real, named
scope this doc does NOT build in this pass. Shipping the gate real and
tested first, before the larger placement UI it unlocks, is this
project's own established shape for a first slice (see `workforce.md`'s
own "smallest possible instance of the general case" precedent).

**Reuses, does not fork**: the recipe/skill/material gates a blueprint
already enforces (`workforce.md` sections 1-3), the `ConstructionProject`/
`ConstructionProjectStore` ledger, and `ConstructionLabor`'s labor-hours
formula. Direct Builder mode is a NEW way to REACH those same real
mechanisms (a placement UI instead of typing a recipe id into
`/buildhouse`), never a second construction pipeline sitting beside them.

## Open questions

- **Wiring real familiarity.** The real, live source should be some
  function of `NpcEncounter.group_by_shared_landmark`'s own co-location
  history and `MemoryStore`'s confidence decay — but neither currently
  tracks "how well do these two specific NPCs know EACH OTHER" as a
  queryable pairwise number; both track events/gossip content instead. A
  real accumulation model (co-location count/recency -> a real familiarity
  score) is a genuine follow-up, not attempted here.
- **One shared formula versus per-role formulas.** Today's three-trait
  self-preference formula is deliberately generic ("willing to take on
  demanding new communal work"), not specific to running a sawmill versus,
  say, standing guard. A future pass giving each role its own trait
  weighting (a Watchtower guard formula favoring `stoic`/`gruff` over
  `greedy`, say) is a real, named extension, not required for this pass's
  own worked example.
- **What happens to a losing candidate's own visible desire.** Today's
  mechanism produces exactly one winner and no other observable effect —
  a real "Bram is visibly disappointed he didn't get picked" follow-on
  (feeding the real event/memory system this doc's pillar 1 already leans
  on) is a natural, unbuilt extension.
