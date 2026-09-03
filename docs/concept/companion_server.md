# Companion Server

A companion webserver the game itself launches locally — a second, browsable
surface onto the same save, for creature bookkeeping, settlement management,
and (once earned) giving NPCs a real voice. It is not a second game; it is a
window, and everything it can *do* (not just show) is deliberately narrow.

## Status

Concept stage. Nothing below is built. Written before any code per
[CLAUDE.md](../../CLAUDE.md)'s "concept docs are the spec" rule — no system
this size gets built without a spec existing first.

## Design pillars

1. **Tier 1 needs zero LLM and zero network.** The base companion view — a
   character sheet, a bestiary, a settlement dashboard — works fully offline,
   for every player, from the start. This mirrors [dialogue.md](dialogue.md)'s
   own floor: a real, complete feature with no model anywhere in it. The
   richer, LLM-touching stuff is additive, never load-bearing.
2. **The server proposes, the core decides.** No write path from the
   companion server reaches a wallet, a contract, a wage, or a quest
   directly. Every write is a proposal validated and applied by the same
   pure core the rest of the sim already runs through — identical in shape
   to dialogue.md's beat contract, where a model returns one string and
   "there is no code path from a model's output to a wallet, a contract, or
   a store." This doc reuses that sentence as a hard constraint, not an
   inspiration.
3. **Richness is earned, not configured.** The interesting Tier 2 features
   (live voice, chronicle, live breeding predictions, remote instructions)
   unlock behind an actual in-world hire — a real wage, a real relationship
   gate, the exact rule [npc.md](npc.md) already specifies for hiring any
   NPC. Not a settings toggle sitting outside the fiction.
4. **One data source, reused.** Every read the server offers is the same
   state another system already computed and persists —
   [persistence.md](persistence.md)'s `Player` save dict, `VillageWages`,
   `village_market.gd`, `AnimalFitness`/DNA fields. No parallel stat is
   invented for the sake of having something to show on a page.
5. **Secrets never live in the shipped client.** Any OAuth/API-key exchange
   for an LLM provider happens entirely on the companion server's side of
   the process boundary, never embedded in or transmitted through the
   Godot binary — the same reasoning [licensing.md](../licensing.md)'s
   GitHub Device Flow already uses for why a distributed client shouldn't
   hold a secret at all.

## Real-world / genre grounding

Asynchronous companion surfaces are an established MMO/colony-sim pattern,
not a novelty for its own sake: WoW's Armory, EVE Online's remote skill
queue and neocom, and the fan-made IV/breeding calculators Pokémon players
build externally because the base game doesn't expose the math. This system
is the native version of that last one — a tool players already reach for
outside the game, built with real data instead of reverse-engineered
guesses, plus the asynchronous "check in between sessions" loop the other
two examples prove players want.

## Mechanism

### Tier 1 — always on, no gate

Launches alongside the game (or via a menu toggle), bound to localhost only,
read-only:

- **Character sheet** — mirrors `Player.to_save_dict()` field-for-field
  (wallet, XP/level, equipment, skill allocations). No new state; a window
  onto what persistence.md already round-trips.
- **Bestiary** — every creature encountered or tamed: name, species, and its
  real DNA/fitness numbers (`strength`, `agility`, `coat_vibrancy`,
  `fitness_score` — see [dna.md](dna.md), [evolution.md](evolution.md),
  [pets.md](pets.md#fitness--in-role-performance-first-pass)). Read-only.
- **Settlement dashboard** — for any settlement visited or founded, the same
  needs/wage/market numbers `VillageWages` and `village_market.gd` already
  compute (see [npc.md](npc.md#needs-and-the-local-production-economy)),
  rendered rather than recomputed.

No outbound network call exists at this tier. Closing the browser tab loses
nothing — every value here is derived, not authored on the page.

### Tier 2 — the Hall and the Scrivener

A buildable structure (see [building.md](building.md)'s blueprint catalog;
working name "Registry Hall," see Open questions) that, once placed and
staffed, turns on the rest.

**A new occupation.** `NpcIdentity.OCCUPATIONS` currently holds `farmer,
blacksmith, merchant, guard, fisher, herbalist, hunter, nurse`
(`src/world/npc_identity.gd`). This adds a ninth: `scrivener` — a
non-producer, same as blacksmith/guard/nurse, eating by buying rather than
gathering (see npc.md's occupation economy section).

**Hiring follows the existing rule exactly**, not a special case: an
ongoing wage out of [economy.md](economy.md)'s gold, gated by relationship —
"a stranger won't work for you at any price" (npc.md's Hiring & instruction
section). What differs is what the wage buys: a cheap/local model is an
always-affordable, barely-literate apprentice; a strong hosted model is a
renowned wordsmith who costs a real recurring wage — and, per the same
relationship gate, may simply decline to work for a low-trust employer
regardless of price. The OAuth/API-key handshake for whichever backend is
chosen happens entirely server-side (pillar 5).

**What hiring one unlocks:**

- **Voice.** Plugs into dialogue.md's already-specified, deliberately narrow
  AI seam: the scribe restyles one `template` string in the villager's
  voice. It does not choose what is said, whether a quest is offered, or
  what it pays — that boundary is unchanged, just given an in-fiction face.
- **Chronicle.** Browsable settlement/NPC history, generated from the real
  append-only `EventStore` plus each NPC's own memory/rumor confidence (see
  npc.md's Memory, beliefs, and rumor propagation section). "The scribe
  wrote it down" doubles as the in-fiction reason an unwitnessed or old
  event reads fainter — reuses the existing decay mechanic rather than
  inventing a second one for display purposes.
- **Live breeding planner.** The bestiary's crossing predictor (mirroring
  `dna_crossover.gd`'s real math) only activates for creatures actually
  walked past the Hall. Registration is a real action with a real in-world
  footprint, not passive omniscience — matches taming.md's "nothing is
  hidden, but nothing is free."
- **Instruction queue.** Remote queuing through npc.md's still-unbuilt
  hiring/instruction DSL — the Scrivener is the one relaying written orders
  to the workforce while the player is away, which is also why this
  specific feature can't exist before that DSL does (see Open questions).

### The boundary, stated once more explicitly

Every Tier 2 write — a queued instruction, a registered creature, a hire —
is a *proposal*. It is validated and applied by the same pure-core module
the rest of the sim already uses for that kind of state change; the
companion server holds no authority to mutate a wallet, a relationship, or
a quest on its own. An LLM's only possible output anywhere in this system is
a rephrased string for Voice — never a decision.

### Local transport (leaning, not decided)

Tier 1 reads: reuse persistence.md's existing `user://`
`FileAccess.store_var`/`get_var` save convention directly rather than
inventing a second one — "one convention, reused" is persistence.md's own
pillar 4, and there's no reason the companion server needs a different
contract with the save file than a reload does. Tier 2 writes: a minimal
local endpoint the running Godot process exposes for proposals only,
validated by the same core the rest of the sim calls.

## Non-goals (for now)

Mirrors [overview.md](overview.md)'s own Non-goals section:

- No multiplayer or shared companion server. Single local player, single
  local save — matches the confirmed single-player MVP scope.
- No LLM output ever reaches game state directly, at any tier, ever.
- Tier 1 requires no network access under any circumstance. Only Tier 2's
  Voice feature makes an outbound call, and only once a Scrivener is
  actually hired.

## Open questions

- **Naming.** "Registry Hall" / "Scrivener" are working names chosen for
  clarity while writing this doc, not a final creative decision — see
  follow-up brainstorm.
- Where the Hall sits in building.md's blueprint catalog, and what gates
  building it (always available at some civic tier? a quest?).
- The wage curve mapping backend "quality" to gold cost needs to be a
  tested/pinned constant once it exists, per CLAUDE.md's no-eyeballed-tuning
  rule — not specified here.
- This doc assumes npc.md's instruction DSL and hiring/relationship systems
  exist; today they don't (see npc.md's own divergence note). The
  Instruction queue feature specifically has no floor to stand on until the
  DSL is real — everything else in Tier 2 doesn't share that dependency.
- Exact LLM backend/provider list is deliberately left open, matching
  overview.md's own unresolved "hosted API vs. local model" question — this
  doc answers *where* that choice is made (companion server, per-hire), not
  *which* backends are supported.
- Should Tier 1 have any gate at all, or is a totally-ungated dashboard the
  right default even before a player has built anything?
