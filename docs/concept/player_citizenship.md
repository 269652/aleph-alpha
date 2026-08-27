# Player Citizenship

The emergence substrate (`docs/emergence/*.md`, tracked phase-by-phase in
`docs/roadmap.md`'s "Emergence substrate" section) already gives
households, institutions, contracts, and memory to every real NPC in this
world — and, repeatedly and deliberately, NOT to the player. Every one of
those phases' own progress notes says some version of the same thing: "the
player isn't a first-class belief-holder yet," "settlement-quest reward
distribution... does it apply to the player," "an institution forms
between two households" (never a player). That was the right call while
those systems were being proven — the player didn't need to be a special
case tangled into every new mechanism while it was still being built. This
doc is the deliberate reversal: a small family of items whose entire job
is making the player a genuine participant in systems that already exist
and already work, using the exact same primitives an NPC household already
uses — never a player-only shortcut or a parallel system.

## Why these can't emerge from physics

A deed, a contract, a charter — none of these are physical objects in any
meaningful sense; a real deed is a claim recognized by a record-keeping
system, not a special kind of paper. [materials.md](materials.md)'s
property/shape grammar has nothing to say about "this parchment makes you
a landowner" — that's not a material property, it's a **write into a real
data structure** (`HouseholdStore`, `ContractStore`, `InstitutionStore` —
all real, all already built). These items are UI/interaction affordances
onto systems that are otherwise NPC-only today, the same category of gap
as `docs/concept/wayfinding.md`'s instruments, just pointed at social/
economic state instead of geographic state.

## Design pillars

1. **The player uses the SAME store, not a parallel one.** A player who
   claims land becomes a real `Household` (see
   `docs/emergence/01-society-and-institutions.md`) that owns real
   `property[]`, indistinguishable in the data from an NPC's own
   household except for who holds it. No `PlayerHousehold` subclass, no
   second ownership table.
2. **Nothing here is free — every action still goes through the same
   guarded transitions NPCs already respect.** A player can't found an
   institution that doesn't meet `InstitutionFormation`'s own real
   thresholds any more than an NPC pair can (see Charter, below); a
   proposed contract still has to move through
   `ContractStore`'s real `proposed → accepted → active → fulfilled`
   lifecycle, not skip straight to "done."
3. **What the player does with these becomes real, causally-grounded
   history.** Every action taken through one of these items is a real
   `Event` (`docs/emergence/00-emergence-architecture.md`), witnessed and
   remembered by whoever is party to it — the exact same
   `MemoryStore.witness_event` composition that already, automatically,
   gives NPCs firsthand memories of contracts and institutions they're
   party to (see `docs/progress.md`'s own repeatedly-observed "memory
   composes with something else automatically" finding across Phases
   2/4/5/6). A player who breaches a contract is *remembered* breaching it
   by the NPC on the other side of it, exactly as another NPC would be.

## Deed

Claims a real structure (or a marked, unbuilt plot) as the player's own
property, through the same `HouseholdStore.grant_property` any NPC
household's own house is already granted through
(`EarthChunkManager.record_settlement_founded_if_new`'s own villager-house
grant is the existing precedent this reuses directly, not a new
mechanism). Using a Deed for the first time forms the player's own
`Household` (`HouseholdStore.form_household`, idempotent exactly as it
already is for an NPC) if one doesn't exist yet — the player becomes a
real household the moment they first own something, not before, matching
`docs/emergence/01`'s own framing of a household as "the smallest
persistent economic/social unit," not a status granted at character
creation.

## Residency — being a member of the place you live in

Owning property and *living somewhere* are two different facts, and until
now this doc only specified the first. The Deed made the player a
household; it did not make them a member of the settlement that household
stands in. `EarthChunkManager._households_in_settlement` derives membership
purely from `npc_settled` events, so a player household was invisible to
every system that asks "who lives here" — settlement tier, institution
formation thresholds, the market's own participant set, governance. The
player could hold a deed inside a village and still not be *of* it.

That is the gap this section closes, and it is deliberately the smallest
possible change to close it: **membership is a witnessed event, exactly
as it already is for an NPC.**

- Claiming a Deed inside the chunk of an already-founded settlement
  records a **`player_settled`** event for that settlement, and
  `_households_in_settlement` reads both `npc_settled` and `player_settled`
  when deriving who lives there. A new event TYPE rather than reusing
  `npc_settled`, because the player is not an NPC and a log that says
  otherwise would be a lie told to every later reader of the event graph —
  including `/why`, which exists to explain that graph back to the player.
- **You cannot settle a place that was never founded.** The event graph is
  the authority on what exists, the same way `record_settlement_founded_if_new`
  and `record_path_worn_if_new` already treat it; a settlement with no
  history is not a settlement. Claiming a deed in empty wilderness makes
  you a landowner, not a citizen.
- **Settling twice is not being two people.** `/deed` re-run in the same
  chunk is ordinary play, not an exploit attempt, and it must not inflate
  the settlement's population — which would otherwise be a free way to push
  a hamlet over a tier threshold or an institution over its formation
  minimum. Idempotent on re-entry, like every other `_if_new` recorder here.

What this switches on, all of it code that already runs and merely could
not see the player: the settlement counts them toward its own tier;
`InstitutionFormation`'s thresholds include them; the settlement's market
has them as a participant; and their contracts and breaches are the history
of a place they actually belong to rather than a private ledger. Pillar 2
still holds throughout — none of those thresholds is lowered for the
player, they simply now apply.

**Status: ✅ built (2026-08-27).** `EarthChunkManager.record_player_settled_if_new`
records the event; `claim_property_with_deed` gained an optional
`settlement_id` and calls it, so the Deed is the player-facing verb;
`_households_in_settlement` now reads `SETTLING_EVENT_TYPES` (both
`npc_settled` and `player_settled`) and dedupes by household id, so one
household is one member however many times it was witnessed settling. Six
tests, including the two guards that carry the weight — you cannot settle a
place that was never founded, and settling twice does not count you twice.

## Ledger

Proposes a real `Contract` (`docs/emergence/03-contracts-property-
economy.md`) between the player's own household and an NPC household or
settlement — a trade, a rent agreement, a supply commitment — using
`EarthChunkManager.propose_contract` exactly as `_step_settlement_trade`
already does for two NPC households, just with the player as one of the
named parties instead of both being NPCs. The Ledger's UI is the accept/
fulfil/breach lifecycle made visible and player-drivable: a player can
walk away from an active contract (a real `breach_contract` call, with
the same real consequences an NPC's own breach already has — see
`docs/progress.md`'s Emergence Phase 4 entry on what a recorded breach
means for `InstitutionFormation`'s downstream trust math), not just
silently stop caring about a quest.

## Charter

Lets the player found, or be invited into, a real `Institution`
(`docs/emergence/01-society-and-institutions.md`) alongside an NPC
household — the exact `EarthChunkManager.attempt_institution_formation`
call `_step_settlement_trade` already drives automatically for two NPCs,
now reachable directly by the player once the same real precondition
(`InstitutionFormation.should_form`'s real fulfilled-contract threshold —
see [Ledger](#ledger) above for how those contracts get proposed and
fulfilled in the first place) is genuinely met. A Charter cannot force an
institution into being on the spot; using one just performs the same
formation ATTEMPT an NPC pair's own automatic trade already performs,
checked against the same real threshold — a player who hasn't built up
real fulfilled history with a household has nothing to found yet, exactly
like an NPC pair wouldn't. `docs/concept/governance.md`'s own real
governance-form inference (a settlement's dominant institution TYPE
shaping what it attempts next) reads the player's own founded
institutions exactly like any other, since they're the same store, the
same type field, the same history.

## Field Journal

Not a claim or a proposal — a real-time READER over `Why`'s own existing
explainers (`explain_event`, `explain_entity`, `explain_household`,
`explain_contracts`, `explain_institutions`, `explain_settlement`,
`explain_world_boss`, all already built and already console-inspectable
via `/why`/`/history`/etc.), rendered as in-world lore instead of dev-
console text. Opening the Journal on a settlement, a ruin
([exploration.md](exploration.md)), or a promoted world boss
([worldbosses.md](worldbosses.md)) shows the SAME real causal history a
`/why` command already surfaces — "this ruin exists because this
settlement's real food stock collapsed on world-clock tick 962" — as
readable prose, not a debug dump. This is the most direct possible
expression of this project's own master thesis (every persistent thing
has a real causal parent) made player-facing: the Journal doesn't
generate lore, it *reads* lore that the simulation already produced and
already keeps a record of. An LLM pass may turn the plain-text `Why`
output into more natural prose (the same "simulation produces the facts,
an LLM may only phrase them, never invent contradicting ones" boundary
`docs/emergence/05-dungeons-bosses-exploration-content.md`'s own "Content
boundary" section already states), but the Journal's content is never
authoritative on its own — `Why`'s own output always is.

## Status

Deed, Ledger, and Charter's own backend coordinators are now real code too
(see below) — a player's deterministic identity now exists
(`PlayerIdentity.PLAYER_ENTITY_ID`, `src/emergence/player_identity.gd`,
`test_player_identity.gd`, 2/2 passing: a real, valid `EntityRef` the same
`"<kind>:<key>"` scheme every other emergence entity already uses), and
each item's own real prerequisite in the emergence substrate now has a
thin `EarthChunkManager` coordinator method built on top of it, strict-TDD,
one method at a time. All four now have a real call site too, as dev-console
commands (`World._on_console_command`, `scenes/world.gd`) gated on the
player actually owning the relevant item: `/deed`, `/ledger
propose|accept|fulfill|breach`, `/charter found`, and `/journal
<entity_id>`. What remains for all four is only the in-world use/equip
interaction and UI — the dev console is a real, honest interim call site
here, not the design's own final interaction. Field Journal's READ side is
likewise already real code (see below):

- Deed: `EarthChunkManager.claim_property_with_deed(property_id) ->
  Household` forms/reuses the player's own `Household` via
  `HouseholdStore.form_household(PlayerIdentity.PLAYER_ENTITY_ID)` and
  grants it `property_id` via `grant_property` — the exact same mechanism
  NPC houses are already granted through — then records a real
  `player_claimed_property` event, the same "one call, two stores kept in
  sync" shape every other coordinator in this file already uses. Both
  underlying calls are already idempotent, so claiming the same property
  twice is a safe no-op (3 new tests in `test_earth_chunk_manager.gd`, all
  passing). A real `/deed` console command now invokes it, requiring the
  player own a `deed` item and deriving `property_id` from the chunk the
  player currently stands on. Still missing: the Deed item's own in-world
  use/equip interaction and UI (the dev console stands in for it today).
- Ledger: `EarthChunkManager.player_propose_contract(type,
  counterparty_id, obligations, consideration, deadline) -> Contract` is a
  thin wrapper over the existing `propose_contract`, naming the player's
  own household as one party. No new accept/fulfil/breach counterpart was
  needed — `ContractStore._transition` never assumes anything about WHICH
  entity a party is, so the existing generic `accept_contract`/
  `activate_contract`/`fulfill_contract`/`breach_contract` already work
  unchanged for a player-named contract (2 new tests, both passing). Real
  `/ledger propose <type> <counterparty_id> <consideration>
  <deadline_seconds>` and `/ledger accept|fulfill|breach <contract_id>`
  console commands now invoke it, requiring the player own a `ledger` item.
  Still missing: the Ledger item's own in-world use/equip interaction and UI.
- Charter: `EarthChunkManager.player_attempt_institution_formation(type,
  counterparty_id) -> Institution` is a thin wrapper over the existing
  `attempt_institution_formation`, naming the player's own household as
  one party, gated by the exact same real
  `InstitutionFormation.should_form` threshold an NPC pair is held to (2
  new tests: below-threshold forms nothing, at-threshold forms a real
  institution containing the player's household — both passing). A real
  `/charter found <type> <counterparty_id>` console command now invokes it.
  A craftable `charter` item id (plank + hide + plant_fibre, deliberately
  the most materially demanding of the four citizenship items) now exists
  too, closing the "unreachable by a player" gap this section originally
  flagged. Still missing: the item's own in-world use/equip interaction and
  UI, same as the other three.
- Field Journal's READ side is built: `src/emergence/field_journal.gd`'s
  `entry_for(entity_id, stores)` dispatches by `EntityRef.kind_of` onto
  `Why`'s existing `explain_*` functions (`tests/unit/test_field_journal.gd`).
  The dispatch is grounded in how these stores are actually keyed by real
  callers (household lookup is by an `"npc:"` member; institution
  membership is by a `"household:"` member; world-boss lookup is by the
  boss's own `individual_id`, convention `"creature:"`, not yet produced
  by any real caller) rather than a naive "kind X routes to explain_X"
  guess — see that module's own doc comment for the full reasoning. A real
  `/journal <entity_id>` console command now invokes it, building the
  `stores` Dictionary directly from `EarthChunkManager`'s own public store
  accessors — the same accessors `/household`/`/institution`/`/boss`/
  `/history` already read directly, so no new coordinator method was
  needed. Still missing: the in-world UI/presentation layer itself
  (in-world lore instead of dev-console text, the optional LLM rephrasing
  pass) — the smallest lift of the four is now smaller still.

Build order followed exactly as planned: Deed first (simplest, no
dependency on the other three), then Ledger (Charter depends on it), then
Charter — all three now real backend coordinators, in that order, each its
own strict-TDD red/green cycle. Field Journal's READ side was built
separately and is likewise real. All four now have a real dev-console call
site too (`/deed`, `/ledger`, `/charter`, `/journal`). What is left for all
four is the same shape of gap: the in-world use/equip interaction and
UI/presentation, not the underlying mechanism nor a call site.

To be explicit about what kind of interaction this is: the dev console is
the real, current interface for all four — typing `/deed`, `/ledger
propose ...`, `/charter found ...`, or `/journal <id>` — not yet the
physical "equip the item, press the action key while holding it"
interaction the Lasso and fishing rod already have in this project
(`World._update_lasso_label`/`local_player.lasso_message`, the closest
real precedent). Each command is gated on `local_player.inventory.has(...)`
for the item's own real id first, though — no command fires for an item
the player doesn't actually hold — the same "a real crafted item gates a
real action, never a free grant" convention `wayfinding.md`'s own design
pillar 4 ("reuse the crafting grammar for acquisition") states for its
instruments, applied here even though this doc doesn't number its own
pillars the same way. Charter's own `charter` item id is now craftable
too, so all four gates can genuinely pass in play, not just three of them.

## Open questions

- Does a player-founded household's own "goals" (`docs/emergence/01`'s
  "Derive goals from member needs, pooled dependencies...") ever get
  populated for the player, the way an NPC household's presumably will
  once that mechanism is built — or does the player's own agency make
  "goals" meaningless for a household they directly control?
- Reward/consequence parity: when a player-party contract is fulfilled or
  breached, do the SAME settlement-level reputation/legitimacy effects
  apply as an NPC-only contract would (`docs/concept/governance.md`'s own
  legitimacy read, `factions.md`'s aggregate reputation), or does player
  action deliberately weight differently? No stated reason yet to treat
  it differently, but not yet decided either.
- Should a Charter let the player found a `criminal_group` institution
  type, given `docs/concept/governance.md`'s own explicit choice to leave
  that type ungoverned (coercion, not legitimacy)? A player-led criminal
  institution is a real, interesting design space this doc doesn't
  resolve.
