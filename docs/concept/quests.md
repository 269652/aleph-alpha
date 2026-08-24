# Quests

This doc specifies how quests come to exist at all — resolving
[overview.md](overview.md#open-questions-to-resolve-during-mvp-work-not-blocking-day-1)'s
open "quest template design" question (2026-08-13 design pass). It does not
introduce a quest-giver system; it specifies the mechanism by which
[npc.md](npc.md#ai-native-npcs)'s existing claim — "NPCs generate requests
from their actual current needs... rather than a fixed quest-giver script" —
actually produces the shapes a player recognizes as quests, including when
several NPCs' needs merge into one settlement-level offer, and how a
village's own wealth/population can put it in genuine danger, closing the
loop back into [exploration.md](exploration.md)'s ruins when that danger
isn't answered.

## Design pillars

1. **Quests are a byproduct of simulation state, never authored content.**
   Every quest in this doc already has to exist as a real need/threat/shortage
   in the simulation before it can be offered — matching
   [synthesis.md](synthesis.md)'s "compose primitives, let simulation resolve
   the result" pattern applied to narrative instead of physics.
2. **Individual by default; settlement-level only by real consensus.** A
   quest starts as one NPC's need. It only promotes to a settlement-wide
   offer when enough *other* NPCs independently have the literal same need,
   never as a separate authoring layer bolted on top.
3. **Real stakes in both directions.** A quest can be ignored, arrive too
   late to matter, or be actively lost — and losing has a lasting, legible
   world consequence, not a quest-log entry silently expiring.
4. **Reuse existing mechanism seams before inventing new ones.** Every
   mechanism below is deliberately built out of a system this project has
   already committed to elsewhere (the replan-interrupt architecture,
   predator carrying capacity, the loaded/unloaded simulation-fidelity
   split) rather than a bespoke quest engine.

## Need sources

[npc.md](npc.md#ai-native-npcs) already gives every NPC "a driving
need/goal." Quests are just what happens when that need becomes
player-actionable. Three sources cover the MVP set:

- **Safety** — a threat is present (a [world boss](worldbosses.md), a rival,
  a disaster). See [Village endangerment](#village-endangerment-the-attractor-mechanism)
  below.
- **Production** — a crafting/farming NPC is short a recipe input they can't
  source themselves. See [Supply and demand](#supply-and-demand-quests).
- **Social** — deliver a message, escort, reconcile a relationship. Lightest
  touch of the three for now; same underlying mechanism, deferred detailed
  design until the first two are proven.

These are need *sources*, not quest *shapes* — the classic
fetch/protect/deliver template list from `overview.md` still describes the
shape a need resolves into; a safety need typically resolves as
protect/join-the-defense, a production need as fetch/deliver.

## Individual vs. settlement-level quests

Default is individual: the NPC with the need offers the quest directly,
exactly as `npc.md` already specifies, and its reward/consequence writes
only into that NPC's own relationship/memory state.

**Promotion rule.** When multiple NPCs in the same settlement carry a need
matching the exact same `(template, target)` pair — three villagers scared
of the *same* boar, not three villagers each wanting iron for unrelated
personal reasons — the individual offers are withdrawn and replaced by one
settlement-level quest. Matching is strict (same target only, no
fuzzy/thematic merging): three NPCs independently needing iron for three
different reasons stay three separate quests. This keeps the merge
predictable and keeps genuinely personal quests from getting flattened into
generic village busywork.

**Quorum.** A need needs `max(2, ceil(population × threshold_fraction))`
independent NPCs sharing it before it promotes, `threshold_fraction` a
tuned, test-pinned constant (starting guess 0.25–0.3, refined once real
villages exist to playtest against). The floor of 2 matters more than the
fraction at small population — a single corroborating NPC is what turns "one
villager's fear" into "an established village-level fact," at any settlement
size.

**Representative.** The settlement-level quest is offered by its highest
social-influence NPC — its de facto mayor. This is a deliberate reuse, not a
new concept: it's the exact weighting
[factions.md](factions.md#open-questions) already needed for its own
unresolved reputation-aggregation question ("the blacksmith's opinion
matters more than a random farmer's?"). One score answers both — no
separate "who's the mayor" system, no hand-placed leader role.

**Reward split.** Individual-quest rewards stay scoped to that one NPC's
relationship/memory. Settlement-quest rewards apply at the settlement level:
see [Consequences](#consequences).

## Village endangerment: the attractor mechanism

Resolves `worldbosses.md`'s open "does a village get any signal, or is
discovery purely incidental" question, and extends
[building.md](building.md#base-defense-diegetic-threat-not-scripted-raid-waves)'s
diegetic-threat philosophy — written there for the player's own homestead —
to NPC villages generally. A settlement's danger is causally grounded, not a
difficulty dial, either way.

**What raises the risk.** A settlement's net worth and population — stored
wealth, livestock, tamed/bred creatures, total NPC+player headcount — feed
into the same local carrying-capacity term `predator_population_model.gd`
already derives from prey/herbivore density, as additional "opportunity
biomass." A rich, populous, heavily-ranched settlement literally raises the
local odds [evolution.md](evolution.md)'s fitness sim crosses the
world-boss threshold nearby. No bespoke boss-targeting AI — the risk falls
out of a carrying-capacity model this project already has.

**What doesn't.** Combat strength (defenders' gear, NPC/player fitness)
deliberately does *not* feed that frequency term. Only wealth/population do.
If defense strength raised danger too, building up a settlement's defenses
would be self-defeating — a settlement should never be *statistically*
punished for being well-guarded. Strength instead determines
[outcome](#resolution-warning-surprise-and-autonomous-defense), not
incidence: a strong settlement faces the same odds of a threat appearing as
a weak one of equal wealth, it's just far more likely to survive the
encounter.

## Resolution: warning, surprise, and autonomous defense

Reuses [world.md](world.md)'s existing loaded/unloaded simulation-fidelity
split rather than a separate warning system:

- **Loaded chunk** (player nearby, whether or not they triggered the
  encounter): the threat is real-time. Individual NPC need-threshold
  crossings (the same interrupt that already triggers an out-of-cycle
  replan per `npc.md`) create the underlying threat awareness; once a
  nearby NPC's own memory of it
  ([npc.md](npc.md#memory-beliefs-and-rumor-propagation)) crosses a
  confidence/salience threshold, it surfaces as a visible rumor/quest offer
  before the attack lands — genuinely preventable, and no longer a hand-wave:
  the rumor *is* a real memory record, not a scripted trigger. Combat, when
  it happens, runs in real time
  between the settlement's defenders — *any* NPC with combat-capable
  build, not a dedicated guard/militia occupation, keeping every villager's
  self-determination intact — and the threat, using the same
  [combat.md](combat.md) system creatures and players already use. A player
  can walk into an already-started fight and reinforce it — **"join the
  defense"** is a first-class quest shape alongside solo protect/kill, not a
  fallback. There's no distinction in how the fight itself plays out between
  a player-triggered encounter and one the player simply wandered into —
  it's the same fight either way.
- **Unloaded chunk**: the catch-up-simulation pass (the same class of
  mechanism as `chunk_ecology_catchup.gd`) resolves the entire
  threat-to-outcome arc off-screen between visits, aggregate defender
  strength vs. threat stats deciding win/loss/damage in one step. A
  well-defended settlement can genuinely repel a threat with zero player
  involvement; a weak one can just as genuinely fall — both while the player
  is elsewhere. A player can return to find nothing happened, a village that
  successfully defended itself, or a fresh ruin, with no warning in the
  last case.

## Consequences

**Success** — settlement reputation rises (the aggregate `factions.md`
already models — no separate quest-specific reputation number), shop prices
soften (`economy.md`), and skill rewards become available: a grateful
crafter teaching or discounting a `skills.md` web node fits its existing
"trainer-NPC-mediated" precedent better than inventing a new reward
currency.

**Failure** — a settlement that loses can be genuinely destroyed, becoming
one of `exploration.md`'s abandoned-settlement ruins. The quest's own
history — who was warned, who tried, what failed — is exactly the kind of
"logged fragment of what happened to its NPCs" that doc already wants
discoverable there.

## Supply and demand quests

A crafting or farming NPC short a recipe input they can't source themselves
is a need exactly like a safety need — same promotion/quorum/representative
machinery above applies unchanged, just sourced from `economy.md`/
`crafting.md` production state instead of a threat. This is genuinely no new
mechanism, just a new need source, and it closes a loop `economy.md`
already half-describes: currency enters via market sales *or* quest/bounty
rewards as two separate faucets; a production quest is the point where
those two faucets are the same transaction — the NPC pays roughly what
they'd have paid the market, plus a relationship premium, for you to skip
the market and hand the input to them directly.

## Settlement growth: migration and player-founded villages

The third piece — what makes an NPC actually move into a player-built
structure cluster — extends [npc.md](npc.md#lifecycle-villagers-age-reproduce-and-die)'s
lifecycle section (villages already "genuinely dwindle or die out" there;
this is the growth half of the same population dynamic) rather than living
here as a separate system, but is specified in this doc because it's what
makes a player-founded settlement eligible for everything above.

**Habitability as a migration pull.** `world.md`'s core pillar —
"population exists wherever conditions make it viable" — already applies to
NPC villages in general per `npc.md`'s lifecycle section. This extends the
habitability signal itself: a roofed, player-built structure is free
shelter a settling NPC doesn't have to build themselves, and specialty
infrastructure (a forge, a dock, a farm plot) is a specific pull for a
specific occupation-need — directly compounding with
[Supply and demand](#supply-and-demand-quests) above: an underserved trade
nearby makes that occupation's pull stronger still.

**Push.** The same replan-interrupt architecture `npc.md` already specifies
(a need crossing a critical threshold triggers an out-of-cycle LLM replan)
gets one more possible resolution: relocate, not just cope in place.
Sustained bad conditions — a declining population, a settlement that lost
its [village-endangerment](#village-endangerment-the-attractor-mechanism)
fight, an oversupplied trade with no local demand — push toward this. No new
LLM-call tier: migration is an existing replan resolving to "leave."

**Source mix.** Migrants are preferentially drawn from push-pressured NPCs
at declining/threatened settlements when one exists nearby, falling back to
a generic wandering-NPC pool otherwise — so this doesn't sit dead-locked
behind village-endangerment being fully built first, but the flavorful case
(a village you failed to save seeds population somewhere else, possibly at
your own doorstep) is the default outcome when both systems are live.

**Floor before eligibility.** A location needs a minimum built
shelter+infrastructure count before it's eligible as a migration target at
all — the same shape as the [quest quorum](#individual-vs-settlement-level-quests)
above, so one placed campfire doesn't spawn a village.

**Player agency.** Passive/emergent by default — build real shelter and
infrastructure, and eventually someone notices. An NPC a player has real
relationship with can additionally be actively invited to accelerate or
guarantee the move, mirroring `npc.md`'s existing hiring trust-gate (a
stranger can't be bought into relocating at any price, an NPC whose need
you've already met can be asked directly).

**Unification.** Once a player-grown settlement crosses the same real
population/infrastructure thresholds a procedurally-seeded village would,
it *is* a settlement, mechanically — the same representative/quorum
machinery above, the same wealth-driven attractor exposure, the same ruin
fate on failure. There is no separate "player base" code path; a homestead's
only difference from an NPC village is its origin story.

## The closed loop

These pieces aren't three independent features — they're one settlement
lifecycle, the same "one evolutionary system governs all life"
[north star](synthesis.md#north-star) applied to settlements instead of
creatures: a settlement is born (worldgen-seeded or player-founded) → grows
via production and trade → that growth is exactly what raises its own risk
→ it can be destroyed or dwindle → its survivors are the migration pool that
seeds the next settlement, possibly the player's own. Losing a village you
failed to save isn't a dead end, it's an input to what grows next.

## Open questions

- **Growth cap/equilibrium** — shared with `npc.md`'s existing open question
  on village population caps; migration is one more growth vector into the
  same unresolved number, not a reason to invent a separate one.
- **Quorum `threshold_fraction`** and the **wealth→opportunity-biomass
  conversion** both need real numbers once there are actual villages/economy
  values to tune against — the wealth conversion specifically mirrors
  `worldbosses.md`'s existing open "exact fitness-threshold/rarity math"
  question, just with a new input term.
- **Settlement-quest reward distribution** — does success/failure apply
  uniformly to every NPC in the settlement, or weighted by the same
  social-influence score that picks the representative?
- **Template taxonomy beyond fetch/protect/deliver/join-the-defense** —
  escort, investigate, vouch-for/diplomacy are plausible future shapes;
  deferred, the current set is enough to prove the mechanism end to end.

## Current implementation status

Nothing in this doc is implemented — this is a pure design pass building on
top of Phase 1's ecosystem/evolution sim and Phase 2's NPC daily-planner
architecture, both themselves partial (see `docs/progress.md`'s Phase 1/2
tables). See `docs/progress.md`'s Phase 4 entry and its new Quests section
for the mechanism-by-mechanism status breakdown.
